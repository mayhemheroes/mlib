#!/usr/bin/env bash
# mlib/mayhem/test.sh — RUN M*LIB's behavioral oracle and unit-test suite
# (already built by mayhem/build.sh with normal flags) → CTRF.
#
# PATCH-grade oracle: this script never compiles; it only RUNS pre-built
# binaries.  The oracle ASSERTS BEHAVIOR (specific computed container values
# printed to stdout), not just "exit 0":
#
#   1) /mayhem/oracle_behavior — a small C program that exercises m-array.h,
#      m-string.h, and m-list.h with known-answer push/pop/get operations and
#      PRINTS the computed values ("oracle:array:size=4", etc.).  grep checks
#      each exact expected string.  A no-op / exit(0) patch to any m-*.h
#      produces wrong values or (when the binary is LD_PRELOAD-neutered) NO
#      output at all — either way the grep fails → oracle FAILS.
#
#   2) M*LIB's own `make check` suite (tests/test-*.c, except-*.c, fail-*.c)
#      compiled with normal flags in build.sh; each test program is packed with
#      assert()s that abort on wrong values, so a functional breakage aborts
#      make and the suite fails.
#
# CTRF is emitted at the end; the process exits non-zero iff failed>0.
set -uo pipefail
[ -n "${SOURCE_DATE_EPOCH:-}" ] || unset SOURCE_DATE_EPOCH
: "${MAYHEM_JOBS:=$(nproc)}"
: "${CC:=clang}"
cd "$SRC"

# emit_ctrf <tool> <passed> <failed> [skipped] [pending] [other]
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

PASSED=0
FAILED=0

# ── 1) Behavioral oracle: known-answer container operations ───────────────────
# This is the anti-reward-hack gate.  The oracle binary prints exact strings for
# specific computed values.  grep_ok <pattern> <output> checks each expected
# line; any mismatch increments FAILED.  When the binary is LD_PRELOAD-neutered
# to exit(0) it produces NO output — every grep fails → oracle is not hackable.
ORACLE=/mayhem/oracle_behavior
if [ ! -x "$ORACLE" ]; then
  echo "test.sh: /mayhem/oracle_behavior missing — build.sh must be re-run" >&2
  emit_ctrf "mlib-oracle" 0 1
  exit 1
fi

echo "test.sh: running behavioral oracle" >&2
ORACLE_OUT="$("$ORACLE" 2>&1)" || { echo "test.sh: oracle exited non-zero" >&2; ((FAILED++)) || true; }

# Each expected key=value pair is one test case.
declare -a EXPECTED=(
  "oracle:array:size=4"
  "oracle:array:a[0]=10"
  "oracle:array:a[3]=40"
  "oracle:string:size=11"
  "oracle:string:cstr=hello,world"
  "oracle:list:size=3"
  "oracle:list:back=item2"
  "oracle:ok"
)

for pat in "${EXPECTED[@]}"; do
  if printf '%s\n' "$ORACLE_OUT" | grep -qF "$pat"; then
    ((PASSED++)) || true
  else
    echo "test.sh: oracle MISSING expected output: $pat" >&2
    ((FAILED++)) || true
  fi
done

ORACLE_TESTS=${#EXPECTED[@]}
echo "test.sh: oracle: ${ORACLE_TESTS} checks, passed=$PASSED failed=$FAILED" >&2

# ── 2) M*LIB's own make check suite ──────────────────────────────────────────
# Count test source files (tracks upstream additions automatically).
NTEST=$(ls "$SRC"/tests/test-*.c   2>/dev/null | wc -l)
NEXC=$( ls "$SRC"/tests/except-*.c 2>/dev/null | wc -l)
NFAIL=$(ls "$SRC"/tests/fail-*.c   2>/dev/null | wc -l)
SUITE_TOTAL=$(( NTEST + NEXC + NFAIL ))

if [ "$SUITE_TOTAL" -gt 0 ]; then
  LOG="$(mktemp)"
  echo "test.sh: running M*LIB 'make check' ($NTEST test-*, $NEXC except-*, $NFAIL fail-* compile checks)" >&2
  if make -C "$SRC/tests" -j"$MAYHEM_JOBS" check CC="$CC -std=c99" XCFLAGS="-O" >"$LOG" 2>&1 \
     && grep -q "All tests passed" "$LOG"; then
    echo "test.sh: make check: all $SUITE_TOTAL items passed" >&2
    (( PASSED += SUITE_TOTAL )) || true
  else
    echo "test.sh: 'make check' FAILED — tail:" >&2
    tail -40 "$LOG" >&2
    # make check is all-or-nothing; report the whole suite as failed.
    (( FAILED += SUITE_TOTAL )) || true
  fi
  rm -f "$LOG"
else
  echo "test.sh: no test-*.c found — skipping make check" >&2
fi

TOTAL=$(( PASSED + FAILED ))
emit_ctrf "mlib-check" "$PASSED" "$FAILED"
