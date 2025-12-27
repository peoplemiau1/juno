# Примеры программ

## Hello World

```juno
fn main(): int {
    print("Hello, World!")
    return 0
}
```

## Калькулятор

```juno
fn add(a: int, b: int): int {
    return a + b
}

fn mul(a: int, b: int): int {
    return a * b
}

fn main(): int {
    let x = 10
    let y = 5
    
    print("x + y =")
    print(add(x, y))
    
    print("x * y =")
    print(mul(x, y))
    
    return 0
}
```

## Факториал

```juno
fn factorial(n: int): int {
    let result = 1
    for (i = 1; i <= n; i++) {
        result = result * i
    }
    return result
}

fn main(): int {
    for (n = 1; n <= 10; n++) {
        print(factorial(n))
    }
    return 0
}
```

## Фибоначчи

```juno
fn fib(n: int): int {
    if (n <= 1) {
        return n
    }
    return fib(n - 1) + fib(n - 2)
}

fn main(): int {
    for (i = 0; i < 15; i++) {
        print(fib(i))
    }
    return 0
}
```

## Простые числа

```juno
fn is_prime(n: int): int {
    if (n < 2) {
        return 0
    }
    for (i = 2; i * i <= n; i++) {
        if (n / i * i == n) {
            return 0
        }
    }
    return 1
}

fn main(): int {
    print("Primes up to 50:")
    for (n = 2; n <= 50; n++) {
        if (is_prime(n) == 1) {
            print(n)
        }
    }
    return 0
}
```

## Сортировка пузырьком

```juno
fn main(): int {
    let arr[10]
    arr[0] = 64
    arr[1] = 34
    arr[2] = 25
    arr[3] = 12
    arr[4] = 22
    arr[5] = 11
    arr[6] = 90
    arr[7] = 42
    arr[8] = 15
    arr[9] = 77
    
    // Bubble sort
    for (i = 0; i < 9; i++) {
        for (j = 0; j < 9 - i; j++) {
            if (arr[j] > arr[j + 1]) {
                let tmp = arr[j]
                arr[j] = arr[j + 1]
                arr[j + 1] = tmp
            }
        }
    }
    
    print("Sorted:")
    for (i = 0; i < 10; i++) {
        print(arr[i])
    }
    
    return 0
}
```

## Битовые флаги

```juno
#define READ  4
#define WRITE 2
#define EXEC  1

fn main(): int {
    let perms = 0
    
    // Установить права rwx
    perms = perms | READ
    perms = perms | WRITE
    perms = perms | EXEC
    print("rwx =")
    print(perms)  // 7
    
    // Проверить право на чтение
    if ((perms & READ) != 0) {
        print("Can read")
    }
    
    // Убрать право на запись
    perms = perms & (~WRITE)
    print("r-x =")
    print(perms)  // 5
    
    return 0
}
```

## Эхо-сервер

```juno
fn main(): int {
    let sock = socket(2, 1, 0)
    let addr = ip(0, 0, 0, 0)
    
    bind(sock, addr, 12345)
    listen(sock, 5)
    print("Echo server on :12345")
    
    let client = accept(sock)
    print("Client connected")
    
    let buf = getbuf()
    let running = 1
    
    while (running == 1) {
        let n = recv(client, buf, 1024)
        if (n > 0) {
            send(client, buf, n)
        } else {
            running = 0
        }
    }
    
    close(client)
    close(sock)
    return 0
}
```

## HTTP сервер

```juno
fn main(): int {
    let sock = socket(2, 1, 0)
    bind(sock, ip(0, 0, 0, 0), 8080)
    listen(sock, 10)
    print("HTTP server on :8080")
    
    let client = accept(sock)
    
    // Прочитать запрос
    let buf = getbuf()
    recv(client, buf, 4096)
    
    // Отправить ответ
    let headers = "HTTP/1.0 200 OK\r\nContent-Type: text/html\r\n\r\n"
    send(client, headers, 45)
    
    let body = "<h1>Hello from Juno!</h1>"
    send(client, body, 25)
    
    close(client)
    close(sock)
    return 0
}
```

## Системный монитор

```juno
fn main(): int {
    print("=== System Info ===")
    
    // PID
    let pid = getpid()
    print("PID:")
    print(pid)
    
    // UID
    let uid = getuid()
    print("UID:")
    print(uid)
    
    // Current directory
    let buf = getbuf()
    getcwd(buf, 1024)
    print("CWD:")
    prints(buf)
    
    // Memory test
    let prot = PROT_READ() | PROT_WRITE()
    let flags = MAP_PRIVATE() | MAP_ANONYMOUS()
    let mem = mmap(0, 4096, prot, flags, 0, 0)
    
    if (mem != 0) {
        print("Memory allocation: OK")
        munmap(mem, 4096)
    }
    
    return 0
}
```

## Запуск примеров

```bash
# Скомпилировать и запустить
ruby main_linux.rb examples/hello.juno
./build/output_linux

# Все примеры в examples/
ls examples/
```
