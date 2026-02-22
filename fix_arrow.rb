file_path = 'src/parser/parts/statements.rb'
content = File.read(file_path)

# Заменяем старую логику проверки типа возврата на новую, которая понимает и ":" и "->"
arrow_fix = <<-'RUBY'
    return_type = nil
    if match?(:colon)
      consume(:colon)
      return_type = consume_type
    elsif match_symbol?('-') && peek_next && peek_next[:value] == '>'
      consume_symbol('-')
      consume_symbol('>')
      return_type = consume_type
    end
RUBY

# Ищем блок обработки return_type в методе parse_fn_definition и заменяем его
content.sub!(/return_type = nil.*?return_type = consume_type\s+end/m, arrow_fix)

File.write(file_path, content)
puts "DONE: Juno now officially supports the '->' arrow for return types!"
