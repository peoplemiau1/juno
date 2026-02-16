# Polymorphic Code Engine - Makes reverse engineering a nightmare
# Генерирует разный машинный код для одних и тех же операций

class PolymorphEngine
  def initialize(seed = nil)
    @rng = Random.new(seed || Random.new_seed)
    @mutation_level = 3  # 1-5, higher = more obfuscation
  end

  attr_accessor :mutation_level

  # Полиморфная генерация MOV RAX, imm64
  # Вместо простого mov rax, N генерирует эквивалентные но разные последовательности
  def poly_mov_rax(value)
    variants = [
      -> { standard_mov(value) },
      -> { xor_based_mov(value) },
      -> { add_sub_mov(value) },
      -> { push_pop_mov(value) },
      -> { lea_based_mov(value) },
      -> { mul_div_mov(value) },
      -> { shift_or_mov(value) },
      -> { neg_not_mov(value) }
    ]

    # Выбираем случайный вариант
    variants[@rng.rand(variants.length)].call
  end

  # Полиморфный ADD
  def poly_add_rax_rbx
    variants = [
      -> { [0x48, 0x01, 0xd8] },  # add rax, rbx
      -> { # lea rax, [rax+rbx]
        [0x48, 0x8d, 0x04, 0x18]
      },
      -> { # sub rax, neg(rbx) эквивалент через xchg
        [0x48, 0x87, 0xd8,        # xchg rax, rbx
         0x48, 0xf7, 0xd8,        # neg rax
         0x48, 0x29, 0xc3,        # sub rbx, rax
         0x48, 0x87, 0xd8,        # xchg rax, rbx
         0x48, 0xf7, 0xd8]        # neg rax (restore)
      },
      -> { # xor magic
        junk = junk_bytes(4)
        [0x48, 0x31, 0xc0] +      # xor rax, rax (будет заменено)
        junk +
        [0x48, 0x01, 0xd8]        # add rax, rbx
      }
    ]
    variants[@rng.rand(variants.length)].call
  end

  # Полиморфный XOR (для обфускации)
  def poly_xor_rax_rax
    variants = [
      -> { [0x48, 0x31, 0xc0] },           # xor rax, rax
      -> { [0x48, 0x29, 0xc0] },           # sub rax, rax
      -> { [0x48, 0xc7, 0xc0, 0, 0, 0, 0] }, # mov rax, 0
      -> { [0x48, 0x6b, 0xc0, 0x00] },     # imul rax, 0
      -> { [0x48, 0x21, 0xc0,              # and rax, rax
            0x48, 0xf7, 0xd0,              # not rax
            0x48, 0x21, 0xc0,              # and rax, rax
            0x48, 0xf7, 0xd0,              # not rax
            0x48, 0x31, 0xc0] }            # xor rax, rax
    ]
    variants[@rng.rand(variants.length)].call
  end

  # Opaque Predicate - условие которое ВСЕГДА true но выглядит сложно
  def opaque_true
    # (x * x) >= 0 всегда true для любого x
    # (x | 1) != 0 всегда true
    # ((x & 1) + (x & 1)) < 3 всегда true

    patterns = [
      -> {
        # push rcx; mov rcx, rax; imul rcx, rcx; test rcx, rcx; jns .true; ...
        [0x51,                              # push rcx
         0x48, 0x89, 0xc1,                  # mov rcx, rax
         0x48, 0x0f, 0xaf, 0xc9,            # imul rcx, rcx
         0x48, 0x85, 0xc9,                  # test rcx, rcx
         0x59,                              # pop rcx
         0x79, 0x00]                        # jns +0 (always taken)
      },
      -> {
        # x | 1 != 0
        [0x50,                              # push rax
         0x48, 0x83, 0xc8, 0x01,            # or rax, 1
         0x48, 0x85, 0xc0,                  # test rax, rax
         0x58,                              # pop rax
         0x75, 0x00]                        # jnz +0 (always taken)
      }
    ]
    patterns[@rng.rand(patterns.length)].call
  end

  # Dead code injection - мёртвый код который никогда не выполняется
  def dead_code_block
    # Генерируем блок кода который выглядит реальным но пропускается
    jmp_over = [0xeb, 0x00]  # jmp short (будет пропатчен)

    dead = []
    (3 + @rng.rand(5)).times do
      dead += random_instruction
    end

    jmp_over[1] = dead.length
    jmp_over + dead
  end

  # Junk code - бессмысленные инструкции между реальными
  def junk_instructions
    count = @rng.rand(@mutation_level) + 1
    result = []
    count.times do
      result += harmless_instruction
    end
    result
  end

  # Control flow obfuscation - запутывание потока управления
  def obfuscated_jump(target_offset)
    variants = [
      -> { [0xe9] + [target_offset].pack("l<").bytes },  # jmp rel32
      -> {
        # push addr; ret
        addr = 0x401000 + target_offset  # примерный адрес
        [0x68] + [addr & 0xFFFFFFFF].pack("V").bytes + [0xc3]
      },
      -> {
        # xor rax,rax; lea rax,[rip+offset]; jmp rax
        [0x48, 0x31, 0xc0,
         0x48, 0x8d, 0x05] + [target_offset - 6].pack("l<").bytes +
        [0xff, 0xe0]
      }
    ]
    variants[@rng.rand(variants.length)].call
  end

  # Metamorphic NOP sled - разные способы "ничего не делать"
  def poly_nop(count = 1)
    nop_variants = [
      [0x90],                           # nop
      [0x66, 0x90],                     # 66 nop
      [0x0f, 0x1f, 0x00],              # nop dword [rax]
      [0x0f, 0x1f, 0x40, 0x00],        # nop dword [rax+0]
      [0x0f, 0x1f, 0x44, 0x00, 0x00],  # nop dword [rax+rax+0]
      [0x87, 0xc0],                     # xchg eax, eax
      [0x87, 0xdb],                     # xchg ebx, ebx
      [0x48, 0x87, 0xc0],              # xchg rax, rax
      [0x8d, 0x40, 0x00],              # lea eax, [rax+0]
      [0x8d, 0x49, 0x00],              # lea ecx, [rcx+0]
    ]

    result = []
    count.times do
      result += nop_variants[@rng.rand(nop_variants.length)]
    end
    result
  end

  # String obfuscation - шифрование строк в коде
  def encrypt_string(str, key = nil)
    key ||= @rng.rand(256)
    encrypted = str.bytes.map.with_index { |b, i| b ^ ((key + i) & 0xFF) }
    { encrypted: encrypted, key: key, length: str.length }
  end

  # Генерация кода для дешифровки строки в runtime
  def string_decrypt_code(encrypted_data)
    key = encrypted_data[:key]
    len = encrypted_data[:length]

    # lea rsi, [encrypted]; mov rcx, len; mov al, key
    # .loop: xor [rsi], al; inc al; inc rsi; loop .loop
    [
      0xb9] + [len].pack("V").bytes +        # mov ecx, len
    [0xb0, key,                               # mov al, key
     0x30, 0x06,                              # .loop: xor [rsi], al
     0xfe, 0xc0,                              # inc al
     0x48, 0xff, 0xc6,                        # inc rsi
     0xe2, 0xf7]                              # loop .loop
  end

  private

  def standard_mov(value)
    if value >= 0 && value <= 0x7FFFFFFF
      [0x48, 0xc7, 0xc0] + [value].pack("l<").bytes
    else
      [0x48, 0xb8] + [value].pack("q<").bytes
    end
  end

  def xor_based_mov(value)
    # xor rax,rax; mov eax, low; shl rax,32; or rax, high
    # или через xor с маской
    mask = @rng.rand(0xFFFFFFFF)
    result = value ^ mask

    [0x48, 0xc7, 0xc0] + [mask].pack("l<").bytes +  # mov rax, mask
    [0x48, 0x35] + [result].pack("l<").bytes        # xor rax, result
  end

  def add_sub_mov(value)
    # mov rax, X; add rax, Y где X+Y = value
    x = @rng.rand(0xFFFFFF)
    y = value - x

    [0x48, 0xc7, 0xc0] + [x].pack("l<").bytes +     # mov rax, x
    [0x48, 0x05] + [y].pack("l<").bytes             # add rax, y
  end

  def push_pop_mov(value)
    # push value; pop rax
    if value >= -0x80 && value <= 0x7F
      [0x6a, value & 0xFF, 0x58]
    elsif value >= 0 && value <= 0xFFFFFFFF
      [0x68] + [value].pack("V").bytes + [0x58]
    else
      standard_mov(value)
    end
  end

  def lea_based_mov(value)
    # lea rax, [rip + offset] где offset вычислен
    if value.abs < 0x7FFFFFFF
      base = @rng.rand(1000)
      offset = value - base
      [0x48, 0x8d, 0x05] + [offset].pack("l<").bytes  # lea rax, [rip+offset]
    else
      standard_mov(value)
    end
  end

  def mul_div_mov(value)
    # mov rax, X; imul rax, Y где X*Y = value (если делится)
    factors = find_factors(value)
    if factors
      [0x48, 0xc7, 0xc0] + [factors[0]].pack("l<").bytes +
      [0x48, 0x6b, 0xc0, factors[1]]
    else
      standard_mov(value)
    end
  end

  def shift_or_mov(value)
    # Построить число через сдвиги и OR
    high = (value >> 32) & 0xFFFFFFFF
    low = value & 0xFFFFFFFF

    if high == 0
      standard_mov(value)
    else
      [0x48, 0xc7, 0xc0] + [high].pack("l<").bytes +  # mov rax, high
      [0x48, 0xc1, 0xe0, 0x20,                         # shl rax, 32
       0x48, 0x0d] + [low].pack("l<").bytes            # or rax, low
    end
  end

  def neg_not_mov(value)
    # mov rax, ~(-value-1) = value через not и neg
    neg_val = -value
    [0x48, 0xc7, 0xc0] + [neg_val].pack("l<").bytes + # mov rax, -value
    [0x48, 0xf7, 0xd8]                                 # neg rax
  end

  def find_factors(n)
    return nil if n <= 0 || n > 0x7FFFFFFF
    (2..127).each do |i|
      if n % i == 0 && (n / i) <= 0x7FFFFFFF
        return [n / i, i]
      end
    end
    nil
  end

  def random_instruction
    instructions = [
      [0x90],                              # nop
      [0x50],                              # push rax
      [0x58],                              # pop rax
      [0x51],                              # push rcx
      [0x59],                              # pop rcx
      [0x48, 0x87, 0xc0],                 # xchg rax, rax
      [0x48, 0x85, 0xc0],                 # test rax, rax
      [0x48, 0x39, 0xc0],                 # cmp rax, rax
    ]
    instructions[@rng.rand(instructions.length)]
  end

  def harmless_instruction
    # Инструкции которые не меняют состояние (или отменяют себя)
    instructions = [
      [0x90],                              # nop
      [0x50, 0x58],                        # push rax; pop rax
      [0x51, 0x59],                        # push rcx; pop rcx
      [0x9c, 0x9d],                        # pushf; popf
      [0x48, 0x87, 0xc9],                 # xchg rcx, rcx
      [0xf8],                              # clc
      [0xf9],                              # stc
      [0xf5],                              # cmc
      [0xf5],                              # cmc (double = restore)
    ]
    instructions[@rng.rand(instructions.length)]
  end

  def junk_bytes(count)
    Array.new(count) { @rng.rand(256) }
  end
end
