# Polymorphic Code Engine - Architecture Neutral
# Generates different machine code for the same operations

class PolymorphEngine
  def initialize(arch = :x86_64, seed = nil)
    @arch = arch
    @rng = Random.new(seed || Random.new_seed)
    @mutation_level = 3
  end

  attr_accessor :mutation_level

  def poly_mov_rax(value)
    return standard_mov(value) if @arch == :aarch64
    variants = [
      -> { standard_mov(value) },
      -> { xor_based_mov(value) },
      -> { add_sub_mov(value) },
      -> { push_pop_mov(value) }
    ]
    variants[@rng.rand(variants.length)].call
  end

  def opaque_true
    if @arch == :aarch64
       # cmp x0, x0; b.eq +8
       return [0x1f, 0x00, 0x00, 0xeb, 0x40, 0x00, 0x00, 0x54]
    end
    [0x48, 0x85, 0xc0, 0x79, 0x00] # test rax, rax; jns +0
  end

  def junk_instructions
    count = @rng.rand(@mutation_level) + 1
    result = []
    count.times { result += harmless_instruction }
    result
  end

  def poly_nop(count = 1)
    if @arch == :aarch64
       return [0x1f, 0x20, 0x03, 0xd5] * count
    end
    [0x90] * count
  end

  def dead_code_block
    if @arch == :aarch64
       return [0x02, 0x00, 0x00, 0x14, 0x1f, 0x20, 0x03, 0xd5, 0x1f, 0x20, 0x03, 0xd5] # b +8, nop, nop
    end
    [0xeb, 0x02, 0x90, 0x90] # jmp +2, nop, nop
  end

  private

  def standard_mov(value)
    if @arch == :aarch64
       # Simplified AArch64 movz/movk
       v = [value].pack("Q<").unpack("L<L<")
       res = [0x00, 0x00, 0x80, 0xd2] # movz x0, #0
       res[0] = (value & 0xFF)
       res[1] = (value >> 8) & 0xFF
       return res
    end
    [0x48, 0xb8] + [value].pack("q<").bytes
  end

  def harmless_instruction
    if @arch == :aarch64
       return [0x1f, 0x20, 0x03, 0xd5] # nop
    end
    [0x90]
  end

  def xor_based_mov(value)
    standard_mov(value)
  end

  def add_sub_mov(value)
    standard_mov(value)
  end

  def push_pop_mov(value)
    standard_mov(value)
  end
end
