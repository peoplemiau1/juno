class CodeEmitter
  attr_reader :bytes, :stack_shadow_size

  REG_RAX = 0; REG_RCX = 1; REG_RDX = 2; REG_RBX = 3
  REG_RSP = 4; REG_RBP = 5; REG_RSI = 6; REG_RDI = 7
  REG_R8 = 8;  REG_R9 = 9;  REG_R10 = 10; REG_R11 = 11
  REG_R12 = 12; REG_R13 = 13; REG_R14 = 14; REG_R15 = 15

  REG_MAP = {
    :rax => REG_RAX, :rcx => REG_RCX, :rdx => REG_RDX, :rbx => REG_RBX,
    :rsp => REG_RSP, :rbp => REG_RBP, :rsi => REG_RSI, :rdi => REG_RDI,
    :r8 => REG_R8, :r9 => REG_R9, :r10 => REG_R10, :r11 => REG_R11,
    :r12 => REG_R12, :r13 => REG_R13, :r14 => REG_R14, :r15 => REG_R15
  }

  def initialize; @bytes = []; @stack_shadow_size = 32; end
  def current_pos; @bytes.length; end
  def emit(arr); @bytes += arr; end

  def emit_prologue(stack_size); emit([0x55, 0x48, 0x89, 0xe5]); emit_sub_rsp(stack_size); end
  def emit_epilogue(stack_size); emit_add_rsp(stack_size); emit([0x5d, 0xc3]); end
  def emit_sub_rsp(size); emit([0x48, 0x81, 0xec] + [size].pack("l<").bytes); end
  def emit_add_rsp(size); emit([0x48, 0x81, 0xc4] + [size].pack("l<").bytes); end

  def mov_rax(val); emit([0x48, 0xb8] + [val].pack("Q<").bytes); end
  def mov_reg_reg(dst, src)
    rex = 0x48; rex |= 0x04 if src >= 8; rex |= 0x01 if dst >= 8
    emit([rex, 0x89, 0xc0 | ((src & 7) << 3) | (dst & 7)])
  end

  def mov_stack_reg_val(offset, src_reg_code)
    return if offset.nil?; rex = 0x48; rex |= 0x04 if src_reg_code >= 8
    emit([rex, 0x89, 0x85 | ((src_reg_code & 7) << 3)] + [(-offset)].pack("l<").bytes)
  end

  def mov_reg_stack_val(dst_reg_code, offset)
    return if offset.nil?; rex = 0x48; rex |= 0x04 if dst_reg_code >= 8
    emit([rex, 0x8b, 0x85 | ((dst_reg_code & 7) << 3)] + [(-offset)].pack("l<").bytes)
  end

  def lea_reg_stack(dst_reg_code, offset)
    return if offset.nil?; rex = 0x48; rex |= 0x04 if dst_reg_code >= 8
    emit([rex, 0x8d, 0x85 | ((dst_reg_code & 7) << 3)] + [(-offset)].pack("l<").bytes)
  end

  def mov_mem_r11(disp); emit([0x4c, 0x89, 0x58, disp & 0xFF]); end
  def mov_rax_mem(disp); emit([0x48, 0x8b, 0x40, disp & 0xFF]); end
  def mov_r11_rax; emit([0x49, 0x89, 0xc3]); end
  def mov_rax_rbp_disp32(disp); emit([0x48, 0x8b, 0x85] + [disp].pack("l<").bytes); end

  def add_rax_rdx; emit([0x48, 0x01, 0xd0]); end
  def sub_rax_rdx; emit([0x48, 0x29, 0xd0]); end
  def imul_rax_rdx; emit([0x48, 0x0f, 0xaf, 0xc2]); end
  def and_rax_rdx; emit([0x48, 0x21, 0xd0]); end
  def or_rax_rdx;  emit([0x48, 0x09, 0xd0]); end
  def xor_rax_rdx; emit([0x48, 0x31, 0xd0]); end
  def not_rax;     emit([0x48, 0xf7, 0xd0]); end
  def shl_rax_imm(count); emit([0x48, 0xc1, 0xe0, count & 0x3f]); end
  def shr_rax_imm(count); emit([0x48, 0xc1, 0xe8, count & 0x3f]); end

  def div_rax_by_rdx; emit([0x48, 0x89, 0xd1, 0x48, 0x99, 0x48, 0xf7, 0xf9]); end
  def mod_rax_by_rdx; emit([0x48, 0x89, 0xd1, 0x48, 0x99, 0x48, 0xf7, 0xf9, 0x48, 0x89, 0xd0]); end
  def save_rax_to_rdx; emit([0x48, 0x89, 0xc2]); end

  def cmp_rax_rdx(op)
    emit([0x48, 0x39, 0xd0, 0x48, 0xc7, 0xc0, 0, 0, 0, 0])
    case op
    when "==" then emit([0x0f, 0x94, 0xc0])
    when "!=" then emit([0x0f, 0x95, 0xc0])
    when "<"  then emit([0x0f, 0x9c, 0xc0])
    when ">"  then emit([0x0f, 0x9f, 0xc0])
    when "<=" then emit([0x0f, 0x9e, 0xc0])
    when ">=" then emit([0x0f, 0x9d, 0xc0])
    end
  end

  def test_rax_rax; emit([0x48, 0x85, 0xc0]); end
  def test_al_al; emit([0x84, 0xc0]); end

  def call_rel32; emit([0xe8, 0, 0, 0, 0]); end
  def call_ind_rel32; emit([0xff, 0x15, 0, 0, 0, 0]); end
  def jmp_rel32; pos = current_pos; emit([0xe9, 0, 0, 0, 0]); pos; end
  def je_rel32; test_rax_rax; pos = current_pos; emit([0x0f, 0x84, 0, 0, 0, 0]); pos; end
  def jne_rel32; test_rax_rax; pos = current_pos; emit([0x0f, 0x85, 0, 0, 0, 0]); pos; end

  def patch_je(pos, target); patch_branch(pos, target, 6); end
  def patch_jne(pos, target); patch_branch(pos, target, 6); end
  def patch_jmp(pos, target); patch_branch(pos, target, 5); end

  def patch_branch(pos, target, instr_len)
    offset = target - (pos + instr_len)
    @bytes[pos+(instr_len-4)...pos+instr_len] = [offset].pack("l<").bytes
  end

  def emit_sys_exit_rax; emit([0x48, 0x89, 0xc7, 0x48, 0xc7, 0xc0, 60, 0, 0, 0, 0x0f, 0x05]); end
  def push_callee_saved(regs); regs.each { |reg| push_reg(REG_MAP[reg] || reg) }; end
  def pop_callee_saved(regs); regs.reverse.each { |reg| pop_reg(REG_MAP[reg] || reg) }; end

  def push_reg(reg_code)
    reg_code >= 8 ? emit([0x41, 0x50 + (reg_code - 8)]) : emit([0x50 + reg_code])
  end

  def pop_reg(reg_code)
    reg_code >= 8 ? emit([0x41, 0x58 + (reg_code - 8)]) : emit([0x58 + reg_code])
  end

  def mov_rax_from_reg(src_reg); mov_reg_reg(REG_RAX, src_reg); end
  def mov_reg_from_rax(dst_reg); mov_reg_reg(dst_reg, REG_RAX); end
  def self.reg_code(sym); REG_MAP[sym] || sym; end

  def mov_rax_mem_sized(size, signed = true)
    case size
    when 1 then signed ? emit([0x48, 0x0f, 0xbe, 0x00]) : emit([0x48, 0x0f, 0xb6, 0x00])
    when 2 then signed ? emit([0x48, 0x0f, 0xbf, 0x00]) : emit([0x48, 0x0f, 0xb7, 0x00])
    when 4 then signed ? emit([0x48, 0x63, 0x00]) : emit([0x8b, 0x00])
    else emit([0x48, 0x8b, 0x00])
    end
  end

  def mov_mem_rax_sized(size)
    case size
    when 1 then emit([0x88, 0x07])
    when 2 then emit([0x66, 0x89, 0x07])
    when 4 then emit([0x89, 0x07])
    else        emit([0x48, 0x89, 0x07])
    end
  end
end
