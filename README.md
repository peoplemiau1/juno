# Juno

Компилируемый язык для Linux. Генерирует нативные ELF x86-64.

## Установка

```bash
git clone https://github.com/peoplemiau1/juno.git
cd juno
./install.sh
source ~/.bashrc
```

## Использование

```bash
juno run hello.juno           # запустить
juno build hello.juno         # скомпилировать
juno build hello.juno -o app  # с именем
juno new project              # создать файл
```

## Пример

```juno
fn main(): int {
    print("Hello!")
    return 0
}
```

## Возможности

- Generics
- Структуры и методы
- TCP сокеты
- HTTPS (curl)
- Многопоточность
- Атомарные операции
- Системные вызовы Linux
- Обфускация (`--hell`)

## Документация

[DOCS.md](DOCS.md) - полная документация

## Лицензия

MIT
