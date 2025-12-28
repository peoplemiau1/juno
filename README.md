<p align="center">
  <img src="juno-logo.png" alt="Juno" width="200"/>
</p>

<h1 align="center">Juno v1.8</h1>

<p align="center">
  <b>Быстрый компилируемый язык для Linux x86-64</b><br>
  Простой синтаксис • Нативный код • Turbo-оптимизатор
</p>

---

## Быстрый старт

```bash
git clone https://github.com/peoplemiau1/juno.git
cd juno && ./install.sh && source ~/.bashrc
```

```bash
juno run hello.juno           # запустить
juno build hello.juno -o app  # скомпилировать
juno build app.juno --hell    # с обфускацией
```

## Синтаксис

```juno
// Функции: fn, func или def
def main(): int {
    // Условия без скобок
    if 1 == 1 {
        prints("Hello, Juno!")
    }
    
    // Циклы
    x = 0
    while x < 5 {
        print(x)
        x = x + 1
    }
    
    return 0
}
```

## Возможности

| Категория | Функции |
|-----------|---------|
| **Оптимизатор** | Инлайнинг, развёртка циклов, CSE, strength reduction |
| **Память** | `malloc`, `free`, `memfd_create`, `mmap` |
| **Строки** | `str_len`, `str_find`, `int_to_str`, `str_to_int` |
| **Файлы** | `file_open`, `file_read_all`, `lseek`, `close` |
| **Коллекции** | `vec_new`, `vec_push`, `vec_pop`, `vec_get` |
| **Сеть** | TCP сокеты, HTTP, `curl_get`, `curl_post` |
| **Система** | `fork`, `execve`, `pipe`, `kill`, `getpid` |
| **Безопасность** | Hell Mode обфускация |

## Примеры

### Системная информация (JunoFetch)
```juno
fn main(): int {
    prints("Kernel:  ")
    prints(file_read_all("/proc/sys/kernel/osrelease"))
    prints("Host:    ")
    prints(file_read_all("/etc/hostname"))
    return 0
}
```

### Память в RAM (memfd)
```juno
fn main(): int {
    fd = memfd_create("data", MFD_CLOEXEC())
    write(fd, "Secret!", 7)
    lseek(fd, 0, SEEK_SET())
    
    buf = malloc(64)
    read(fd, buf, 64)
    prints(buf)
    
    close(fd)
    return 0
}
```

### HTTP Сервер
```juno
fn main(): int {
    sock = socket(2, 1, 0)
    bind(sock, ip(0,0,0,0), 8080)
    listen(sock, 100)
    
    while 1 {
        client = accept(sock)
        send(client, "HTTP/1.1 200 OK\r\n\r\nHello!", 25)
        close(client)
    }
}
```

### Бенчмарк (быстрее Rust?)
```juno
fn main(): int {
    prints("Sum 1..1000000:")
    total = 0
    for (i = 0; i < 1000000; i++) {
        total = total + i
    }
    print(total)  // 11ms!
    return 0
}
```

## Производительность

```
Sum 1M iterations:    11ms
Nested 1000x1000:     instant
Math ops 1M:          instant
```

Turbo Optimizer включает:
- Инлайнинг функций (<10 нод)
- Развёртка циклов (<8 итераций)  
- Удаление общих подвыражений (CSE)
- Strength reduction (mul→shift, div→shift)
- Константная пропагация

## Документация

| Файл | Описание |
|------|----------|
| [DOCS.md](DOCS.md) | Полный справочник API |
| [CHANGELOG.md](CHANGELOG.md) | История версий |
| [examples/](examples/) | 34 рабочих примера |

## Лицензия

MIT
