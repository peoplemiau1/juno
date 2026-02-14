<p align="center">
  <img src="juno-logo.png" alt="Juno" width="200"/>
</p>

<h1 align="center">Juno v2.0</h1>

<p align="center">
  <b>Быстрый компилируемый язык для Linux x86-64 и AArch64</b><br>
  Простой синтаксис • Нативный код • Turbo-оптимизатор • Поддержка ARM64
</p>

---

## Быстрый старт

```bash
git clone https://github.com/peoplemiau1/juno.git
cd juno && ./install.sh && source ~/.bashrc
```

```bash
juno run hello.juno           # запустить
juno build hello.juno -o app  # скомпилировать (x86_64 по умолчанию)
juno build hello.juno --arch aarch64 -o app_arm  # скомпилировать для ARM64
juno build app.juno --hell    # с обфускацией
```

## Синтаксис

```juno
// Функции: fn, func или def
def main(): int {
    // Условия без скобок
    if 1 == 1 {
        prints("Hello, Juno!")
    }
    
    // Циклы
    x = 0
    while x < 5 {
        print(x)
        x = x + 1
    }
    
    // Оператор остатка от деления
    let rem = 10 % 3 // rem = 1

    return 0
}
```

## Возможности

| Категория | Функции |
|-----------|---------|
| **Архитектуры** | Linux x86-64, **Linux AArch64 (ARM64)**, Windows (PE) |
| **Оптимизатор** | Инлайнинг, развёртка циклов, CSE, strength reduction |
| **Память** | `malloc`, `realloc`, `free`, `memfd_create`, `mmap` |
| **Строки** | `concat`, `substr`, `str_len`, `str_find`, `itoa`, `atoi` |
| **Стандартная библиотека** | `List`, `Stack`, `Queue`, `bubble_sort`, `is_prime` |
| **Файлы** | `file_open`, `file_read_all`, `lseek`, `close` |
| **Коллекции** | `vec_new`, `vec_push`, `vec_pop`, `vec_get` |
| **Сеть** | TCP сокеты, HTTP, `curl_get`, `curl_post` |
| **Система** | `fork`, `execve`, `pipe`, `kill`, `thread_create`, `getpid` |
| **Безопасность** | Hell Mode обфускация |

## Примеры

### Работа со структурами данных (stdlib)
```juno
import "stdlib/std.juno"

fn main(): int {
    let list = List
    list.init(10)
    list.add(42)
    list.add(13)

    print(list.get(0))
    return 0
}
```

### Системная информация (JunoFetch)
```juno
fn main(): int {
    prints("Kernel:  ")
    prints(file_read_all("/proc/sys/kernel/osrelease"))
    prints("Host:    ")
    prints(file_read_all("/etc/hostname"))
    return 0
}
```

### Память в RAM (memfd)
```juno
fn main(): int {
    fd = memfd_create("data", MFD_CLOEXEC())
    write(fd, "Secret!", 7)
    lseek(fd, 0, SEEK_SET())
    
    buf = malloc(64)
    read(fd, buf, 64)
    prints(buf)
    
    close(fd)
    return 0
}
```

## Производительность

```
Sum 1M iterations:    11ms
Nested 1000x1000:     instant
Math ops 1M:          instant
```

Turbo Optimizer включает:
- Инлайнинг функций (<10 нод)
- Развёртка циклов (<8 итераций)  
- Удаление общих подвыражений (CSE)
- Strength reduction (mul→shift, div→shift)
- Константная пропагация

## Документация

| Файл | Описание |
|------|----------|
| [DOCS.md](DOCS.md) | Полный справочник API |
| [Подробная документация](docs/) | Разделенная документация по темам |
| [CHANGELOG.md](CHANGELOG.md) | История версий |
| [examples/](examples/) | 34 рабочих примера |

## Лицензия

MIT
