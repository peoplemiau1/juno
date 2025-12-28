<p align="center">
  <img src="juno-logo.png" alt="Juno" width="200"/>
</p>

<h1 align="center">Juno</h1>

<p align="center">
  Компилируемый язык программирования для Linux x86-64
</p>

---

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
juno build app.juno --hell    # с обфускацией
juno new project              # создать файл
```

## Пример

```juno
fn main(): int {
    print("Hello, World!")
    return 0
}
```

## Возможности

| Категория | Функции |
|-----------|---------|
| **Язык** | Generics, структуры, методы, указатели |
| **Память** | `malloc`, `free`, `realloc` |
| **Строки** | `str_find`, `int_to_str`, `str_to_int`, `str_upper` |
| **Файлы** | `file_open`, `file_read_all`, `file_writeln` |
| **Коллекции** | `vec_new`, `vec_push`, `vec_pop`, `vec_get` |
| **Сеть** | TCP сокеты, HTTP сервер, `curl_get`, `curl_post` |
| **Потоки** | `thread_create`, `atomic_add`, `spin_lock` |
| **Безопасность** | Hell Mode обфускация (`--hell`) |

## Примеры

### HTTP Сервер
```juno
fn main(): int {
    let sock = socket(2, 1, 0)
    bind(sock, ip(0,0,0,0), 8080)
    listen(sock, 100)
    
    while (1) {
        let client = accept(sock)
        send(client, "HTTP/1.1 200 OK\r\n\r\nHello!", 25)
        close(client)
    }
    return 0
}
```

### Работа с файлами
```juno
fn main(): int {
    let fd = file_open("/tmp/log.txt", 1)
    file_writeln(fd, "Hello from Juno!")
    file_close(fd)
    
    let content = file_read_all("/tmp/log.txt")
    prints(content)
    return 0
}
```

### Динамические массивы
```juno
fn main(): int {
    let v = vec_new(16)
    vec_push(v, 10)
    vec_push(v, 20)
    vec_push(v, 30)
    
    print(vec_get(v, 1))  // 20
    print(vec_len(v))     // 3
    return 0
}
```

## Документация

**[DOCS.md](DOCS.md)** - полная документация со всеми функциями

## Лицензия

MIT
