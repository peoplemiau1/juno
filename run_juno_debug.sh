#!/bin/bash
for test in tests/*.juno; do
    echo "--------------------------------------------------"
    echo "ТЕСТ: $test"
    ./bin/juno --asm -o build/output "$test" > build/asm.log 2>&1
    if [ $? -ne 0 ]; then
        echo "[FAIL] Ошибка компиляции!"
        continue
    fi
    echo "Компиляция OK. Первые 20 строк ассемблера:"
    head -n 20 build/asm.log
    echo "Запуск..."
    ./build/output > build/run.log 2>&1
    if [ $? -eq 0 ]; then
        echo "[OK] Тест прошел успешно."
    else
        echo "[FAIL] CRASH! GDB Дамп:"
        gdb -batch -ex "run" -ex "bt full" -ex "info registers" ./build/output
    fi
    echo "--------------------------------------------------"
done
