#!/bin/bash
echo "Running Juno tests..."
FAILED=0
PASSED=0

for test_file in tests/test_*.juno; do
    if [[ "$test_file" == *"test_flat_binary.juno"* ]]; then continue; fi

    # Expected failure tests
    EXPECT_FAIL=0
    if [[ "$test_file" == *"test_error.juno"* || "$test_file" == *"test_syntax_error.juno"* ]]; then
        EXPECT_FAIL=1
    fi

    echo -n "Testing $test_file... "
    if ./juno "$test_file" > /dev/null 2>&1; then
        if [ "$EXPECT_FAIL" -eq 1 ]; then
            echo "[FAIL] Expected compilation error but it passed"
            FAILED=$((FAILED + 1))
        elif ./build/output_x86_64 > /dev/null 2>&1; then
            echo "[OK]"
            PASSED=$((PASSED + 1))
        else
            echo "[FAIL] Runtime error (Exit code: $?)"
            FAILED=$((FAILED + 1))
        fi
    else
        if [ "$EXPECT_FAIL" -eq 1 ]; then
            echo "[OK] (Expected failure)"
            PASSED=$((PASSED + 1))
        else
            echo "[FAIL] Compilation error"
            FAILED=$((FAILED + 1))
        fi
    fi
done

echo ""
echo "Results: $PASSED passed, $FAILED failed"
if [ $FAILED -eq 0 ]; then exit 0; else exit 1; fi
