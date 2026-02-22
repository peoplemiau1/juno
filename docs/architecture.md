# Системная архитектура Juno v2.1

## Обзор конвейера (Compiler Pipeline)

### 1. Фронтенд (Frontend)
- **Lexer**: Потоковая токенизация с поддержкой UTF-8. Генерирует поток токенов с метаданными о позиционировании.
- **Parser**: Рекурсивный нисходящий парсер. Реализует многопроходную обработку для поддержки forward-references. На выходе — типизированное AST.
- **Importer**: Рекурсивное разрешение зависимостей. Поддерживает относительные и системные пути.

### 2. Мидл-энд (Middle-end)
- **Monomorphizer**: Специализация generic-структур и функций. Разворачивает полиморфизм в конкретные реализации на этапе компиляции.
- **Resource Auditor**: Проверка графа владения (Ownership Graph). Гарантирует детерминированный жизненный цикл каждого выделенного блока памяти.
- **Turbo Optimizer**:
    - **Inlining**: Подстановка тел малых функций.
    - **CSE**: Elimination of common subexpressions.
    - **Simulator**: Compile-time evaluation of constant-bounded loops.

### 3. Бэкенд (Backend)
- **Register Allocator**: Алгоритм Linear Scan. Распределяет переменные по регистрам с учетом их времени жизни (Live ranges).
- **Native Generator**:
    - **ABI Compliance Layer**: Управление кадрами стека (Stack frames), выравниванием (Alignment) и сохранением контекста (Callee-saved regs).
    - **Instruction Emitter**: Прямая кодировка машинных команд (x86-64 и AArch64).
- **Metamorphic Engine**: Динамический мутатор байт-кода. Использует `X86Decoder` для безопасной инъекции junk-кода.

### 4. Линковка (Linker)
- **Symbol Resolution**: Сборка `.text`, `.data` и `.bss`.
- **Relocation Patching**: Финализация адресов функций, строк и глобальных переменных.
- **Post-Mutation Mapping**: Пересчет смещений после работы обфускатора.
