# Быстрый старт

## 1. Установка

```bash
git clone https://github.com/peoplemiau1/juno.git
cd juno
./install.sh
source ~/.bashrc
```

## 2. Первая программа

Создай файл `hello.juno`:

```juno
fn main(): int {
    print("Hello!")
    return 0
}
```

Запусти:

```bash
juno run hello.juno
```

## 3. Команды

| Команда | Что делает |
|---------|-----------|
| `juno build file.juno` | Компилирует в `build/output` |
| `juno run file.juno` | Компилирует и запускает |
| `juno build file.juno -o name` | Компилирует в `build/name` |
| `juno build file.juno --hell` | Компилирует с обфускацией |
| `juno test` | Запускает тесты |
| `juno new name` | Создаёт новый файл |

## 4. Основы языка

### Переменные

```juno
let x = 10
let name = "Juno"
```

### Функции

```juno
fn add(a: int, b: int): int {
    return a + b
}

fn main(): int {
    let result = add(2, 3)
    print_int(result)
    return 0
}
```

### Условия

```juno
if (x > 0) {
    print("positive")
} else {
    print("not positive")
}
```

### Циклы

```juno
for (i = 0; i < 10; i++) {
    print_int(i)
}

while (x > 0) {
    x--
}
```

### Структуры

```juno
struct Point {
    x: int
    y: int
}

fn main(): int {
    let p = Point
    p.x = 10
    p.y = 20
    return 0
}
```

### Массивы

```juno
let arr[10]
arr[0] = 100
arr[1] = 200
```

### Указатели

```juno
let x = 10
let ptr = &x    // адрес x
let val = *ptr  // значение по адресу
*ptr = 20       // запись по адресу
```

### Generics

```juno
fn identity<T>(x: T): T {
    return x
}

let a = identity<int>(42)
```

## 5. Примеры

Смотри папку `examples/`:

```bash
juno run examples/echo_server.juno  # TCP сервер
juno run examples/client.juno       # TCP клиент
juno run examples/http_hello.juno   # HTTP сервер
```

## 6. Обфускация

Защита от реверс-инжиниринга:

```bash
juno build secret.juno --hell
```

Добавляет:
- Мусорный код
- Шифрование строк
- Анти-отладку
- Полиморфные инструкции
