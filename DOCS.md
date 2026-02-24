# Техническое руководство Juno

Это руководство содержит подробное описание синтаксиса и возможностей языка Juno. Язык ориентирован на системное программирование, обеспечивая строгий контроль над памятью и ресурсами при сохранении выразительности.

## Содержание
1. [Основы синтаксиса](#основы-синтаксиса)
2. [Переменные и Мутабельность](#переменные-и-мутабельность)
3. [Типы данных](#типы-данных)
4. [Функции](#функции)
5. [Управляющие конструкции](#управляющие-конструкции)
6. [Структуры (Structs)](#структуры)
7. [Перечисления (Enums) и Pattern Matching](#перечисления)
8. [Управление ресурсами и Владение](#управление-ресурсами)
9. [Низкоуровневые возможности и FFI](#низкоуровневые-возможности)

---

## 1. Основы синтаксиса

Juno использует C-подобный синтаксис с блоками кода, ограниченными фигурными скобками `{}`. Инструкции могут разделяться точкой с запятой `;` или переносом строки.

```watt
// Это однострочный комментарий
# Это тоже комментарий (в стиле shell/python)

/*
   Это многострочный
   комментарий
*/
```

---

## 2. Переменные и Мутабельность

В Juno существует два способа объявления переменных: `let` (неизменяемые) и `let mut` (изменяемые).

```watt
let x = 10        // x нельзя изменить после инициализации
let mut y = 20    // y является изменяемой переменной

y = 30            // OK
// x = 5          // Ошибка компиляции: Cannot reassign to non-mutable variable
```

### Глобальные переменные
Глобальные переменные объявляются на уровне модуля.

```watt
let GLOBAL_CONST = 100
let mut global_counter = 0

fn increment() {
    global_counter = global_counter + 1
}
```

---

## 3. Типы данных

### Базовые типы
- `int`: Знаковое 64-битное целое число (по умолчанию).
- `bool`: Логическое значение (`true` или `false`).
- `string`: Строка (указатель на последовательность байт).
- `ptr`: Универсальный указатель.
- `real`: 64-битное число с плавающей запятой (зарезервировано).

### Приведение типов
Используется ключевое слово `as`.

```watt
let a = 10
let b = a as ptr
let c = b as int
```

---

## 4. Функции

Функции объявляются с помощью `fn`. Поддерживается явное указание типов аргументов и возвращаемого значения.

```watt
fn add(a: int, b: int) -> int {
    return a + b
}

// Если тип возвращаемого значения не указан, считается int
fn print_val(val) {
    print(val)
    prints("\n")
}
```

---

## 5. Управляющие конструкции

### Условные переходы
```watt
if (x > 10) {
    prints("Greater than 10\n")
} elif (x == 10) {
    prints("Exactly 10\n")
} else {
    prints("Less than 10\n")
}
```

### Циклы
```watt
// Цикл while
let mut i = 0
while (i < 5) {
    print(i)
    i = i + 1
}

// Бесконечный цикл
loop {
    if (ready()) { break }
}

// Цикл for (по диапазону)
for i in 0..10 {
    print(i)
}
```

---

## 6. Структуры (Structs)

Структуры позволяют объединять данные разных типов.

```watt
struct Point {
    x: int
    y: int
}

fn test_struct() {
    // Аллокация в куче
    let p: Point = malloc(16)
    p.x = 10
    p.y = 20

    print(p.x)
    free(p)
}
```

---

## 7. Перечисления (Enums) и Pattern Matching

Enums в Juno — это полноценные Tagged Unions (варианты могут содержать данные).

```watt
enum Option {
    None
    Some(int)
}

fn handle_option(opt: Option) {
    match opt {
        Option.None => {
            prints("Nothing found\n")
        }
        Option.Some(val) => {
            prints("Found value: ")
            print(val)
            prints("\n")
        }
    }
}
```

---

## 8. Управление ресурсами и Владение

Компилятор Juno отслеживает жизненный цикл указателей, чтобы предотвратить утечки памяти и использование после освобождения.

```watt
fn process_data() {
    let data = malloc(1024) // Born: Ресурс создан

    do_something(data)      // Владение может быть передано

    free(data)              // Kill: Ресурс уничтожен

    // print(byte_at(data, 0)) // Ошибка компиляции: Use after consumption
}
```

Если ресурс был создан, но не был освобожден или передан другой функции к концу области видимости, компилятор выдаст ошибку `E0007 (Leak)`.

---

## 9. Низкоуровневые возможности и FFI

### Прямой доступ к памяти
```watt
let p = malloc(8)
byte_set(p, 0, 0xFF)      // Записать байт по смещению 0
let val = byte_at(p, 0)   // Прочитать байт
```

### Системные вызовы (Syscalls)
```watt
// write(stdout, "Hi", 2)
syscall(1, 1, "Hi", 2)
```

### Внешние функции (FFI)
```watt
extern fn printf(fmt: string, val: int) -> int from "libc.so.6"

fn main() {
    printf("Value from C: %d\n", 42)
}
```

### Вставка сырого C-кода (experimental)
Для интеграции с существующими C-инструментами можно использовать `insertC`.
```watt
insertC {
    #include <stdio.h>
    void hello() { printf("Hello from C block\n"); }
}
```

---

## 10. Примеры реализации алгоритмов

### Быстрая сортировка (Quick Sort)
```watt
fn partition(arr: ptr, low: int, high: int) -> int {
    let pivot = byte_at(arr, high)
    let mut i = low - 1

    for j in low..high {
        if (byte_at(arr, j) <= pivot) {
            i = i + 1
            let temp = byte_at(arr, i)
            byte_set(arr, i, byte_at(arr, j))
            byte_set(arr, j, temp)
        }
    }

    let temp = byte_at(arr, i + 1)
    byte_set(arr, i + 1, byte_at(arr, high))
    byte_set(arr, high, temp)
    return i + 1
}

fn quick_sort(arr: ptr, low: int, high: int) {
    if (low < high) {
        let pi = partition(arr, low, high)
        quick_sort(arr, low, pi - 1)
        quick_sort(arr, pi + 1, high)
    }
}
```

### Работа со связанным списком
```watt
struct Node {
    value: int
    next: ptr
}

fn list_append(head: ptr, val: int) -> ptr {
    let new_node: Node = malloc(16)
    new_node.value = val
    new_node.next = 0

    if (head == 0) { return new_node }

    let mut curr: Node = head
    while (curr.next != 0) {
        curr = curr.next
    }
    curr.next = new_node
    return head
}
```
