module X64
  # Базовые опкоды x86_64
  PUSH_RBP = [0x55]
  POP_RBP  = [0x5d]
  RET      = [0xc3]
  
  MOV_RBP_RSP = [0x48, 0x89, 0xe5]
  ADD_RSP_IMM8 = [0x48, 0x83, 0xc4]
  SUB_RSP_IMM8 = [0x48, 0x83, 0xec]
  
  XOR_RAX_RAX = [0x48, 0x31, 0xc0]
  SYSCALL     = [0x0f, 0x05]
  
  # Регистры для syscalls/функций
  def self.mov_rax_imm64(val); [0x48, 0xb8] + [val].pack("Q<").bytes; end
  def self.mov_rcx_imm64(val); [0x48, 0xb9] + [val].pack("Q<").bytes; end
  def self.mov_rdx_imm64(val); [0x48, 0xba] + [val].pack("Q<").bytes; end
  def self.mov_rbx_imm64(val); [0x48, 0xbb] + [val].pack("Q<").bytes; end
  def self.mov_rsp_imm64(val); [0x48, 0xbc] + [val].pack("Q<").bytes; end
  def self.mov_rbp_imm64(val); [0x48, 0xbd] + [val].pack("Q<").bytes; end
  def self.mov_rsi_imm64(val); [0x48, 0xbe] + [val].pack("Q<").bytes; end
  def self.mov_rdi_imm64(val); [0x48, 0xbf] + [val].pack("Q<").bytes; end
  
  # R8-R15 (REX.B bit is used)
  def self.mov_r8_imm64(val);  [0x49, 0xb8] + [val].pack("Q<").bytes; end
  def self.mov_r9_imm64(val);  [0x49, 0xb9] + [val].pack("Q<").bytes; end

  # Сравнение rax с imm32
  def self.cmp_rax_imm32(val); [0x48, 0x3d] + [val].pack("l<").bytes; end

  # Прыжки (rel8)
  def self.je_rel8(offset);  [0x74, offset & 0xFF]; end
  def self.jne_rel8(offset); [0x75, offset & 0xFF]; end
  def self.jmp_rel8(offset); [0xeb, offset & 0xFF]; end

  # call [rip + offset] (косвенный вызов через IAT)
  def self.call_rip_rel32(offset)
    [0xff, 0x15] + [offset].pack("l<").bytes
  end

  # call rel32 (прямой вызов функции по смещению)
  def self.call_rel32(offset)
    [0xe8] + [offset].pack("l<").bytes
  end

  # lea rdx, [rip + offset] (загрузка адреса данных)
  def self.lea_rdx_rip_rel32(offset)
    [0x48, 0x8d, 0x15] + [offset].pack("l<").bytes
  end

  # cmp [rbp - offset], imm8
  def self.cmp_rbp_mem8_imm8(offset, imm)
    [0x80, 0x7d, 256 - offset, imm]
  end

  # cmp rax, imm32
  def self.cmp_rax_imm32(val)
    [0x48, 0x3d] + [val].pack("l<").bytes
  end
  
  # Системный вызов ExitProcess для Windows (через таблицу импорта)
  # Или просто ret если мы в main.
end
