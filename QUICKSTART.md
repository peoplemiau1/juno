# Juno - Быстрый старт

## Установка

```bash
git clone https://github.com/user/juno.git
cd juno
./install.sh
source ~/.bashrc
```

Теперь команда `juno` доступна из любой директории!

## Первая программа

```bash
juno new hello
```

Создаётся файл `hello.juno`:

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

```bash
juno build app.juno           # Компиляция
juno build app.juno -o myapp  # С именем
juno build app.juno --hell    # С обфускацией
juno run app.juno             # Компиляция + запуск
juno test                     # Все тесты
juno test simple              # Один тест
juno new myproject            # Новый файл
juno help                     # Справка
```

## Примеры кода

### Переменные

```juno
fn main(): int {
    let x = 10
    let y = 20
    let sum = x + y
    print_int(sum)
    return 0
}
```

### Функции

```juno
fn add(a: int, b: int): int {
    return a + b
}

fn main(): int {
    let result = add(5, 3)
    print_int(result)
    return 0
}
```

### Generics

```juno
fn identity<T>(x: T): T {
    return x
}

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

### Структуры

```juno
struct Point {
    x: int
    y: int
}

fn Point.init(px: int, py: int) {
    self.x = px
    self.y = py
}

fn main(): int {
    let p = Point
    p.init(3, 4)
    print_int(p.x)
    return 0
}
```

### Массивы

```juno
fn main(): int {
    let arr[5]
    arr[0] = 10
    arr[1] = 20
    print_int(arr[0])
    return 0
}
```

### Указатели

```juno
fn swap(a, b) {
    let temp = *a
    *a = *b
    *b = temp
}

fn main(): int {
    let x = 10
    let y = 20
    swap(&x, &y)
    print_int(x)  // 20
    return 0
}
```

### Циклы

```juno
fn main(): int {
    for (i = 0; i < 10; i++) {
        print_int(i)
    }
    
    let x = 0
    while (x < 5) {
        print_int(x)
        x++
    }
    return 0
}
```

## Hell Mode (Обфускация)

Защита от реверс-инжиниринга:

```bash
juno build secret.juno --hell
```

Включает:
- Полиморфные инструкции
- Anti-debug
- Мёртвый код
- Шифрование строк

## Встроенные функции

| Функция | Описание |
|---------|----------|
| `print(x)` | Вывод строки |
| `print_int(n)` | Вывод числа |
| `input()` | Ввод строки |
| `len(x)` | Длина |
| `alloc(n)` | Выделить память |
| `free(ptr, n)` | Освободить |
| `exit(code)` | Завершить |
| `sleep(ms)` | Пауза |
| `time()` | Unix timestamp |
| `rand()` | Случайное число |

## Сеть

```juno
fn main(): int {
    let sock = socket()
    bind(sock, 8080)
    listen(sock)
    let client = accept(sock)
    send(client, "Hello!")
    close(client)
    close(sock)
    return 0
}
```

## Тесты

```bash
juno test           # Все тесты
juno test simple    # Конкретный тест
```

## Примеры

```bash
juno run examples/echo_server.juno   # TCP сервер
juno run examples/client.juno        # TCP клиент
juno run examples/http_hello.juno    # HTTP сервер
juno run examples/hell_demo.juno --hell  # Обфускация
```

## Дальше

- [README.md](README.md) - Обзор
- [docs/syntax.md](docs/syntax.md) - Синтаксис
- [docs/builtins.md](docs/builtins.md) - Функции
- [docs/threading.md](docs/threading.md) - Потоки
