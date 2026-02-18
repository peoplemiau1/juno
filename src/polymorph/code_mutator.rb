# Code Mutator - интеграция полиморфного движка с генератором кода Juno
# Превращает обычный код в кошмар для реверсера

require_relative 'polymorph_engine'

class CodeMutator
  attr_reader :stats
  attr_accessor :arch

  def initialize(options = {})
    @engine = PolymorphEngine.new(options[:seed])
    @engine.mutation_level = options[:level] || 3
    @stats = { junk_added: 0 }
    @enabled = options[:enabled] != false
    @anti_debug = options[:anti_debug] || false
    @encrypt_strings = options[:encrypt_strings] || false
    @arch = options[:arch] || :x86_64
  end

  # Мутировать блок машинного кода
  def mutate_code(bytes)
    return bytes unless @enabled
    
    result = []
    
    # Добавляем junk в начале
    result += @engine.junk_instructions
    
    # Добавляем opaque predicate
    if rand < 0.3
      result += @engine.opaque_true
    end
    
    # Основной код
    result += bytes
    
    # Junk в конце
    result += @engine.poly_nop(rand(3) + 1)
    
    result
  end

  # Мутировать функцию целиком
  def mutate_function(func_bytes)
    return func_bytes unless @enabled
    
    result = []
    
    # Anti-debug пролог
    if @anti_debug
      result += anti_debug_check
    end
    
    # Dead code перед функцией
    if rand < 0.4
      result += @engine.dead_code_block
    end
    
    # Основной код функции с junk между инструкциями
    res, _ = inject_junk(func_bytes)
    result += res
    
    result
  end

  # Генерация anti-debug кода
  def anti_debug_check
    # Проверка через ptrace
    # mov rax, 101 (ptrace syscall)
    # xor rdi, rdi (PTRACE_TRACEME)
    # xor rsi, rsi
    # xor rdx, rdx
    # syscall
    # test rax, rax
    # js .debugger_detected
    [
      0x48, 0xc7, 0xc0, 0x65, 0x00, 0x00, 0x00,  # mov rax, 101
      0x48, 0x31, 0xff,                          # xor rdi, rdi
      0x48, 0x31, 0xf6,                          # xor rsi, rsi  
      0x48, 0x31, 0xd2,                          # xor rdx, rdx
      0x0f, 0x05,                                # syscall
      0x48, 0x85, 0xc0,                          # test rax, rax
      0x79, 0x05,                                # jns +5 (skip trap)
      0xcc,                                      # int3 (trap debugger)
      0xcc,                                      # int3
      0xcc,                                      # int3
      0xcc,                                      # int3
      0xcc,                                      # int3
    ]
  end

  # Вставка junk между инструкциями с возвратом маппинга смещений
  def inject_junk(bytes)
    return [bytes, {}] if bytes.empty? || !@enabled
    
    result = []
    i = 0
    mapping = {}
    
    while i < bytes.length
      # Запоминаем маппинг для каждого байта текущей инструкции
      instr_len = (@arch == :aarch64) ? 4 : estimate_instruction_length(bytes, i)
      instr_len.times { |j| mapping[i + j] = result.length + j }

      result += bytes[i, instr_len]
      i += instr_len
      
      # С вероятностью добавляем junk после инструкции
      if rand < 0.3 && i < bytes.length
        # Junk instructions for AArch64 should be 4-byte aligned
        junk = (@arch == :aarch64) ? [0x1f, 0x20, 0x03, 0xd5] * (rand(3)+1) : @engine.poly_nop(rand(3)+1)
        result += junk
        @stats[:junk_added] += 1
      end
    end
    
    mapping[bytes.length] = result.length
    [result, mapping]
  end

  # Для обратной совместимости
  def mutate_code(bytes)
    res, _ = inject_junk(bytes)
    res
  end

  # Контроль сложности обфускации
  def set_level(level)
    @engine.mutation_level = [[level, 1].max, 5].min
  end

  # Генерация полиморфного mov rax, value
  def poly_load_rax(value)
    @engine.poly_mov_rax(value)
  end

  # Генерация полиморфного xor rax, rax (обнуление)
  def poly_zero_rax
    @engine.poly_xor_rax_rax
  end

  # Шифрование строки
  def encrypt_string(str)
    return { plain: str.bytes } unless @encrypt_strings
    @engine.encrypt_string(str)
  end

  # Код дешифровки строки
  def string_decrypt_stub(encrypted_data)
    return [] unless @encrypt_strings
    @engine.string_decrypt_code(encrypted_data)
  end

  private

  # Улучшенная оценка длины x64 инструкции (для Juno)
  def estimate_instruction_length(bytes, offset)
    return 1 if offset >= bytes.length
    
    start = offset
    b = bytes[offset]
    
    # Skip prefixes
    has_rex = false
    while b && ([0x66, 0x67, 0xf0, 0xf2, 0xf3].include?(b) || (b >= 0x40 && b <= 0x4f))
      has_rex = true if b >= 0x40 && b <= 0x4f
      offset += 1
      b = bytes[offset]
    end

    return offset - start + 1 if offset >= bytes.length
    
    opcode = bytes[offset]
    offset += 1
    
    # 2-byte opcodes
    if opcode == 0x0f
      opcode = bytes[offset]
      offset += 1

      # 0x0F 0x05 (syscall), 0x0F 0xA4 (shld), 0x0F 0xAF (imul)
      return offset - start if opcode == 0x05 # syscall

      # Jcc rel32 (0x0F 0x80 - 0x0F 0x8F)
      return offset - start + 4 if opcode >= 0x80 && opcode <= 0x8f

      # Common 0x0F instructions with ModRM (like cmov, imul, setcc)
      offset += 1 # ModRM
      return offset - start
    end
    
    # One-byte opcodes with immediate
    return offset - start + 4 if opcode == 0xe8 || opcode == 0xe9 # call/jmp rel32
    return offset - start + 1 if opcode == 0xeb || (opcode >= 0x70 && opcode <= 0x7f) # short jmp/jcc
    
    # mov reg, imm64 (REX.W + B8+r)
    return offset - start + 8 if has_rex && (opcode >= 0xb8 && opcode <= 0xbf)

    # mov reg, imm32 (B8+r)
    return offset - start + 4 if (opcode >= 0xb8 && opcode <= 0xbf)
    
    # Instructions with ModRM
    # 0x80-0x83 (arith/cmp), 0x88-0x8B (mov), 0xC6-0xC7 (mov imm), 0x8d (lea)
    # 0x01 (add), 0x29 (sub), 0x31 (xor), 0x39 (cmp), 0x85 (test), 0xf7 (not/idiv)
    # 0x09 (or), 0x21 (and), 0x8a/0x8b (mov)
    if [0x80, 0x81, 0x82, 0x83, 0x88, 0x89, 0x8a, 0x8b, 0xc6, 0xc7, 0x8d, 0x31, 0x01, 0x29, 0x39,
        0x85, 0xf7, 0x09, 0x21, 0xd3, 0xc1, 0x84].include?(opcode)
      modrm = bytes[offset]
      offset += 1
      return offset - start if modrm.nil?

      mod = (modrm >> 6) & 3
      rm  = modrm & 7

      # SIB
      if mod != 3 && rm == 4
        offset += 1 # SIB byte
      end

      # Displacement
      if mod == 1
        offset += 1
      elsif mod == 2 || (mod == 0 && rm == 5)
        offset += 4
      end

      # Immediate
      if opcode == 0x81 || opcode == 0xc7
        offset += 4
      elsif opcode == 0x80 || opcode == 0x82 || opcode == 0x83 || opcode == 0xc1 || opcode == 0xc6
        offset += 1
      end

      return offset - start
    end
    
    # Simple one-byte instructions
    return offset - start if [0x90, 0xc3, 0x50, 0x51, 0x52, 0x53, 0x54, 0x55,
                               0x56, 0x57, 0x58, 0x59, 0x5a, 0x5b, 0x5c, 0x5d,
                               0x5e, 0x5f, 0xcc, 0x9c, 0x9d, 0xf8, 0xf9, 0xf5,
                               0xa4, 0xaa, 0x99].include?(opcode)

    # Default: if we don't know, assume it might have a ModRM or is just 1 byte
    # For Juno, most unknown are 1-byte opcodes or handled above
    offset - start
  end
end

# Глобальный мутатор для использования в компиляторе
$code_mutator = nil

def init_mutator(options = {})
  $code_mutator = CodeMutator.new(options)
end

def mutate(bytes)
  return bytes unless $code_mutator
  $code_mutator.mutate_code(bytes)
end
