# Requirements Document

## Introduction

Расширение языка Juno для поддержки массивов и строк. Это позволит работать с коллекциями данных и текстом на системном уровне, сохраняя философию минимализма и прямого контроля над памятью.

## Glossary

- **Array**: Непрерывный блок памяти фиксированного размера для хранения элементов одного типа (64-bit integers)
- **String**: Массив байтов, представляющий текст в кодировке ASCII, завершающийся нулевым байтом (null-terminated)
- **Index**: Целочисленное смещение для доступа к элементу массива (начиная с 0)
- **Length**: Количество элементов в массиве или символов в строке
- **Stack Allocation**: Выделение памяти на стеке функции
- **Juno Compiler**: Компилятор языка Juno, генерирующий нативный x64 код

## Requirements

### Requirement 1

**User Story:** As a developer, I want to create fixed-size arrays, so that I can store multiple values of the same type efficiently.

#### Acceptance Criteria

1. WHEN a developer declares an array with syntax `let arr[N]` THEN the Juno Compiler SHALL allocate N * 8 bytes on the stack
2. WHEN a developer accesses an array element with syntax `arr[i]` THEN the Juno Compiler SHALL compute the address as base + i * 8
3. WHEN a developer assigns to an array element with syntax `arr[i] = value` THEN the Juno Compiler SHALL store the value at the computed address
4. WHEN an array is declared THEN the Juno Compiler SHALL initialize all elements to zero

### Requirement 2

**User Story:** As a developer, I want to create and manipulate strings, so that I can work with text data in my programs.

#### Acceptance Criteria

1. WHEN a developer declares a string literal with syntax `let s = "text"` THEN the Juno Compiler SHALL store the string in the data section with null terminator
2. WHEN a developer accesses a string character with syntax `s[i]` THEN the Juno Compiler SHALL return the byte value at position i
3. WHEN a developer assigns to a string character with syntax `s[i] = c` THEN the Juno Compiler SHALL store the byte value at position i
4. WHEN a string literal is parsed THEN the Juno Compiler SHALL produce an AST node containing the string content
5. WHEN a string literal is printed THEN the Juno Compiler SHALL output the string followed by a newline using sys_write syscall

### Requirement 3

**User Story:** As a developer, I want built-in functions for array and string operations, so that I can perform common tasks without manual memory manipulation.

#### Acceptance Criteria

1. WHEN a developer calls `len(arr)` on an array THEN the Juno Compiler SHALL return the declared size of the array
2. WHEN a developer calls `len(s)` on a string THEN the Juno Compiler SHALL compute and return the length by counting bytes until null terminator
3. WHEN a developer calls `print(s)` on a string THEN the Juno Compiler SHALL output the string to stdout using sys_write syscall
4. WHEN a developer calls `print(n)` on an integer THEN the Juno Compiler SHALL convert the integer to string and output to stdout

### Requirement 4

**User Story:** As a developer, I want to iterate over arrays and strings, so that I can process each element sequentially.

#### Acceptance Criteria

1. WHEN a developer uses a for loop with array length THEN the Juno Compiler SHALL correctly iterate from 0 to len-1
2. WHEN a developer accesses array elements inside a loop THEN the Juno Compiler SHALL correctly compute element addresses for each iteration
3. WHEN a developer iterates over a string THEN the Juno Compiler SHALL allow access to each character by index

### Requirement 5

**User Story:** As a developer, I want to pass arrays and strings to functions, so that I can create reusable code for data processing.

#### Acceptance Criteria

1. WHEN a developer passes an array to a function THEN the Juno Compiler SHALL pass the base address of the array
2. WHEN a developer passes a string to a function THEN the Juno Compiler SHALL pass the pointer to the first character
3. WHEN a function receives an array or string parameter THEN the Juno Compiler SHALL allow element access using index syntax
