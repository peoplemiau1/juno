file_path = 'src/parser/parts/statements.rb'
content = File.read(file_path)

# 1. Добавляем метод consume_type в начало модуля
type_helper = <<-'RUBY'
  def consume_type
    name = consume_ident
    if match?(:langle)
      name += "<"
      consume(:langle)
      until match?(:rangle)
        name += consume_type # Рекурсивно для вложенных типа Box<vec<int>>
        if match_symbol?(',')
          consume_symbol(',')
          name += ","
        end
      end
      consume(:rangle)
      name += ">"
    end
    name
  end
RUBY

# Вставляем хелпер после определения модуля
content.sub!(/module ParserStatements/, "module ParserStatements\n#{type_helper}")

# 2. Заменяем consume_ident на consume_type там, где ожидаются ТИПЫ
# В parse_fn_definition (параметры и возврат)
content.gsub!(/param_types\[param_name\] = consume_ident/, "param_types[param_name] = consume_type")
content.gsub!(/return_type = consume_ident/, "return_type = consume_type")

# В структурах и юнионах
content.gsub!(/field_types\[field_name\] = consume_ident/, "field_types[field_name] = consume_type")

# В let x: type = ...
content.gsub!(/var_type = consume_ident/, "var_type = consume_type")

File.write(file_path, content)
puts "UPGRADED: Parser now understands complex types like CipherKey<i64>!"
