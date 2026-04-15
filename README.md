# Juno: Systems Programming Language

Juno — это нативный компилируемый язык программирования для системного уровня. Ориентирован на производительность, безопасность ресурсов и прямой контроль над железом. Компилируется напрямую в машинный код для архитектур **x86-64** и **AArch64** (Linux).

## Ключевые возможности

*   **Native Code Generation**: Прямая генерация машинных инструкций. Никакого байт-кода, интерпретации или зависимости от LLVM/GCC.
*   **Zero-Overhead Memory**: Ручное управление памятью (`malloc`/`free`) и эффективная работа со стеком.
*   **Linear Scan Register Allocation**: Автоматическое распределение переменных по регистрам процессора для минимизации обращений к памяти.
*   **Monomorphization**: Поддержка дженериков через генерацию специализированного кода для каждого типа.
*   **Static Resource Audit**: Встроенный анализатор владения ресурсами для предотвращения утечек памяти на этапе компиляции.
*   **Transparent ABI**: Строгое соблюдение System V ABI для бесшовной интеграции с библиотеками C и системными вызовами Linux.

## Установка и запуск

Для работы требуется Ruby 3.0+.

```bash
# Сборка и запуск примера
./bin/juno -r examples/hello.juno
```

### Использование CLI

```bash
Usage: juno [options] <input_file>
    -a, --arch ARCH                  Target architecture (x86_64, aarch64)
    -o, --output FILE                Output binary path
    -t, --target OS                  Target OS (linux, flat)
    -r, --run                        Run after compilation
```

## Синтаксические особенности

Синтаксис Juno вдохновлен современными языками (Swift, Rust), но сохраняет семантическую простоту C.

```juno
import "std/io.juno"

struct Point {
    let x: int
    let y: int
}

fn main(): int {
    let p: Point = malloc(16)
    p.x = 10
    p.y = 20
    
    print(p.x + p.y)
    
    free(p)
    return 0
}
```

## Документация

Подробную информацию можно найти в директории `docs/`:
- [Синтаксис](docs/syntax.md)
- [Функции](docs/functions.md)
- [Архитектура компилятора](docs/architecture.md)
- [Стандартная библиотека](docs/stdlib.md)
- [Системные вызовы](docs/syscalls.md)

## Лицензия

Juno распространяется под лицензией MIT.
