class CodeEmitter
  attr_reader :bytes, :stack_shadow_size

  REG_RAX = 0; REG_RCX = 1; REG_RDX = 2; REG_RBX = 3
  REG_RSP = 4; REG_RBP = 5; REG_RSI = 6; REG_RDI = 7
  REG_R8 = 8;  REG_R9 = 9;  REG_R11 = 11

  def initialize
    @bytes = []
    @stack_shadow_size = 32 # Windows default
  end

  def current_pos
    @bytes.length
  end

  def emit(arr)
    @bytes += arr
  end

  # --- Prologue/Epilogue ---
  def emit_prologue(stack_size)
    emit([0x55, 0x48, 0x89, 0xe5]) # push rbp; mov rbp, rsp
    emit_sub_rsp(stack_size)
  end

  def emit_epilogue(stack_size)
    emit_add_rsp(stack_size)
    emit([0x5d, 0xc3]) # pop rbp, ret
  end

  # --- Stack Ops ---
  def emit_sub_rsp(size)
    # 48 81 EC imm32
    emit([0x48, 0x81, 0xec] + [size].pack("l<").bytes)
  end

  def emit_add_rsp(size)
    # 48 81 C4 imm32
    emit([0x48, 0x81, 0xc4] + [size].pack("l<").bytes)
  end

  # --- Register/Mov Ops ---
  def mov_rax(val)
    emit([0x48, 0xb8] + [val].pack("Q<").bytes)
  end

  def mov_reg_reg(dst, src)
    rex = 0x48
    rex |= 0x04 if src >= 8 # REX.R
    rex |= 0x01 if dst >= 8 # REX.B
    
    modrm = 0xc0 | ((src & 7) << 3) | (dst & 7)
    emit([rex, 0x89, modrm])
  end

  # MOV [RBP - offset], REG (disp32, safe for large offsets)
  def mov_stack_reg_val(offset, src_reg_code)
    rex = 0x48
    rex |= 0x04 if src_reg_code >= 8 # REX.R for reg field
    modrm = 0x85 | ((src_reg_code & 7) << 3) # mod=10 (disp32), rm=101 (rbp)
    emit([rex, 0x89, modrm] + [(-offset)].pack("l<").bytes)
  end

  # MOV REG, [RBP - offset] (disp32)
  def mov_reg_stack_val(dst_reg_code, offset)
    rex = 0x48
    rex |= 0x04 if dst_reg_code >= 8 # REX.R for reg field
    modrm = 0x85 | ((dst_reg_code & 7) << 3)
    emit([rex, 0x8b, modrm] + [(-offset)].pack("l<").bytes)
  end
  
  # LEA REG, [RBP - offset] (disp32)
  def lea_reg_stack(dst_reg_code, offset)
    rex = 0x48
    rex |= 0x04 if dst_reg_code >= 8 # REX.R
    modrm = 0x85 | ((dst_reg_code & 7) << 3)
    emit([rex, 0x8d, modrm] + [(-offset)].pack("l<").bytes)
  end

  # MOV [RAX + offset], R11
  def mov_mem_r11(disp)
    # 4C 89 58 disp
    emit([0x4c, 0x89, 0x58, disp & 0xFF])
  end
  
  # MOV RAX, [RAX + offset]
  def mov_rax_mem(disp)
    # 48 8B 40 disp
    emit([0x48, 0x8b, 0x40, disp & 0xFF])
  end

  def mov_r11_rax
    emit([0x49, 0x89, 0xc3])
  end

  # MOV RAX, [RBP + disp32] (used for stack-passed arguments)
  def mov_rax_rbp_disp32(disp)
    emit([0x48, 0x8b, 0x85] + [disp].pack("l<").bytes)
  end

  # --- Math ---
  def add_rax_rdx; emit([0x48, 0x01, 0xd0]); end
  def sub_rax_rdx; emit([0x48, 0x29, 0xd0]); end # sub rax, rdx
  def imul_rax_rdx; emit([0x48, 0x0f, 0xaf, 0xc2]); end
  
  # Shift left RAX by immediate (for multiply by power of 2)
  def shl_rax_imm(count)
    emit([0x48, 0xc1, 0xe0, count & 0x3f])  # shl rax, imm8
  end
  
  # Shift right RAX by immediate (for divide by power of 2)
  def shr_rax_imm(count)
    emit([0x48, 0xc1, 0xe8, count & 0x3f])  # shr rax, imm8
  end
  
  # Division: RAX = RAX / RCX (RDX holds divisor, need to move it)
  def div_rax_by_rdx
    # Move divisor from RDX to RCX
    emit([0x48, 0x89, 0xd1]) # mov rcx, rdx
    # Sign-extend RAX into RDX:RAX
    emit([0x48, 0x99]) # cqo
    # Divide RDX:RAX by RCX, result in RAX
    emit([0x48, 0xf7, 0xf9]) # idiv rcx
  end
  
  def save_rax_to_rdx; emit([0x48, 0x89, 0xc2]); end
  
  # Compare RAX with RDX and set RAX to 0 or 1
  def cmp_rax_rdx(op)
    emit([0x48, 0x39, 0xd0]) # cmp rax, rdx
    # Use mov instead of xor to preserve flags!
    emit([0x48, 0xc7, 0xc0, 0x00, 0x00, 0x00, 0x00]) # mov rax, 0
    case op
    when "=="
      emit([0x0f, 0x94, 0xc0]) # sete al
    when "!="
      emit([0x0f, 0x95, 0xc0]) # setne al
    when "<"
      emit([0x0f, 0x9c, 0xc0]) # setl al
    when ">"
      emit([0x0f, 0x9f, 0xc0]) # setg al
    when "<="
      emit([0x0f, 0x9e, 0xc0]) # setle al
    when ">="
      emit([0x0f, 0x9d, 0xc0]) # setge al
    end
  end

  # --- Jumps ---
  def call_rel32; emit([0xe8, 0, 0, 0, 0]); end
  def call_ind_rel32; emit([0xff, 0x15, 0, 0, 0, 0]); end # call [rip + offset]
  def jmp_rel32; emit([0xe9, 0, 0, 0, 0]); end
  def je_rel32; emit([0x0f, 0x84, 0, 0, 0, 0]); end
  
  def emit_sys_exit(code)
    emit([0x48, 0xc7, 0xc0, 60, 0, 0, 0]) # mov rax, 60
    emit([0x48, 0xc7, 0xc7, code, 0, 0, 0]) # mov rdi, code
    emit([0x0f, 0x05])
  end

  # Exit with RAX as exit code (Linux syscall)
  def emit_sys_exit_rax
    emit([0x48, 0x89, 0xc7]) # mov rdi, rax (exit code from rax)
    emit([0x48, 0xc7, 0xc0, 60, 0, 0, 0]) # mov rax, 60 (sys_exit)
    emit([0x0f, 0x05]) # syscall
  end
end
