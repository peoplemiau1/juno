# Синтаксис Juno

## Содержание

- [Переменные](#переменные)
- [Функции](#функции)
- [Generics](#generics)
- [Структуры](#структуры)
- [Условия и циклы](#условия)
- [Указатели](#указатели)
- [Массивы](#массивы)

## Переменные

```juno
let x = 10              // Без типа
let y: int = 20         // С типом
let arr[5]              // Массив из 5 элементов
```

## Типы данных

| Тип | Размер | Описание |
|-----|--------|----------|
| `int` / `i64` | 8 байт | Знаковое целое |
| `u64` | 8 байт | Беззнаковое целое |
| `i32` / `u32` | 4 байта | 32-бит целое |
| `i16` / `u16` | 2 байта | 16-бит целое |
| `i8` / `u8` | 1 байт | 8-бит целое |
| `ptr` | 8 байт | Указатель |

## Функции

```juno
fn add(a: int, b: int): int {
    return a + b
}

fn main(): int {
    let result = add(10, 20)
    print(result)
    return 0
}
```

## Generics

Параметрический полиморфизм с мономорфизацией на этапе компиляции.

### Generic функции

```juno
fn identity<T>(x: T): T {
    return x
}

fn swap<T>(a, b) {
    let temp = *a
    *a = *b
    *b = temp
}

fn main(): int {
    let num = identity<int>(42)
    let str = identity<string>("hello")
    
    let x = 10
    let y = 20
    swap<int>(&x, &y)
    
    return 0
}
```

### Generic структуры

```juno
struct Box<T> {
    value: T
}

struct Pair<K, V> {
    key: K
    val: V
}

fn main(): int {
    let intBox = Box<int>
    intBox.value = 100
    
    let pair = Pair<int, int>
    pair.key = 1
    pair.val = 42
    
    return 0
}
```

### Мономорфизация

Компилятор создаёт специализированные версии для каждого типа:

```juno
// Исходный код
fn identity<T>(x: T): T { return x }
let a = identity<int>(1)
let b = identity<string>("hi")

// После мономорфизации (внутренне)
fn identity__int(x: int): int { return x }
fn identity__string(x: string): string { return x }
let a = identity__int(1)
let b = identity__string("hi")
```

## Структуры

```juno
struct Point {
    x
    y
}

fn main(): int {
    let p = Point
    p.x = 10
    p.y = 20
    print(p.x)
    return 0
}
```

## Условия

```juno
if (x > 0) {
    print("positive")
} else {
    print("negative or zero")
}
```

## Циклы

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

## Операторы

### Арифметические
```juno
a + b       // Сложение
a - b       // Вычитание
a * b       // Умножение
a / b       // Деление
```

### Сравнения
```juno
a == b      // Равно
a != b      // Не равно
a < b       // Меньше
a > b       // Больше
a <= b      // Меньше или равно
a >= b      // Больше или равно
```

### Битовые
```juno
a & b       // AND
a | b       // OR
a ^ b       // XOR
~a          // NOT
a << n      // Сдвиг влево
a >> n      // Сдвиг вправо
```

### Логические
```juno
a && b      // Логическое AND
a || b      // Логическое OR
```

## Указатели

```juno
let x = 10
let ptr = &x        // Взять адрес
let val = *ptr      // Разыменование
*ptr = 20           // Запись по указателю

// Арифметика указателей
let ptr2 = ptr_add(ptr, 1)  // ptr + 1 элемент
let ptr3 = ptr_sub(ptr, 1)  // ptr - 1 элемент
```

## Массивы

```juno
let arr[10]         // Массив из 10 элементов
arr[0] = 100        // Запись
let val = arr[0]    // Чтение
let ptr = &arr[0]   // Указатель на первый элемент
```

## Литералы

```juno
let dec = 255       // Десятичное
let hex = 0xFF      // Шестнадцатеричное
let bin = 0b11111111 // Двоичное
let oct = 0o377     // Восьмеричное
let str = "Hello"   // Строка
```

## Препроцессор

```juno
#define VERSION 1
#define BUFFER_SIZE 1024

#ifdef LINUX
    // Код только для Linux
#endif

#ifndef WINDOWS
    // Код если не Windows
#endif
```

## Комментарии

```juno
// Однострочный комментарий

/* Многострочный
   комментарий */
```
