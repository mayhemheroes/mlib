/* mayhem/oracle_behavior.c — behavioral oracle for M*LIB's container library.
 * Exercises m-array.h (push/pop/get) and m-string.h (init/set/size/cstr) with
 * KNOWN-ANSWER operations and prints the computed values to stdout.  The grep
 * harness in test.sh asserts exact expected strings; a no-op / exit(0) patch to
 * any m-*.h header produces wrong values (or no output at all when LD_PRELOAD
 * neuters this binary), so the oracle FAILS — it is not reward-hackable.
 *
 * Compile: clang -std=c99 -D_GNU_SOURCE -I<src> oracle_behavior.c -o oracle_behavior
 * Run:     ./oracle_behavior    (exits 0 on success, non-zero on any assertion)
 */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

/* Pull in M*LIB headers (header-only; this TU IS the library for compilation). */
#include "m-array.h"
#include "m-string.h"

/* ── integer array ── */
ARRAY_DEF(array_int, int)

/* ── string list (singly-linked) ── */
#include "m-list.h"
LIST_DEF(list_str, string_t, STRING_OPLIST)

/* Abort with a message if condition fails. */
#define CHECK(cond, msg) \
  do { if (!(cond)) { fprintf(stderr, "ORACLE FAIL: %s\n", msg); exit(1); } } while(0)

int main(void)
{
    /* ── 1) Array: push 5 integers, pop one, get the rest ── */
    array_int_t a;
    array_int_init(a);
    for (int i = 1; i <= 5; i++)
        array_int_push_back(a, i * 10);   /* 10 20 30 40 50 */
    CHECK(array_int_size(a) == 5, "array size after 5 pushes");
    array_int_pop_back(NULL, a);          /* remove 50 */
    CHECK(array_int_size(a) == 4, "array size after pop");
    CHECK(*array_int_get(a, 0) == 10, "a[0]==10");
    CHECK(*array_int_get(a, 3) == 40, "a[3]==40");

    /* Print known-answer values — the grep harness matches these exact strings. */
    printf("oracle:array:size=%zu\n", array_int_size(a));
    printf("oracle:array:a[0]=%d\n",  *array_int_get(a, 0));
    printf("oracle:array:a[3]=%d\n",  *array_int_get(a, 3));
    array_int_clear(a);

    /* ── 2) String: build, append, size, cstr round-trip ── */
    string_t s;
    string_init(s);
    string_set_str(s, "hello");
    string_cat_str(s, ",world");
    CHECK(string_size(s) == 11, "string size==11");
    CHECK(strcmp(string_get_cstr(s), "hello,world") == 0, "string cstr");

    printf("oracle:string:size=%zu\n",    string_size(s));
    printf("oracle:string:cstr=%s\n",     string_get_cstr(s));
    string_clear(s);

    /* ── 3) List of strings: push, iter, count ── */
    list_str_t lst;
    list_str_init(lst);
    string_t tmp;
    string_init(tmp);
    for (int i = 0; i < 3; i++) {
        string_printf(tmp, "item%d", i);
        list_str_push_back(lst, tmp);
    }
    CHECK(list_str_size(lst) == 3, "list size==3");
    /* Peek at the first element pushed (back of the list in push_back order). */
    const string_t *front = list_str_back(&lst);
    CHECK(strcmp(string_get_cstr(*front), "item2") == 0, "list back==item2");

    printf("oracle:list:size=%zu\n",     list_str_size(lst));
    printf("oracle:list:back=%s\n",      string_get_cstr(*front));
    string_clear(tmp);
    list_str_clear(lst);

    printf("oracle:ok\n");
    return 0;
}
