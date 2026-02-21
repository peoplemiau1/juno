# CHANGELOG

## v2.1 - 21.02.2026 "Architectural Integrity"

### Реестровое управление (Register Management)
- **Linear Scan Register Allocator**: Переменные теперь живут в регистрах (`RBX`, `R12-R15` для x86; `X19-X28` для ARM).
- **Preservation logic**: Корректное сохранение/восстановление callee-saved регистров.
- **Scratch Manager**: Безопасное управление временными регистрами.
- **16-byte Alignment**: Строгое выравнивание стека для соответствия System V ABI.

### Безопасность ресурсов (Ownership Audit)
- **ResourceAuditor**: Внедрена система отслеживания владения указателями (Born -> Kill).
- **Ошибка E0007**: Детекция утечек памяти и использования после освобождения (`use-after-free`) на этапе компиляции.

### Hell Mode v2.1 (Hardened)
- **Precise Decoder**: Внедрен полноценный декодер длин инструкций x86-64.
- **Linker Mapping**: Интеллектуальный патчинг смещений после инъекции junk-кода.

### Compiler UX & CLI
- **Structured Errors**: Ошибки теперь включают фрагменты кода, указатели и номера строк/колонок.
- **Unified CLI**: Новый интерфейс `juno` на базе OptionParser с поддержкой подсказок "Did you mean?".
- **Internal Error Handler**: Ruby-исключения теперь перехватываются и выводятся как красивые ICE (Internal Compiler Error).

### Стандартная библиотека v3
- `std/str`: Высокоуровневые строки.
- `std/vec`: Динамические векторы.
- `std/json`: Профессиональный JSON-парсер.
- `std/net`: TCP сервер и сетевые обертки.
- `std/arena`: Арена-аллокатор.
- `std/fs`: Высокоуровневая работа с файловой системой.

---

## v1.8 - 28.12.2025

### Упрощённый синтаксис
- **Ключевые слова функций**: `fn`, `func`, `def` - все работают
- **Опциональные скобки**: `if x > 5 {...}` и `while x < 10 {...}`
- Полная обратная совместимость

### Новые системные вызовы
- `memfd_create(name, flags)` - анонимный файл в RAM
- `lseek(fd, offset, whence)` - позиционирование в файле
- Константы: `MFD_CLOEXEC`, `MFD_ALLOW_SEALING`, `SEEK_SET`, `SEEK_CUR`, `SEEK_END`

### Turbo Optimizer
- Инлайнинг функций (<10 нод)
- Развёртка циклов (<8 итераций)
- Common Subexpression Elimination (CSE)
- Strength reduction: `x * 2` → `x << 1`
- Algebraic simplifications: `x - x` → `0`
- Константная пропагация

### Bulletproof Mode
- Автоматическое объявление переменных
- Функции без return автоматически возвращают 0
- Nil-safe генерация кода

### Исправления
- `str_to_int()` - исправлены jump offsets
- UTF-8 комментарии поддерживаются
- Добавлена поддержка `insertASM`

### Документация
- Обновлён README.md
- Обновлён DOCS.md с полным API
- 34 рабочих примера в `examples/`

---

## v1.7 - 28.12.2025

### Стандартная библиотека v2

#### Память (Heap)
- `malloc(size)`, `free(ptr)`, `realloc(ptr, size)`

#### String API
- `str_len`, `str_copy`, `str_cat`, `str_cmp`
- `str_find(s, sub)` - поиск подстроки
- `str_to_int` / `atoi`, `int_to_str` / `itoa`
- `str_upper`, `str_lower`, `str_trim`

#### File API
- `file_open(path, mode)` - режимы: 0=read, 1=write, 2=append
- `file_close`, `file_read`, `file_write`, `file_writeln`
- `file_read_all`, `file_exists`, `file_size`

#### Collections (Vector)
- `vec_new(capacity)`, `vec_push`, `vec_pop`
- `vec_get`, `vec_set`, `vec_len`, `vec_cap`, `vec_clear`

### HTTPS
- `curl_get(url)`, `curl_post(url, data)`

---

## v1.6 - 28.12.2025

### Generics
- Параметрический полиморфизм с мономорфизацией
- Generic функции: `fn identity<T>(x: T): T`
- Generic структуры: `struct Box<T> { value: T }`

### CLI интерфейс
- `juno build`, `juno run`, `juno test`, `juno new`
- Скрипт установки `install.sh`

### Hell Mode (Обфускация)
- Полиморфный генератор инструкций
- Anti-debug техники
- Шифрование строк
- Флаг `--hell`

---

## v1.5 - 27.12.2025

- Многопоточность (`thread_create`, `thread_join`)
- Атомарные операции
- Spinlock

---

## v1.3 - 26.12.2025

### Исправления
- Вызовы функций с 2+ аргументами

### Организация
- Тесты в `/tests`, примеры в `/examples`
- Создан `STRUCTURE.md`

---

## v1.2 и ранее

- 26.12.2024: Переработка codegen
- 27.12.2024: include и insertC
- 04.03.2025: Нативная генерация кода
