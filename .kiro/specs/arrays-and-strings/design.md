# Design Document: Arrays and Strings

## Overview

Расширение компилятора Juno для поддержки массивов фиксированного размера и null-terminated строк. Реализация на уровне стека (stack allocation) без динамического выделения памяти.

## Architecture

```
┌─────────────────────────────────────────────────────────┐
│                      Source Code                         │
│  let arr[5]                                              │
│  arr[0] = 42                                             │
│  let s = "hello"                                         │
│  print(s)                                                │
└─────────────────────────────────────────────────────────┘
                           │
                           ▼
┌─────────────────────────────────────────────────────────┐
│                        Lexer                             │
│  Новые токены: :lbracket, :rbracket, :string            │
└─────────────────────────────────────────────────────────┘
                           │
                           ▼
┌─────────────────────────────────────────────────────────┐
│                        Parser                            │
│  Новые AST ноды:                                        │
│  - :array_decl { name, size }                           │
│  - :array_access { name, index }                        │
│  - :array_assign { name, index, value }                 │
│  - :string_literal { value }                            │
└─────────────────────────────────────────────────────────┘
                           │
                           ▼
┌─────────────────────────────────────────────────────────┐
│                      CodeGen                             │
│  - Stack allocation для массивов                        │
│  - Data section для строковых литералов                 │
│  - Index computation: base + i * 8                      │
│  - sys_write для print()                                │
└─────────────────────────────────────────────────────────┘
```

## Components and Interfaces

### 1. Lexer Extensions

Новые токены:
```ruby
:lbracket   # [
:rbracket   # ]
:string     # "..."  (уже есть)
```

Изменения в `src/lexer.rb`:
- `[` и `]` уже обрабатываются как symbols
- Строки уже токенизируются как `:string`

### 2. Parser Extensions

Новые AST ноды:

```ruby
# Объявление массива: let arr[10]
{ type: :array_decl, name: "arr", size: 10 }

# Доступ к элементу: arr[i]
{ type: :array_access, name: "arr", index: <expr> }

# Присваивание элементу: arr[i] = value
{ type: :array_assign, name: "arr", index: <expr>, value: <expr> }

# Строковый литерал: "hello"
{ type: :string_literal, value: "hello" }
```

### 3. CodeGen Extensions

#### Array Stack Layout

```
Stack (growing down):
┌─────────────────┐ ← RBP
│   saved RBP     │
├─────────────────┤ RBP - 8
│   arr_ptr       │  (pointer to arr[0])
├─────────────────┤ RBP - 16
│   arr[0]        │
├─────────────────┤ RBP - 24
│   arr[1]        │
├─────────────────┤ RBP - 32
│   arr[2]        │
│      ...        │
└─────────────────┘
```

#### String Data Section

```
.data:
  str_0: db "hello", 0
  str_1: db "world", 0
```

### 4. Built-in Functions

```ruby
# len(arr) - возвращает размер массива (compile-time constant)
# len(s) - вычисляет длину строки (runtime, до null terminator)
# print(s) - sys_write(1, s, len(s))
# print(n) - конвертация int→string, затем sys_write
```

## Data Models

### Array Metadata in Context

```ruby
@ctx.arrays = {
  "arr" => { 
    offset: 16,      # offset от RBP до arr[0]
    size: 10,        # количество элементов
    ptr_offset: 8    # offset переменной-указателя
  }
}
```

### String Literals in Linker

```ruby
@linker.strings = {
  "str_0" => { data: "hello\0", offset: 0 },
  "str_1" => { data: "world\0", offset: 6 }
}
```

## Correctness Properties

*A property is a characteristic or behavior that should hold true across all valid executions of a system-essentially, a formal statement about what the system should do. Properties serve as the bridge between human-readable specifications and machine-verifiable correctness guarantees.*

### Property 1: Array bounds consistency
*For any* array declaration `let arr[N]`, the allocated stack space SHALL be exactly N * 8 bytes, and accessing `arr[i]` where 0 <= i < N SHALL return the value previously stored at that index.
**Validates: Requirements 1.1, 1.2, 1.3**

### Property 2: Array initialization
*For any* newly declared array, all elements SHALL have initial value 0 before any assignment.
**Validates: Requirements 1.4**

### Property 3: String round-trip
*For any* string literal in source code, parsing then code generation SHALL produce a data section entry containing the exact same bytes plus null terminator.
**Validates: Requirements 2.1, 2.4**

### Property 4: String length computation
*For any* null-terminated string, `len(s)` SHALL return the count of bytes before the null terminator.
**Validates: Requirements 3.2**

### Property 5: Array/String pass-by-reference
*For any* array or string passed to a function, modifications to elements inside the function SHALL be visible to the caller.
**Validates: Requirements 5.1, 5.2, 5.3**

## Error Handling

| Error | Detection | Message |
|-------|-----------|---------|
| Array size not a literal | Parser | "Array size must be a constant integer" |
| Negative array size | Parser | "Array size must be positive" |
| Undefined array | CodeGen | "Undefined array: {name}" |
| Index not an expression | Parser | "Expected expression for array index" |

## Testing Strategy

### Unit Tests
- Lexer: токенизация `[`, `]`, строк
- Parser: AST для array_decl, array_access, array_assign
- CodeGen: правильные offsets для массивов

### Property-Based Tests
- **Property 1**: Генерация случайных размеров массивов, проверка stack allocation
- **Property 2**: Проверка нулевой инициализации
- **Property 3**: Round-trip для строковых литералов
- **Property 4**: Генерация случайных строк, проверка len()
- **Property 5**: Модификация массива в функции, проверка видимости

### Integration Tests
- Полная программа с массивами и циклами
- Программа с print() для строк и чисел
