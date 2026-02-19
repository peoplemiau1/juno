# X86-64 Instruction Length Decoder for Juno
# Precise enough for the opcodes Juno actually generates.

class X86Decoder
  def self.estimate_length(bytes, offset)
    return 0 if offset >= bytes.length
    start = offset

    # Prefixes (including REX)
    has_rex = false
    while offset < bytes.length && is_prefix?(bytes[offset])
      has_rex = true if bytes[offset] >= 0x40 && bytes[offset] <= 0x4f
      offset += 1
    end

    return offset - start if offset >= bytes.length

    opcode = bytes[offset]
    offset += 1

    # 2-byte opcodes (0F prefix)
    if opcode == 0x0f
      return offset - start if offset >= bytes.length
      opcode = bytes[offset]
      offset += 1

      # 0F 05 (syscall)
      return offset - start if opcode == 0x05

      # Jcc rel32 (0F 80 - 0F 8F)
      if opcode >= 0x80 && opcode <= 0x8f
        return offset - start + 4
      end

      # Opcodes with ModRM
      # cmovcc (0F 40 - 0F 4F), imul (0F AF), setcc (0F 90 - 0F 9F)
      if (opcode >= 0x40 && opcode <= 0x4f) || (opcode >= 0x90 && opcode <= 0x9f) || opcode == 0xaf
        return decode_modrm(bytes, offset, start)
      end

      return offset - start
    end

    # Common opcodes
    case opcode
    when 0xb8..0xbf # mov reg, imm
      return offset - start + (has_rex ? 8 : 4)
    when 0x05, 0x0d, 0x15, 0x1d, 0x25, 0x2d, 0x35, 0x3d # add/or/adc/sbb/and/sub/xor/cmp rax, imm32
      return offset - start + 4
    when 0xc6, 0xc7 # mov mem, imm
      len = decode_modrm(bytes, offset, start)
      return len + (opcode == 0xc7 ? 4 : 1)
    when 0xe8, 0xe9 # call/jmp rel32
      return offset - start + 4
    when 0xeb, 0x70..0x7f # short jumps
      return offset - start + 1
    when 0x80, 0x81, 0x82, 0x83, 0xc0, 0xc1 # Arith/Shift imm
      len = decode_modrm(bytes, offset, start)
      return len + (opcode == 0x81 ? 4 : 1)
    when 0x01, 0x03, 0x09, 0x0b, 0x21, 0x23, 0x29, 0x2b, 0x31, 0x33, 0x39, 0x3b,
         0x88, 0x89, 0x8a, 0x8b, 0x8d, 0x84, 0x85, 0xf7, 0x63 # Common ModRM instructions
      return decode_modrm(bytes, offset, start)
    when 0x90..0x97, 0x50..0x5f, 0xc3, 0x5d, 0x55, 0x99, 0xa4, 0xaa # 1-byte instructions
      return offset - start
    when 0xff # call/jmp/push mem/reg
      return decode_modrm(bytes, offset, start)
    else
      # Fallback: if it's unknown but looks like ModRM...
      # This is risky, but better than nothing.
      return offset - start
    end
  end

  def self.is_prefix?(b)
    # REX (40-4F), Segment overrides (26, 2E, 36, 3E, 64, 65), Operand size (66), Address size (67)
    (b >= 0x40 && b <= 0x4f) || [0x26, 0x2e, 0x36, 0x3e, 0x64, 0x65, 0x66, 0x67, 0xf0, 0xf2, 0xf3].include?(b)
  end

  def self.decode_modrm(bytes, offset, start_offset)
    return offset - start_offset if offset >= bytes.length
    modrm = bytes[offset]
    offset += 1

    mod = (modrm >> 6) & 3
    rm  = modrm & 7

    # SIB
    if mod != 3 && rm == 4
      offset += 1 # SIB
    end

    # Displacement
    if mod == 1
      offset += 1
    elsif mod == 2 || (mod == 0 && rm == 5)
      offset += 4
    end

    offset - start_offset
  end
end
