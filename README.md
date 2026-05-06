# Juno Programming Language v3.0

Juno — системный язык программирования, ориентированный на максимальную производительность, безопасность ресурсов и кросс-платформенную разработку. В версии 3.0 внедрен полноценный LLVM-тулчейн, поддержка новых архитектур и автоматизированная стандартная библиотека.

## Основные возможности

*   **LLVM Backend**: Использование инфраструктуры LLVM 19 для генерации высокооптимизированного машинного кода.
*   **Multi-Arch**: Нативная поддержка `x86_64`, `aarch64`, `arm`, `riscv32` и `riscv64`.
*   **Flat Binary**: Режим прямой генерации сырых бинарных образов для разработки ядер ОС, загрузчиков и bare-metal приложений.
*   **Resource Safety**: Комбинация статического аудита ресурсов (Resource Auditor) и системы владения (Borrow Checker) для предотвращения утечек и double-free на этапе компиляции.
*   **Zero-Cost StdLib**: Модульная стандартная библиотека на чистом Juno, заменяющая встроенные примитивы компилятора.
*   **Atomic Primitives**: Встроенная поддержка атомарных операций (`spin_lock`, `spin_unlock`) на уровне инструкций LLVM.

## Быстрый старт

### Требования
*   Ruby 3.0+
*   LLVM 19 (`llc-19`, `llvm-objcopy-19`)
*   GCC (для линковки под хост)

### Использование CLI
```bash
# Компиляция и запуск под текущую архитектуру
./bin/juno -r main.juno

# Кросс-компиляция в плоский бинарник для ARM
./bin/juno -a arm -t flat kernel.juno -o build/kernel.bin

# Компиляция объектного файла без линковки
./bin/juno -t obj module.juno
```

### Параметры командной строки
| Флаг | Описание | Значения |
| :--- | :--- | :--- |
| `-a, --arch` | Целевая архитектура | `x86_64`, `aarch64`, `arm`, `riscv32`, `riscv64` |
| `-t, --target` | Тип выходного файла | `exe` (elf), `flat` (raw bin), `obj` (object) |
| `-o, --output` | Путь к результату | По умолчанию `build/output` |
| `-r, --run` | Запуск после сборки | Только для `target: exe` |
| `--asm` | Дамп IR/Assembly | Вывод логов генерации кода |
| `--no-audit` | Отключить аудит | Пропустить проверку безопасности ресурсов |

## Обзор синтаксиса

### Модули и Импорт
Juno автоматически импортирует `std.juno` при компиляции. Ручной импорт используется для сторонних модулей.
```juno
import "ds/collections.juno"
```

### Функции и Типы
```juno
// Определение структуры
struct Buffer {
    data: ptr
    size: int
}

// Метод (имена манглятся как Buffer_init)
fn Buffer.init(self, sz: int) {
    self.data = malloc(sz)
    self.size = sz
}

fn main() {
    let mut buf: Buffer = malloc(16)
    buf.init(1024)
    
    output("Buffer allocated")
    
    free(buf.data)
    free(buf)
}
```

### Синхронизация (Atomics)
```juno
let lock: SpinLock = malloc(8)
lock.init()

lock.lock()
// критическая секция
lock.unlock()
```

## Архитектура
1.  **Frontend**: Лексический анализ и парсинг в AST.
2.  **Middle-end**: 
    - `Importer`: Разрешение зависимостей.
    - `Monomorphizer`: Генерация типизированных копий функций.
    - `BorrowChecker`: Анализ владения.
    - `TurboOptimizer`: Инлайнинг, константная свертка, DCE.
3.  **Backend**: Генерация LLVM IR и вызов `llc-19`.

## Лицензия
MIT License. См. файл [LICENSE](LICENSE).
