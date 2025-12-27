# Juno v1.4

**Juno** — системный язык программирования с прямой компиляцией в нативный код (x86-64).

## Возможности

- **Нативная компиляция** — генерация PE (Windows) и ELF (Linux) без LLVM
- **Системное программирование** — прямой доступ к syscalls, памяти, сокетам
- **Препроцессор** — `#define`, `#ifdef`, `#ifndef`, `#endif`
- **Типизация** — `let x: int = 5`, `fn add(a: int, b: int): int`
- **Структуры и методы** — ООП-подобный синтаксис
- **Указатели** — `&x`, `*ptr`, арифметика указателей
- **Битовые операции** — `&`, `|`, `^`, `~`, `<<`, `>>`
- **Атомарные операции** — `atomic_add`, `spin_lock`
- **Сокеты** — TCP клиент/сервер

## Hello World

```juno
fn main(): int {
    print("Hello, World!")
    return 0
}
```

```bash
# Linux
ruby main_linux.rb examples/hello.juno
./build/output_linux

# Windows
ruby main_native.rb examples/hello.juno
build\output.exe
```

## Примеры

### Переменные и арифметика
```juno
fn main(): int {
    let x: int = 10
    let y: int = 3
    print(x + y)    // 13
    print(x * y)    // 30
    return 0
}
```

### Условия и циклы
```juno
fn factorial(n: int): int {
    let result = 1
    for (i = 1; i <= n; i++) {
        result = result * i
    }
    return result
}

fn main(): int {
    print(factorial(5))  // 120
    return 0
}
```

### Структуры
```juno
struct Point { x y }

fn Point.move(dx: int, dy: int): int {
    self.x = self.x + dx
    self.y = self.y + dy
    return 0
}

fn main(): int {
    let p = Point
    p.x = 10
    p.y = 20
    p.move(5, -3)
    print(p.x)  // 15
    return 0
}
```

### Указатели и массивы
```juno
fn main(): int {
    let arr[5]
    arr[0] = 100
    arr[1] = 200
    
    let ptr = &arr[0]
    print(*ptr)  // 100
    
    let ptr2 = ptr_add(ptr, 1)
    print(*ptr2)  // 200
    
    return 0
}
```

### Битовые операции
```juno
fn main(): int {
    let flags = 0
    flags = flags | (1 << 0)  // Set bit 0
    flags = flags | (1 << 2)  // Set bit 2
    
    let hex = 0xCAFE
    let bin = 0b11110000
    
    print(flags)  // 5
    print(hex)    // 51966
    print(bin)    // 240
    return 0
}
```

### Сокеты (TCP клиент)
```juno
fn main(): int {
    let sock = socket(2, 1, 0)  // AF_INET, SOCK_STREAM
    
    let addr = ip(127, 0, 0, 1)
    connect(sock, addr, 8080)
    
    let msg = "GET / HTTP/1.0\r\n\r\n"
    send(sock, msg, 18)
    
    let buf = getbuf()
    let n = recv(sock, buf, 1024)
    prints(buf)
    
    close(sock)
    return 0
}
```

### Сокеты (TCP сервер)
```juno
fn main(): int {
    let sock = socket(2, 1, 0)
    let addr = ip(0, 0, 0, 0)
    
    bind(sock, addr, 8888)
    listen(sock, 10)
    
    print("Listening on port 8888...")
    
    let client = accept(sock)
    print("Client connected!")
    
    let response = "HTTP/1.0 200 OK\r\n\r\nHello!"
    send(client, response, 30)
    
    close(client)
    close(sock)
    return 0
}
```

### Системные вызовы
```juno
fn main(): int {
    let pid = getpid()
    print("PID:")
    print(pid)
    
    let child = fork()
    if (child == 0) {
        print("Child process")
        exit(0)
    } else {
        wait(0)
        print("Child finished")
    }
    
    return 0
}
```

### Препроцессор
```juno
#define VERSION 1
#define BUFFER_SIZE 1024

#ifdef LINUX
#define PLATFORM "Linux"
#endif

fn main(): int {
    print("Version:")
    print(VERSION)
    return 0
}
```

## Встроенные функции

### I/O
| Функция | Описание |
|---------|----------|
| `print(x)` | Вывести число |
| `prints(s)` | Вывести строку |
| `read(fd, buf, n)` | Читать из файла |
| `write(fd, buf, n)` | Писать в файл |
| `open(path, flags)` | Открыть файл |
| `close(fd)` | Закрыть файл |

### Память
| Функция | Описание |
|---------|----------|
| `getbuf()` | Получить буфер 4KB |
| `mmap(...)` | Выделить память |
| `munmap(addr, len)` | Освободить память |
| `memset(ptr, val, n)` | Заполнить память |
| `memcpy(dst, src, n)` | Копировать память |

### Сокеты
| Функция | Описание |
|---------|----------|
| `socket(domain, type, proto)` | Создать сокет |
| `bind(sock, ip, port)` | Привязать к адресу |
| `listen(sock, backlog)` | Слушать соединения |
| `accept(sock)` | Принять соединение |
| `connect(sock, ip, port)` | Подключиться |
| `send(sock, buf, len)` | Отправить данные |
| `recv(sock, buf, len)` | Получить данные |
| `ip(a, b, c, d)` | Создать IP адрес |

### Процессы
| Функция | Описание |
|---------|----------|
| `fork()` | Создать процесс |
| `wait(status)` | Ждать дочерний |
| `exit(code)` | Завершить процесс |
| `getpid()` | Получить PID |
| `getppid()` | Получить PID родителя |
| `kill(pid, sig)` | Послать сигнал |

### Атомарные операции
| Функция | Описание |
|---------|----------|
| `atomic_add(ptr, val)` | Атомарное сложение |
| `atomic_sub(ptr, val)` | Атомарное вычитание |
| `spin_lock(ptr)` | Захватить spinlock |
| `spin_unlock(ptr)` | Освободить spinlock |

### Типы
| Функция | Описание |
|---------|----------|
| `i8(val)` | Привести к i8 |
| `u8(val)` | Привести к u8 |
| `i16(val)` | Привести к i16 |
| `u16(val)` | Привести к u16 |
| `i32(val)` | Привести к i32 |
| `u32(val)` | Привести к u32 |
| `ptr_add(ptr, n)` | ptr + n элементов |
| `ptr_sub(ptr, n)` | ptr - n элементов |
| `sizeof(type)` | Размер типа |

## Структура проекта

```
juno/
├── src/                    # Компилятор
│   ├── lexer.rb            # Лексер
│   ├── parser.rb           # Парсер
│   ├── preprocessor.rb     # Препроцессор
│   └── codegen/            # Генерация кода
├── examples/               # Примеры программ
│   ├── hello.juno          # Hello World
│   ├── calculator.juno     # Калькулятор
│   ├── arrays.juno         # Массивы
│   ├── structs.juno        # Структуры
│   ├── fibonacci.juno      # Фибоначчи
│   ├── primes.juno         # Простые числа
│   ├── tcp_client.juno     # TCP клиент
│   ├── tcp_server.juno     # TCP сервер
│   └── sysmon.juno         # Системный монитор
├── tests/                  # Тесты
├── stdlib/                 # Стандартная библиотека
├── build/                  # Артефакты сборки
├── main_linux.rb           # Компилятор (Linux)
└── main_native.rb          # Компилятор (Windows)
```

## Установка

Требуется только Ruby 2.7+:

```bash
git clone https://github.com/example/juno
cd juno
ruby main_linux.rb examples/hello.juno
./build/output_linux
```

## Лицензия

MIT
