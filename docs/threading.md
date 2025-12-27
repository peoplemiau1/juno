# Многопоточность

## Потоки

| Функция | Описание |
|---------|----------|
| `thread_create(fn, stack, arg)` | Создать поток |
| `thread_exit(code)` | Завершить поток |
| `alloc_stack(size)` | Выделить стек для потока |
| `clone(flags, stack)` | Низкоуровневый clone() |

## Синхронизация

| Функция | Описание |
|---------|----------|
| `sleep(seconds)` | Пауза в секундах |
| `usleep(microseconds)` | Пауза в микросекундах |
| `spin_lock(ptr)` | Захватить spinlock |
| `spin_unlock(ptr)` | Освободить spinlock |
| `futex(addr, op, val)` | Futex операция |

## Атомарные операции

| Функция | Описание |
|---------|----------|
| `atomic_add(ptr, val)` | Атомарное сложение |
| `atomic_sub(ptr, val)` | Атомарное вычитание |
| `atomic_load(ptr)` | Атомарное чтение |
| `atomic_store(ptr, val)` | Атомарная запись |
| `atomic_cas(ptr, exp, new)` | Compare-and-swap |

## Константы Clone

| Константа | Описание |
|-----------|----------|
| `CLONE_VM()` | Общая память |
| `CLONE_FS()` | Общая файловая система |
| `CLONE_FILES()` | Общие файловые дескрипторы |
| `CLONE_SIGHAND()` | Общие обработчики сигналов |
| `CLONE_THREAD()` | Тот же thread group |

## Константы Futex

| Константа | Значение |
|-----------|----------|
| `FUTEX_WAIT()` | 0 |
| `FUTEX_WAKE()` | 1 |

## Примеры

### Sleep

```juno
fn main(): int {
    print("Sleeping 2 seconds...")
    sleep(2)
    print("Done!")
    
    print("Sleeping 500ms...")
    usleep(500000)
    print("Done!")
    
    return 0
}
```

### Spinlock

```juno
fn main(): int {
    let lock = 0
    
    // Захватить
    spin_lock(&lock)
    print("Critical section")
    spin_unlock(&lock)
    
    return 0
}
```

### Атомарный счётчик

```juno
fn main(): int {
    let counter = 0
    
    // Атомарно увеличить на 10
    let old = atomic_add(&counter, 10)
    print("Old value:")
    print(old)      // 0
    
    print("New value:")
    print(counter)  // 10
    
    // Ещё раз
    atomic_add(&counter, 5)
    print("Final:")
    print(counter)  // 15
    
    return 0
}
```

### Compare-and-Swap

```juno
fn main(): int {
    let value = 100
    
    // Если value == 100, заменить на 200
    let old = atomic_cas(&value, 100, 200)
    
    print("Old:")
    print(old)      // 100
    print("New:")
    print(value)    // 200
    
    // Попробуем снова (не сработает)
    old = atomic_cas(&value, 100, 300)
    print("After failed CAS:")
    print(value)    // Всё ещё 200
    
    return 0
}
```

### Простой поток

```juno
#define STACK_SIZE 65536

fn worker(arg: int): int {
    print("Worker started with arg:")
    print(arg)
    sleep(1)
    print("Worker done")
    return 42
}

fn main(): int {
    // Выделить стек
    let stack = alloc_stack(STACK_SIZE)
    
    // Создать поток
    let tid = thread_create(&worker, stack, 123)
    
    if (tid > 0) {
        print("Created thread:")
        print(tid)
    }
    
    // Подождать (простой способ)
    sleep(2)
    
    return 0
}
```
