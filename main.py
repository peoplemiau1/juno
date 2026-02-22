import pathlib

# Конфигурация
EXTENSIONS = {'.juno', '.mc', '.rb'}
OUTPUT_FILE = "combined_project.txt"

def collect_files():
    root = pathlib.Path('.')
    count = 0
    
    with open(OUTPUT_FILE, 'w', encoding='utf-8') as outfile:
        # Рекурсивный поиск файлов
        for path in root.rglob('*'):
            if path.suffix.lower() in EXTENSIONS and path.name != OUTPUT_FILE:
                outfile.write(f"\n\n{'='*50}\n")
                outfile.write(f"FILE: {path}\n")
                outfile.write(f"{'='*50}\n\n")
                
                try:
                    content = path.read_text(encoding='utf-8', errors='ignore')
                    outfile.write(content)
                    count += 1
                    print(f"[+] Добавлен: {path}")
                except Exception as e:
                    print(f"[!] Ошибка в {path}: {e}")

    print(f"\nГотово! Собрано файлов: {count} в {OUTPUT_FILE}")

if __name__ == "__main__":
    collect_files()
