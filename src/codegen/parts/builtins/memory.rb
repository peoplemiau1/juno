# Memory built-in functions for Juno
module BuiltinMemory
  # alloc(size) - allocate via mmap
  def gen_alloc(node)
    return unless @target_os == :linux
    
    eval_expression(node[:args][0])
    @emitter.emit([0x48, 0x89, 0xc6]) # mov rsi, rax (size)
    
    # mmap(NULL, size, PROT_READ|PROT_WRITE, MAP_PRIVATE|MAP_ANONYMOUS, -1, 0)
    # rdi = addr (NULL)
    # rsi = size (already set)
    # rdx = prot (PROT_READ|PROT_WRITE = 3)
    # r10 = flags (MAP_PRIVATE|MAP_ANONYMOUS = 0x22)
    # r8 = fd (-1)
    # r9 = offset (0)
    
    @emitter.emit([0x48, 0x31, 0xff])                         # xor rdi, rdi
    @emitter.emit([0xba, 0x03, 0x00, 0x00, 0x00])             # mov edx, 3
    @emitter.emit([0x41, 0xba, 0x22, 0x00, 0x00, 0x00])       # mov r10d, 0x22
    @emitter.emit([0x49, 0x83, 0xc8, 0xff])                   # or r8, -1
    @emitter.emit([0x4d, 0x31, 0xc9])                         # xor r9, r9
    @emitter.emit([0xb8, 0x09, 0x00, 0x00, 0x00])             # mov eax, 9
    @emitter.emit([0x0f, 0x05])                               # syscall
  end

  # free(ptr) or free(ptr, size) - deallocate
  def gen_free(node)
    return unless @target_os == :linux
    
    args = node[:args] || []
    return if args.empty?
    
    eval_expression(args[0])
    
    if args.length >= 2
      # munmap with explicit size
      @emitter.emit([0x50]) # push ptr
      eval_expression(args[1])
      @emitter.emit([0x48, 0x89, 0xc6]) # mov rsi, rax (size)
      @emitter.emit([0x5f])             # pop rdi (ptr)
      @emitter.emit([0xb8, 0x0b, 0x00, 0x00, 0x00]) # mov eax, 11 (munmap)
      @emitter.emit([0x0f, 0x05])
    else
      # Simple free - get size from header at ptr-8
      @emitter.emit([0x48, 0x83, 0xe8, 0x08]) # sub rax, 8
      @emitter.emit([0x48, 0x89, 0xc7])       # mov rdi, rax
      @emitter.emit([0x48, 0x8b, 0x37])       # mov rsi, [rdi] (size)
      @emitter.emit([0xb8, 0x0b, 0x00, 0x00, 0x00]) # mov eax, 11
      @emitter.emit([0x0f, 0x05])
    end
  end
end
