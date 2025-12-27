# Быстрый старт

## Требования

- Ruby 2.7+ (только для компиляции)
- Linux x86-64 или Windows x64

## Установка

```bash
git clone https://github.com/example/juno
cd juno
```

## Hello World

Создайте файл `hello.juno`:

```juno
fn main(): int {
    print("Hello, World!")
    return 0
}
```

## Компиляция

### Linux

```bash
ruby main_linux.rb hello.juno
./build/output_linux
```

### Windows

```powershell
ruby main_native.rb hello.juno
.\build\output.exe
```

## Структура проекта

```
juno/
├── main_linux.rb       # Компилятор для Linux
├── main_native.rb      # Компилятор для Windows
├── src/                # Исходники компилятора
├── examples/           # Примеры программ
├── tests/              # Тесты
├── stdlib/             # Стандартная библиотека
└── build/              # Скомпилированные программы
```

## Следующие шаги

- [Синтаксис языка](syntax.md)
- [Встроенные функции](builtins.md)
- [Примеры](examples.md)
