@echo off
REM Run all tests

echo Running Juno tests...
echo.

set FAILED=0

for %%f in (tests\test_*.juno) do (
    echo Testing %%f...
    ruby main_native.rb %%f > nul 2>&1
    if %ERRORLEVEL% EQU 0 (
        build\output.exe > nul 2>&1
        if %ERRORLEVEL% EQU 0 (
            echo [OK] %%f
        ) else (
            echo [FAIL] %%f - Runtime error
            set FAILED=1
        )
    ) else (
        echo [FAIL] %%f - Compilation error
        set FAILED=1
    )
)

echo.
if %FAILED% EQU 0 (
    echo All tests passed!
) else (
    echo Some tests failed!
    exit /b 1
)
