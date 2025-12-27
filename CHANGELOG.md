# CHANGELOG

## v1.3 - 26.12.2024

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