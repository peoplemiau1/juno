# Juno v1.5

**Juno** — системный язык программирования с прямой компиляцией в машинный код x86-64.

## Особенности

- **Нативная компиляция** — PE (Windows) и ELF (Linux) без LLVM
- **Системное программирование** — syscalls, память, сокеты, потоки
- **Минимализм** — только Ruby для сборки компилятора
- **Низкий уровень** — указатели, битовые операции, атомики

## Быстрый старт

```juno
fn main(): int {
    print("Hello, World!")
    return 0
}
```

```bash
# Linux
ruby main_linux.rb hello.juno && ./build/output_linux

# Windows
ruby main_native.rb hello.juno && build\output.exe
```

## Документация

| Документ | Описание |
|----------|----------|
| [Быстрый старт](docs/getting-started.md) | Установка и первая программа |
| [Синтаксис](docs/syntax.md) | Переменные, функции, структуры |
| [Встроенные функции](docs/builtins.md) | I/O, строки, память |
| [Системные вызовы](docs/syscalls.md) | Процессы, файлы, сокеты |
| [Многопоточность](docs/threading.md) | Потоки, атомики, мьютексы |
| [Примеры](docs/examples.md) | Готовые программы |

## Примеры программ

```
examples/
├── hello.juno          # Hello World
├── calculator.juno     # Калькулятор
├── arrays.juno         # Массивы
├── fibonacci.juno      # Фибоначчи
├── tcp_server.juno     # TCP сервер
├── httpd.juno          # HTTP сервер
└── sysmon.juno         # Системный монитор
```

## Лицензия

MIT
