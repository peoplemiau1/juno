# Code Mutator - интеграция полиморфного движка с генератором кода Juno
# Превращает обычный код в кошмар для реверсера

require_relative 'polymorph_engine'

class CodeMutator
  def initialize(options = {})
    @engine = PolymorphEngine.new(options[:seed])
    @engine.mutation_level = options[:level] || 3
    @enabled = options[:enabled] != false
    @anti_debug = options[:anti_debug] || false
    @encrypt_strings = options[:encrypt_strings] || false
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
    result += inject_junk(func_bytes)
    
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

  # Вставка junk между инструкциями
  def inject_junk(bytes)
    return bytes if bytes.empty?
    
    result = []
    i = 0
    
    while i < bytes.length
      # Копируем инструкцию (упрощённо - по 1-7 байт)
      instr_len = estimate_instruction_length(bytes, i)
      result += bytes[i, instr_len]
      i += instr_len
      
      # С вероятностью добавляем junk после инструкции
      if rand < 0.3 && i < bytes.length
        result += @engine.junk_instructions
      end
    end
    
    result
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

  # Примерная оценка длины x64 инструкции
  def estimate_instruction_length(bytes, offset)
    return 1 if offset >= bytes.length
    
    b = bytes[offset]
    
    # REX prefix
    has_rex = (b >= 0x40 && b <= 0x4f)
    base = has_rex ? offset + 1 : offset
    return 1 if base >= bytes.length
    
    opcode = bytes[base]
    
    # Простые однобайтовые
    return (has_rex ? 2 : 1) if [0x90, 0xc3, 0xcc, 0x50, 0x51, 0x52, 0x53, 
                                  0x54, 0x55, 0x56, 0x57, 0x58, 0x59, 0x5a,
                                  0x5b, 0x5c, 0x5d, 0x5e, 0x5f, 0x9c, 0x9d,
                                  0xf8, 0xf9, 0xf5].include?(opcode)
    
    # mov reg, imm32
    return (has_rex ? 7 : 6) if opcode == 0xc7
    
    # mov reg, imm64 (REX.W + B8+r)
    return 10 if has_rex && (opcode >= 0xb8 && opcode <= 0xbf)
    
    # Syscall
    return 2 if opcode == 0x0f && bytes[base + 1] == 0x05
    
    # Default - возвращаем 3
    [3, bytes.length - offset].min
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
