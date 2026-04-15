# Стандартная библиотека Juno

Стандартная библиотека предоставляет базовый набор функций для работы с системой, структурами данных и вводом-выводом.

## Базовый ввод-вывод (`core/io.juno`)
- `print(n)`: Вывод целого числа в stdout.
- `prints(s)`: Вывод строки в stdout.
- `print_ptr(p)`: Вывод указателя (адреса).

## Работа с памятью (`core/mem.juno`)
- `malloc(size)`: Выделение памяти.
- `free(ptr)`: Освобождение памяти.
- `memcpy(dst, src, len)`: Копирование блоков памяти.
- `memset(dst, val, len)`: Заполнение памяти.

## Математика (`core/math.juno`)
- `min_val(a, b)`, `max_val(a, b)`: Поиск минимума/максимума.
- `abs_val(x)`: Модуль числа.
- `factorial(n)`, `fib(n)`, `gcd(a, b)`: Классические алгоритмы.

## Строки (`std/str.juno`)
- `str_len(s)`: Длина null-terminated строки.
- `str_cmp(s1, s2)`: Сравнение строк.
- `str_equals(s1, s2)`: Проверка на равенство.
- `str_to_int(s)`, `int_to_str(n)`: Конвертация.

## Динамические структуры данных (`ds/collections.juno`)
### List
Динамический массив с автоматическим расширением.
```swift
let list = List
list.init(10)
list.add(42)
let val = list.get(0)
let s = list.size()
```

## Работа с файлами (`std/fs.juno`)
- `file_open(path, flags)`
- `file_read_all(path)`: Чтение всего содержимого файла в буфер.
- `file_exists(path)`: Проверка наличия файла.

## Сеть (`std/net.juno`)
- `tcp_connect(host, port)`
- `tcp_listen(port)`
- `http_get(url)`: Простой HTTP-запрос.
