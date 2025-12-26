#!/bin/bash
# Build script for Juno (Linux)

set -e

echo "Building Juno program..."

# Compile Juno to assembly
ruby main_linux.rb "$1"

# Assemble and link
nasm -f elf64 build/output.asm -o build/output.o
ld build/output.o -o build/output

echo "Build complete: build/output"
