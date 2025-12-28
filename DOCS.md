# Juno - Документация

## Содержание

1. [Установка](#установка)
2. [Команды CLI](#команды-cli)
3. [Синтаксис](#синтаксис)
4. [Встроенные функции](#встроенные-функции)
5. [Сетевое программирование](#сетевое-программирование)
6. [Многопоточность](#многопоточность)
7. [Системные вызовы](#системные-вызовы)
8. [Обфускация](#обфускация)
9. [Примеры](#примеры)

---

## Установка

```bash
git clone https://github.com/peoplemiau1/juno.git
cd juno
./install.sh
source ~/.bashrc
```

Требования: Ruby 2.7+, Linux x86-64

---

## Команды CLI

```bash
juno run <file>           # Запустить программу
juno build <file>         # Скомпилировать в бинарник
juno build <file> -o name # Скомпилировать с именем
juno new <name>           # Создать новый файл
juno test                 # Запустить тесты
juno help                 # Справка
```

Опции:
- `--hell` - включить обфускацию

---

## Синтаксис

### Переменные

```juno
let x = 10
let name = "hello"
let arr[5]              // массив из 5 элементов
```

### Функции

```juno
fn add(a: int, b: int): int {
    return a + b
}

fn main(): int {
    let sum = add(10, 20)
    print(sum)
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
    let a = identity<int>(42)
    let b = identity<string>("hello")
    return 0
}
```

### Структуры

```juno
struct Point {
    x: int
    y: int
}

fn Point.move(dx: int, dy: int) {
    self.x = self.x + dx
    self.y = self.y + dy
}

fn main(): int {
    let p = Point
    p.x = 10
    p.y = 20
    p.move(5, 5)
    return 0
}
```

### Условия

```juno
if (x > 0) {
    print("positive")
} else if (x < 0) {
    print("negative")
} else {
    print("zero")
}
```

### Циклы

```juno
// while
let i = 0
while (i < 10) {
    print(i)
    i++
}

// for
for (i = 0; i < 10; i++) {
    print(i)
}
```

### Указатели

```juno
let x = 10
let ptr = &x      // адрес
let val = *ptr    // разыменование
*ptr = 20         // запись
```

### Массивы

```juno
let arr[10]
arr[0] = 100
let ptr = &arr[0]
```

### Операторы

```
+  -  *  /        // арифметика
== != < > <= >=   // сравнение
&& ||             // логика
& | ^ ~ << >>     // битовые
```

---

## Встроенные функции

### Ввод/Вывод

| Функция | Описание |
|---------|----------|
| `print(x)` | Вывести число |
| `prints(s)` | Вывести строку |
| `read(fd, buf, n)` | Читать из файла |
| `write(fd, buf, n)` | Писать в файл |
| `open(path, flags)` | Открыть файл |
| `close(fd)` | Закрыть файл |
| `getbuf()` | Получить буфер 4KB |
| `input()` | Читать строку с stdin |

### Строки

| Функция | Описание |
|---------|----------|
| `len(s)` | Длина строки |
| `concat(a, b)` | Объединить строки |
| `substr(s, start, len)` | Подстрока |
| `chr(code)` | Символ по коду |
| `ord(char)` | Код символа |
| `str_len(s)` | Длина строки |
| `str_copy(dst, src)` | Копировать строку |
| `str_cat(dst, src)` | Конкатенация на месте |
| `str_cmp(a, b)` | Сравнить (0 = равны) |
| `str_find(s, sub)` | Найти подстроку (-1 если нет) |
| `str_to_int(s)` / `atoi(s)` | Строка в число |
| `int_to_str(n)` / `itoa(n)` | Число в строку |
| `str_upper(s)` | В верхний регистр |
| `str_lower(s)` | В нижний регистр |
| `str_trim(s)` | Убрать пробелы |

### Память (Heap)

| Функция | Описание |
|---------|----------|
| `malloc(size)` | Выделить память |
| `free(ptr)` | Освободить память |
| `realloc(ptr, size)` | Изменить размер |
| `heap_init(size)` | Инициализировать кучу |

### Память (Low-level)

| Функция | Описание |
|---------|----------|
| `mmap(addr, len, prot, flags, fd, off)` | Выделить страницы |
| `munmap(addr, len)` | Освободить страницы |
| `memset(ptr, val, n)` | Заполнить память |
| `memcpy(dst, src, n)` | Копировать память |

### Файлы

| Функция | Описание |
|---------|----------|
| `file_open(path, mode)` | Открыть (0=read, 1=write, 2=append) |
| `file_close(fd)` | Закрыть |
| `file_read(fd, buf, size)` | Читать |
| `file_write(fd, buf, size)` | Писать |
| `file_writeln(fd, str)` | Писать строку + \\n |
| `file_read_all(path)` | Прочитать весь файл |
| `file_exists(path)` | Файл существует? (1/0) |
| `file_size(path)` | Размер файла |

### Коллекции (Vector)

| Функция | Описание |
|---------|----------|
| `vec_new(cap)` | Создать вектор |
| `vec_push(v, val)` | Добавить в конец |
| `vec_pop(v)` | Удалить и вернуть последний |
| `vec_get(v, i)` | Получить по индексу |
| `vec_set(v, i, val)` | Установить по индексу |
| `vec_len(v)` | Длина |
| `vec_cap(v)` | Ёмкость |
| `vec_clear(v)` | Очистить |

### Математика

| Функция | Описание |
|---------|----------|
| `abs(x)` | Модуль |
| `min(a, b)` | Минимум |
| `max(a, b)` | Максимум |
| `rand()` | Случайное число |
| `time()` | Unix timestamp |

### Типы

| Функция | Описание |
|---------|----------|
| `i8(x)` `u8(x)` | 8-бит |
| `i16(x)` `u16(x)` | 16-бит |
| `i32(x)` `u32(x)` | 32-бит |
| `sizeof(type)` | Размер типа |

### Указатели

| Функция | Описание |
|---------|----------|
| `ptr_add(ptr, n)` | ptr + n |
| `ptr_sub(ptr, n)` | ptr - n |
| `ptr_diff(a, b)` | a - b |

### Константы

```juno
PROT_READ()      // 1
PROT_WRITE()     // 2
PROT_EXEC()      // 4
MAP_PRIVATE()    // 2
MAP_ANONYMOUS()  // 32
SIGTERM()        // 15
SIGKILL()        // 9
SIGINT()         // 2
```

---

## Сетевое программирование

### Функции

| Функция | Описание |
|---------|----------|
| `socket(domain, type, proto)` | Создать сокет |
| `bind(sock, ip, port)` | Привязать к адресу |
| `listen(sock, backlog)` | Слушать |
| `accept(sock)` | Принять соединение |
| `connect(sock, ip, port)` | Подключиться |
| `send(sock, buf, len)` | Отправить |
| `recv(sock, buf, len)` | Получить |
| `ip(a, b, c, d)` | Создать IP |
| `curl_get(url)` | HTTP GET запрос |
| `curl_post(url, data)` | HTTP POST запрос |

### Константы сокетов

```juno
// domain
AF_INET = 2      // IPv4

// type  
SOCK_STREAM = 1  // TCP
SOCK_DGRAM = 2   // UDP
```

### TCP Сервер

```juno
fn main(): int {
    let sock = socket(2, 1, 0)
    bind(sock, ip(0,0,0,0), 8080)
    listen(sock, 10)
    
    let client = accept(sock)
    send(client, "Hello!", 6)
    close(client)
    close(sock)
    return 0
}
```

### TCP Клиент

```juno
fn main(): int {
    let sock = socket(2, 1, 0)
    connect(sock, ip(127,0,0,1), 8080)
    
    send(sock, "Hi", 2)
    
    let buf = getbuf()
    recv(sock, buf, 4096)
    prints(buf)
    
    close(sock)
    return 0
}
```

### HTTPS (через curl)

```juno
fn main(): int {
    // GET запрос
    let response = curl_get("https://api.example.com/data")
    prints(response)
    
    // POST запрос с JSON
    let data = "{\"key\":\"value\"}"
    let result = curl_post("https://api.example.com/post", data)
    prints(result)
    
    return 0
}
```

### Telegram Bot

```juno
fn send_telegram(token: string, chat_id: string, text: string) {
    let url = concat("https://api.telegram.org/bot", token)
    let url2 = concat(url, "/sendMessage")
    
    let body1 = concat("{\"chat_id\":\"", chat_id)
    let body2 = concat(body1, "\",\"text\":\"")
    let body3 = concat(body2, text)
    let body = concat(body3, "\"}")
    
    curl_post(url2, body)
}

fn main(): int {
    let token = "123456:ABC-DEF..."
    let chat = "987654321"
    
    send_telegram(token, chat, "Hello from Juno!")
    return 0
}
```

---

## Многопоточность

### Функции

| Функция | Описание |
|---------|----------|
| `thread_create(fn, stack, arg)` | Создать поток |
| `thread_exit(code)` | Завершить поток |
| `alloc_stack(size)` | Стек для потока |
| `sleep(sec)` | Пауза (секунды) |
| `usleep(usec)` | Пауза (микросекунды) |

### Атомарные операции

| Функция | Описание |
|---------|----------|
| `atomic_add(ptr, val)` | Атомарное + |
| `atomic_sub(ptr, val)` | Атомарное - |
| `atomic_load(ptr)` | Атомарное чтение |
| `atomic_store(ptr, val)` | Атомарная запись |
| `atomic_cas(ptr, old, new)` | Compare-and-swap |

### Spinlock

| Функция | Описание |
|---------|----------|
| `spin_lock(ptr)` | Захватить |
| `spin_unlock(ptr)` | Освободить |

### Пример

```juno
fn worker(arg: int): int {
    print(arg)
    return 0
}

fn main(): int {
    let stack = alloc_stack(65536)
    let tid = thread_create(&worker, stack, 42)
    sleep(1)
    return 0
}
```

---

## Системные вызовы

### Процессы

| Функция | Описание |
|---------|----------|
| `fork()` | Создать процесс |
| `exit(code)` | Завершить |
| `wait(status)` | Ждать потомка |
| `getpid()` | PID |
| `getppid()` | PID родителя |
| `getuid()` | UID |
| `getgid()` | GID |
| `kill(pid, sig)` | Сигнал |
| `execve(path, argv, env)` | Запустить программу |

### Файлы

| Функция | Описание |
|---------|----------|
| `mkdir(path, mode)` | Создать папку |
| `rmdir(path)` | Удалить папку |
| `unlink(path)` | Удалить файл |
| `chmod(path, mode)` | Права |
| `chdir(path)` | Сменить папку |
| `getcwd(buf, size)` | Текущая папка |

### Каналы

| Функция | Описание |
|---------|----------|
| `pipe(fds)` | Создать pipe |
| `dup(fd)` | Дублировать fd |
| `dup2(old, new)` | Дублировать в new |

---

## Обфускация

Hell Mode - защита от реверс-инжиниринга:

```bash
juno build secret.juno --hell
```

Что делает:
- Мусорный код между инструкциями
- Шифрование строк
- Anti-debug (ptrace detection)
- Полиморфные инструкции
- Opaque predicates

---

## Примеры

### Hello World

```juno
fn main(): int {
    print("Hello, World!")
    return 0
}
```

### Факториал

```juno
fn factorial(n: int): int {
    if (n <= 1) {
        return 1
    }
    return n * factorial(n - 1)
}

fn main(): int {
    print(factorial(5))  // 120
    return 0
}
```

### Числа Фибоначчи

```juno
fn fib(n: int): int {
    if (n < 2) {
        return n
    }
    return fib(n-1) + fib(n-2)
}

fn main(): int {
    for (i = 0; i < 10; i++) {
        print(fib(i))
    }
    return 0
}
```

### Linked List

```juno
struct Node {
    value: int
    next: ptr
}

fn main(): int {
    let a = Node
    let b = Node
    let c = Node
    
    a.value = 1
    a.next = &b
    
    b.value = 2
    b.next = &c
    
    c.value = 3
    c.next = 0
    
    let cur = &a
    while (cur != 0) {
        let node = *cur
        print(node.value)
        cur = node.next
    }
    
    return 0
}
```

### HTTP Сервер

```juno
fn main(): int {
    let sock = socket(2, 1, 0)
    bind(sock, ip(0,0,0,0), 8080)
    listen(sock, 10)
    
    print("Server on :8080")
    
    while (1) {
        let client = accept(sock)
        
        let response = "HTTP/1.0 200 OK\r\n\r\nHello from Juno!"
        send(client, response, 38)
        
        close(client)
    }
    
    return 0
}
```

### Echo Server

```juno
fn main(): int {
    let sock = socket(2, 1, 0)
    bind(sock, ip(0,0,0,0), 9000)
    listen(sock, 10)
    
    while (1) {
        let client = accept(sock)
        let buf = getbuf()
        
        let n = recv(client, buf, 4096)
        if (n > 0) {
            send(client, buf, n)
        }
        
        close(client)
    }
    
    return 0
}
```

---

## Обновление

```bash
cd ~/juno && git pull
```

## Удаление

```bash
./uninstall.sh
rm -rf ~/juno
```
