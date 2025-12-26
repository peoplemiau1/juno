# Juno v1.1 - Progress Report

## ✅ Реализовано

### Базовый язык (v1.0)
- Переменные (`let x = 5`)
- Функции (`fn name() {}`)
- Структуры и методы
- Циклы `for`, `while`
- Условия `if/else`
- Арифметика, сравнения, инкремент (`++`, `--`)
- `insertC {}` — ассемблерные вставки
- Нативная компиляция PE (Windows) / ELF (Linux)

### Массивы и строки (v1.1)
- `let arr[N]` — статические массивы
- `arr[i]` — доступ по индексу
- Escape-последовательности (`\x1b[...`, `\n`, `\t`)
- Унарный минус (`-42`)

### Файловый I/O (v1.1)
- `open(path)` — открыть файл
- `read(fd, buf, size)` — читать
- `write(fd, buf, len)` — писать
- `close(fd)` — закрыть
- `syscall(num, ...)` — прямые системные вызовы
- `getbuf()` — буфер 4KB

### Стандартная библиотека (built-in, без импортов)

**I/O:**
- `print(x)` — вывод числа/строки
- `prints(s)` — вывод строки из переменной
- `input()` — ввод строки
- `len(x)` — длина массива/строки

**Строки:**
- `concat(s1, s2)` — склеить строки
- `substr(s, start, len)` — подстрока
- `chr(n)` — число → символ
- `ord(s)` — символ → число

**Математика:**
- `abs(n)` — модуль
- `min(a, b)`, `max(a, b)`
- `pow(base, exp)` — степень

**Память:**
- `alloc(size)` — выделить через mmap
- `free(ptr, size)` — освободить

**Утилиты:**
- `exit(code)` — завершить программу
- `sleep(ms)` — пауза
- `time()` — unix timestamp
- `rand()`, `srand(seed)` — случайные числа

**Сеть (Linux):**
- `socket(domain, type, proto)` — создать сокет
- `connect(sock, ip, port)` — подключиться
- `send(sock, buf, len)` — отправить
- `recv(sock, buf, len)` — получить
- `bind(sock, ip, port)` — привязать
- `listen(sock, backlog)` — слушать
- `accept(sock)` — принять соединение
- `ip(a, b, c, d)` — собрать IP адрес

### Оптимизатор
- Constant folding (`2 + 3` → `5` на этапе компиляции)
- Dead code elimination (удаление кода после `return`)

### Улучшенные ошибки
- Цветной вывод с номерами строк
- Указание позиции ошибки

### Модульная архитектура
```
src/codegen/parts/
├── calls.rb          # Диспетчер функций
├── builtins/
│   ├── strings.rb    # Строковые функции
│   ├── math.rb       # Математика
│   ├── memory.rb     # Память
│   ├── utils.rb      # Утилиты
│   ├── io.rb         # Файловый I/O
│   └── network.rb    # Сеть
```

---

## ⏳ Roadmap (что осталось)

### Высокий приоритет
- [ ] **Самохостинг** — переписать компилятор на Juno
- [ ] **Register allocation** — оптимизация использования регистров
- [ ] **Строковые литералы в выражениях** — `"Hello" + name`

### Средний приоритет
- [ ] **Импорт модулей** — `import "file.juno"`
- [ ] **Указатели** — `&x`, `*ptr`
- [ ] **Типизация** — `let x: int = 5`
- [ ] **Массивы переменной длины** — динамические массивы

### Низкий приоритет
- [ ] **Windows сеть** — Winsock API
- [ ] **Отладчик** — breakpoints, step
- [ ] **LSP** — подсветка синтаксиса в IDE
- [ ] **Пакетный менеджер** — установка библиотек

---

## Примеры

### Hello World
```juno
fn main() {
    print("Hello, World!")
    return 0
}
```

### HTTP клиент
```juno
fn main() {
    let sock = socket(2, 1, 0)
    let addr = ip(127, 0, 0, 1)
    connect(sock, addr, 8080)
    
    let req = "GET / HTTP/1.0\r\n\r\n"
    send(sock, req, 18)
    
    let buf = getbuf()
    recv(sock, buf, 4000)
    prints(buf)
    
    close(sock)
    return 0
}
```

### Математика
```juno
fn main() {
    let a = abs(-42)      // 42
    let b = pow(2, 10)    // 1024
    let c = min(5, 10)    // 5
    print(a + b + c)
    return 0
}
```

---

## Сборка

```bash
# Linux
ruby juno build program.juno
./output_linux

# Windows
ruby juno build program.juno --windows
./output.exe

# Интерпретатор
ruby juno run program.juno
```
