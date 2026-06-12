#!/bin/bash

# Выходим при любой ошибке
set -e

# Получаем абсолютный путь к текущей папке проекта Juno
JUNO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "=== 1. Установка системных зависимостей ==="
if command -v apt-get &> /dev/null; then
    sudo apt-get update
    sudo apt-get install -y ruby llvm clang gcc tree
else
    echo "Предупреждение: apt-get не найден. Убедитесь, что ruby, llvm, clang и gcc установлены вручную."
fi

echo "=== 2. Удаление старых оберток ==="
sudo rm -f /usr/local/bin/juno
sudo rm -f /usr/local/bin/jpm

echo "=== 3. Создание символических ссылок (Symlinks) ==="

# Ссылка для juno
if [ -f "${JUNO_DIR}/bin/juno" ]; then
    chmod +x "${JUNO_DIR}/bin/juno"
    echo "Создание символической ссылки /usr/local/bin/juno -> ${JUNO_DIR}/bin/juno..."
    sudo ln -sf "${JUNO_DIR}/bin/juno" /usr/local/bin/juno
else
    echo "Ошибка: файл bin/juno не найден!"
    exit 1
fi

# Ссылка для jpm
if [ -f "${JUNO_DIR}/bin/jpm" ]; then
    chmod +x "${JUNO_DIR}/bin/jpm"
    echo "Создание символической ссылки /usr/local/bin/jpm -> ${JUNO_DIR}/bin/jpm..."
    sudo ln -sf "${JUNO_DIR}/bin/jpm" /usr/local/bin/jpm
fi

echo ""
echo "=== Установка завершена! ==="
echo "Проверьте запуск справки: juno -h"
