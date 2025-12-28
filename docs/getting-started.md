# Быстрый старт

## Требования

- Ruby 2.7+
- Linux x86-64 или Windows x64

## Установка

```bash
git clone https://github.com/user/juno
cd juno
./install.sh
source ~/.bashrc
```

Теперь команда `juno` доступна глобально!

## Hello World

```bash
juno new hello
```

Создаётся `hello.juno`:

```juno
fn main(): int {
    print("Hello, Juno!")
    return 0
}
```

Запуск:

```bash
juno run hello.juno
```

## CLI Команды

| Команда | Описание |
|---------|----------|
| `juno build <file>` | Компиляция |
| `juno run <file>` | Компиляция и запуск |
| `juno test` | Запуск тестов |
| `juno new <name>` | Новый файл |
| `juno help` | Справка |

### Опции

```bash
juno build app.juno -o myapp    # Имя выходного файла
juno build app.juno --hell      # Обфускация
```

## Альтернативный способ (без CLI)

```bash
# Linux
ruby main_linux.rb hello.juno
./build/output_linux

# Windows
ruby main_native.rb hello.juno
.\build\output.exe
```

## Структура проекта

```
juno/
├── juno                # CLI
├── install.sh          # Установщик
├── main_linux.rb       # Компилятор Linux
├── main_native.rb      # Компилятор Windows
├── src/                # Исходники компилятора
│   ├── polymorph/      # Обфускация
│   └── monomorphizer.rb # Generics
├── examples/           # Примеры
├── tests/              # Тесты
└── build/              # Бинарники
```

## Следующие шаги

- [Синтаксис](syntax.md) - переменные, функции, generics
- [Встроенные функции](builtins.md) - I/O, память
- [Примеры](examples.md) - готовые программы
