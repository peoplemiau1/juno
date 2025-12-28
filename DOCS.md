# Juno v1.8 - Документация

## Содержание

1. [Установка](#установка)
2. [Синтаксис](#синтаксис)
3. [Встроенные функции](#встроенные-функции)
4. [Сеть и HTTP](#сеть-и-http)
5. [Системные вызовы](#системные-вызовы)
6. [Многопоточность](#многопоточность)
7. [Оптимизатор](#оптимизатор)
8. [Обфускация](#обфускация)
9. [Примеры](#примеры)

---

## Установка

```bash
git clone https://github.com/peoplemiau1/juno.git
cd juno && ./install.sh && source ~/.bashrc
```

**CLI:**
```bash
juno run file.juno          # запустить
juno build file.juno -o app # скомпилировать
juno build file.juno --hell # с обфускацией
juno new name               # создать файл
```

---

## Синтаксис

### Функции

```juno
// Три способа объявить функцию:
fn add(a: int, b: int): int { return a + b }
func add(a: int, b: int): int { return a + b }
def add(a: int, b: int): int { return a + b }
```

### Переменные

```juno
x = 10              // простое присваивание
let y = 20          // с let (опционально)
let arr[5]          // массив
```

### Условия и циклы

```juno
// Скобки опциональны:
if x > 5 { ... }
if (x > 5) { ... }    // тоже работает

while x < 10 { x = x + 1 }
while (x < 10) { ... } // тоже работает

for (i = 0; i < 10; i++) { ... }
```

### Указатели

```juno
ptr = &x        // адрес
val = *ptr      // разыменование
*ptr = 100      // запись по адресу
```

### Структуры

```juno
struct Point { x: int, y: int }

fn Point.move(dx: int, dy: int) {
    self.x = self.x + dx
}

fn main(): int {
    p = Point
    p.x = 10
    p.move(5, 0)
    return 0
}
```

### Generics

```juno
fn identity<T>(x: T): T { return x }

struct Box<T> { value: T }
```

---

## Встроенные функции

### I/O

| Функция | Описание |
|---------|----------|
| `print(n)` | Вывести число |
| `prints(s)` | Вывести строку |
| `input()` | Читать строку |
| `read(fd, buf, n)` | Читать из fd |
| `write(fd, buf, n)` | Писать в fd |
| `open(path, flags)` | Открыть файл |
| `close(fd)` | Закрыть fd |
| `getbuf()` | Буфер 4KB |

### Строки

| Функция | Описание |
|---------|----------|
| `str_len(s)` | Длина |
| `concat(a, b)` | Объединить |
| `str_find(s, sub)` | Найти (-1 если нет) |
| `str_to_int(s)` | "42" → 42 |
| `int_to_str(n)` | 42 → "42" |
| `str_upper(s)` | В верхний регистр |
| `str_lower(s)` | В нижний регистр |
| `str_cmp(a, b)` | Сравнить (0=равны) |

### Память

| Функция | Описание |
|---------|----------|
| `malloc(size)` | Выделить |
| `free(ptr)` | Освободить |
| `realloc(ptr, size)` | Изменить размер |
| `memset(ptr, val, n)` | Заполнить |
| `memcpy(dst, src, n)` | Копировать |
| `memfd_create(name, flags)` | Анонимный файл в RAM |
| `mmap(...)` | Выделить страницы |

### Файлы

| Функция | Описание |
|---------|----------|
| `file_open(path, mode)` | 0=read, 1=write, 2=append |
| `file_close(fd)` | Закрыть |
| `file_read_all(path)` | Прочитать весь файл |
| `file_writeln(fd, s)` | Записать строку + \n |
| `file_exists(path)` | Существует? (1/0) |
| `lseek(fd, off, whence)` | Переместить позицию |

### Коллекции

| Функция | Описание |
|---------|----------|
| `vec_new(cap)` | Создать вектор |
| `vec_push(v, val)` | Добавить |
| `vec_pop(v)` | Удалить последний |
| `vec_get(v, i)` | Получить |
| `vec_len(v)` | Длина |

### Математика

| Функция | Описание |
|---------|----------|
| `abs(x)` | Модуль |
| `min(a, b)` | Минимум |
| `max(a, b)` | Максимум |
| `rand()` | Случайное число |
| `time()` | Unix timestamp |

---

## Сеть и HTTP

### Сокеты

```juno
sock = socket(2, 1, 0)        // AF_INET, SOCK_STREAM
bind(sock, ip(0,0,0,0), 8080)
listen(sock, 10)
client = accept(sock)
send(client, "Hi", 2)
recv(client, buf, 4096)
close(client)
```

### HTTP запросы

```juno
// GET
response = curl_get("https://api.example.com/data")

// POST
body = "{\"key\":\"value\"}"
response = curl_post("https://api.example.com", body)
```

---

## Системные вызовы

### Процессы

| Функция | Описание |
|---------|----------|
| `fork()` | Создать процесс |
| `exit(code)` | Завершить |
| `getpid()` | PID |
| `kill(pid, sig)` | Сигнал |
| `execve(path, argv, env)` | Запустить |
| `wait(status)` | Ждать |

### Файловая система

| Функция | Описание |
|---------|----------|
| `mkdir(path, mode)` | Создать папку |
| `rmdir(path)` | Удалить папку |
| `unlink(path)` | Удалить файл |
| `chdir(path)` | Сменить папку |
| `getcwd(buf, n)` | Текущая папка |

### Каналы

| Функция | Описание |
|---------|----------|
| `pipe(fds)` | Создать pipe |
| `dup(fd)` | Дублировать |
| `dup2(old, new)` | Дублировать в new |

### Константы

```juno
// lseek
SEEK_SET()  // 0 - от начала
SEEK_CUR()  // 1 - от текущей
SEEK_END()  // 2 - от конца

// memfd_create
MFD_CLOEXEC()        // 1
MFD_ALLOW_SEALING()  // 2

// mmap
PROT_READ()   // 1
PROT_WRITE()  // 2
PROT_EXEC()   // 4

// signals
SIGTERM() SIGKILL() SIGINT()
```

---

## Многопоточность

```juno
fn worker(arg: int): int {
    print(arg)
    return 0
}

fn main(): int {
    stack = alloc_stack(65536)
    tid = thread_create(&worker, stack, 42)
    sleep(1)
    return 0
}
```

### Атомарные операции

```juno
atomic_add(&counter, 1)
atomic_sub(&counter, 1)
val = atomic_load(&counter)
atomic_store(&counter, 0)
atomic_cas(&ptr, old, new)
```

### Spinlock

```juno
spin_lock(&lock)
// critical section
spin_unlock(&lock)
```

---

## Оптимизатор

Turbo Optimizer включается автоматически:

- **Инлайнинг** - функции <10 нод встраиваются
- **Развёртка циклов** - циклы <8 итераций
- **CSE** - удаление общих подвыражений
- **Strength reduction** - `x * 2` → `x << 1`
- **Константная пропагация**
- **Algebraic simplifications** - `x - x` → `0`

**Бенчмарк:**
```
Sum 1M:     11ms
Nested 1Kx1K: instant
```

---

## Обфускация

```bash
juno build app.juno --hell
```

Hell Mode включает:
- Мусорный код
- Шифрование строк
- Anti-debug (ptrace)
- Полиморфные инструкции
- Opaque predicates

---

## Примеры

### Hello World
```juno
def main(): int {
    prints("Hello, World!")
    return 0
}
```

### Факториал
```juno
fn factorial(n: int): int {
    if n <= 1 { return 1 }
    return n * factorial(n - 1)
}
```

### HTTP Сервер
```juno
fn main(): int {
    sock = socket(2, 1, 0)
    bind(sock, ip(0,0,0,0), 8080)
    listen(sock, 10)
    
    while 1 {
        client = accept(sock)
        send(client, "HTTP/1.0 200 OK\r\n\r\nHello!", 26)
        close(client)
    }
}
```

### memfd (RAM файл)
```juno
fn main(): int {
    fd = memfd_create("data", MFD_CLOEXEC())
    write(fd, "Secret", 6)
    lseek(fd, 0, SEEK_SET())
    
    buf = malloc(64)
    read(fd, buf, 64)
    prints(buf)
    close(fd)
    return 0
}
```

### JunoFetch
```juno
fn main(): int {
    prints("Kernel: ")
    prints(file_read_all("/proc/sys/kernel/osrelease"))
    prints("Host:   ")
    prints(file_read_all("/etc/hostname"))
    return 0
}
```

---

## Обновление

```bash
cd ~/juno && git pull
```
