# Anti-Reverse Engineering Module
# Техники которые заставят IDA Pro, Ghidra и реверсеров страдать

class AntiReverse
  def initialize
    @rng = Random.new
  end

  # ============================================
  # 1. CONTROL FLOW OBFUSCATION
  # ============================================

  # Flattening - все блоки через dispatcher
  def flatten_control_flow(blocks)
    # Создаём dispatcher который прыгает на блоки по номеру
    dispatcher = generate_dispatcher(blocks.length)
    
    # Каждый блок в конце устанавливает номер следующего и прыгает на dispatcher
    result = dispatcher
    blocks.each_with_index do |block, idx|
      result += block
      result += set_next_block(idx + 1)
      result += jump_to_dispatcher
    end
    
    result
  end

  # Fake branches - ветки которые никогда не выполняются
  def insert_fake_branches(code)
    result = []
    
    # Opaque predicate - всегда false
    result += opaque_false
    result += [0x0f, 0x84] # jz (never taken)
    result += [0x00, 0x00, 0x00, 0x00] # offset to fake code
    
    result += code
    result
  end

  # ============================================
  # 2. ANTI-DISASSEMBLY
  # ============================================

  # Junk bytes that confuse linear disassemblers
  def anti_disasm_junk
    patterns = [
      # Jump over junk that looks like valid instruction
      [0xeb, 0x02, 0x0f, 0x85],  # jmp +2; fake jnz
      [0xeb, 0x01, 0xe8],        # jmp +1; fake call opcode
      [0xeb, 0x02, 0xcd, 0x80],  # jmp +2; fake int 0x80
      
      # Overlapping instructions
      [0xeb, 0xff, 0xc0, 0x48],  # creates different instruction depending on entry point
      
      # Call $+5; pop - confuses call graph
      [0xe8, 0x00, 0x00, 0x00, 0x00, 0x58],  # call $+5; pop rax
    ]
    
    patterns[@rng.rand(patterns.length)]
  end

  # ============================================
  # 3. ANTI-DEBUGGING
  # ============================================

  # Check if running under debugger (Linux)
  def anti_debug_linux
    checks = []
    
    # 1. ptrace check
    checks += ptrace_check
    
    # 2. /proc/self/status check for TracerPid
    checks += tracer_pid_check
    
    # 3. Timing check
    checks += timing_check
    
    # 4. int3 scan
    checks += int3_scan
    
    checks
  end

  # ============================================
  # 4. STRING ENCRYPTION
  # ============================================

  # XOR encryption with rolling key
  def encrypt_string_rolling(str)
    key = @rng.rand(256)
    result = []
    k = key
    
    str.bytes.each do |b|
      result << (b ^ k)
      k = (k * 31 + 17) & 0xFF  # Rolling key
    end
    
    { data: result, key: key }
  end

  # Generate decryption routine
  def decrypt_routine(addr, len, key)
    # rsi = addr, rcx = len, al = key
    [
      0x48, 0xbe] + [addr].pack("Q<").bytes +   # mov rsi, addr
    [0x48, 0xc7, 0xc1] + [len].pack("l<").bytes + # mov rcx, len  
    [0xb0, key,                                  # mov al, key
     # .loop:
     0x30, 0x06,                                 # xor [rsi], al
     # Rolling key: al = al * 31 + 17
     0x50,                                       # push rax
     0x6b, 0xc0, 0x1f,                          # imul eax, 31
     0x04, 0x11,                                 # add al, 17
     0x88, 0xc3,                                 # mov bl, al
     0x58,                                       # pop rax
     0x88, 0xd8,                                 # mov al, bl
     0x48, 0xff, 0xc6,                          # inc rsi
     0xe2, 0xec]                                 # loop .loop
  end

  # ============================================
  # 5. CODE METAMORPHISM
  # ============================================

  # Self-modifying code stub
  def self_modify_stub
    # Модифицирует следующую инструкцию в runtime
    [
      0x48, 0x8d, 0x05, 0x08, 0x00, 0x00, 0x00,  # lea rax, [rip+8]
      0xc6, 0x00, 0x90,                          # mov byte [rax], 0x90 (nop)
      0xcc,                                       # int3 (will become nop)
      0x90,                                       # nop
    ]
  end

  # ============================================
  # 6. VM DETECTION
  # ============================================

  def vm_detect
    # CPUID check for hypervisor
    [
      0x53,                                       # push rbx
      0xb8, 0x01, 0x00, 0x00, 0x00,              # mov eax, 1
      0x0f, 0xa2,                                 # cpuid
      0x89, 0xc8,                                 # mov eax, ecx
      0x25, 0x00, 0x00, 0x00, 0x80,              # and eax, 0x80000000 (hypervisor bit)
      0x5b,                                       # pop rbx
      0x85, 0xc0,                                 # test eax, eax
      0x75, 0x00,                                 # jnz vm_detected
    ]
  end

  # ============================================
  # 7. IMPORT HIDING
  # ============================================

  # Hash-based function resolution (Windows-style but concept applies)
  def hash_function_name(name)
    hash = 0
    name.bytes.each do |b|
      hash = ((hash >> 13) | (hash << 19)) & 0xFFFFFFFF
      hash = (hash + b) & 0xFFFFFFFF
    end
    hash
  end

  private

  def generate_dispatcher(num_blocks)
    # cmp rax, N; je block_N; ...
    result = []
    num_blocks.times do |i|
      result += [0x48, 0x83, 0xf8, i]  # cmp rax, i
      result += [0x74, 0x00]            # je (patched)
    end
    result
  end

  def set_next_block(n)
    [0x48, 0xc7, 0xc0] + [n].pack("l<").bytes  # mov rax, n
  end

  def jump_to_dispatcher
    [0xe9, 0x00, 0x00, 0x00, 0x00]  # jmp dispatcher (patched)
  end

  def opaque_false
    # (x^x) != 0 is always false
    [
      0x50,                          # push rax
      0x48, 0x31, 0xc0,             # xor rax, rax  
      0x48, 0x85, 0xc0,             # test rax, rax
      0x58,                          # pop rax
    ]
  end

  def ptrace_check
    [
      0x48, 0xc7, 0xc0, 0x65, 0x00, 0x00, 0x00,  # mov rax, 101 (ptrace)
      0x48, 0xc7, 0xc7, 0x00, 0x00, 0x00, 0x00,  # mov rdi, 0 (PTRACE_TRACEME)
      0x48, 0x31, 0xf6,                          # xor rsi, rsi
      0x48, 0x31, 0xd2,                          # xor rdx, rdx
      0x0f, 0x05,                                # syscall
      0x48, 0x83, 0xf8, 0xff,                    # cmp rax, -1
      0x74, 0x00,                                # je debugger_detected (patched)
    ]
  end

  def tracer_pid_check
    # open("/proc/self/status"), read, search for "TracerPid:\t0"
    # Simplified - just concept
    [0x90] * 10  # placeholder
  end

  def timing_check
    # rdtsc before and after, compare difference
    [
      0x0f, 0x31,                    # rdtsc
      0x48, 0x89, 0xc3,             # mov rbx, rax (save)
      # ... code ...
      0x0f, 0x31,                    # rdtsc  
      0x48, 0x29, 0xd8,             # sub rax, rbx
      0x48, 0x3d] + [0x00, 0x10, 0x00, 0x00] +  # cmp rax, threshold
    [0x77, 0x00]                     # ja debugger_detected
  end

  def int3_scan
    # Scan own code for int3 breakpoints
    [0x90] * 5  # placeholder
  end
end
