# Синтаксис Juno

## Переменные

```juno
let x = 10              // число
let name = "hello"      // строка
let arr[5]              // массив из 5 элементов
```

## Типы

| Тип | Описание |
|-----|----------|
| `int` | целое число (64 бит) |
| `string` | строка |
| `ptr` | указатель |

## Функции

```juno
fn имя(параметры): тип_возврата {
    // тело
    return значение
}
```

Пример:

```juno
fn add(a: int, b: int): int {
    return a + b
}

fn greet(name: string) {
    print("Hello, ")
    print(name)
}

fn main(): int {
    let sum = add(10, 20)
    greet("World")
    return 0
}
```

## Generics (шаблоны)

Функции и структуры могут быть параметризованы типами:

```juno
fn identity<T>(x: T): T {
    return x
}

struct Box<T> {
    value: T
}

fn main(): int {
    let num = identity<int>(42)
    let str = identity<string>("hello")
    
    let box = Box<int>
    box.value = 100
    
    return 0
}
```

## Структуры

```juno
struct Point {
    x: int
    y: int
}

// Метод структуры
fn Point.move(dx: int, dy: int) {
    self.x = self.x + dx
    self.y = self.y + dy
}

fn main(): int {
    let p = Point
    p.x = 10
    p.y = 20
    p.move(5, 5)
    // p.x = 15, p.y = 25
    return 0
}
```

## Условия

```juno
if (условие) {
    // если true
} else {
    // если false
}
```

Пример:

```juno
if (x > 0) {
    print("positive")
} else if (x < 0) {
    print("negative")
} else {
    print("zero")
}
```

## Циклы

### while

```juno
let i = 0
while (i < 10) {
    print_int(i)
    i++
}
```

### for

```juno
for (i = 0; i < 10; i++) {
    print_int(i)
}
```

## Операторы

### Арифметика

```juno
a + b    // сложение
a - b    // вычитание
a * b    // умножение
a / b    // деление
```

### Сравнение

```juno
a == b   // равно
a != b   // не равно
a < b    // меньше
a > b    // больше
a <= b   // меньше или равно
a >= b   // больше или равно
```

### Логические

```juno
a && b   // И
a || b   // ИЛИ
```

### Битовые

```juno
a & b    // AND
a | b    // OR
a ^ b    // XOR
~a       // NOT
a << n   // сдвиг влево
a >> n   // сдвиг вправо
```

## Указатели

```juno
let x = 10
let ptr = &x      // взять адрес
let val = *ptr    // прочитать значение
*ptr = 20         // записать значение
```

## Массивы

```juno
let arr[10]       // создать массив
arr[0] = 100      // записать
let x = arr[0]    // прочитать
let ptr = &arr[0] // указатель на элемент
```

## Комментарии

```juno
// однострочный комментарий

/* многострочный
   комментарий */
```

## Импорт

```juno
import "path/to/file.juno"
```
