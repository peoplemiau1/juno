# Стандартная библиотека Juno

## Математика
В `stdlib/std.juno` определены:
*   `square(x)`, `cube(x)`
*   `abs_val(x)`, `min_val(a, b)`, `max_val(a, b)`
*   `clamp(x, lo, hi)`
*   `factorial(n)`, `fib(n)`, `gcd(a, b)`

## Работа со строками
*   `str_len(s)`: Длина строки.
*   `str_cmp(s1, s2)`: Сравнение.
*   `str_empty(s)`: Проверка на пустоту.
*   `str_equals(s1, s2)`: Проверка на равенство.
*   `int_to_str(n)`, `str_to_int(s)`

## Коллекции
### List
Динамический массив с автоматическим изменением размера.
*   `List.init(cap)`: Инициализация.
*   `List.add(val)`: Добавление элемента.
*   `List.get(index)`: Получение элемента.
*   `List.size()`: Текущий размер.

## Ввод-вывод
*   `print(n)`: Вывод числа.
*   `prints(s)`: Вывод строки.
*   `file_read_all(path)`: Чтение файла полностью.
*   `os_write_file(path, buf, len)`
