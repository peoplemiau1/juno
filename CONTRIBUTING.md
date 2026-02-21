# Contributing to Juno

Thank you for your interest in contributing to Juno! This document provides guidelines for contributing to the compiler, standard library, and documentation.

## Code of Conduct

Please be respectful and professional in all interactions. Juno is a community project, and we value helpful, constructive feedback.

## How to Contribute

### 1. Reporting Bugs

If you find a bug, please open an issue with:
- A clear description of the problem.
- A minimal reproducible example (`.juno` file).
- The compiler version and architecture (x86_64 or AArch64).
- Expected vs. actual behavior.

### 2. Standard Library

The standard library is located in `stdlib/`. New modules should follow the naming convention `stdlib/std/<module>.juno`.
- Use descriptive function names.
- Ensure proper resource management (Born -> Kill).
- Add tests for new library features in `tests/`.

### 3. Compiler Development

Juno is written in Ruby. Key components:
- `src/lexer.rb`: Tokenizer.
- `src/parser.rb`: Recursive descent parser.
- `src/analyzer/`: Semantic analysis and Resource Auditor.
- `src/codegen/`: Native code generation.
- `src/optimizer/`: Turbo optimizer and Register Allocator.

When modifying the compiler:
- Ensure 16-byte stack alignment for all generated code.
- Update `X86Decoder` if adding new opcodes that might be obfuscated.
- Run the test suite: `./test.sh`.

## Coding Style

### Juno Code
- Use `let` for explicit declarations.
- Prefer register-based locals (avoid `&var` where possible for speed).
- Clean up all allocated memory with `free()` or use `Arena`.

### Ruby Code
- Follow standard Ruby idioms.
- Add comments for complex assembly generation logic.
- Use structured errors (`JunoError`) for user-facing messages.

## Pull Request Process

1. Create a new branch for your feature or bugfix.
2. Add tests covering your changes.
3. Ensure all tests pass: `./test.sh`.
4. Update relevant documentation (`DOCS.md`, `README.md`).
5. Submit the PR with a clear description of changes.

## License

By contributing, you agree that your contributions will be licensed under the MIT License.
