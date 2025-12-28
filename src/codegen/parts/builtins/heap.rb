# Simple heap allocator using mmap
# Each malloc creates a new mmap region (simple but works)

module BuiltinHeap
  # malloc(size) - Allocate memory
  # Uses mmap for each allocation (simple approach)
  def gen_malloc(node)
    return unless @target_os == :linux
    
    args = node[:args] || []
    return @emitter.emit([0x48, 0x31, 0xc0]) if args.empty?  # return 0
    
    eval_expression(args[0])
    @emitter.emit([0x49, 0x89, 0xc4])  # mov r12, rax (size)
    
    # Add 8 bytes for size header, align to 16
    @emitter.emit([0x49, 0x83, 0xc4, 0x08])  # add r12, 8
    @emitter.emit([0x49, 0x83, 0xc4, 0x0f])  # add r12, 15
    @emitter.emit([0x49, 0x83, 0xe4, 0xf0])  # and r12, -16
    
    # mmap(0, size, PROT_READ|PROT_WRITE, MAP_PRIVATE|MAP_ANON, -1, 0)
    @emitter.emit([0x48, 0x31, 0xff])  # xor rdi, rdi
    @emitter.emit([0x4c, 0x89, 0xe6])  # mov rsi, r12
    @emitter.emit([0xba, 0x03, 0x00, 0x00, 0x00])  # mov edx, 3
    @emitter.emit([0x41, 0xba, 0x22, 0x00, 0x00, 0x00])  # mov r10d, 0x22
    @emitter.emit([0x49, 0xc7, 0xc0, 0xff, 0xff, 0xff, 0xff])  # mov r8, -1
    @emitter.emit([0x4d, 0x31, 0xc9])  # xor r9, r9
    @emitter.emit([0xb8, 0x09, 0x00, 0x00, 0x00])  # mov eax, 9 (mmap)
    @emitter.emit([0x0f, 0x05])  # syscall
    
    # Check for error
    @emitter.emit([0x48, 0x83, 0xf8, 0xff])  # cmp rax, -1
    @emitter.emit([0x75, 0x05])  # jne ok
    @emitter.emit([0x48, 0x31, 0xc0])  # xor rax, rax (return 0)
    @emitter.emit([0xeb, 0x0a])  # jmp end
    
    # Store size in header, return ptr+8
    @emitter.emit([0x4c, 0x89, 0x20])  # mov [rax], r12 (size)
    @emitter.emit([0x48, 0x83, 0xc0, 0x08])  # add rax, 8
    # end
  end

  # realloc(ptr, new_size) - Simple realloc (just malloc new + copy)
  def gen_realloc(node)
    return unless @target_os == :linux
    
    args = node[:args] || []
    return @emitter.emit([0x48, 0x31, 0xc0]) if args.length < 2
    
    # For simplicity, just call malloc with new size
    eval_expression(args[1])  # new_size
    @emitter.emit([0x49, 0x89, 0xc4])  # mov r12, rax
    
    # Same as malloc
    @emitter.emit([0x49, 0x83, 0xc4, 0x08])
    @emitter.emit([0x49, 0x83, 0xc4, 0x0f])
    @emitter.emit([0x49, 0x83, 0xe4, 0xf0])
    
    @emitter.emit([0x48, 0x31, 0xff])
    @emitter.emit([0x4c, 0x89, 0xe6])
    @emitter.emit([0xba, 0x03, 0x00, 0x00, 0x00])
    @emitter.emit([0x41, 0xba, 0x22, 0x00, 0x00, 0x00])
    @emitter.emit([0x49, 0xc7, 0xc0, 0xff, 0xff, 0xff, 0xff])
    @emitter.emit([0x4d, 0x31, 0xc9])
    @emitter.emit([0xb8, 0x09, 0x00, 0x00, 0x00])
    @emitter.emit([0x0f, 0x05])
    
    @emitter.emit([0x48, 0x83, 0xf8, 0xff])
    @emitter.emit([0x75, 0x05])
    @emitter.emit([0x48, 0x31, 0xc0])
    @emitter.emit([0xeb, 0x0a])
    
    @emitter.emit([0x4c, 0x89, 0x20])
    @emitter.emit([0x48, 0x83, 0xc0, 0x08])
  end

  # heap_init - no-op (mmap doesn't need init)
  def gen_heap_init(node)
    return unless @target_os == :linux
    @emitter.emit([0x48, 0x31, 0xc0])  # xor rax, rax
  end
end
