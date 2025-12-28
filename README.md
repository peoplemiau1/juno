# Juno v1.6

**Juno** — системный язык программирования с прямой компиляцией в машинный код x86-64.

## Особенности

- **Нативная компиляция** — PE (Windows) и ELF (Linux) без LLVM
- **Generics** — параметрический полиморфизм с мономорфизацией
- **Hell Mode** — полиморфная обфускация для защиты от реверс-инжиниринга
- **CLI** — удобный интерфейс командной строки
- **Системное программирование** — syscalls, память, сокеты, потоки
- **Минимализм** — только Ruby для сборки компилятора

## Быстрый старт

### Установка

```bash
git clone https://github.com/user/juno.git
cd juno
./install.sh
source ~/.bashrc
```

### Hello World

```juno
fn main(): int {
    print("Hello, World!")
    return 0
}
```

```bash
juno run hello.juno
```

## CLI Команды

| Команда | Описание |
|---------|----------|
| `juno build <file>` | Компиляция в бинарник |
| `juno run <file>` | Компиляция и запуск |
| `juno test` | Запуск всех тестов |
| `juno new <name>` | Создать новый файл |
| `juno help` | Справка |

### Опции компиляции

```bash
juno build app.juno -o myapp      # Имя выходного файла
juno build app.juno --hell        # Максимальная обфускация
juno build app.juno --obfuscate   # Стандартная обфускация
```

## Generics

```juno
// Generic функция
fn identity<T>(x: T): T {
    return x
}

// Generic структура
struct Box<T> {
    value: T
}

fn main(): int {
    let num = identity<int>(42)
    let b = Box<int>
    b.value = 100
    return 0
}
```

## Hell Mode (Anti-Reverse-Engineering)

```bash
juno build secret.juno --hell
```

Включает:
- Полиморфные инструкции (разный машинный код каждый раз)
- Anti-debug (ptrace detection, timing checks)
- Мёртвый код и opaque predicates
- Шифрование строк

## Документация

| Документ | Описание |
|----------|----------|
| [Быстрый старт](docs/getting-started.md) | Установка и первая программа |
| [Синтаксис](docs/syntax.md) | Переменные, функции, структуры, generics |
| [Встроенные функции](docs/builtins.md) | I/O, строки, память |
| [Системные вызовы](docs/syscalls.md) | Процессы, файлы, сокеты |
| [Многопоточность](docs/threading.md) | Потоки, атомики, мьютексы |
| [Примеры](docs/examples.md) | Готовые программы |

## Примеры

```
examples/
├── hello.juno          # Hello World
├── echo_server.juno    # Echo TCP сервер
├── client.juno         # TCP клиент
├── http_hello.juno     # HTTP сервер
├── hell_demo.juno      # Демо обфускации
└── junofetch.juno      # Системная информация
```

## Лицензия

MIT
