# Code Mutator - интеграция полиморфного движка с генератором кода Juno
# Превращает обычный код в кошмар для реверсера

require_relative 'polymorph_engine'
require_relative 'x86_decoder'

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
    res, _ = inject_junk(bytes)
    res
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
    [
      0x48, 0xc7, 0xc0, 0x65, 0x00, 0x00, 0x00,  # mov rax, 101
      0x48, 0x31, 0xff,                          # xor rdi, rdi
      0x48, 0x31, 0xf6,                          # xor rsi, rsi  
      0x48, 0x31, 0xd2,                          # xor rdx, rdx
      0x0f, 0x05,                                # syscall
      0x48, 0x85, 0xc0,                          # test rax, rax
      0x79, 0x05,                                # jns +5 (skip trap)
      0xcc,                                      # int3 (trap debugger)
      0xcc, 0xcc, 0xcc, 0xcc, 0xcc
    ]
  end

  # Вставка junk между инструкциями с возвратом маппинга смещений
  def inject_junk(bytes)
    return [bytes, {}] if bytes.empty? || !@enabled
    
    result = []
    i = 0
    mapping = {}
    
    while i < bytes.length
      # PRECISE INSTRUCTION DECODING
      instr_len = (@arch == :aarch64) ? 4 : X86Decoder.estimate_length(bytes, i)

      # Safety fallback - should not happen with proper decoder
      if instr_len <= 0
        instr_len = 1
      end

      # Check if we are overshooting
      if i + instr_len > bytes.length
        instr_len = bytes.length - i
      end

      # Map every byte of the instruction to its new position
      instr_len.times { |j| mapping[i + j] = result.length + j }

      result += bytes[i, instr_len]
      i += instr_len
      
      # Probabilistically add junk after the instruction
      if rand < 0.3 && i < bytes.length
        junk = (@arch == :aarch64) ? [0x1f, 0x20, 0x03, 0xd5] * (rand(2)+1) : @engine.poly_nop(rand(3)+1)
        result += junk
        @stats[:junk_added] += 1
      end
    end
    
    mapping[bytes.length] = result.length
    [result, mapping]
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
