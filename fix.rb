# Скрипт для исправления критических багов ARM64 в Juno
paths = {
  emitter: 'src/codegen/parts/emitter_aarch64.rb',
  linker: 'src/codegen/parts/linker.rb'
}

# 1. Исправляем AArch64Emitter (добавляем mov_mem_idx и правим патчи)
emitter_code = File.read(paths[:emitter])

# Добавляем правильный mov_mem_idx, если его нет
unless emitter_code.include?('def mov_mem_idx')
  new_methods = <<~RUBY
    def mov_mem_idx(base, offset, src, size = 8)
      if size == 8
        emit32(0xf9000000 | (((offset / 8) & 0xFFF) << 10) | (base << 5) | src)
      elsif size == 4
        emit32(0xb9000000 | ((offset & 0xFFF) << 10) | (base << 5) | src)
      elsif size == 1
        emit32(0x39000000 | ((offset & 0xFFF) << 10) | (base << 5) | src)
      end
    end
  RUBY
  emitter_code.sub!(/^end\s*$/i, "\n\#{new_methods}\nend")
end

# Исправляем маски для JE/JNE/JMP (чтобы отрицательные оффсеты не ломали опкод)
emitter_code.gsub!('offset << 5', '(offset & 0x7ffff) << 5')
emitter_code.gsub!('offset & 0x3FFFFFF', 'offset & 0x03FFFFFF')

File.write(paths[:emitter], emitter_code)

# 2. Исправляем Linker (правильный расчет ADR и BL)
linker_code = File.read(paths[:linker])
linker_code.gsub!('immhi = (offset >> 2) & 0x7FFFF', 'immhi = ((offset >> 2) & 0x7FFFF)')
linker_code.gsub!('instr = (instr & 0xFC000000) | (offset & 0x03FFFFFF)', 'instr = (instr & 0xFC000000) | (offset & 0x03FFFFFF)')

File.write(paths[:linker], linker_code)

puts "Juno ARM64 Backend repaired successfully!"
