# Peephole Optimizer - Low-level x86-64 instruction optimizations
# Runs after code generation to optimize instruction sequences

class PeepholeOptimizer
  def initialize(code_bytes)
    @code = code_bytes.dup
    @pos = 0
  end

  def optimize
    @pos = 0
    while @pos < @code.length - 4
      optimized = false
      
      # Pattern 1: mov rax, 0 -> xor eax, eax (shorter)
      if match_mov_rax_zero?
        replace_with_xor_eax
        optimized = true
      end
      
      # Pattern 2: mov reg, reg (same) -> nop
      if !optimized && match_mov_same_reg?
        replace_with_nops(3)
        optimized = true
      end
      
      # Pattern 3: push rax; pop rax -> nothing
      if !optimized && match_push_pop_same?
        replace_with_nops(2)
        optimized = true
      end
      
      # Pattern 4: add rax, 0 -> nothing
      if !optimized && match_add_zero?
        replace_with_nops(4)
        optimized = true
      end
      
      # Pattern 5: imul rax, 1 -> nothing
      if !optimized && match_imul_one?
        replace_with_nops(4)
        optimized = true
      end
      
      # Pattern 6: consecutive mov to same reg
      if !optimized && match_redundant_mov?
        remove_first_mov
        optimized = true
      end
      
      @pos += 1 unless optimized
    end
    
    remove_nops
    @code
  end

  private

  # mov rax, 0 = 48 c7 c0 00 00 00 00
  def match_mov_rax_zero?
    return false if @pos + 7 > @code.length
    @code[@pos, 7] == [0x48, 0xc7, 0xc0, 0x00, 0x00, 0x00, 0x00]
  end

  # xor eax, eax = 31 c0 (only 2 bytes!)
  def replace_with_xor_eax
    @code[@pos, 7] = [0x31, 0xc0, 0x90, 0x90, 0x90, 0x90, 0x90]
  end

  # mov reg, reg (same register)
  def match_mov_same_reg?
    return false if @pos + 3 > @code.length
    b0, b1, b2 = @code[@pos, 3]
    return false unless b0 == 0x48 || b0 == 0x49 || b0 == 0x4c || b0 == 0x4d
    return false unless b1 == 0x89 || b1 == 0x8b
    
    # Check if src == dst in ModRM
    src = (b2 >> 3) & 7
    dst = b2 & 7
    src == dst && (b2 & 0xc0) == 0xc0
  end

  # push reg; pop reg (same register)
  def match_push_pop_same?
    return false if @pos + 2 > @code.length
    b0, b1 = @code[@pos, 2]
    
    # push rax (50) pop rax (58)
    if b0 >= 0x50 && b0 <= 0x57
      expected_pop = b0 + 8
      return b1 == expected_pop
    end
    
    false
  end

  # add rax, 0 = 48 83 c0 00 or 48 05 00 00 00 00
  def match_add_zero?
    return false if @pos + 4 > @code.length
    @code[@pos, 4] == [0x48, 0x83, 0xc0, 0x00]
  end

  # imul rax, rax, 1 = 48 6b c0 01
  def match_imul_one?
    return false if @pos + 4 > @code.length
    @code[@pos, 4] == [0x48, 0x6b, 0xc0, 0x01]
  end

  # Two consecutive mov to same destination
  def match_redundant_mov?
    return false if @pos + 10 > @code.length
    
    # Check for mov reg, X followed by mov reg, Y
    b0, b1, b2 = @code[@pos, 3]
    return false unless (b0 == 0x48 || b0 == 0x49) && b1 == 0xc7
    
    dst1 = b2 & 0x07
    
    # Find next mov (skip immediate)
    next_pos = @pos + 7
    return false if next_pos + 3 > @code.length
    
    n0, n1, n2 = @code[next_pos, 3]
    return false unless (n0 == 0x48 || n0 == 0x49) && n1 == 0xc7
    
    dst2 = n2 & 0x07
    dst1 == dst2
  end

  def remove_first_mov
    @code[@pos, 7] = [0x90] * 7
  end

  def replace_with_nops(count)
    @code[@pos, count] = [0x90] * count
  end

  def remove_nops
    # Remove sequences of NOPs (0x90)
    result = []
    i = 0
    while i < @code.length
      if @code[i] == 0x90
        # Skip consecutive NOPs
        while i < @code.length && @code[i] == 0x90
          i += 1
        end
      else
        result << @code[i]
        i += 1
      end
    end
    @code = result
  end
end

# Instruction combiner - combines sequences into better instructions
class InstructionCombiner
  PATTERNS = [
    # mov rax, X; add rax, Y -> mov rax, X+Y (if X,Y are constants)
    {
      match: [[0x48, 0xc7, 0xc0], [0x48, 0x05]],
      combine: :combine_mov_add
    },
    # lea rax, [rax+N]; lea rax, [rax+M] -> lea rax, [rax+N+M]
    {
      match: [[0x48, 0x8d, 0x40], [0x48, 0x8d, 0x40]],
      combine: :combine_lea_lea
    }
  ]

  def initialize(code_bytes)
    @code = code_bytes.dup
  end

  def optimize
    PATTERNS.each do |pattern|
      @code = apply_pattern(pattern)
    end
    @code
  end

  private

  def apply_pattern(pattern)
    result = []
    i = 0
    
    while i < @code.length
      matched = try_match(pattern[:match], i)
      if matched
        combined = send(pattern[:combine], matched)
        result.concat(combined)
        i += matched[:length]
      else
        result << @code[i]
        i += 1
      end
    end
    
    result
  end

  def try_match(patterns, pos)
    # Simplified matching - would need full implementation
    nil
  end

  def combine_mov_add(match)
    # Would combine mov rax, X; add rax, Y -> mov rax, X+Y
    match[:bytes]
  end

  def combine_lea_lea(match)
    # Would combine consecutive LEAs
    match[:bytes]
  end
end
