# Встроенные функции

## Ввод/Вывод

| Функция | Описание | Пример |
|---------|----------|--------|
| `print(x)` | Вывести число | `print(42)` |
| `prints(s)` | Вывести строку | `prints("Hello")` |
| `read(fd, buf, n)` | Читать из файла | `read(0, buf, 100)` |
| `write(fd, buf, n)` | Писать в файл | `write(1, msg, 5)` |
| `open(path, flags)` | Открыть файл | `open("/tmp/f", 0)` |
| `close(fd)` | Закрыть файл | `close(fd)` |

### Пример: Ввод/Вывод

```juno
fn main(): int {
    // Вывод
    print(42)
    prints("Hello, World!")
    
    // Чтение из stdin
    let buf = getbuf()
    let n = read(0, buf, 100)
    prints(buf)
    
    return 0
}
```

## Строки

| Функция | Описание |
|---------|----------|
| `len(s)` | Длина строки |
| `concat(a, b)` | Конкатенация строк |
| `substr(s, start, len)` | Подстрока |
| `chr(code)` | Символ по коду |
| `ord(char)` | Код символа |

### Пример: Строки

```juno
fn main(): int {
    let s = "Hello"
    print(len(s))       // 5
    
    let code = ord("A")
    print(code)         // 65
    
    return 0
}
```

## Память

| Функция | Описание |
|---------|----------|
| `getbuf()` | Получить буфер 4KB |
| `mmap(addr, len, prot, flags, fd, off)` | Выделить память |
| `munmap(addr, len)` | Освободить память |
| `memset(ptr, val, n)` | Заполнить память |
| `memcpy(dst, src, n)` | Копировать память |

### Пример: Память

```juno
fn main(): int {
    // Выделить страницу памяти
    let prot = PROT_READ() | PROT_WRITE()
    let flags = MAP_PRIVATE() | MAP_ANONYMOUS()
    let mem = mmap(0, 4096, prot, flags, 0, 0)
    
    // Заполнить нулями
    memset(mem, 0, 4096)
    
    // Освободить
    munmap(mem, 4096)
    
    return 0
}
```

## Математика

| Функция | Описание |
|---------|----------|
| `abs(x)` | Модуль числа |
| `min(a, b)` | Минимум |
| `max(a, b)` | Максимум |
| `rand()` | Случайное число |

## Типы

| Функция | Описание |
|---------|----------|
| `i8(val)` | Привести к i8 |
| `u8(val)` | Привести к u8 |
| `i16(val)` | Привести к i16 |
| `u16(val)` | Привести к u16 |
| `i32(val)` | Привести к i32 |
| `u32(val)` | Привести к u32 |
| `sizeof(type)` | Размер типа |

### Пример: Приведение типов

```juno
fn main(): int {
    let big = 1000
    let byte = u8(big)  // 232 (1000 % 256)
    print(byte)
    
    let hex = 0x12345678
    let low = u16(hex)  // 0x5678
    print(low)
    
    return 0
}
```

## Указатели

| Функция | Описание |
|---------|----------|
| `ptr_add(ptr, n)` | ptr + n элементов |
| `ptr_sub(ptr, n)` | ptr - n элементов |
| `ptr_diff(p1, p2)` | Разница указателей |

### Пример: Указатели

```juno
fn main(): int {
    let arr[5]
    arr[0] = 10
    arr[1] = 20
    arr[2] = 30
    
    let ptr = &arr[0]
    print(*ptr)             // 10
    
    let ptr2 = ptr_add(ptr, 2)
    print(*ptr2)            // 30
    
    return 0
}
```

## Константы

### Защита памяти (mmap)
| Константа | Значение |
|-----------|----------|
| `PROT_READ()` | 1 |
| `PROT_WRITE()` | 2 |
| `PROT_EXEC()` | 4 |
| `MAP_PRIVATE()` | 2 |
| `MAP_ANONYMOUS()` | 32 |

### Сигналы
| Константа | Значение |
|-----------|----------|
| `SIGTERM()` | 15 |
| `SIGKILL()` | 9 |
| `SIGINT()` | 2 |
