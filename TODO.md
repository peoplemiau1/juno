# Juno TODO

## Выполнено в v1.4

### Системное программирование
- [x] Битовые операции (`&`, `|`, `^`, `~`, `<<`, `>>`)
- [x] Логические операции (`&&`, `||`)
- [x] Hex/binary/octal литералы (`0xFF`, `0b1010`, `0o755`)
- [x] Размерные типы (`i8`, `u8`, `i16`, `u16`, `i32`, `u32`, `i64`, `u64`)
- [x] Приведение типов (`u8(val)`, `i32(val)`)
- [x] Арифметика указателей (`ptr_add`, `ptr_sub`, `ptr_diff`)
- [x] `sizeof()`
- [x] Union типы
- [x] Packed структуры
- [x] Препроцессор (`#define`, `#ifdef`, `#ifndef`, `#else`, `#endif`)

### Системные вызовы (Linux)
- [x] Процессы: `fork`, `wait`, `exit`, `getpid`, `getppid`, `getuid`, `getgid`, `kill`
- [x] Файлы: `open`, `close`, `read`, `write`, `mkdir`, `rmdir`, `unlink`, `chmod`, `chdir`, `getcwd`
- [x] Память: `mmap`, `munmap`, `memcpy`, `memset`
- [x] Каналы: `pipe`, `dup`, `dup2`

### Сокеты
- [x] `socket(domain, type, protocol)`
- [x] `bind(sock, ip, port)`
- [x] `listen(sock, backlog)`
- [x] `accept(sock)`
- [x] `connect(sock, ip, port)`
- [x] `send(sock, buf, len)`
- [x] `recv(sock, buf, len)`
- [x] `ip(a, b, c, d)` - helper для создания IP

### Атомарные операции
- [x] `atomic_add`, `atomic_sub`
- [x] `atomic_load`, `atomic_store`
- [x] `atomic_cas`
- [x] `spin_lock`, `spin_unlock`
- [x] `futex`

### Компилятор
- [x] Регистровый аллокатор (RBX, R12-R15)
- [x] Синтаксис типов (`let x: int`, `fn f(a: int): int`)

## В разработке

### Высокий приоритет
- [ ] Type checker (проверка типов)
- [ ] Строковая интерполяция
- [ ] Windows сокеты (Winsock)
- [ ] Улучшенные сообщения об ошибках

### Средний приоритет
- [ ] LSP (Language Server Protocol)
- [ ] Многострочные комментарии `/* */`
- [ ] Inline функции
- [ ] Tail call оптимизация

### Низкий приоритет
- [ ] Самохостинг (компилятор на Juno)
- [ ] Debug info (DWARF/PDB)
- [ ] Пакетный менеджер

## Известные ограничения

1. Сокеты работают только на Linux
2. Строки не поддерживают escape-последовательности кроме `\r\n\t`
3. Нет garbage collector (ручное управление памятью)
4. Максимум 6 аргументов функции (ограничение ABI)
