# Начало работы

## Требования

- Ruby 2.7 или новее
- Linux x64 или Windows x64

## Установка

### Вариант 1: С CLI (рекомендуется)

```bash
git clone https://github.com/peoplemiau1/juno.git
cd juno
./install.sh
source ~/.bashrc
```

После этого команда `juno` доступна из любой папки.

### Вариант 2: Без установки

```bash
git clone https://github.com/peoplemiau1/juno.git
cd juno

# Linux
ruby main_linux.rb program.juno
./build/output_linux

# Windows
ruby main_native.rb program.juno
build\output.exe
```

## Первая программа

Создай `hello.juno`:

```juno
fn main(): int {
    print("Hello, Juno!")
    return 0
}
```

Запусти:

```bash
juno run hello.juno
```

Вывод:
```
Hello, Juno!
```

## Структура проекта

```
juno/
├── juno              # CLI утилита
├── install.sh        # Установщик
├── main_linux.rb     # Компилятор для Linux
├── main_native.rb    # Компилятор для Windows
├── src/              # Исходники компилятора
├── examples/         # Примеры программ
├── tests/            # Тесты
├── stdlib/           # Стандартная библиотека
└── build/            # Скомпилированные программы
```

## Что дальше

1. [Синтаксис языка](syntax.md) — переменные, функции, структуры
2. [Встроенные функции](builtins.md) — ввод/вывод, память, строки
3. [Примеры](examples.md) — готовые программы
