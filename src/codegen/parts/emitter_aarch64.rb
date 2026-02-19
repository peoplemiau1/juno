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
    @internal_patches = []
  end

  attr_reader :internal_patches

  def callee_saved_regs; [19, 20, 21, 22, 23, 24, 25, 26, 27, 28]; end

  def current_pos; @bytes.length; end
  def emit32(v); @bytes += [v].pack("L<").bytes; end
  def emit(arr); @bytes += arr; end

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

  def emit_add_imm(rd, rn, imm)
    emit32(0x91000000 | ((imm & 0xFFF) << 10) | (rn << 5) | rd)
  end

  def emit_sub_imm(rd, rn, imm)
    emit32(0xd1000000 | ((imm & 0xFFF) << 10) | (rn << 5) | rd)
  end

  def emit_sub_rsp(size)
    return if size <= 0
    while size > 0
      chunk = [size, 0xfff].min
      emit_sub_imm(31, 31, chunk)
      size -= chunk
    end
  end

  def emit_add_rsp(size)
    return if size <= 0
    while size > 0
      chunk = [size, 0xfff].min
      emit_add_imm(31, 31, chunk)
      size -= chunk
    end
  end

  def mov_reg_imm(reg, val)
    if val == 0
      emit32(0xd2800000 | reg)
      return
    end
    first = true
    4.times do |i|
      part = (val >> (i * 16)) & 0xFFFF
      if part != 0 || (first && val >= 0)
        opcode = first ? 0xd2800000 : 0xf2800000
        emit32(opcode | (part << 5) | (i << 21) | reg)
        first = false
      end
    end
  end

  def mov_rax(val); mov_reg_imm(0, val); end

  def mov_reg_reg(dst, src)
    emit32(0xaa0003e0 | (src << 16) | dst)
  end

  def mov_reg_sp(dst)
    # mov dst, sp  -> add dst, sp, #0
    emit32(0x910003e0 | dst)
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

  def mov_reg_mem_idx(dst, base, offset, size = 8)
    # ldr dst, [base, #offset]
    if size == 8
      emit32(0xf9400000 | ((offset / 8) << 10) | (base << 5) | dst)
    elsif size == 4
      emit32(0xb9400000 | (offset << 10) | (base << 5) | dst)
    elsif size == 1
      emit32(0x39400000 | (offset << 10) | (base << 5) | dst)
    end
  end

  def mov_rax_mem_idx(reg, offset, size = 8); mov_reg_mem_idx(0, reg, offset, size); end
  def mov_rcx_mem_idx(reg, offset, size = 8); mov_reg_mem_idx(1, reg, offset, size); end

  def mov_r11_rax; mov_reg_reg(11, 0); end

  def mov_rax_rbp_disp32(disp)
    emit32(0xf94003a0 | 0 | ((disp / 8) << 10))
  end

  def add_reg_reg(dst, src)
    emit32(0x8b000000 | (src << 16) | (dst << 5) | dst) # actually Rn, Rm, Rd. Rn=dst, Rm=src, Rd=dst
    # wait, add rd, rn, rm is 0x8b000000 | (rm << 16) | (rn << 5) | rd
  end
  def add_rax_rdx; emit32(0x8b020000); end

  def sub_reg_reg(dst, src)
    emit32(0xcb000000 | (src << 16) | (dst << 5) | dst)
  end
  def sub_rax_rdx; emit32(0xcb020000); end

  def mul_reg_reg(dst, src)
    # madd rd, rn, rm, xzr -> rd = rn * rm + 0
    emit32(0x9b007c00 | (src << 16) | (dst << 5) | dst)
  end
  def imul_rax_rdx; emit32(0x9b027c00); end

  def and_reg_reg(dst, src)
    emit32(0x8a000000 | (src << 16) | (dst << 5) | dst)
  end
  def and_rax_rdx; emit32(0x8a020000); end
  def and_rax_reg(src); and_reg_reg(0, src); end
  def add_rax_reg(src); add_reg_reg(0, src); end
  def sub_rax_reg(src); sub_reg_reg(0, src); end

  def add_reg_imm(reg, imm)
    emit32(0x91000000 | ((imm & 0xFFF) << 10) | (reg << 5) | reg)
  end

  def sub_reg_imm(reg, imm)
    emit32(0xd1000000 | ((imm & 0xFFF) << 10) | (reg << 5) | reg)
  end

  def emit_add_rax(imm); add_reg_imm(0, imm); end
  def emit_sub_rax(imm); sub_reg_imm(0, imm); end

  def or_reg_reg(dst, src)
    emit32(0xaa000000 | (src << 16) | (dst << 5) | dst)
  end
  def or_rax_rdx; emit32(0xaa020000); end
  def or_rax_reg(src); or_reg_reg(0, src); end

  def xor_reg_reg(dst, src)
    emit32(0xca000000 | (src << 16) | (dst << 5) | dst)
  end
  def xor_rax_rdx; emit32(0xca020000); end
  def xor_rax_reg(src); xor_reg_reg(0, src); end

  def not_reg(reg)
    # orn rd, xzr, rm -> rd = ~rm
    emit32(0xaa2003e0 | (reg << 16) | reg)
  end
  def not_rax; emit32(0xaa2003e0); end

  def shl_reg_cl(reg)
    # asrv rd, rn, rm -> x0, x0, x1
    emit32(0x9ac12000 | (reg << 5) | reg)
  end
  def shl_rax_cl; shl_reg_cl(0); end

  def shr_reg_cl(reg)
    # lsrv rd, rn, rm
    emit32(0x9ac12400 | (reg << 5) | reg)
  end
  def shr_rax_cl; shr_reg_cl(0); end

  def shl_reg_imm(reg, c)
    c &= 63
    emit32(0xd3400000 | (reg << 5) | reg | (((64 - c) & 63) << 16) | ((63 - c) << 10))
  end
  def shl_rax_imm(c); shl_reg_imm(0, c); end

  def shr_reg_imm(reg, c)
    c &= 63
    emit32(0xd3400000 | (reg << 5) | reg | (c << 16) | (63 << 10))
  end
  def shr_rax_imm(c); shr_reg_imm(0, c); end

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

  def test_rax_rax; emit32(0xf100001f); end # cmp x0, #0
  def test_reg_reg(r1, r2); emit32(0xeb00001f | (r2 << 16) | (r1 << 5)); end # cmp r1, r2

  def cmp_reg_reg(r1, r2)
    # subs xzr, r1, r2
    emit32(0xeb00001f | (r2 << 16) | (r1 << 5))
  end

  def cmp_reg_imm(reg, imm)
    # subs xzr, reg, #imm
    emit32(0xf100001f | ((imm & 0xfff) << 10) | (reg << 5))
  end

  def csel(cond, rd, rn, rm)
    c = case cond
        when "==" then 0 when "!=" then 1 when "<"  then 11
        when ">"  then 12 when "<=" then 13 when ">=" then 10
        end
    emit32(0x9a800000 | (rm << 16) | (c << 12) | (rn << 5) | rd)
  end

  def call_rel32; emit32(0x94000000); end
  def call_ind_rel32; emit32(0xd63f0000); end

  def jmp_rel32; pos = current_pos; emit32(0x14000000); pos; end
  def je_rel32; pos = current_pos; emit32(0x54000000); pos; end
  def jne_rel32; pos = current_pos; emit32(0x54000001); pos; end

  def patch_jmp(pos, target)
    @internal_patches << { pos: pos, target: target, type: :jmp_rel32 }
    offset = (target - pos) / 4
    @bytes[pos...pos+4] = [0x14000000 | (offset & 0x03FFFFFF)].pack("L<").bytes
  end

  def patch_je(pos, target)
    @internal_patches << { pos: pos, target: target, type: :je_rel32 }
    offset = (target - pos) / 4
    # imm19 at bits 5-23
    @bytes[pos...pos+4] = [0x54000000 | ((offset & 0x7FFFF) << 5)].pack("L<").bytes
  end

  def patch_jne(pos, target)
    @internal_patches << { pos: pos, target: target, type: :jne_rel32 }
    offset = (target - pos) / 4
    # imm19 at bits 5-23, cond=1 (NE)
    @bytes[pos...pos+4] = [0x54000001 | ((offset & 0x7FFFF) << 5)].pack("L<").bytes
  end

  def mov_x8(val); mov_reg_imm(8, val); end

  def emit_sys_exit_rax
    mov_x8(93)
    # x0 is already rax
    emit32(0xd4000001)
  end

  def push_reg(r); emit32(0xf81f0fe0 | r); end # str r, [sp, #-16]!
  def pop_reg(r); emit32(0xf84107e0 | r); end  # ldr r, [sp], #16

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

  def syscall; emit32(0xd4000001); end

  def memcpy
    # dest=X0, src=X1, n=X2
    # x3 = temp byte
    emit32(0xb4000082) # cbz x2, +16 (to end)
    # loop:
    emit32(0x38400423) # ldrb w3, [x1], #1
    emit32(0x38000403) # strb w3, [x0], #1
    emit32(0xd1000442) # sub x2, x2, #1
    emit32(0x35fffffd) # cbnz x2, -12 (back to ldrb)
    # end:
  end

  def memset
    # dest=X0, val=X1, n=X2
    emit32(0xb4000062) # cbz x2, +12 (to end)
    # loop:
    emit32(0x38000401) # strb w1, [x0], #1
    emit32(0xd1000442) # sub x2, x2, #1
    emit32(0x35fffffe) # cbnz x2, -8 (back to strb)
    # end:
  end

  def mov_mem_idx(base, offset, src, size = 8); mov_mem_reg_idx(base, offset, src, size); end

  def mov_mem_reg_idx(base, offset, src, size = 8)
    if size == 8
      emit32(0xf9000000 | ((offset / 8) << 10) | (base << 5) | src)
    elsif size == 4
      emit32(0xb9000000 | (offset << 10) | (base << 5) | src)
    elsif size == 2
      emit32(0x79000000 | ((offset / 2) << 10) | (base << 5) | src)
    elsif size == 1
      emit32(0x39000000 | (offset << 10) | (base << 5) | src)
    end
  end
end
