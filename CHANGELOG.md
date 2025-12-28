# CHANGELOG

## v1.7 - 28.12.2025

### Стандартная библиотека v2

#### Память (Heap)
- `malloc(size)` - выделение памяти
- `free(ptr)` - освобождение
- `realloc(ptr, size)` - изменение размера

#### String API
- `str_len`, `str_copy`, `str_cat`, `str_cmp`
- `str_find(s, sub)` - поиск подстроки
- `str_to_int` / `atoi` - парсинг числа
- `int_to_str` / `itoa` - форматирование числа
- `str_upper`, `str_lower`, `str_trim`

#### File API
- `file_open(path, mode)` - режимы: 0=read, 1=write, 2=append
- `file_close`, `file_read`, `file_write`
- `file_writeln` - запись строки с переводом строки
- `file_read_all` - чтение всего файла
- `file_exists`, `file_size`

#### Collections (Vector)
- `vec_new(capacity)` - создание динамического массива
- `vec_push`, `vec_pop` - добавление/удаление
- `vec_get`, `vec_set` - доступ по индексу
- `vec_len`, `vec_cap`, `vec_clear`

### HTTPS
- `curl_get(url)` - GET запрос
- `curl_post(url, data)` - POST запрос с JSON

### Лексер
- Поддержка escape-последовательностей: `\"`, `\\`, `\n`, `\r`, `\t`

### Примеры
- `examples/shadownet.juno` - HTTP сервер
- `examples/telegram_bot.juno` - Telegram бот
- `examples/stdlib_demo.juno` - демо stdlib

---

## v1.6 - 28.12.2025

### Новые возможности

#### Generics
- Параметрический полиморфизм с мономорфизацией
- Generic функции: `fn identity<T>(x: T): T`
- Generic структуры: `struct Box<T> { value: T }`
- Автоматическая специализация типов при компиляции

#### CLI интерфейс
- Новая команда `juno` для работы с компилятором
- `juno build <file>` - компиляция
- `juno run <file>` - компиляция и запуск
- `juno test` - запуск тестов
- `juno new <name>` - создание нового файла
- Скрипт установки `install.sh`

#### Hell Mode (Обфускация)
- Полиморфный генератор инструкций
- Anti-debug техники (ptrace, timing)
- Anti-disassembly junk code
- Opaque predicates
- Dead code injection
- Шифрование строк
- Флаг `--hell` для максимальной обфускации

### Изменения
- Лексер: новые токены `:langle` и `:rangle` для `<` `>`
- Парсер: поддержка type parameters
- Новый файл `src/monomorphizer.rb`
- Новые файлы `src/polymorph/*.rb`

### Примеры
- `examples/client.juno` - TCP клиент
- `examples/http_hello.juno` - HTTP сервер
- `examples/hell_demo.juno` - демо обфускации

---

## v1.5 - 27.12.2025

### Новые возможности
- Многопоточность (thread_create, thread_join)
- Атомарные операции
- Документация по потокам

---

## v1.3 - 26.12.2025

### Исправления
- **Критический баг:** Исправлены вызовы функций с 2+ аргументами
  - Проблема: `add(100, 200)` возвращал 44 вместо 300
  - Решение: Все аргументы теперь вычисляются и сохраняются на стек перед загрузкой в регистры
  - Изменены: `gen_user_fn_call` и `gen_method_call` в `src/codegen/parts/calls.rb`

### Организация проекта
- Все тесты (`test_*.juno`) перемещены в `/tests`
- Примеры программ перемещены в `/examples`
- Артефакты сборки перемещены в `/build`
- Удалены дампы кода (all_code.txt, combined_ruby.txt, juno_complete_source.txt)

### Документация
- Создан `STRUCTURE.md` с описанием структуры проекта
- Создан `CLEANUP_SUMMARY.md` с описанием исправлений
- Обновлен `README.md` с информацией о v1.3
- Обновлен `TODO.md` - отмечены исправленные баги

### Конфигурация
- Обновлен `.gitignore` - добавлены правила для build/, логов, IDE файлов
- Создан `.editorconfig` для консистентного форматирования кода

### Тесты
- Создан `tests/test_multiarg_fix.juno` для проверки исправления

---

## v1.2 - Предыдущие версии

- **26.12.2024** _Started reworking codegen. Codegen now translates code into C and then compiles with tcc. also codegen has been split into different files._
- **27.12.2024** _work continued on the codegen revision. include and insertc was added._
- **04.03.2025** _