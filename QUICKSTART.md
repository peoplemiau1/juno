# Juno - Быстрый старт

## Установка

Требования:
- Ruby 2.7+
- Windows или Linux

```bash
git clone https://github.com/yourusername/juno-lang
cd juno-lang
```

## Первая программа

Создайте файл `hello.juno`:

```juno
fn main() {
    print("Hello, Juno!")
    return 0
}
```

Скомпилируйте и запустите:

```bash
# Windows
ruby main_native.rb hello.juno
build\output.exe

# Linux
ruby main_linux.rb hello.juno
./build/output_linux
```

Или используйте быстрый скрипт:

```bash
# Windows
build.bat hello.juno

# Linux
./build.sh hello.juno
```

## Примеры

### Переменные и арифметика

```juno
fn main() {
    let x = 10
    let y = 20
    let sum = x + y
    
    print("Sum: ")
    print(sum)
    
    return sum
}
```

### Функции

```juno
fn add(a, b) {
    return a + b
}

fn multiply(x, y) {
    return x * y
}

fn main() {
    let result = add(5, multiply(3, 4))
    print(result)  // 17
    return 0
}
```

### Циклы

```juno
fn main() {
    // For loop
    for (i = 0; i < 10; i++) {
        print(i)
    }
    
    // While loop
    let x = 0
    while (x < 5) {
        print(x)
        x++
    }
    
    return 0
}
```

### Структуры

```juno
struct Point {
    x
    y
}

fn Point.init(px, py) {
    self.x = px
    self.y = py
}

fn Point.distance() {
    return self.x * self.x + self.y * self.y
}

fn main() {
    let p = Point
    p.init(3, 4)
    
    let dist = p.distance()
    print(dist)  // 25
    
    return 0
}
```

### Массивы

```juno
fn main() {
    let arr[5]
    
    arr[0] = 10
    arr[1] = 20
    arr[2] = 30
    
    print(arr[0])  // 10
    print(arr[1])  // 20
    
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

fn main() {
    let x = 10
    let y = 20
    
    swap(&x, &y)
    
    print(x)  // 20
    print(y)  // 10
    
    return 0
}
```

### Импорт модулей

```juno
import "stdlib/std.juno"

fn main() {
    let x = abs(-42)
    print(x)  // 42
    
    let y = pow(2, 10)
    print(y)  // 1024
    
    return 0
}
```

## Встроенные функции

### I/O
- `print(x)` - вывод числа/строки
- `prints(s)` - вывод строки из переменной
- `input()` - ввод строки
- `len(x)` - длина массива/строки

### Строки
- `concat(s1, s2)` - склеить строки
- `substr(s, start, len)` - подстрока
- `chr(n)` - число → символ
- `ord(s)` - символ → число

### Математика
- `abs(n)` - модуль
- `min(a, b)`, `max(a, b)` - минимум/максимум
- `pow(base, exp)` - степень

### Память
- `alloc(size)` - выделить память
- `free(ptr, size)` - освободить память

### Утилиты
- `exit(code)` - завершить программу
- `sleep(ms)` - пауза
- `time()` - unix timestamp
- `rand()`, `srand(seed)` - случайные числа

## Тестирование

Запустите все тесты:

```bash
# Windows
test.bat

# Linux
./test.sh
```

Запустите конкретный тест:

```bash
ruby main_native.rb tests/test_math.juno
build\output.exe
```

## Демо программы

Посмотрите примеры в папке `examples/`:

```bash
# Демонстрация всех возможностей
build.bat demo_v1.juno

# Простая игра
build.bat examples/game.juno

# Hello World
build.bat hello.juno
```

## Отладка

Используйте `insertC` для прямых ассемблерных вставок:

```juno
fn main() {
    // xor rax, rax (обнулить RAX)
    insertC { 0x48 0x31 0xc0 }
    
    // ret
    insertC { 0xc3 }
    
    return 0
}
```

## Дальнейшее чтение

- [README.md](README.md) - Обзор проекта
- [docs.md](docs.md) - Полная документация
- [TODO.md](TODO.md) - Планы развития
- [STRUCTURE.md](STRUCTURE.md) - Структура проекта
- [RECOMMENDATIONS.md](RECOMMENDATIONS.md) - Рекомендации

## Помощь

Нашли баг? Создайте issue на GitHub!

Хотите помочь? Смотрите [CONTRIBUTING.md](CONTRIBUTING.md)

---

Удачи с Juno! 🗡️
