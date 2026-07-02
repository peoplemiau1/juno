#!/usr/bin/env python3
import os
import sys
import subprocess
import shutil

def run_sudo_cmd(cmd):
    # Check if we are root, if not, prepend sudo
    if os.getuid() != 0:
        full_cmd = ["sudo"] + cmd
    else:
        full_cmd = cmd
    print(f"Running: {' '.join(full_cmd)}")
    subprocess.run(full_cmd, check=True)

def main():
    print("=== 1. Установка системных зависимостей ===")
    if shutil.which("apt-get"):
        try:
            run_sudo_cmd(["apt-get", "update"])
            run_sudo_cmd(["apt-get", "install", "-y", "ruby", "llvm", "clang", "gcc", "tree"])
        except subprocess.CalledProcessError as e:
            print(f"Ошибка при установке системных зависимостей: {e}")
            sys.exit(1)
    else:
        print("Предупреждение: apt-get не найден. Убедитесь, что ruby, llvm, clang и gcc установлены вручную.")

    # Get absolute path of Juno project directory
    juno_dir = os.path.dirname(os.path.abspath(__file__))

    print("=== 2. Удаление старых оберток ===")
    for binary in ["juno", "jpm"]:
        dest = f"/usr/local/bin/{binary}"
        if os.path.exists(dest) or os.path.islink(dest):
            try:
                run_sudo_cmd(["rm", "-f", dest])
            except Exception as e:
                print(f"Предупреждение: Не удалось удалить {dest}: {e}")

    print("=== 3. Создание символических ссылок (Symlinks) ===")
    
    # Symlink for juno
    juno_bin = os.path.join(juno_dir, "bin", "juno")
    if os.path.isfile(juno_bin):
        os.chmod(juno_bin, 0o755)
        print(f"Создание символической ссылки /usr/local/bin/juno -> {juno_bin}...")
        try:
            run_sudo_cmd(["ln", "-sf", juno_bin, "/usr/local/bin/juno"])
        except subprocess.CalledProcessError as e:
            print(f"Ошибка при создании ссылки для juno: {e}")
            sys.exit(1)
    else:
        print(f"Ошибка: файл {juno_bin} не найден!")
        sys.exit(1)

    # Symlink for jpm
    jpm_bin = os.path.join(juno_dir, "bin", "jpm")
    if os.path.isfile(jpm_bin):
        os.chmod(jpm_bin, 0o755)
        print(f"Создание символической ссылки /usr/local/bin/jpm -> {jpm_bin}...")
        try:
            run_sudo_cmd(["ln", "-sf", jpm_bin, "/usr/local/bin/jpm"])
        except subprocess.CalledProcessError as e:
            print(f"Предупреждение: не удалось создать ссылку для jpm: {e}")

    print("\n=== Установка завершена! ===")
    print("Проверьте запуск справки: juno -h")

if __name__ == "__main__":
    main()
