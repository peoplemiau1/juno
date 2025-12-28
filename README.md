# Juno

Компилируемый язык программирования для Linux и Windows. Генерирует нативные исполняемые файлы (ELF/PE) без внешних зависимостей.

## Возможности

- Компиляция в машинный код x86-64
- Generics (шаблоны)
- ООП со структурами и методами
- Указатели и ручное управление памятью
- Сокеты и многопоточность
- Обфускация кода (защита от реверса)

## Установка

```bash
git clone https://github.com/peoplemiau1/juno.git
cd juno
./install.sh
source ~/.bashrc
```

## Использование

```bash
juno build program.juno        # компиляция
juno run program.juno          # компиляция и запуск
juno build program.juno --hell # с обфускацией
```

## Пример

```juno
fn main(): int {
    print("Hello, World!")
    return 0
}
```

## Документация

- [Быстрый старт](QUICKSTART.md)
- [Синтаксис](docs/syntax.md)
- [Встроенные функции](docs/builtins.md)
- [Примеры](docs/examples.md)

## Лицензия

MIT
