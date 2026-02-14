class AArch64Emitter
  attr_reader :bytes, :stack_shadow_size

  REG_MAP = {
    rax: 0, rcx: 1, rdx: 2, rbx: 19,
    rsp: 31, rbp: 29, rsi: 6, rdi: 7,
    r8: 8, r9: 9, r10: 10, r11: 11,
    r12: 12, r13: 13, r14: 14, r15: 15
  }

  def initialize
    @bytes = []
    @stack_shadow_size = 0
  end

  def current_pos; @bytes.length; end
  def emit32(v); @bytes += [v].pack("L<").bytes; end

  def emit_prologue(stack_size)
    emit32(0xa9bf7bfd) # stp x29, x30, [sp, #-16]!
    emit32(0x910003fd) # mov x29, sp
    emit_sub_rsp(stack_size)
  end

  def emit_epilogue(stack_size)
    emit_add_rsp(stack_size)
    emit32(0xa8c17bfd) # ldp x29, x30, [sp], #16
    emit32(0xd65f03c0) # ret
  end

  def emit_sub_rsp(size)
    return if size <= 0
    while size > 0
      chunk = [size, 0xfff].min
      emit32(0xd10003ff | (chunk << 10))
      size -= chunk
    end
  end

  def emit_add_rsp(size)
    return if size <= 0
    while size > 0
      chunk = [size, 0xfff].min
      emit32(0x910003ff | (chunk << 10))
      size -= chunk
    end
  end

  def mov_rax(val)
    if val == 0
      emit32(0xd2800000)
      return
    end
    first = true
    4.times do |i|
      part = (val >> (i * 16)) & 0xFFFF
      if part != 0 || (first && val >= 0)
        opcode = first ? 0xd2800000 : 0xf2800000
        emit32(opcode | (part << 5) | (i << 21))
        first = false
      end
    end
  end

  def mov_reg_reg(dst, src)
    emit32(0xaa0003e0 | (src << 16) | dst)
  end

  def mov_stack_reg_val(offset, src)
    imm = (-offset)
    emit32(0xf90003a0 | src | ((imm / 8) << 10))
  end

  def mov_reg_stack_val(dst, offset)
    imm = (-offset)
    emit32(0xf94003a0 | dst | ((imm / 8) << 10))
  end

  def lea_reg_stack(dst, offset)
    imm = -offset
    emit32(0x910003a0 | dst | (imm << 10))
  end

  def mov_mem_r11(disp)
    emit32(0xf900000b | ((disp / 8) << 10))
  end

  def mov_rax_mem(disp)
    emit32(0xf9400000 | ((disp / 8) << 10))
  end

  def mov_r11_rax; mov_reg_reg(11, 0); end

  def mov_rax_rbp_disp32(disp)
    emit32(0xf94003a0 | 0 | ((disp / 8) << 10))
  end

  def add_rax_rdx; emit32(0x8b020000); end
  def sub_rax_rdx; emit32(0xcb020000); end
  def imul_rax_rdx; emit32(0x9b027c00); end
  def and_rax_rdx; emit32(0x8a020000); end
  def or_rax_rdx; emit32(0xaa020000); end
  def xor_rax_rdx; emit32(0xca020000); end
  def not_rax; emit32(0xaa2003e0); end

  def shl_rax_cl; emit32(0x9ac12000); end
  def shr_rax_cl; emit32(0x9ac12400); end
  def shl_rax_imm(c); emit32(0xd3400000 | ((64 - c) << 16) | (63 - c)); end
  def shr_rax_imm(c); emit32(0xd3400000 | (c << 16) | 63); end

  def div_rax_by_rdx; emit32(0x9ac20c00); end

  def mod_rax_by_rdx
    emit32(0x9ac20c01) # sdiv x1, x0, x2
    emit32(0x9b028020) # msub x0, x1, x2, x0
  end

  def cmp_rax_rdx(op)
    emit32(0xeb02001f)
    cond = case op
           when "==" then 0 when "!=" then 1 when "<"  then 11
           when ">"  then 12 when "<=" then 13 when ">=" then 10
           end
    emit32(0x1a9f07e0 | (cond << 12))
  end

  def test_rax_rax; emit32(0xeb00001f); end

  def call_rel32; emit32(0x94000000); end
  def call_ind_rel32; emit32(0xd63f0000); end

  def jmp_rel32; pos = current_pos; emit32(0x14000000); pos; end
  def je_rel32; pos = current_pos; emit32(0x54000000); pos; end

  def patch_jmp(pos, target)
    offset = (target - pos) / 4
    @bytes[pos...pos+4] = [0x14000000 | (offset & 0x3FFFFFF)].pack("L<").bytes
  end

  def patch_je(pos, target)
    offset = (target - pos) / 4
    @bytes[pos...pos+4] = [0x54000000 | ((offset << 5) & 0xFFFFE0)].pack("L<").bytes
  end

  def emit_sys_exit_rax
    mov_rax(93)
    mov_reg_reg(8, 0)
    emit32(0xd4000001)
  end

  def push_reg(r); emit32(0xf81f0fe0 | r); end
  def pop_reg(r); emit32(0xf84007e0 | r); end

  def push_callee_saved(regs); regs.each { |r| push_reg(REG_MAP[r] || r) }; end
  def pop_callee_saved(regs); regs.reverse.each { |r| pop_reg(REG_MAP[r] || r) }; end

  def mov_rax_from_reg(s); mov_reg_reg(0, s); end
  def mov_reg_from_rax(d); mov_reg_reg(d, 0); end

  def self.reg_code(s); REG_MAP[s] || s; end

  def emit_load_address(label, linker)
    pos = current_pos
    emit32(0x10000000) # ADR X0, 0
    linker.add_data_patch(pos, label, :aarch64_adr)
  end

  def mov_rax_mem_sized(size, signed = true)
    case size
    when 1 then emit32(signed ? 0x39c00000 : 0x39400000)
    when 2 then emit32(signed ? 0x79c00000 : 0x79400000)
    when 4 then emit32(signed ? 0xb9c00000 : 0xb9400000)
    else        emit32(0xf9400000)
    end
  end

  def mov_mem_rax_sized(size)
    case size
    when 1 then emit32(0x390000e0)
    when 2 then emit32(0x790000e0)
    when 4 then emit32(0xb90000e0)
    else        emit32(0xf90000e0)
    end
  end
end
