@echo off
REM Quick build script for Juno compiler

if "%1"=="" (
    echo Usage: build.bat [file.juno]
    echo Example: build.bat demo_v1.juno
    exit /b 1
)

echo Compiling %1...
ruby main_native.rb %1

if %ERRORLEVEL% EQU 0 (
    echo.
    echo Build successful! Running...
    echo ================================
    build\output.exe
    echo ================================
    echo Exit code: %ERRORLEVEL%
) else (
    echo Build failed!
    exit /b 1
)
