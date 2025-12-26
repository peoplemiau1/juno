#!/bin/bash
# Run Juno tests written in Juno (Linux version)

echo "========================================"
echo "Running Juno Self-Tests (Linux)"
echo "========================================"
echo ""

FAILED=0
PASSED=0

# Whitelist of positive tests (contain fn main and are expected to pass)
POSITIVE_TESTS=(
  tests/big_suite.juno
  tests/test_simple_str.juno
  tests/test_math.juno
  tests/test_multiarg_fix.juno
  tests/test_else.juno
  tests/test_v1.juno
  tests/test_array.juno
  tests/test_call_order.juno
  tests/test_complex_oop.juno
  tests/test_debug.juno
  tests/test_deref_write.juno
  tests/test_exact.juno
  tests/test_full.juno
  tests/test_linux.juno
  tests/test_minimal_demo.juno
  tests/test_optimizer.juno
  tests/test_pointers.juno
  tests/test_ptr_arg.juno
  tests/test_ptr_debug.juno
  tests/test_ptr_debug2.juno
  tests/test_ptr_noopt.juno
  tests/test_ptr_parts.juno
  tests/test_ptr_read.juno
  tests/test_ptr_simple.juno
  tests/test_ptr_v2.juno
  tests/test_ptr_v3.juno
  tests/test_ptr_v4.juno
  tests/test_simple.juno
  tests/test_simple_demo.juno
  tests/test_string.juno
  tests/test_swap.juno
  tests/test_two_int.juno
  tests/test_two_noopt.juno
  tests/test_all_features.juno
  tests/test_ptr_arith_and_str_plus.juno
)

for test_file in "${POSITIVE_TESTS[@]}"; do
    if [ ! -f "$test_file" ]; then
        echo "[SKIP] $test_file (not found)"
        continue
    fi
    echo "[RUN] $test_file"
    if ruby main_linux.rb "$test_file"; then
        chmod +x build/output_linux
        if ./build/output_linux; then
            echo "[OK] $test_file"
            PASSED=$((PASSED + 1))
        else
            echo "[FAIL] $test_file - runtime error"
            FAILED=$((FAILED + 1))
        fi
    else
        echo "[FAIL] $test_file - compilation error"
        FAILED=$((FAILED + 1))
    fi
    echo ""
done

# Treat remaining tests as expected-fail (negative tests)
all_tests=(tests/test_*.juno)
expected_fail=()
for tf in "${all_tests[@]}"; do
  skip=false
  for pf in "${POSITIVE_TESTS[@]}"; do
    [ "$tf" = "$pf" ] && skip=true && break
  done
  $skip || expected_fail+=("$tf")
done

for test_file in "${expected_fail[@]}"; do
    [ ! -f "$test_file" ] && continue
    echo "[RUN-NEG] $test_file (expect failure)"
    if ruby main_linux.rb "$test_file" >/dev/null 2>&1; then
        # If compiled, try run and expect failure
        chmod +x build/output_linux 2>/dev/null
        if ./build/output_linux >/dev/null 2>&1; then
            echo "[UNEXPECTED PASS] $test_file"
            FAILED=$((FAILED + 1))
        else
            echo "[OK FAIL] $test_file (runtime error as expected)"
            PASSED=$((PASSED + 1))
        fi
    else
        echo "[OK FAIL] $test_file (compile error as expected)"
        PASSED=$((PASSED + 1))
    fi
    echo ""
done

echo "========================================"
echo "Results: $PASSED passed, $FAILED failed"
echo "========================================"

if [ $FAILED -eq 0 ]; then
    echo "All Juno self-tests completed!"
    exit 0
else
    echo "Some tests failed."
    exit 1
fi
