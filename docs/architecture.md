# Архитектура компилятора Juno v2.1

## Конвейер компиляции
1.  **Preprocessor**: Обработка макросов и условий компиляции.
2.  **Lexer**: Токенизация с учетом позиций (line, column).
3.  **Parser**: Рекурсивный нисходящий парсер. Обрабатывает forward-references.
4.  **Importer**: Поиск и подстановка модулей `import`.
5.  **Monomorphizer**: Поддержка Generics через создание специализаций.
6.  **Resource Auditor**: Анализ графа владения и детекция утечек (E0007).
7.  **Turbo Optimizer**:
    *   Inlining
    *   CSE (Common Subexpression Elimination)
    *   Constant Propagation
    *   Simulator (Compile-time loop evaluation)
8.  **Register Allocator**: Linear Scan алгоритм для отображения переменных на регистры CPU.
9.  **Native Generator**:
    *   `CodeEmitter` (x86-64)
    *   `AArch64Emitter` (ARM64)
10. **Linker**: Сборка `.text`, `.data`, `.bss`. Патчинг адресов функций и меток.

## Особенности v2.1
*   **Регистры**: Juno использует callee-saved регистры для долгоживущих переменных и scratch-регистры для промежуточных вычислений.
*   **ABI**: Полное соответствие System V ABI (x86_64) и AArch64 ABI.
*   **Hell Mode**: Модуль `X86Decoder` гарантирует, что инъекция junk-кода не разрежет существующие инструкции.
