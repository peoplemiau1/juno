class AArch64Emitter
  attr_reader :bytes, :stack_shadow_size

  # Registers X0-X30, SP=31
  (0..30).each { |i| const_set("REG_X#{i}", i) }
  REG_SP = 31
  REG_FP = 29
  REG_LR = 30

  # Aliases for compatibility with x86 logic
  REG_RAX = 0
  REG_RCX = 1
  REG_RDX = 2
  REG_RBX = 19
  REG_RSP = 31
  REG_RBP = 29
  REG_RSI = 3
  REG_RDI = 4
  REG_R8 = 5
  REG_R9 = 6
  REG_R10 = 7
  REG_R11 = 9
  REG_R12 = 20
  REG_R13 = 21
  REG_R14 = 22
  REG_R15 = 23

  # Mapping x86 register names to AArch64 registers for common logic
  REG_MAP = {
    :rax => 0, :rcx => 1, :rdx => 2, :rbx => 19,
    :rsp => 31, :rbp => 29, :rsi => 3, :rdi => 4,
    :r8 => 5,  :r9 => 6,  :r10 => 7, :r11 => 9,
    :r12 => 20, :r13 => 21, :r14 => 22, :r15 => 23
  }

  def initialize
    @bytes = []
    @stack_shadow_size = 0 # No shadow space on AArch64
  end

  def current_pos
    @bytes.length
  end

  def emit(arr)
    @bytes += arr
  end

  def emit32(val)
    emit([val].pack("L<").bytes)
  end

  # --- Prologue/Epilogue ---
  def emit_prologue(stack_size)
    # stp x29, x30, [sp, #-16]!
    # mov x29, sp
    emit32(0xa9bf7bfd)
    emit32(0x910003fd)
    emit_sub_sp(stack_size) if stack_size > 0
  end

  def emit_epilogue(stack_size)
    emit_add_sp(stack_size) if stack_size > 0
    # ldp x29, x30, [sp], #16
    # ret
    emit32(0xa8c17bfd)
    emit32(0xd65f03c0)
  end

  # --- Stack Ops ---
  def emit_sub_sp(size)
    # sub sp, sp, #size
    imm = (size + 15) & ~15
    emit32(0xd10003ff | ((imm & 0xFFF) << 10))
  end

  def emit_add_sp(size)
    imm = (size + 15) & ~15
    emit32(0x910003ff | ((imm & 0xFFF) << 10))
  end

  def emit_sub_rsp(size); emit_sub_sp(size); end
  def emit_add_rsp(size); emit_add_sp(size); end

  # --- Register/Mov Ops ---
  def mov_rax(val)
    reg = 0 # X0
    emit32(0xd2800000 | ((val & 0xFFFF) << 5) | reg) # movz x0, #low16
    if val > 0xFFFF
      emit32(0xf2a00000 | (((val >> 16) & 0xFFFF) << 5) | reg) # movk x0, #imm16, lsl 16
    end
    if val > 0xFFFFFFFF
      emit32(0xf2c00000 | (((val >> 32) & 0xFFFF) << 5) | reg) # movk x0, #imm16, lsl 32
    end
    if val > 0xFFFFFFFFFFFF
      emit32(0xf2e00000 | (((val >> 48) & 0xFFFF) << 5) | reg) # movk x0, #imm16, lsl 48
    end
  end

  def mov_reg_reg(dst, src)
    # orr dst, xzr, src
    emit32(0xaa0003e0 | (src << 16) | dst)
  end

  def mov_stack_reg_val(offset, src_reg)
    off = -offset
    if off >= -256 && off <= 255
      # stur reg, [fp, #off]
      emit32(0xf80003a0 | ((off & 0x1FF) << 12) | (REG_FP << 5) | src_reg)
    else
      emit32(0xf90003a0 | (((off/8) & 0xFFF) << 10) | (REG_FP << 5) | src_reg)
    end
  end

  def mov_reg_stack_val(dst_reg, offset)
    off = -offset
    if off >= -256 && off <= 255
      # ldur reg, [fp, #off]
      emit32(0xf84003a0 | ((off & 0x1FF) << 12) | (REG_FP << 5) | dst_reg)
    else
      emit32(0xf94003a0 | (((off/8) & 0xFFF) << 10) | (REG_FP << 5) | dst_reg)
    end
  end

  def lea_reg_stack(dst_reg, offset)
    # sub dst_reg, fp, #offset
    emit32(0xd10003a0 | ((offset & 0xFFF) << 10) | dst_reg)
  end

  def mov_mem_r11(disp)
    # str x9, [x0, #disp]
    emit32(0xf9000009 | (((disp/8) & 0xFFF) << 10) | (0 << 5))
  end

  def mov_rax_mem(disp)
    # ldr x0, [x0, #disp]
    emit32(0xf9400000 | (((disp/8) & 0xFFF) << 10) | (0 << 5))
  end

  def mov_r11_rax
    mov_reg_reg(9, 0)
  end

  def mov_rax_rbp_disp32(disp)
    # ldr x0, [fp, #disp]
    emit32(0xf94003a0 | (((disp/8) & 0xFFF) << 10) | (REG_FP << 5) | 0)
  end

  def mov_rax_from_reg(src_reg)
    mov_reg_reg(REG_RAX, src_reg)
  end

  def mov_reg_from_rax(dst_reg)
    mov_reg_reg(dst_reg, REG_RAX)
  end

  # --- Math ---
  def add_rax_rdx; emit32(0x8b020000); end # add x0, x0, x2
  def sub_rax_rdx; emit32(0xcb020000); end # sub x0, x0, x2
  def imul_rax_rdx; emit32(0x9b027c00); end # mul x0, x0, x2

  def shl_rax_imm(count)
    # LSL x0, x0, #count -> UBFM x0, x0, #(-count & 63), #(63-count)
    r = (-count) & 63
    s = 63 - count
    emit32(0xd3400000 | (r << 16) | (s << 10) | (0 << 5) | 0)
  end

  def shr_rax_imm(count)
    # LSR x0, x0, #count -> UBFM x0, x0, #count, #63
    emit32(0xd3400000 | (count << 16) | (63 << 10) | (0 << 5) | 0)
  end

  # --- Bitwise ---
  def and_rax_rdx; emit32(0x8a020000); end # and x0, x0, x2
  def or_rax_rdx;  emit32(0xaa020000); end # or x0, x0, x2
  def xor_rax_rdx; emit32(0xca020000); end # eor x0, x0, x2
  def not_rax;     emit32(0xaa2003e0 | (0 << 16) | 0); end # orn x0, xzr, x0

  # --- Jumps ---
  def call_rel32; emit32(0x94000000); end # bl #0
  def jmp_rel32;  emit32(0x14000000); end # b #0
  def je_rel32
    emit32(0xf100001f) # cmp x0, #0
    emit32(0x54000000) # b.eq #0
  end

  def emit_sys_exit(code)
    emit32(0xd2800000 | ((code & 0xFFFF) << 5) | 0)
    emit32(0xd2800ba8) # mov x8, #93
    emit32(0xd4000001) # svc #0
  end

  def emit_sys_exit_rax
    emit32(0xd2800ba8) # mov x8, #93
    emit32(0xd4000001) # svc #0
  end

  # --- Push/Pop ---
  def push_reg(reg)
    # str reg, [sp, #-16]!
    emit32(0xf81f0fe0 | reg)
  end

  def pop_reg(reg)
    # ldr reg, [sp], #16
    emit32(0xf84107e0 | reg)
  end

  def push_callee_saved(regs)
    regs.each { |r| push_reg(REG_MAP[r] || r) }
  end

  def pop_callee_saved(regs)
    regs.reverse.each { |r| pop_reg(REG_MAP[r] || r) }
  end

  def self.reg_code(sym)
    REG_MAP[sym] || sym
  end

  # --- Sized memory ops ---
  def mov_rax_mem_sized(size, signed = true)
    case size
    when 1
      if signed
        emit32(0x39400000) # ldrb w0, [x0]
        emit32(0x93400c00) # sxtb x0, w0
      else
        emit32(0x39400000) # ldrb w0, [x0]
      end
    when 4
      if signed
        emit32(0xb9800000) # ldrsw x0, [x0]
      else
        emit32(0xb9400000) # ldr w0, [x0]
      end
    else # 8
      emit32(0xf9400000) # ldr x0, [x0]
    end
  end

  def mov_mem_rax_sized(size)
    case size
    when 1 then emit32(0x39000080) # strb w0, [x4] (x4 = rdi)
    when 4 then emit32(0xb9000080) # str w0, [x4]
    else        emit32(0xf9000080) # str x0, [x4]
    end
  end

  def method_missing(m, *args, &block)
    # Silently ignore missing methods for now to allow partial support
    # (Should be improved later)
  end
end
