#!/usr/bin/env bash
# mlib/mayhem/test.sh — RUN M*LIB's OWN unit-test suite (tests/, already built by mayhem/build.sh with
# the project's normal flags) → CTRF. PATCH-grade oracle: it never compiles the harness/fuzz build, and
# it asserts BEHAVIOR, not just exit status.
#
# `make check` (in tests/) compiles + RUNS every tests/test-*.c (28) and tests/except-*.c (7) — each is
# a self-checking C program packed with assert()s over the m-*.h containers (e.g. test-mstring.c alone
# has 320 asserts: it builds strings, mutates them, and asserts the EXACT resulting size/contents/cstr,
# round-trips serialization, etc.) and abort()s on any mismatch — and it verifies the tests/fail-*.c (3)
# programs FAIL to compile (negative compile tests for the oplist machinery). It prints "All tests
# passed" only if every one of those held. A no-op / exit(0) "patch" to any m-*.h header makes the
# asserted values wrong and abort()s the corresponding test program, so `make check` fails — this
# oracle cannot be reward-hacked by "ran without crashing".
#
# build.sh already compiled the suite with NORMAL flags (clean, sanitizer-free) so this stays an honest
# PATCH oracle; `make check` here only (re)links what is stale and runs the programs.
set -uo pipefail
[ -n "${SOURCE_DATE_EPOCH:-}" ] || unset SOURCE_DATE_EPOCH
: "${MAYHEM_JOBS:=$(nproc)}"
: "${CC:=clang}"
cd "$SRC"

# emit_ctrf <tool> <passed> <failed> [skipped] [pending] [other]
# Writes a CTRF report (file + stdout `CTRF {...}` marker) and returns non-zero iff failed>0.
emit_ctrf() {
  local tool="$1" passed="$2" failed="$3" skipped="${4:-0}" pending="${5:-0}" other="${6:-0}"
  local tests=$(( passed + failed + skipped + pending + other ))
  cat > "${CTRF_REPORT:-$SRC/ctrf-report.json}" <<JSON
{
  "results": {
    "tool": { "name": "$tool" },
    "summary": {
      "tests": $tests,
      "passed": $passed,
      "failed": $failed,
      "pending": $pending,
      "skipped": $skipped,
      "other": $other
    }
  }
}
JSON
  printf 'CTRF {"results":{"tool":{"name":"%s"},"summary":{"tests":%d,"passed":%d,"failed":%d,"pending":%d,"skipped":%d,"other":%d}}}\n' \
    "$tool" "$tests" "$passed" "$failed" "$pending" "$skipped" "$other"
  [ "$failed" -eq 0 ]
}

[ -d "$SRC/tests" ] || { echo "missing $SRC/tests — wrong tree?" >&2; emit_ctrf "mlib-check" 0 1; exit 2; }

# The number of self-checking test programs `make check` runs + compile-reject groups it verifies:
# tests/test-*.c (run), tests/except-*.c (run), tests/fail-*.c (must-fail-to-compile). Counted from the
# tree so the total tracks upstream as it adds tests.
NTEST=$(ls "$SRC"/tests/test-*.c   2>/dev/null | wc -l)
NEXC=$( ls "$SRC"/tests/except-*.c 2>/dev/null | wc -l)
NFAIL=$(ls "$SRC"/tests/fail-*.c   2>/dev/null | wc -l)
TOTAL=$(( NTEST + NEXC + NFAIL ))
[ "$TOTAL" -gt 0 ] || { echo "no test-*.c found under $SRC/tests" >&2; emit_ctrf "mlib-check" 0 1; exit 2; }

# Run M*LIB's own suite with the project's normal C99 flags, pinned to the image's compiler. `make
# check` aborts (non-zero) on the FIRST failing program / unexpected compile result, and prints
# "All tests passed" only when all $TOTAL items held.
LOG="$(mktemp)"
echo "test.sh: running M*LIB 'make check' ($NTEST test-*, $NEXC except-*, $NFAIL fail-* compile checks)" >&2
if make -C "$SRC/tests" -j"$MAYHEM_JOBS" check CC="$CC -std=c99" XCFLAGS="-O" >"$LOG" 2>&1 \
   && grep -q "All tests passed" "$LOG"; then
  echo "test.sh: All tests passed ($TOTAL items)" >&2
  emit_ctrf "mlib-check" "$TOTAL" 0
else
  echo "test.sh: 'make check' FAILED — tail:" >&2
  tail -60 "$LOG" >&2
  # make check is all-or-nothing (it aborts on the first failure), so we cannot attribute a precise
  # passed/failed split; report the whole suite as failed so the grader treats the patch as breaking.
  emit_ctrf "mlib-check" 0 "$TOTAL"
  exit 1
fi
