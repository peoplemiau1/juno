#!/bin/bash
# Run all Juno tests (Linux)

echo "Running Juno tests..."
echo ""

FAILED=0
PASSED=0

for test_file in tests/test_*.juno; do
    # Skip tests that are not for Linux
    if [[ "$test_file" == *"test_flat_binary.juno"* ]]; then
        continue
    fi

    echo "Testing $test_file..."
    
    if ruby main_linux.rb "$test_file" > /dev/null 2>&1; then
        if ./build/output_linux > /dev/null 2>&1; then
            echo "[OK] $test_file"
            PASSED=$((PASSED + 1))
        else
            echo "[FAIL] $test_file - Runtime error"
            FAILED=$((FAILED + 1))
        fi
    else
        echo "[FAIL] $test_file - Compilation error"
        FAILED=$((FAILED + 1))
    fi
done

echo ""
echo "Results: $PASSED passed, $FAILED failed"

if [ $FAILED -eq 0 ]; then
    echo "All tests passed!"
    exit 0
else
    echo "Some tests failed!"
    exit 1
fi
