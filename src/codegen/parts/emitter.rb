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
    @internal_patches = []
  end

  attr_reader :internal_patches

  def callee_saved_regs; [:rbx, :r12, :r13, :r14, :r15]; end

  def current_pos; @bytes.length; end
  def emit(arr); @bytes += arr; end

  private

  def rex_prefix(w: false, r: false, x: false, b: false)
    rex = 0x40
    rex |= 0x08 if w
    rex |= 0x04 if r
    rex |= 0x02 if x
    rex |= 0x01 if b
    rex
  end

  def modrm_byte(mod, reg, rm)
    ((mod & 3) << 6) | ((reg & 7) << 3) | (rm & 7)
  end

  def sib_byte(ss, index, base)
    ((ss & 3) << 6) | ((index & 7) << 3) | (base & 7)
  end

  public

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

  def mov_reg_imm(reg, val)
    rex = 0x48
    rex |= 0x01 if reg >= 8
    emit([rex, 0xb8 + (reg % 8)] + [val].pack("Q<").bytes)
  end

  def mov_rax(val); mov_reg_imm(0, val); end

  def mov_reg_reg(dst, src)
    rex = rex_prefix(w: true, r: src >= 8, b: dst >= 8)
    modrm = modrm_byte(3, src, dst)
    emit([rex, 0x89, modrm])
  end

  def mov_reg_sp(dst)
    rex = rex_prefix(w: true, b: dst >= 8)
    modrm = modrm_byte(3, 4, dst) # mov dst, rsp
    emit([rex, 0x89, modrm])
  end

  def mov_stack_reg_val(offset, src)
    return if offset.nil?
    rex = rex_prefix(w: true, r: src >= 8)
    modrm = modrm_byte(2, src, 5) # [RBP + disp32]
    emit([rex, 0x89, modrm] + [(-offset)].pack("l<").bytes)
  end

  def mov_reg_stack_val(dst, offset)
    return if offset.nil?
    rex = rex_prefix(w: true, r: dst >= 8)
    modrm = modrm_byte(2, dst, 5) # [RBP + disp32]
    emit([rex, 0x8b, modrm] + [(-offset)].pack("l<").bytes)
  end

  def lea_reg_stack(dst, offset)
    return if offset.nil?
    rex = rex_prefix(w: true, r: dst >= 8)
    modrm = modrm_byte(2, dst, 5) # [RBP + disp32]
    emit([rex, 0x8d, modrm] + [(-offset)].pack("l<").bytes)
  end

  def mov_mem_r11(disp)
    emit([0x4c, 0x89, 0x58, disp & 0xFF])
  end

  def mov_rax_mem(disp)
    emit([0x48, 0x8b, 0x40, disp & 0xFF])
  end

  def mov_reg_mem_idx(dst, base, offset, size = 8)
    rex = rex_prefix(w: size == 8, r: dst >= 8, b: base >= 8)
    opcode = (size == 1) ? 0x8a : 0x8b

    if offset == 0 && (base % 8) != 5 && (base % 8) != 4
      modrm = modrm_byte(0, dst, base)
      emit([rex, opcode, modrm])
    elsif offset >= -128 && offset <= 127
      modrm = modrm_byte(1, dst, base)
      if (base % 8) == 4 # SIB needed
        emit([rex, opcode, modrm, 0x24, offset & 0xFF])
      else
        emit([rex, opcode, modrm, offset & 0xFF])
      end
    else
      modrm = modrm_byte(2, dst, base)
      if (base % 8) == 4 # SIB needed
        emit([rex, opcode, modrm, 0x24] + [offset].pack("l<").bytes)
      else
        emit([rex, opcode, modrm] + [offset].pack("l<").bytes)
      end
    end
  end

  def mov_rax_mem_idx(reg, offset, size = 8); mov_reg_mem_idx(0, reg, offset, size); end
  def mov_rcx_mem_idx(reg, offset, size = 8); mov_reg_mem_idx(1, reg, offset, size); end

  def mov_r11_rax; emit([0x49, 0x89, 0xc3]); end

  def mov_rax_rbp_disp32(disp)
    emit([0x48, 0x8b, 0x85] + [disp].pack("l<").bytes)
  end

  def add_reg_reg(dst, src)
    rex = rex_prefix(w: true, r: src >= 8, b: dst >= 8)
    modrm = modrm_byte(3, src, dst)
    emit([rex, 0x01, modrm])
  end
  def add_rax_rdx; add_reg_reg(0, 2); end

  def sub_reg_reg(dst, src)
    rex = rex_prefix(w: true, r: src >= 8, b: dst >= 8)
    modrm = modrm_byte(3, src, dst)
    emit([rex, 0x29, modrm])
  end
  def sub_rax_rdx; sub_reg_reg(0, 2); end

  def mul_reg_reg(dst, src)
    rex = rex_prefix(w: true, r: dst >= 8, b: src >= 8)
    modrm = modrm_byte(3, dst, src)
    emit([rex, 0x0f, 0xaf, modrm])
  end
  def imul_rax_rdx; mul_reg_reg(0, 2); end

  def and_reg_reg(dst, src)
    rex = rex_prefix(w: true, r: src >= 8, b: dst >= 8)
    modrm = modrm_byte(3, src, dst)
    emit([rex, 0x21, modrm])
  end
  def and_rax_rdx; and_reg_reg(0, 2); end
  def and_rax_reg(src); and_reg_reg(0, src); end
  def add_rax_reg(src); add_reg_reg(0, src); end
  def sub_rax_reg(src); sub_reg_reg(0, src); end

  def add_reg_imm(reg, imm)
    rex = rex_prefix(w: true, b: reg >= 8)
    if imm >= -128 && imm <= 127
      modrm = modrm_byte(3, 0, reg) # ADD /0
      emit([rex, 0x83, modrm, imm & 0xFF])
    else
      modrm = modrm_byte(3, 0, reg)
      emit([rex, 0x81, modrm] + [imm].pack("l<").bytes)
    end
  end

  def sub_reg_imm(reg, imm)
    rex = rex_prefix(w: true, b: reg >= 8)
    if imm >= -128 && imm <= 127
      modrm = modrm_byte(3, 5, reg) # SUB /5
      emit([rex, 0x83, modrm, imm & 0xFF])
    else
      modrm = modrm_byte(3, 5, reg)
      emit([rex, 0x81, modrm] + [imm].pack("l<").bytes)
    end
  end

  def emit_add_rax(imm); add_reg_imm(0, imm); end
  def emit_sub_rax(imm); sub_reg_imm(0, imm); end

  def or_reg_reg(dst, src)
    rex = rex_prefix(w: true, r: src >= 8, b: dst >= 8)
    modrm = modrm_byte(3, src, dst)
    emit([rex, 0x09, modrm])
  end
  def or_rax_rdx; or_reg_reg(0, 2); end
  def or_rax_reg(src); or_reg_reg(0, src); end

  def xor_reg_reg(dst, src)
    rex = rex_prefix(w: true, r: src >= 8, b: dst >= 8)
    modrm = modrm_byte(3, src, dst)
    emit([rex, 0x31, modrm])
  end
  def xor_rax_rdx; xor_reg_reg(0, 2); end
  def xor_rax_reg(src); xor_reg_reg(0, src); end
  def xor_rax_rax; xor_reg_reg(0, 0); end

  def not_reg(reg)
    rex = rex_prefix(w: true, b: reg >= 8)
    modrm = modrm_byte(3, 2, reg) # 0xF7 /2
    emit([rex, 0xf7, modrm])
  end
  def not_rax; not_reg(0); end

  def shl_reg_cl(reg)
    mov_reg_reg(1, 2) # RCX = RDX (shift count in RCX)
    rex = rex_prefix(w: true, b: reg >= 8)
    modrm = modrm_byte(3, 4, reg) # SHL reg, CL (/4)
    emit([rex, 0xd3, modrm])
  end
  def shl_rax_cl; shl_reg_cl(0); end

  def shr_reg_cl(reg)
    mov_reg_reg(1, 2) # RCX = RDX
    rex = rex_prefix(w: true, b: reg >= 8)
    modrm = modrm_byte(3, 5, reg) # SHR reg, CL (/5)
    emit([rex, 0xd3, modrm])
  end
  def shr_rax_cl; shr_reg_cl(0); end

  def shl_reg_imm(reg, c)
    rex = rex_prefix(w: true, b: reg >= 8)
    modrm = modrm_byte(3, 4, reg) # SHL reg, imm8 (/4)
    emit([rex, 0xc1, modrm, c & 0x7f])
  end
  def shl_rax_imm(c); shl_reg_imm(0, c); end

  def shr_reg_imm(reg, c)
    rex = rex_prefix(w: true, b: reg >= 8)
    modrm = modrm_byte(3, 5, reg) # SHR reg, imm8 (/5)
    emit([rex, 0xc1, modrm, c & 0x7f])
  end
  def shr_rax_imm(c); shr_reg_imm(0, c); end

  def div_rax_by_rdx
    mov_reg_reg(1, 2) # mov rcx, rdx
    emit([0x48, 0x99]) # cqo
    rex = rex_prefix(w: true)
    modrm = modrm_byte(3, 7, 1) # idiv rcx (/7)
    emit([rex, 0xf7, modrm])
  end

  def mod_rax_by_rdx
    div_rax_by_rdx
    mov_reg_reg(0, 2) # mov rax, rdx (remainder is in RDX)
  end

  def cmp_rax_rdx(op)
    cmp_reg_reg(0, 2)
    mov_rax(0)
    cond_op = case op
              when "==" then 0x94 when "!=" then 0x95
              when "<"  then 0x9c when ">"  then 0x9f
              when "<=" then 0x9e when ">=" then 0x9d
              end
    emit([0x0f, cond_op, 0xc0]) # setCC al
  end

  def cmov(cond, dst, src)
    # CMOVcc reg64, r/m64: 0F 4x /r
    op = case cond
         when "==" then 0x44 when "!=" then 0x45
         when "<"  then 0x4c when ">"  then 0x4f
         when "<=" then 0x4e when ">=" then 0x4d
         end
    rex = rex_prefix(w: true, r: dst >= 8, b: src >= 8)
    modrm = modrm_byte(3, dst, src)
    emit([rex, 0x0f, op, modrm])
  end

  def test_reg_reg(r1, r2)
    rex = 0x48
    rex |= 0x04 if r2 >= 8
    rex |= 0x01 if r1 >= 8
    emit([rex, 0x85, 0xc0 | ((r2 & 7) << 3) | (r1 & 7)]) # test r1, r2
  end
  def test_rax_rax; test_reg_reg(0, 0); end

  def cmp_reg_reg(r1, r2)
    rex = 0x48
    rex |= 0x04 if r2 >= 8
    rex |= 0x01 if r1 >= 8
    emit([rex, 0x39, 0xc0 | ((r2 & 7) << 3) | (r1 & 7)])
  end

  def cmp_reg_imm(reg, imm)
    rex = rex_prefix(w: true, b: reg >= 8)
    if reg == 0
      emit([rex, 0x3d] + [imm].pack("L<").bytes)
    else
      modrm = modrm_byte(3, 7, reg) # CMP /7
      emit([rex, 0x81, modrm] + [imm].pack("L<").bytes)
    end
  end

  def call_rel32; emit([0xe8, 0, 0, 0, 0]); end
  def call_ind_rel32; emit([0xff, modrm_byte(0, 2, 5), 0, 0, 0, 0]); end
  def call_reg(reg)
    rex = rex_prefix(b: reg >= 8)
    modrm = modrm_byte(3, 2, reg) # CALL /2
    emit([rex, 0xff, modrm])
  end

  def jmp_rel32; pos = current_pos; emit([0xe9, 0, 0, 0, 0]); pos; end
  def je_rel32; pos = current_pos; emit([0x0f, 0x84, 0, 0, 0, 0]); pos; end
  def jne_rel32; pos = current_pos; emit([0x0f, 0x85, 0, 0, 0, 0]); pos; end
  def jae_rel32; pos = current_pos; emit([0x0f, 0x83, 0, 0, 0, 0]); pos; end

  def cld; emit([0xfc]); end
  def rep_movsb; emit([0xf3, 0xa4]); end
  def rep_stosb; emit([0xf3, 0xaa]); end

  def memcpy
    cld
    rep_movsb
  end

  def memset
    cld
    rep_stosb
  end

  def patch_jmp(pos, target)
    @internal_patches << { pos: pos, target: target, type: :jmp_rel32 }
    offset = target - (pos + 5)
    @bytes[pos+1..pos+4] = [offset].pack("l<").bytes
  end

  def patch_je(pos, target)
    @internal_patches << { pos: pos, target: target, type: :je_rel32 }
    offset = target - (pos + 6)
    @bytes[pos+2..pos+5] = [offset].pack("l<").bytes
  end

  def patch_jae(pos, target)
    @internal_patches << { pos: pos, target: target, type: :jae_rel32 }
    offset = target - (pos + 6)
    @bytes[pos+2..pos+5] = [offset].pack("l<").bytes
  end

  def patch_jne(pos, target)
    @internal_patches << { pos: pos, target: target, type: :jne_rel32 }
    offset = target - (pos + 6)
    @bytes[pos+2..pos+5] = [offset].pack("l<").bytes
  end

  def emit_sys_exit_rax
    emit([0x48, 0x89, 0xc7, 0x48, 0xc7, 0xc0, 60, 0, 0, 0, 0x0f, 0x05])
  end

  def push_reg(r)
    if r >= 8
      emit([rex_prefix(b: true), 0x50 + (r % 8)])
    else
      emit([0x50 + r])
    end
  end

  def pop_reg(r)
    if r >= 8
      emit([rex_prefix(b: true), 0x58 + (r % 8)])
    else
      emit([0x58 + r])
    end
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

  def div_reg(reg)
    rex = rex_prefix(w: true, b: reg >= 8)
    modrm = modrm_byte(3, 6, reg) # DIV /6 (unsigned) or IDIV /7
    emit([rex, 0xf7, modrm])
  end

  def idiv_reg(reg)
    rex = rex_prefix(w: true, b: reg >= 8)
    modrm = modrm_byte(3, 7, reg) # IDIV /7
    emit([rex, 0xf7, modrm])
  end

  def mov_mem_reg_reg8(dst, src)
    rex = rex_prefix(r: src >= 8, b: dst >= 8)
    modrm = modrm_byte(0, src, dst)
    if (dst & 7) == 4
      emit([rex, 0x88, modrm, 0x24].compact)
    else
      emit([rex, 0x88, modrm].compact)
    end
  end

  def dec_reg(reg)
    rex = rex_prefix(w: true, b: reg >= 8)
    modrm = modrm_byte(3, 1, reg) # DEC /1
    emit([rex, 0xff, modrm])
  end

  def mov_mem8_imm8(reg, imm)
    rex = rex_prefix(b: reg >= 8)
    modrm = modrm_byte(0, 0, reg)
    if (reg & 7) == 4 # RSP/R12 need SIB
      emit([rex, 0xc6, modrm, 0x24, imm & 0xff])
    else
      emit([rex, 0xc6, modrm, imm & 0xff])
    end
  end

  def mov_rax_rsp_disp8(disp)
    rex = rex_prefix(w: true)
    modrm = modrm_byte(1, 0, 4) # [RSP + disp8]
    sib = sib_byte(0, 4, 4)
    emit([rex, 0x8b, modrm, sib, disp & 0xff])
  end

  def mov_mem_reg_idx(base, offset, src, size = 8)
    rex = rex_prefix(w: size == 8, r: src >= 8, b: base >= 8)
    opcode = (size == 1) ? 0x88 : 0x89

    if offset == 0 && (base % 8) != 5 && (base % 8) != 4
      modrm = modrm_byte(0, src, base)
      emit([rex, opcode, modrm])
    elsif offset >= -128 && offset <= 127
      modrm = modrm_byte(1, src, base)
      if (base % 8) == 4 # SIB needed
        emit([rex, opcode, modrm, 0x24, offset & 0xFF])
      else
        emit([rex, opcode, modrm, offset & 0xFF])
      end
    else
      modrm = modrm_byte(2, src, base)
      if (base % 8) == 4 # SIB needed
        emit([rex, opcode, modrm, 0x24] + [offset].pack("l<").bytes)
      else
        emit([rex, opcode, modrm] + [offset].pack("l<").bytes)
      end
    end
  end

  def syscall; emit([0x0f, 0x05]); end

  def memcpy
    # dest=RDI, src=RSI, n=RCX
    emit([0xfc, 0xf3, 0xa4]) # cld; rep movsb
  end

  def memset
    # dest=RDI, val=AL, n=RCX
    emit([0xfc, 0xf3, 0xaa]) # cld; rep stosb
  end
end
