// mayhem/fuzz_string.c — libFuzzer harness for M*LIB's m-string.h dynamic-string container, the
// in-process, sanitized successor to the original mayhemheroes `string` target.
//
// The original target compiled example/ex-string01.c (`gcc -o string example/ex-string01.c -I.`) and
// fuzzed it as a CLI over a file (`/string @@`): it read a (C-header-like) text file line by line into
// an M*LIB string_t via string_fgets(..., STRING_READ_PURE_LINE), then reformatted each line —
// padding/pulling-back '\' continuation markers around column 80 — using the m-string.h API
// (string_size, string_get_char, string_left, string_push_back, string_get_cstr). m-string.h's
// line reader + in-place string mutation is the exact parsing/manipulation surface those CLI runs
// exercised.
//
// We drive that SAME surface in-process here: the fuzz bytes are wrapped in an in-memory FILE via
// fmemopen() and fed through string_fgets(STRING_READ_PURE_LINE) + the identical reformat logic from
// ex-string01.c's format(). This keeps the fuzzed code (m-string.h) the real target — now compiled
// WITH $SANITIZER_FLAGS — while running fully in-process (no exec, no exit() on benign input), so the
// libFuzzer/standalone process survives every input. Output is sent to /dev/null so the formatter runs
// to completion (the original printed to stdout; we discard it, only the m-string.h work matters).
#include "m-string.h"

#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define MAX_COLUMN 80

// The reformat routine from example/ex-string01.c, verbatim in its m-string.h API usage, reading from
// an arbitrary FILE* (here an fmemopen'd buffer of the fuzz bytes) and writing to `out`.
static void format(FILE *f, FILE *out)
{
    string_t s;
    string_init(s);
    while (string_fgets(s, f, STRING_READ_PURE_LINE) == true)
    {
        size_t n = string_size(s);
        if (n > 0 && string_get_char(s, n-1) == '\\' && n < MAX_COLUMN) {
            string_left(s, n-1);
            while (n < MAX_COLUMN-1) {
                string_push_back(s, ' ');
                n++;
            }
            string_push_back(s, '\\');
        }
        if (n >= MAX_COLUMN && string_get_char(s, n-1) == '\\') {
            n--;
            string_left(s, n);
            while (n >= MAX_COLUMN-2 && string_get_char(s, n-1) == ' ') {
                n--;
                string_left(s, n);
            }
            string_push_back(s, ' ');
            string_push_back(s, '\\');
        }
        fprintf(out, "%s\n", string_get_cstr(s));
    }
    string_clear(s);
}

int LLVMFuzzerTestOneInput(const uint8_t *data, size_t size)
{
    // string_fgets() is m-string.h's TEXT line reader (the original target opened its file in text
    // mode "rt"); it is built on libc fgets, whose contract is NUL-free text. An embedded NUL makes
    // fgets return a chunk whose strlen() is 0 at a read boundary, tripping m-string.h's own
    // M_ASSERT(size >= 1) precondition (m-string.h:1300) — a library text-input contract assertion,
    // not a memory-safety bug, that random binary fuzz bytes hit on a large fraction of inputs and
    // would flood the campaign before it explores the real string-mutation surface. We honor the
    // text-input precondition at the harness boundary (reject embedded NULs) so the fuzzer drives the
    // actual m-string.h reformat/mutation code with ASan+UBSan AND all remaining M*LIB contract
    // asserts fully ON and halting. (This is the one documented benign-precondition relax.)
    if (memchr(data, 0, size) != NULL)
        return 0;

    // Wrap the fuzz bytes as a read-only text stream. fmemopen needs a non-NULL buffer; for size 0
    // pass a 1-byte scratch so we still drive string_fgets (it returns false immediately on EOF).
    FILE *f;
    if (size == 0) {
        static char empty = 0;
        f = fmemopen(&empty, 0, "r");
    } else {
        f = fmemopen((void *)data, size, "r");
    }
    if (!f)
        return 0;

    FILE *out = fopen("/dev/null", "w");
    if (!out) { fclose(f); return 0; }

    format(f, out);

    fclose(out);
    fclose(f);
    return 0;
}
