# Simple heap allocator using mmap
# Each malloc creates a new mmap region (simple but works)

module BuiltinHeap
  # malloc(size) - Allocate memory
  def gen_malloc(node)
    return unless @target_os == :linux
    
    args = node[:args] || []
    return @emitter.emit([0x48, 0x31, 0xc0]) if args.empty?
    
    eval_expression(args[0])
    @emitter.emit([0x49, 0x89, 0xc3])  # mov r11, rax (size)
    
    # Add 8 bytes for size header, align to 16
    @emitter.emit([0x49, 0x83, 0xc3, 0x08])
    @emitter.emit([0x49, 0x83, 0xc3, 0x0f])
    @emitter.emit([0x49, 0x83, 0xe3, 0xf0])
    
    @emitter.emit([0x48, 0x31, 0xff])  # rdi = 0
    @emitter.emit([0x4c, 0x89, 0xde])  # rsi = r11
    @emitter.emit([0xba, 0x03, 0x00, 0x00, 0x00])  # rdx = 3
    @emitter.emit([0x41, 0xba, 0x22, 0x00, 0x00, 0x00])  # r10 = 0x22
    @emitter.emit([0x49, 0xc7, 0xc0, 0xff, 0xff, 0xff, 0xff])  # r8 = -1
    @emitter.emit([0x4d, 0x31, 0xc9])  # xor r9, r9
    @emitter.emit([0xb8, 0x09, 0x00, 0x00, 0x00])  # eax = 9
    @emitter.emit([0x0f, 0x05])
    
    @emitter.emit([0x48, 0x83, 0xf8, 0xff])
    @emitter.emit([0x75, 0x05])
    @emitter.emit([0x48, 0x31, 0xc0])
    @emitter.emit([0xeb, 0x0a])
    
    @emitter.emit([0x4c, 0x89, 0x18])  # store size header
    @emitter.emit([0x48, 0x83, 0xc0, 0x08])  # return ptr+8
  end

  # realloc(ptr, new_size)
  def gen_realloc(node)
    return unless @target_os == :linux
    
    args = node[:args] || []
    return @emitter.emit([0x48, 0x31, 0xc0]) if args.length < 2
    
    # Save all potentially clobbered registers
    @emitter.push_reg(CodeEmitter::REG_R12)
    @emitter.push_reg(CodeEmitter::REG_R13)
    @emitter.push_reg(CodeEmitter::REG_R14)
    @emitter.push_reg(CodeEmitter::REG_R15)
    
    eval_expression(args[0])
    @emitter.emit([0x49, 0x89, 0xc7]) # mov r15, rax (old_ptr)
    eval_expression(args[1])
    @emitter.emit([0x49, 0x89, 0xc6]) # mov r14, rax (new_size)

    # 1. malloc(new_size)
    @emitter.emit([0x4c, 0x89, 0xf3]) # mov rbx, r14
    @emitter.emit([0x48, 0x83, 0xc3, 0x08, 0x48, 0x83, 0xc3, 0x0f, 0x48, 0x83, 0xe3, 0xf0])
    @emitter.emit([0x48, 0x31, 0xff, 0x48, 0x89, 0xde, 0xba, 0x03, 0,0,0])
    @emitter.emit([0x41, 0xba, 0x22, 0,0,0, 0x49, 0xc7, 0xc0, 0xff, 0xff, 0xff, 0xff, 0x4d, 0x31, 0xc9, 0xb8, 0x09, 0,0,0, 0x0f, 0x05])
    
    @emitter.emit([0x48, 0x89, 0x18, 0x48, 0x83, 0xc0, 0x08]) # rax = new_ptr
    
    # 2. Copy if old_ptr != 0
    @emitter.emit([0x4d, 0x85, 0xff]) # test r15, r15
    jz_pos = @emitter.current_pos
    @emitter.emit([0x74, 0x00])

    @emitter.emit([0x50]) # push new_ptr
    @emitter.emit([0x4d, 0x8b, 0x4f, 0xf8]) # mov r9, [r15-8]
    @emitter.emit([0x49, 0x83, 0xe9, 0x08]) # r9 = old_user
    @emitter.emit([0x4d, 0x39, 0xf1, 0x4d, 0x0f, 0x47, 0xce]) # count = min(old, new)
    @emitter.emit([0x48, 0x89, 0xc7]) # rdi = new_ptr
    @emitter.emit([0x4c, 0x89, 0xfe]) # rsi = old_ptr
    @emitter.emit([0x4c, 0x89, 0xc9]) # rcx = count
    @emitter.emit([0xf3, 0xa4])       # rep movsb
    @emitter.emit([0x58]) # pop rax
    
    # 3. Done
    target = @emitter.current_pos
    @emitter.bytes[jz_pos + 1] = (target - (jz_pos + 2)) & 0xFF

    @emitter.pop_reg(CodeEmitter::REG_R15)
    @emitter.pop_reg(CodeEmitter::REG_R14)
    @emitter.pop_reg(CodeEmitter::REG_R13)
    @emitter.pop_reg(CodeEmitter::REG_R12)
  end

  # heap_init - no-op
  def gen_heap_init(node)
    return unless @target_os == :linux
    @emitter.emit([0x48, 0x31, 0xc0])
  end

  # free(ptr) or free(ptr, size)
  def gen_free(node)
    return unless @target_os == :linux
    args = node[:args] || []
    return if args.empty?

    eval_expression(args[0])
    @emitter.emit([0x48, 0x85, 0xc0, 0x74, 0x20]) # skip if ptr == 0

    if args.length >= 2
      @emitter.emit([0x50]) # push ptr
      eval_expression(args[1])
      @emitter.emit([0x48, 0x89, 0xc6]) # rsi = size
      @emitter.emit([0x5f])             # rdi = ptr
      @emitter.emit([0xb8, 0x0b, 0x00, 0x00, 0x00, 0x0f, 0x05]) # munmap
    else
      @emitter.emit([0x48, 0x89, 0xc7, 0x48, 0x83, 0xef, 0x08]) # rdi = ptr - 8
      @emitter.emit([0x48, 0x8b, 0x37]) # rsi = [rdi] (size)
      @emitter.emit([0xb8, 0x0b, 0x00, 0x00, 0x00, 0x0f, 0x05]) # munmap
    end
  end
end
