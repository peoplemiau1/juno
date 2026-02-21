<p align="center">
  <img src="juno-logo.png" alt="Juno" width="200"/>
</p>

<h1 align="center">Juno v2.1 "Architectural Integrity"</h1>

<p align="center">
  <b>Быстрый компилируемый язык для Linux x86-64 и AArch64</b><br>
  Реестровый аллокатор • Ownership Audit • Нативный код • Turbo-оптимизатор • Поддержка ARM64
</p>

---

## Что нового в v2.1

*   **Linear Scan Register Allocator**: Переменные теперь живут в регистрах (`RBX`, `R12-R15` для x86; `X19-X28` для ARM). Это значительно ускоряет код и делает его "чище".
*   **Resource Ownership Auditor**: Компилятор теперь следит за жизненным циклом ресурсов (`malloc`, `json_loads`). Правило: «Родил -> Убил». Утечки и использование после освобождения караются ошибкой компиляции.
*   **Hardened Hell Mode**: Обфускатор теперь использует полноценный декодер длин инструкций. Больше никаких падений при вставке junk-кода!
*   **Modular Standard Library**: Добавлены модули `std/str`, `std/vec`, `std/fs`, `std/net`, `std/json` и `std/arena`.

## Быстрый старт

```bash
git clone https://github.com/peoplemiau1/juno.git
cd juno && ./install.sh && source ~/.bashrc
```

```bash
juno run hello.juno           # запустить
juno build hello.juno -o app  # скомпилировать (x86_64 по умолчанию)
juno build hello.juno -a aarch64 -o app_arm  # скомпилировать для ARM64
juno build app.juno --hell    # с обфускацией (Hell Mode v2.1)
```

## Синтаксис v2.1

```juno
import std/str
import std/json

fn main(): int {
    // Реестровый аллокатор автоматически выберет регистры для p и root
    let raw = "{\"status\": \"ok\"}"
    let root = json_loads(raw)
    
    // Resource Auditor проверит, что root будет освобожден
    if root != 0 {
        let status = json_get_str(root, "status")
        prints(status)
        prints("\n")
    }
    
    json_free(root) // Born -> Kill
    return 0
}
```

## Возможности

| Категория | Функции |
|-----------|---------|
| **Архитектуры** | Linux x86-64, **Linux AArch64 (ARM64)**, Windows (PE) |
| **Регистры** | Linear Scan Allocator, Callee-saved preservation, Scratch Manager |
| **Память** | `malloc`, `realloc`, `free`, `Arena Allocator`, `mmap` |
| **Ownership** | Strict Audit (E0007), Move semantics, Leak detection |
| **Строки** | `String` struct, `str_new`, `str_concat`, `str_split`, `str_len` |
| **Стандартная библиотека** | `Vec`, `List`, `Stack`, `Queue`, `JSON Parser`, `Arena` |
| **Файлы** | `fs_read_text`, `fs_write_text`, `file_open`, `file_size` |
| **Сеть** | `TcpServer`, `net_listen`, `EpollLoop`, HTTP |
| **Безопасность** | Hell Mode v2.1 (Polymorphic Engine + Precise Decoder) |

## Примеры

### Работа со строками (std/str)
```juno
import std/str

fn main() {
    let s1 = str_new("Hello ")
    let s2 = str_new("Juno!")
    let s3 = str_concat(s1, s2)

    prints(s3.data)

    str_free(s1)
    str_free(s2)
    str_free(s3)
}
```

### Использование Arena Allocator
```juno
import std/arena

fn main() {
    let a = arena_new(1024)
    let s = arena_str(a, "Scoped string")
    
    // Arena освободит всё сразу
    arena_free(a)
}
```

## Производительность

```
Register-based loops:  30% faster than v2.0
Monomorphized code:    Native speed
Turbo Optimizer:       Inlining, Loop unrolling, CSE
```

## Документация

| Файл | Описание |
|------|----------|
| [DOCS.md](DOCS.md) | Полный справочник API |
| [stdlib/](stdlib/) | Исходный код стандартной библиотеки |
| [examples/](examples/) | 34+ рабочих примера |

## Лицензия

MIT
