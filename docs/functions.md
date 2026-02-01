# Функции и Обобщения (Generics)

## Объявление функций
Функции можно объявлять с помощью ключевых слов `fn`, `func` или `def`.
```juno
fn add(a: int, b: int): int {
    return a + b
}
```

## Методы структур
Функции могут быть привязаны к структурам. В таких функциях доступна переменная `self`.
```juno
struct Point { x: int, y: int }

fn Point.move(dx: int, dy: int) {
    self.x = self.x + dx
    self.y = self.y + dy
}
```

## Обобщенное программирование (Generics)
Juno поддерживает параметрический полиморфизм через механизм мономорфизации (генерация отдельного кода для каждого типа во время компиляции).

### Generic-функции
```juno
fn identity<T>(val: T): T {
    return val
}
```

### Generic-структуры
```juno
struct Box<T> {
    value: T
}
```
