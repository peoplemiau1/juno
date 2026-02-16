# HELL MODE - Maximum obfuscation that makes reverse engineers cry
# Включает ВСЁ: полиморфизм, антиотладка, метаморфизм, обфускация CFG

require_relative 'polymorph_engine'
require_relative 'code_mutator'  
require_relative 'anti_reverse'

class HellMode
  LEVELS = {
    easy: 1,      # Лёгкая обфускация
    medium: 2,    # Средняя
    hard: 3,      # Сложная  
    nightmare: 4, # Кошмар
    hell: 5       # АД - максимум всего
  }

  def initialize(level = :hell)
    @level = LEVELS[level] || 5
    @poly = PolymorphEngine.new
    @poly.mutation_level = @level
    @mutator = CodeMutator.new(level: @level, anti_debug: @level >= 4, encrypt_strings: @level >= 3)
    @anti = AntiReverse.new
    
    @stats = { 
      junk_added: 0, 
      strings_encrypted: 0,
      fake_branches: 0,
      metamorphic_blocks: 0
    }
  end

  attr_reader :stats

  # Применить все техники к машинному коду
  def obfuscate(code_bytes)
    result = []
    
    # 1. Anti-debug в начале (hell level)
    if @level >= 4
      result += @anti.anti_debug_linux
      @stats[:junk_added] += 1
    end
    
    # 2. VM detection (hell level)
    if @level >= 5
      result += @anti.vm_detect
    end
    
    # 3. Anti-disassembly junk
    (@level * 2).times do
      result += @anti.anti_disasm_junk
      @stats[:junk_added] += 1
    end
    
    # 4. Основной код с мутациями
    result += transform_code(code_bytes)
    
    # 5. Добавляем dead code в конце
    if @level >= 3
      result += generate_dead_code_maze
    end
    
    result
  end

  # Обфускация конкретной функции
  def obfuscate_function(name, code_bytes)
    result = []
    
    # Пролог с junk
    result += @poly.poly_nop(@level)
    
    # Opaque predicates
    if @level >= 2
      result += @poly.opaque_true
      @stats[:fake_branches] += 1
    end
    
    # Fake branches
    if @level >= 3
      result += @anti.insert_fake_branches([])
      @stats[:fake_branches] += 1
    end
    
    # Self-modifying stub (nightmare+)
    if @level >= 4
      result += @anti.self_modify_stub
      @stats[:metamorphic_blocks] += 1
    end
    
    # Основной код функции
    result += @mutator.mutate_function(code_bytes)
    
    # Эпилог с junk
    result += @poly.junk_instructions
    
    result
  end

  # Шифрование строки
  def encrypt_string(str)
    @stats[:strings_encrypted] += 1
    @anti.encrypt_string_rolling(str)
  end

  # Генерация кода дешифровки
  def decrypt_string_code(addr, len, key)
    @anti.decrypt_routine(addr, len, key)
  end

  # Полиморфная загрузка константы
  def poly_constant(value)
    @poly.poly_mov_rax(value)
  end

  # Статистика обфускации
  def report
    puts "=== HELL MODE OBFUSCATION REPORT ==="
    puts "Level: #{@level}/5"
    puts "Junk blocks added: #{@stats[:junk_added]}"
    puts "Strings encrypted: #{@stats[:strings_encrypted]}"
    puts "Fake branches: #{@stats[:fake_branches]}"  
    puts "Metamorphic blocks: #{@stats[:metamorphic_blocks]}"
    puts "===================================="
  end

  private

  def transform_code(bytes)
    result = []
    
    bytes.each_slice(random_chunk_size) do |chunk|
      # Добавляем junk между чанками
      if rand < 0.3 * @level
        result += @poly.junk_instructions
        @stats[:junk_added] += 1
      end
      
      # Добавляем opaque predicate
      if rand < 0.2 * @level
        result += @poly.opaque_true
        @stats[:fake_branches] += 1
      end
      
      # Сам чанк кода
      result += chunk
      
      # Metamorphic nops
      result += @poly.poly_nop(1)
    end
    
    result
  end

  def random_chunk_size
    3 + rand(5)
  end

  def generate_dead_code_maze
    maze = []
    
    # Лабиринт из dead code блоков
    (@level * 3).times do
      maze += @poly.dead_code_block
      @stats[:junk_added] += 1
    end
    
    maze
  end
end

# Демо
if __FILE__ == $0
  puts "Testing HELL MODE obfuscation..."
  
  hell = HellMode.new(:hell)
  
  # Тестовый код: mov rax, 42; ret
  test_code = [0x48, 0xc7, 0xc0, 0x2a, 0x00, 0x00, 0x00, 0xc3]
  
  puts "Original code (#{test_code.length} bytes):"
  puts test_code.map { |b| "%02x" % b }.join(' ')
  
  obfuscated = hell.obfuscate(test_code)
  
  puts "\nObfuscated code (#{obfuscated.length} bytes):"
  puts obfuscated.each_slice(16).map { |row| row.map { |b| "%02x" % b }.join(' ') }.join("\n")
  
  puts "\n"
  hell.report
  
  # Тест шифрования строки
  str = "Hello, World!"
  encrypted = hell.encrypt_string(str)
  puts "\nString '#{str}' encrypted:"
  puts "Key: #{encrypted[:key]}"
  puts "Data: #{encrypted[:data].map { |b| "%02x" % b }.join(' ')}"
end
