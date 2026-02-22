import pathlib

def merge_ruby_files(output_filename="combined_ruby.txt", search_dir="."):
    # Создаем объект пути для директории поиска
    base_path = pathlib.Path(search_dir)
    # Имя выходного файла
    output_path = pathlib.Path(output_filename)

    count = 0

    with open(output_path, "w", encoding="utf-8") as outfile:
        # Рекурсивный поиск всех файлов с расширением .rb
        for rb_file in base_path.rglob("*.rb"):
            # Пропускаем сам выходной файл, если он вдруг попал в поиск
            if rb_file.name == output_path.name:
                continue

            try:
                # Записываем заголовок с именем файла для удобства навигации
                outfile.write(f"\n{'='*50}\n")
                outfile.write(f"FILE: {rb_file}\n")
                outfile.write(f"{'='*50}\n\n")

                # Читаем содержимое .rb файла и записываем в общий
                with open(rb_file, "r", encoding="utf-8", errors="ignore") as infile:
                    outfile.write(infile.read())

                outfile.write("\n")
                count += 1
                print(f"Добавлен: {rb_file}")

            except Exception as e:
                print(f"Ошибка при чтении {rb_file}: {e}")

    print(f"\nГотово! Объединено файлов: {count}")
    print(f"Результат сохранен в: {output_path.absolute()}")

if __name__ == "__main__":
    merge_ruby_files()