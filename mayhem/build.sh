#!/usr/bin/env bash
# mlib/mayhem/build.sh — build (a) the sanitized fuzz_string libFuzzer harness over M*LIB's
# m-string.h dynamic-string container (plus its standalone reproducer), and (b) M*LIB's OWN unit-test
# suite (tests/) with NORMAL flags, so mayhem/test.sh only RUNS it (an honest PATCH oracle, never
# compiles).
#
# M*LIB is a HEADER-ONLY C library: there is no library to compile — the "project" is the set of
# m-*.h headers, and the fuzzed code is m-string.h, which is #included (and thus instrumented WITH
# $SANITIZER_FLAGS) directly into the harness translation unit. The Mayhem target `string` is the
# in-process, sanitized successor to the original mayhemheroes integration, which compiled
# example/ex-string01.c and fuzzed it as a CLI over a file (`/string @@`); mayhem/fuzz_string.c drives
# the SAME m-string.h surface (string_fgets line reader + the ex-string01 reformat logic) in-process.
set -euo pipefail

# clang rejects SOURCE_DATE_EPOCH='' (empty) — must be unset or a valid integer.
[ -n "${SOURCE_DATE_EPOCH:-}" ] || unset SOURCE_DATE_EPOCH

# Build knobs from the ENV, overridable. SANITIZER_FLAGS uses `=` (not `:=`) so an explicit empty
# value (--build-arg SANITIZER_FLAGS=) is honored → no-sanitizer build (natural crash).
: "${SANITIZER_FLAGS=-fsanitize=address,undefined -fno-sanitize-recover=all -fno-omit-frame-pointer -g}"
: "${CC:=clang}" ; : "${CXX:=clang++}" ; : "${LIB_FUZZING_ENGINE:=-fsanitize=fuzzer}"
: "${MAYHEM_JOBS:=$(nproc)}"
export SANITIZER_FLAGS CC CXX LIB_FUZZING_ENGINE MAYHEM_JOBS

cd "$SRC"

# m-string.h uses fmemopen() in the harness (and other GNU bits); compile gnu99 with _GNU_SOURCE.
HARNESS_CFLAGS="-std=gnu99 -D_GNU_SOURCE -I$SRC"

# ── 1) Sanitized fuzz target ──────────────────────────────────────────────────
# Header-only: m-string.h is #included into the harness TU, so compiling the harness WITH
# $SANITIZER_FLAGS instruments the FUZZED CODE (the m-string.h string container) itself.
#
# 1a) libFuzzer harness (the Mayhem target `string`): harness + m-string.h + engine.
$CC $SANITIZER_FLAGS $HARNESS_CFLAGS \
    "$SRC/mayhem/fuzz_string.c" $LIB_FUZZING_ENGINE \
    -o /mayhem/fuzz_string

# 1b) Standalone (non-fuzzer) reproducer: same harness + LLVM's run-once driver. C harness, so
#     $STANDALONE_FUZZ_MAIN compiles cleanly with $CC. Respects $SANITIZER_FLAGS.
$CC $SANITIZER_FLAGS -c "$STANDALONE_FUZZ_MAIN" -o /tmp/standalone_main.o
$CC $SANITIZER_FLAGS $HARNESS_CFLAGS \
    "$SRC/mayhem/fuzz_string.c" /tmp/standalone_main.o \
    -o /mayhem/fuzz_string-standalone

# ── 2) M*LIB's OWN unit-test suite (NORMAL flags, no sanitizers) ─────────────────────────────────
# `make check` (in tests/) compiles + runs every tests/test-*.c and tests/except-*.c (each is a
# self-checking C program that assert()s its expected results and aborts on mismatch), and verifies
# the tests/fail-*.c programs FAIL to compile. It prints "All tests passed" on success. We compile it
# here with the project's normal C99 flags (a separate, clean, sanitizer-free build) so mayhem/test.sh
# only RUNS it and stays an honest PATCH oracle. The suite builds the test binaries in tests/ in place;
# leave the tree as-is for test.sh.
#
# Drop M*LIB's -Werror-ish hardening flags that assume a specific gcc (e.g. -Wtrampolines, -ftrapv)
# and pin CC=clang to match the rest of the image; the tests themselves are compiler-agnostic.
echo "build.sh: building M*LIB test suite (tests/) with normal flags"
make -C "$SRC/tests" -j"$MAYHEM_JOBS" exe CC="$CC -std=c99" XCFLAGS="-O" \
    >/tmp/mlib-test-build.log 2>&1 || {
  echo "build.sh: test-suite build failed:" >&2; tail -60 /tmp/mlib-test-build.log >&2; exit 1; }

# Sanity: confirm the suite produced its test executables (test.sh runs `make check`, which rebuilds
# only what's stale and runs them).
ls "$SRC"/tests/test-*.exe >/dev/null 2>&1 || {
  echo "build.sh: no tests/test-*.exe produced — test build is broken" >&2; exit 1; }

echo "build.sh: built /mayhem/fuzz_string (+ -standalone) and the M*LIB test suite"
ls -l /mayhem/fuzz_string /mayhem/fuzz_string-standalone
