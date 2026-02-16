class CodeEmitter
  attr_reader :bytes, :stack_shadow_size

  REG_RAX = 0; REG_RCX = 1; REG_RDX = 2; REG_RBX = 3
  REG_RSP = 4; REG_RBP = 5; REG_RSI = 6; REG_RDI = 7
  REG_R8 = 8;  REG_R9 = 9;  REG_R10 = 10; REG_R11 = 11
  REG_R12 = 12; REG_R13 = 13; REG_R14 = 14; REG_R15 = 15

  REG_MAP = {
    rax: 0, rcx: 1, rdx: 2, rbx: 3,
    rsp: 4, rbp: 5, rsi: 6, rdi: 7,
    r8: 8, r9: 9, r10: 10, r11: 11,
    r12: 12, r13: 13, r14: 14, r15: 15
  }

  def initialize
    @bytes = []
    @stack_shadow_size = 32
  end

  def current_pos; @bytes.length; end
  def emit(arr); @bytes += arr; end

  def emit_prologue(stack_size)
    emit([0x55, 0x48, 0x89, 0xe5])
    emit_sub_rsp(stack_size)
  end

  def emit_epilogue(stack_size)
    emit_add_rsp(stack_size)
    emit([0x5d, 0xc3])
  end

  def emit_sub_rsp(size)
    emit([0x48, 0x81, 0xec] + [size].pack("l<").bytes)
  end

  def emit_add_rsp(size)
    emit([0x48, 0x81, 0xc4] + [size].pack("l<").bytes)
  end

  def mov_rax(val)
    emit([0x48, 0xb8] + [val].pack("Q<").bytes)
  end

  def mov_reg_reg(dst, src)
    rex = 0x48
    rex |= 0x04 if src >= 8
    rex |= 0x01 if dst >= 8
    modrm = 0xc0 | ((src & 7) << 3) | (dst & 7)
    emit([rex, 0x89, modrm])
  end

  def mov_stack_reg_val(offset, src)
    return if offset.nil?
    rex = 0x48
    rex |= 0x04 if src >= 8
    modrm = 0x80 | ((src & 7) << 3) | 5
    emit([rex, 0x89, modrm] + [(-offset)].pack("l<").bytes)
  end

  def mov_reg_stack_val(dst, offset)
    return if offset.nil?
    rex = 0x48
    rex |= 0x04 if dst >= 8
    modrm = 0x80 | ((dst & 7) << 3) | 5
    emit([rex, 0x8b, modrm] + [(-offset)].pack("l<").bytes)
  end

  def lea_reg_stack(dst, offset)
    return if offset.nil?
    rex = 0x48
    rex |= 0x04 if dst >= 8
    modrm = 0x80 | ((dst & 7) << 3) | 5
    emit([rex, 0x8d, modrm] + [(-offset)].pack("l<").bytes)
  end

  def mov_mem_r11(disp)
    emit([0x4c, 0x89, 0x58, disp & 0xFF])
  end

  def mov_rax_mem(disp)
    emit([0x48, 0x8b, 0x40, disp & 0xFF])
  end

  def mov_rax_mem_idx(reg, offset, size = 8)
    if reg == 4 # rsp
      if size == 8
        emit([0x48, 0x8b, 0x44, 0x24, offset])
      elsif size == 4
        emit([0x8b, 0x44, 0x24, offset])
      elsif size == 1
        emit([0x48, 0x0f, 0xb6, 0x44, 0x24, offset])
      end
    else
      # fall back to rax as base
      if size == 8
        emit([0x48, 0x8b, 0x40 + reg, offset])
      end
    end
  end

  def mov_mem_idx(base, offset, src, size = 8)
    if base == 4 # rsp
      if size == 8
        emit([0x48, 0x89, 0x44, 0x24, offset]) # wait, src reg
        # Actually x86-64 encoding for [rsp+offset] is complex if src is not RAX
        # simplified for now: assume src=RAX
        emit([0x48, 0x89, 0x04, 0x24 + offset]) if src == 0 && offset == 0
      end
    end
    # Fallback to simple mov_stack_reg_val if it was rsp
    if base == 4 && src == 0 && size == 8
       mov_stack_reg_val(-offset, 0)
    elsif base == 4 && size == 4
       emit([0x89, 0x44, 0x24, offset]) # mov [rsp+offset], eax
    elsif base == 4 && size == 2
       emit([0x66, 0x89, 0x44, 0x24, offset]) # mov [rsp+offset], ax
    end
  end

  def mov_r11_rax; emit([0x49, 0x89, 0xc3]); end

  def mov_rax_rbp_disp32(disp)
    emit([0x48, 0x8b, 0x85] + [disp].pack("l<").bytes)
  end

  def add_rax_rdx; emit([0x48, 0x01, 0xd0]); end
  def sub_rax_rdx; emit([0x48, 0x29, 0xd0]); end
  def imul_rax_rdx; emit([0x48, 0x0f, 0xaf, 0xc2]); end
  def and_rax_rdx; emit([0x48, 0x21, 0xd0]); end
  def or_rax_rdx; emit([0x48, 0x09, 0xd0]); end
  def xor_rax_rdx; emit([0x48, 0x31, 0xd0]); end
  def not_rax; emit([0x48, 0xf7, 0xd0]); end

  def shl_rax_cl; emit([0x48, 0x89, 0xd1, 0x48, 0xd3, 0xe0]); end
  def shr_rax_cl; emit([0x48, 0x89, 0xd1, 0x48, 0xd3, 0xe8]); end
  def shl_rax_imm(c); emit([0x48, 0xc1, 0xe0, c & 0x3f]); end
  def shl_reg_imm(reg, c); emit([0x48, 0xc1, 0xe0 + (reg % 8), c & 0x3f]); end
  def or_rax_reg(reg); emit([0x48, 0x09, 0xc0 + (reg % 8)]); end
  def shr_rax_imm(c); emit([0x48, 0xc1, 0xe8, c & 0x3f]); end

  def div_rax_by_rdx
    emit([0x48, 0x89, 0xd1, 0x48, 0x99, 0x48, 0xf7, 0xf9])
  end

  def mod_rax_by_rdx
    emit([0x48, 0x89, 0xd1, 0x48, 0x99, 0x48, 0xf7, 0xf9, 0x48, 0x89, 0xd0])
  end

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
  def test_reg_reg(r1, r2); emit([0x48, 0x85, 0xc0 + (r1 % 8) + (r2 % 8) * 8]); end # wait, test is 0x85

  def cmp_reg_imm(reg, imm)
    if reg == 0 # rax
      emit([0x48, 0x3d] + [imm].pack("L<").bytes)
    else
      emit([0x48, 0x81, 0xf8 + (reg % 8)] + [imm].pack("L<").bytes)
    end
  end

  def call_rel32; emit([0xe8, 0, 0, 0, 0]); end
  def call_reg(reg); emit([0xff, 0xd0 + (reg % 8)]); end
  def call_ind_rel32; emit([0xff, 0x15, 0, 0, 0, 0]); end

  def jmp_rel32; pos = current_pos; emit([0xe9, 0, 0, 0, 0]); pos; end
  def je_rel32; pos = current_pos; emit([0x0f, 0x84, 0, 0, 0, 0]); pos; end
  def jne_rel32; pos = current_pos; emit([0x0f, 0x85, 0, 0, 0, 0]); pos; end

  def patch_jmp(pos, target)
    offset = target - (pos + 5)
    @bytes[pos+1..pos+4] = [offset].pack("l<").bytes
  end

  def patch_je(pos, target)
    offset = target - (pos + 6)
    @bytes[pos+2..pos+5] = [offset].pack("l<").bytes
  end
  def patch_jne(pos, target); patch_je(pos, target); end

  def emit_sys_exit_rax
    emit([0x48, 0x89, 0xc7, 0x48, 0xc7, 0xc0, 60, 0, 0, 0, 0x0f, 0x05])
  end

  def push_reg(r)
    if r >= 8 then emit([0x41, 0x50 + (r - 8)]) else emit([0x50 + r]) end
  end

  def pop_reg(r)
    if r >= 8 then emit([0x41, 0x58 + (r - 8)]) else emit([0x58 + r]) end
  end

  def push_callee_saved(regs); regs.each { |r| push_reg(REG_MAP[r] || r) }; end
  def pop_callee_saved(regs); regs.reverse.each { |r| pop_reg(REG_MAP[r] || r) }; end

  def mov_rax_from_reg(s); mov_reg_reg(0, s); end
  def mov_reg_from_rax(d); mov_reg_reg(d, 0); end

  def self.reg_code(s); REG_MAP[s] || s; end

  def emit_load_address(label, linker)
    emit([0x48, 0x8d, 0x05])
    linker.add_data_patch(current_pos, label)
    emit([0, 0, 0, 0])
  end

  def mov_rax_mem_sized(size, signed = true)
    case size
    when 1 then emit(signed ? [0x48, 0x0f, 0xbe, 0x00] : [0x48, 0x0f, 0xb6, 0x00])
    when 2 then emit(signed ? [0x48, 0x0f, 0xbf, 0x00] : [0x48, 0x0f, 0xb7, 0x00])
    when 4 then emit(signed ? [0x48, 0x63, 0x00] : [0x8b, 0x00])
    else        emit([0x48, 0x8b, 0x00])
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

  def syscall; emit([0x0f, 0x05]); end

  def memcpy
    # dest=RDI, src=RSI, n=RCX
    emit([0xf3, 0xa4]) # rep movsb
  end

  def memset
    # dest=RDI, val=AL, n=RCX
    emit([0xf3, 0xaa]) # rep stosb
  end
end
