# Juno v1.0 Documentation

## Обзор

**Juno** — минималистичный системный язык программирования, компилируемый напрямую в нативные исполняемые файлы (PE для Windows, ELF для Linux) без внешних зависимостей.

## Возможности языка

### 1. Переменные и типы данных

```juno
let x = 42
let name = 100
x = x + 1
```

Все переменные — 64-битные целые числа. Объявление через `let`.

### 2. Арифметические операции

```juno
let sum = a + b      // Сложение
let diff = a - b     // Вычитание
let prod = a * b     // Умножение
let quot = a / b     // Деление
```

### 3. Операторы сравнения

```juno
let eq = (a == b)    // Равно
let neq = (a != b)   // Не равно
let lt = (a < b)     // Меньше
let gt = (a > b)     // Больше
let lte = (a <= b)   // Меньше или равно
let gte = (a >= b)   // Больше или равно
```

Результат: 1 (true) или 0 (false).

### 4. Инкремент и декремент

```juno
x++    // x = x + 1
x--    // x = x - 1
```

### 5. Условные операторы

```juno
if (condition) {
    // код если true
} else {
    // код если false
}
```

### 6. Циклы

#### While

```juno
while (condition) {
    // тело цикла
}
```

#### For

```juno
for (i = 0; i < 10; i++) {
    // тело цикла
}
```

### 7. Функции

```juno
fn add(a, b) {
    return a + b
}

fn main() {
    let result = add(10, 20)
    return result
}
```

- Точка входа: `fn main()`
- Возврат значения через `return`

### 8. Структуры (struct)

```juno
struct Point {
    x
    y
}

fn main() {
    let p = Point
    p.x = 10
    p.y = 20
}
```

### 9. Методы структур

```juno
struct Counter {
    value
}

fn Counter.init(start) {
    self.value = start
}

fn Counter.increment() {
    self.value = self.value + 1
}

fn Counter.get() {
    return self.value
}

fn main() {
    let c = Counter
    c.init(0)
    c.increment()
    let val = c.get()
    return val
}
```

- `self` автоматически передаётся как первый аргумент
- Вызов: `instance.method(args)`

### 10. Массивы (NEW in v1.1)

```juno
fn main() {
    let arr[5]           // Объявление массива из 5 элементов
    
    arr[0] = 10          // Присваивание по индексу
    arr[1] = 20
    
    let x = arr[0]       // Чтение по индексу
    let size = len(arr)  // Длина массива (5)
    
    // Итерация
    for (i = 0; i < 5; i++) {
        arr[i] = i * 10
    }
    
    return arr[2]        // 20
}
```

- Массивы фиксированного размера на стеке
- Индексация с 0
- `len(arr)` возвращает размер массива

### 11. Строки и print() (NEW in v1.1)

```juno
fn main() {
    print("Hello, World!")   // Вывод строки
    print(42)                // Вывод числа
    print(100 + 23)          // Вывод выражения
    
    return 0
}
```

- `print(s)` — вывод строки в stdout
- `print(n)` — вывод числа в stdout
- Строки null-terminated в data section

### 12. Импорт модулей (NEW in v1.2)

```juno
import "stdlib/std.juno"
import "mylib/utils.juno"

fn main() {
    let sq = square(5)      // Из stdlib
    let f = factorial(6)    // Из stdlib
    return sq + f
}
```

- Импорт функций и структур из других файлов
- Относительные пути от текущего файла
- Защита от циклических импортов
- `main()` из импортированных модулей игнорируется

### 13. Ассемблерные вставки (insertC)

Прямая инъекция машинного кода x64:

```juno
fn main() {
    // xor rax, rax (обнуление регистра)
    insertC { 0x48 0x31 0xc0 }
    
    // nop
    insertC { 0x90 }
    
    return 0
}
```

### 13. Комментарии

```juno
// Однострочный комментарий
let x = 42  // Комментарий в конце строки
```

## Built-in функции

| Функция | Описание |
|---------|----------|
| `print(s)` | Вывод строки в stdout |
| `print(n)` | Вывод числа в stdout |
| `len(arr)` | Размер массива (compile-time) |
| `len(s)` | Длина строки (runtime) |

## Компиляция

### Windows (PE x64)

```powershell
ruby main_native.rb program.juno
./output.exe
echo %ERRORLEVEL%
```

### Linux (ELF x64)

```bash
ruby main_linux.rb program.juno
chmod +x output_linux
./output_linux
echo $?
```

## Примеры

### Сумма массива

```juno
fn main() {
    let arr[5]
    arr[0] = 10
    arr[1] = 20
    arr[2] = 30
    arr[3] = 40
    arr[4] = 50
    
    let sum = 0
    for (i = 0; i < 5; i++) {
        sum = sum + arr[i]
    }
    
    print(sum)  // 150
    return sum
}
```

### Hello World

```juno
fn main() {
    print("Hello, Juno!")
    return 0
}
```

### Факториал

```juno
fn factorial(n) {
    let result = 1
    for (i = 1; i <= n; i++) {
        result = result * i
    }
    return result
}

fn main() {
    print(factorial(5))  // 120
    return 0
}
```

### 14. Полиморфная компиляция (Generics) (NEW in v1.3)

Juno поддерживает нативную полиморфную компиляцию через мономорфизацию:

```juno
// Generic функция
fn identity<T>(x) {
    return x
}

// Generic структура
struct Box<T> {
    value
}

// Generic метод
fn Box<T>.set(v) {
    self.value = v
}

fn Box<T>.get() {
    return self.value
}

fn main() {
    // Вызов generic функции с конкретным типом
    let x = identity<int>(42)
    
    // Создание generic структуры
    let b = Box<int>
    b.set(100)
    let val = b.get()
    
    return x + val  // 142
}
```

**Особенности:**
- Мономорфизация: для каждого уникального набора типов создаётся специализированная версия функции/структуры
- Нулевая стоимость в рантайме - всё разрешается на этапе компиляции
- Поддержка generic структур и их методов

## Changelog

### v1.3
- ✅ Полиморфная компиляция (generics) с мономорфизацией
- ✅ Generic функции: `fn name<T>(args)`
- ✅ Generic структуры: `struct Name<T> { fields }`
- ✅ Generic методы: `fn Struct<T>.method(args)`

### v1.2
- Импорт модулей (`import "path/module.juno"`)
- Стандартная библиотека (`stdlib/std.juno`)
- Оптимизатор: constant folding, strength reduction
- Оптимизатор: dead code elimination
- Оптимизатор: constant propagation
- Shift вместо умножения/деления на степени 2

### v1.1
- Массивы фиксированного размера (`let arr[N]`)
- Доступ по индексу (`arr[i]`)
- Строковые литералы (`"hello"`)
- `print()` для строк и чисел
- `len()` для массивов и строк

### v1.0
- Базовый синтаксис (let, if, while, for)
- Функции и return
- Структуры и методы
- Арифметика и сравнения
- insertC (ассемблерные вставки)
- Нативная компиляция PE/ELF

---

**Juno** — минималистичный системный язык программирования.
