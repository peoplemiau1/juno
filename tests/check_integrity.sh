#!/bin/bash
# check_integrity.sh - Regression suite for Juno compiler

EXAMPLES_DIR="examples"
BUILD_DIR="build"
mkdir -p $BUILD_DIR

FAILED=0
PASSED=0

echo "Starting Integrity Check..."

for f in $EXAMPLES_DIR/*.juno; do
    name=$(basename "$f" .juno)
    echo -n "Testing $name... "

    # Try to compile
    ./juno "$f" -o "$BUILD_DIR/$name" > /dev/null 2>&1
    if [ $? -ne 0 ]; then
        echo "FAILED (Compilation)"
        FAILED=$((FAILED + 1))
        continue
    fi

    # Run if it's a simple example (no network/loop)
    case "$name" in
        hello|math|gcd|fibonacci|primes|arrays|structs|geometry)
            ./"$BUILD_DIR/$name" > /dev/null 2>&1
            if [ $? -eq 0 ]; then
                echo "PASSED"
                PASSED=$((PASSED + 1))
            else
                echo "FAILED (Runtime)"
                FAILED=$((FAILED + 1))
            fi
            ;;
        *)
            echo "PASSED (Compiled only)"
            PASSED=$((PASSED + 1))
            ;;
    esac
done

echo "------------------------"
echo "Tests Passed: $PASSED"
echo "Tests Failed: $FAILED"

if [ $FAILED -eq 0 ]; then
    exit 0
else
    exit 1
fi
