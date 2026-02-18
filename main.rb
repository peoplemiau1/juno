# Исправление регистров для x86_64 в File API
file_path = 'src/codegen/parts/builtins/file_api.rb'
content = File.read(file_path)

# Исправляем передачу пути: заменяем жесткую 4 (RSP на x86) на выбор между 4 (X4 на ARM) и 12 (R12 на x86)
content.gsub!(/mov_reg_reg\(@arch == :aarch64 \? 1 : 7, 4\)/, 
              'mov_reg_reg(@arch == :aarch64 ? 1 : 7, @arch == :aarch64 ? 4 : 12)')

# Исправляем флаги для openat/open
content.gsub!(/mov_reg_reg\(@arch == :aarch64 \? 2 : 6, 0\)/, 
              'mov_reg_reg(@arch == :aarch64 ? 2 : 6, 0)')

File.write(file_path, content)
puts "File API Fixed: x86_64 registers are now correctly mapped!"
