class AArch64Emitter
  attr_reader :bytes, :stack_shadow_size

  # Registers X0-X30, SP=31
  (0..30).each { |i| const_set("REG_X#{i}", i) }
  REG_SP = 31; REG_FP = 29; REG_LR = 30; REG_RAX = 0; REG_RCX = 1; REG_RDX = 2; REG_RBX = 19; REG_RSP = 31; REG_RBP = 29; REG_RSI = 3; REG_RDI = 4; REG_R8 = 5; REG_R9 = 6; REG_R10 = 7; REG_R11 = 9; REG_R12 = 20; REG_R13 = 21; REG_R14 = 22; REG_R15 = 23
  REG_MAP = { :rax => 0, :rcx => 1, :rdx => 2, :rbx => 19, :rsp => 31, :rbp => 29, :rsi => 3, :rdi => 4, :r8 => 5, :r9 => 6, :r10 => 7, :r11 => 9, :r12 => 20, :r13 => 21, :r14 => 22, :r15 => 23 }

  def initialize; @bytes = []; @stack_shadow_size = 0; end
  def current_pos; @bytes.length; end
  def emit(arr); @bytes += arr; end
  def emit32(val); emit([val].pack("L<").bytes); end

  def emit_prologue(stack_size); emit32(0xa9bf7bfd); emit32(0x910003fd); emit_sub_sp(stack_size) if stack_size > 0; end
  def emit_epilogue(stack_size); emit_add_sp(stack_size) if stack_size > 0; emit32(0xa8c17bfd); emit32(0xd65f03c0); end
  def emit_sub_sp(size); imm = (size + 15) & ~15; emit32(0xd10003ff | ((imm & 0xFFF) << 10)); end
  def emit_add_sp(size); imm = (size + 15) & ~15; emit32(0x910003ff | ((imm & 0xFFF) << 10)); end
  def emit_sub_rsp(size); emit_sub_sp(size); end
  def emit_add_rsp(size); emit_add_sp(size); end

  def mov_rax(val)
    reg = 0; emit32(0xd2800000 | ((val & 0xFFFF) << 5) | reg)
    emit32(0xf2a00000 | (((val >> 16) & 0xFFFF) << 5) | reg) if val > 0xFFFF
    emit32(0xf2c00000 | (((val >> 32) & 0xFFFF) << 5) | reg) if val > 0xFFFFFFFF
    emit32(0xf2e00000 | (((val >> 48) & 0xFFFF) << 5) | reg) if val > 0xFFFFFFFFFFFF
  end

  def mov_reg_reg(dst, src); emit32(0xaa0003e0 | (src << 16) | dst); end
  def mov_stack_reg_val(offset, src_reg)
    off = -offset
    if off >= -256 && off <= 255 then emit32(0xf80003a0 | ((off & 0x1FF) << 12) | (REG_FP << 5) | src_reg)
    else emit32(0xf90003a0 | (((off/8) & 0xFFF) << 10) | (REG_FP << 5) | src_reg)
    end
  end
  def mov_reg_stack_val(dst_reg, offset)
    off = -offset
    if off >= -256 && off <= 255 then emit32(0xf84003a0 | ((off & 0x1FF) << 12) | (REG_FP << 5) | dst_reg)
    else emit32(0xf94003a0 | (((off/8) & 0xFFF) << 10) | (REG_FP << 5) | dst_reg)
    end
  end
  def lea_reg_stack(dst_reg, offset); emit32(0xd10003a0 | ((offset & 0xFFF) << 10) | dst_reg); end
  def mov_mem_r11(disp); emit32(0xf9000009 | (((disp/8) & 0xFFF) << 10) | (0 << 5)); end
  def mov_rax_mem(disp); emit32(0xf9400000 | (((disp/8) & 0xFFF) << 10) | (0 << 5)); end
  def mov_r11_rax; mov_reg_reg(9, 0); end
  def mov_rax_rbp_disp32(disp); emit32(0xf94003a0 | (((disp/8) & 0xFFF) << 10) | (REG_FP << 5) | 0); end
  def mov_rax_from_reg(src_reg); mov_reg_reg(REG_RAX, src_reg); end
  def mov_reg_from_rax(dst_reg); mov_reg_reg(dst_reg, REG_RAX); end

  def add_rax_rdx; emit32(0x8b020000); end
  def sub_rax_rdx; emit32(0xcb020000); end
  def imul_rax_rdx; emit32(0x9b027c00); end
  def shl_rax_imm(count); r = (-count) & 63; s = 63 - count; emit32(0xd3400000 | (r << 16) | (s << 10) | (0 << 5) | 0); end
  def shr_rax_imm(count); emit32(0xd3400000 | (count << 16) | (63 << 10) | (0 << 5) | 0); end
  def and_rax_rdx; emit32(0x8a020000); end
  def or_rax_rdx;  emit32(0xaa020000); end
  def xor_rax_rdx; emit32(0xca020000); end
  def not_rax;     emit32(0xaa2003e0 | (0 << 16) | 0); end

  def test_rax_rax; emit32(0xf100001f); end
  def call_rel32; emit32(0x94000000); end
  def jmp_rel32;  pos = current_pos; emit32(0x14000000); pos; end
  def je_rel32; test_rax_rax; pos = current_pos; emit32(0x54000000); pos; end
  def jne_rel32; test_rax_rax; pos = current_pos; emit32(0x54000001); pos; end # b.ne

  def patch_je(pos, target); offset = (target - pos) / 4; @bytes[pos..pos+3] = [0x54000000 | ((offset & 0x7FFFF) << 5)].pack("L<").bytes; end
  def patch_jne(pos, target); offset = (target - pos) / 4; @bytes[pos..pos+3] = [0x54000001 | ((offset & 0x7FFFF) << 5)].pack("L<").bytes; end
  def patch_jmp(pos, target); offset = (target - pos) / 4; @bytes[pos..pos+3] = [0x14000000 | (offset & 0x3FFFFFF)].pack("L<").bytes; end

  def emit_sys_exit_rax; emit32(0xd2800ba8); emit32(0xd4000001); end
  def push_reg(reg); emit32(0xf81f0fe0 | reg); end
  def pop_reg(reg); emit32(0xf84107e0 | reg); end
  def push_callee_saved(regs); regs.each { |r| push_reg(REG_MAP[r] || r) }; end
  def pop_callee_saved(regs); regs.reverse.each { |r| pop_reg(REG_MAP[r] || r) }; end
  def self.reg_code(sym); REG_MAP[sym] || sym; end

  def mov_rax_mem_sized(size, signed = true)
    case size
    when 1 then signed ? (emit32(0x39400000); emit32(0x93400c00)) : emit32(0x39400000)
    when 4 then signed ? emit32(0xb9800000) : emit32(0xb9400000)
    else emit32(0xf9400000)
    end
  end
  def mov_mem_rax_sized(size)
    case size
    when 1 then emit32(0x39000080)
    when 4 then emit32(0xb9000080)
    else        emit32(0xf9000080)
    end
  end

  # Raise error for missing methods to avoid silent failures
  def method_missing(m, *args, &block)
    raise "AArch64Emitter: method #{m} not implemented"
  end
end
