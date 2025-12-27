# Системные вызовы (Linux)

## Процессы

| Функция | Описание |
|---------|----------|
| `fork()` | Создать дочерний процесс |
| `exit(code)` | Завершить процесс |
| `wait(status)` | Ждать дочерний процесс |
| `getpid()` | Получить PID |
| `getppid()` | Получить PID родителя |
| `getuid()` | Получить UID |
| `getgid()` | Получить GID |
| `kill(pid, sig)` | Послать сигнал процессу |
| `execve(path, argv, envp)` | Запустить программу |

### Пример: Fork

```juno
fn main(): int {
    let pid = fork()
    
    if (pid == 0) {
        // Дочерний процесс
        print("Child!")
        exit(0)
    } else {
        // Родительский процесс
        print("Parent, child PID:")
        print(pid)
        wait(0)
        print("Child finished")
    }
    
    return 0
}
```

## Файловая система

| Функция | Описание |
|---------|----------|
| `open(path, flags)` | Открыть файл |
| `close(fd)` | Закрыть файл |
| `read(fd, buf, n)` | Читать из файла |
| `write(fd, buf, n)` | Писать в файл |
| `mkdir(path, mode)` | Создать директорию |
| `rmdir(path)` | Удалить директорию |
| `unlink(path)` | Удалить файл |
| `chmod(path, mode)` | Изменить права |
| `chdir(path)` | Сменить директорию |
| `getcwd(buf, size)` | Получить текущую директорию |

### Пример: Файлы

```juno
fn main(): int {
    // Получить текущую директорию
    let buf = getbuf()
    getcwd(buf, 1024)
    prints(buf)
    
    // Создать директорию
    mkdir("/tmp/test", 0o755)
    
    return 0
}
```

## Каналы

| Функция | Описание |
|---------|----------|
| `pipe(fds)` | Создать канал |
| `dup(fd)` | Дублировать дескриптор |
| `dup2(old, new)` | Дублировать в конкретный fd |

## TCP Сокеты

| Функция | Описание |
|---------|----------|
| `socket(domain, type, proto)` | Создать сокет |
| `bind(sock, ip, port)` | Привязать к адресу |
| `listen(sock, backlog)` | Начать слушать |
| `accept(sock)` | Принять соединение |
| `connect(sock, ip, port)` | Подключиться |
| `send(sock, buf, len)` | Отправить данные |
| `recv(sock, buf, len)` | Получить данные |
| `ip(a, b, c, d)` | Создать IP адрес |

### Пример: TCP Сервер

```juno
fn main(): int {
    // Создать сокет
    let sock = socket(2, 1, 0)  // AF_INET, SOCK_STREAM
    
    // Привязать к порту
    let addr = ip(0, 0, 0, 0)   // 0.0.0.0
    bind(sock, addr, 8080)
    
    // Слушать
    listen(sock, 10)
    print("Listening on :8080")
    
    // Принять соединение
    let client = accept(sock)
    print("Client connected!")
    
    // Отправить ответ
    let response = "HTTP/1.0 200 OK\r\n\r\nHello!"
    send(client, response, 31)
    
    close(client)
    close(sock)
    return 0
}
```

### Пример: TCP Клиент

```juno
fn main(): int {
    let sock = socket(2, 1, 0)
    
    let addr = ip(127, 0, 0, 1)  // localhost
    connect(sock, addr, 8080)
    
    let msg = "GET / HTTP/1.0\r\n\r\n"
    send(sock, msg, 18)
    
    let buf = getbuf()
    let n = recv(sock, buf, 4096)
    prints(buf)
    
    close(sock)
    return 0
}
```

## Память

| Функция | Описание |
|---------|----------|
| `mmap(addr, len, prot, flags, fd, off)` | Выделить память |
| `munmap(addr, len)` | Освободить память |

### Пример: Анонимная память

```juno
fn main(): int {
    let prot = PROT_READ() | PROT_WRITE()
    let flags = MAP_PRIVATE() | MAP_ANONYMOUS()
    
    // Выделить 1MB
    let mem = mmap(0, 1048576, prot, flags, 0, 0)
    
    if (mem != 0) {
        print("Allocated 1MB")
        memset(mem, 0, 1048576)
        munmap(mem, 1048576)
        print("Freed")
    }
    
    return 0
}
```
