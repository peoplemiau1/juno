# Heap memory management - malloc/free/realloc
# Uses a simple free-list allocator backed by mmap

module BuiltinHeap
  def setup_heap
    return if @heap_setup
    @heap_setup = true
    
    # Heap state (64 bytes)
    # [0-7]: heap_start (ptr to mmap'd region)
    # [8-15]: heap_end
    # [16-23]: heap_current (bump pointer for simple alloc)
    # [24-31]: free_list (ptr to first free block)
    # [32-39]: heap_size
    # [40-47]: initialized flag
    @linker.add_data("heap_state", "\x00" * 64)
    @linker.add_data("heap_size_default", [16 * 1024 * 1024].pack("Q<"))  # 16MB default
  end

  # heap_init(size) - Initialize heap with given size
  # Called automatically on first malloc if not initialized
  def gen_heap_init(node)
    return unless @target_os == :linux
    setup_heap
    
    if node[:args] && node[:args][0]
      eval_expression(node[:args][0])
    else
      # Default 16MB
      @emitter.emit([0x48, 0xc7, 0xc0, 0x00, 0x00, 0x00, 0x01])  # mov rax, 16MB
    end
    @emitter.emit([0x49, 0x89, 0xc4])  # mov r12, rax (size)
    
    # mmap(0, size, PROT_READ|PROT_WRITE, MAP_PRIVATE|MAP_ANON, -1, 0)
    @emitter.emit([0x48, 0x31, 0xff])  # xor rdi, rdi (addr = 0)
    @emitter.emit([0x4c, 0x89, 0xe6])  # mov rsi, r12 (size)
    @emitter.emit([0xba, 0x03, 0x00, 0x00, 0x00])  # mov edx, 3 (PROT_READ|PROT_WRITE)
    @emitter.emit([0x41, 0xba, 0x22, 0x00, 0x00, 0x00])  # mov r10d, 0x22 (MAP_PRIVATE|MAP_ANON)
    @emitter.emit([0x49, 0xc7, 0xc0, 0xff, 0xff, 0xff, 0xff])  # mov r8, -1
    @emitter.emit([0x4d, 0x31, 0xc9])  # xor r9, r9
    @emitter.emit([0xb8, 0x09, 0x00, 0x00, 0x00])  # mov eax, 9 (mmap)
    @emitter.emit([0x0f, 0x05])  # syscall
    
    @emitter.emit([0x49, 0x89, 0xc5])  # mov r13, rax (heap_start)
    
    # Store in heap_state
    @linker.add_data_patch(@emitter.current_pos + 2, "heap_state")
    @emitter.emit([0x48, 0xbf] + [0] * 8)  # mov rdi, heap_state
    
    @emitter.emit([0x4c, 0x89, 0x2f])  # mov [rdi], r13 (heap_start)
    @emitter.emit([0x4d, 0x01, 0xe5])  # add r13, r12 (heap_end = start + size)
    @emitter.emit([0x4c, 0x89, 0x6f, 0x08])  # mov [rdi+8], r13 (heap_end)
    
    # Reset r13 to start for heap_current
    @emitter.emit([0x4c, 0x8b, 0x2f])  # mov r13, [rdi]
    @emitter.emit([0x4c, 0x89, 0x6f, 0x10])  # mov [rdi+16], r13 (heap_current = start)
    
    @emitter.emit([0x48, 0xc7, 0x47, 0x18, 0x00, 0x00, 0x00, 0x00])  # mov qword [rdi+24], 0 (free_list)
    @emitter.emit([0x4c, 0x89, 0x67, 0x20])  # mov [rdi+32], r12 (heap_size)
    @emitter.emit([0x48, 0xc7, 0x47, 0x28, 0x01, 0x00, 0x00, 0x00])  # mov qword [rdi+40], 1 (initialized)
    
    @emitter.emit([0x4c, 0x8b, 0x2f])  # mov r13, [rdi] (return heap_start)
    @emitter.emit([0x4c, 0x89, 0xe8])  # mov rax, r13
  end

  # malloc(size) - Allocate memory from heap
  # Returns pointer or 0 on failure
  # Block format: [8 bytes: size | data...]
  def gen_malloc(node)
    return unless @target_os == :linux
    setup_heap
    
    eval_expression(node[:args][0])
    @emitter.emit([0x49, 0x89, 0xc4])  # mov r12, rax (requested size)
    
    # Add 8 bytes for header, align to 16
    @emitter.emit([0x49, 0x83, 0xc4, 0x08])  # add r12, 8 (header)
    @emitter.emit([0x49, 0x83, 0xc4, 0x0f])  # add r12, 15 (for alignment)
    @emitter.emit([0x49, 0x83, 0xe4, 0xf0])  # and r12, -16 (align to 16)
    
    # Load heap_state
    @linker.add_data_patch(@emitter.current_pos + 2, "heap_state")
    @emitter.emit([0x48, 0xbf] + [0] * 8)  # mov rdi, heap_state
    
    # Check if initialized
    @emitter.emit([0x48, 0x8b, 0x47, 0x28])  # mov rax, [rdi+40]
    @emitter.emit([0x48, 0x85, 0xc0])  # test rax, rax
    @emitter.emit([0x75, 0x15])  # jnz skip_init
    
    # Initialize heap if needed (16MB default)
    @emitter.emit([0x50])  # push rax
    @emitter.emit([0x57])  # push rdi
    @emitter.emit([0x41, 0x54])  # push r12
    @emitter.emit([0x48, 0xc7, 0xc0, 0x00, 0x00, 0x00, 0x01])  # mov rax, 16MB
    gen_heap_init_internal
    @emitter.emit([0x41, 0x5c])  # pop r12
    @emitter.emit([0x5f])  # pop rdi
    @emitter.emit([0x58])  # pop rax
    
    # Try free list first (simplified - just bump allocator for now)
    # skip_init:
    @emitter.emit([0x48, 0x8b, 0x47, 0x10])  # mov rax, [rdi+16] (heap_current)
    @emitter.emit([0x49, 0x89, 0xc5])  # mov r13, rax (result ptr)
    
    # Check if enough space
    @emitter.emit([0x4c, 0x01, 0xe0])  # add rax, r12 (new_current)
    @emitter.emit([0x48, 0x3b, 0x47, 0x08])  # cmp rax, [rdi+8] (heap_end)
    @emitter.emit([0x76, 0x07])  # jbe ok
    
    # Out of memory
    @emitter.emit([0x48, 0x31, 0xc0])  # xor rax, rax
    @emitter.emit([0xe9, 0x15, 0x00, 0x00, 0x00])  # jmp end
    
    # ok:
    @emitter.emit([0x48, 0x89, 0x47, 0x10])  # mov [rdi+16], rax (update heap_current)
    
    # Store size in header
    @emitter.emit([0x4d, 0x89, 0x65, 0x00])  # mov [r13], r12 (size in header)
    
    # Return ptr after header
    @emitter.emit([0x49, 0x83, 0xc5, 0x08])  # add r13, 8
    @emitter.emit([0x4c, 0x89, 0xe8])  # mov rax, r13
    # end:
  end

  def gen_heap_init_internal
    # Internal helper - assumes rax has size
    @emitter.emit([0x49, 0x89, 0xc4])  # mov r12, rax
    @emitter.emit([0x48, 0x31, 0xff])  # xor rdi, rdi
    @emitter.emit([0x4c, 0x89, 0xe6])  # mov rsi, r12
    @emitter.emit([0xba, 0x03, 0x00, 0x00, 0x00])  # mov edx, 3
    @emitter.emit([0x41, 0xba, 0x22, 0x00, 0x00, 0x00])  # mov r10d, 0x22
    @emitter.emit([0x49, 0xc7, 0xc0, 0xff, 0xff, 0xff, 0xff])  # mov r8, -1
    @emitter.emit([0x4d, 0x31, 0xc9])  # xor r9, r9
    @emitter.emit([0xb8, 0x09, 0x00, 0x00, 0x00])  # mov eax, 9
    @emitter.emit([0x0f, 0x05])
    
    @linker.add_data_patch(@emitter.current_pos + 2, "heap_state")
    @emitter.emit([0x48, 0xbf] + [0] * 8)
    @emitter.emit([0x48, 0x89, 0x07])  # mov [rdi], rax
    @emitter.emit([0x48, 0x89, 0xc2])  # mov rdx, rax
    @emitter.emit([0x4c, 0x01, 0xe2])  # add rdx, r12
    @emitter.emit([0x48, 0x89, 0x57, 0x08])  # mov [rdi+8], rdx
    @emitter.emit([0x48, 0x89, 0x47, 0x10])  # mov [rdi+16], rax
    @emitter.emit([0x48, 0xc7, 0x47, 0x28, 0x01, 0x00, 0x00, 0x00])  # initialized = 1
  end

  # free(ptr) - Free allocated memory
  # For bump allocator, this is a no-op (memory reclaimed on exit)
  def gen_free(node)
    return unless @target_os == :linux
    setup_heap
    
    eval_expression(node[:args][0])
    # Simple bump allocator - free is no-op
    # In real impl, would add to free list
    @emitter.emit([0x48, 0x31, 0xc0])  # xor rax, rax (return 0)
  end

  # realloc(ptr, new_size) - Reallocate memory
  def gen_realloc(node)
    return unless @target_os == :linux
    setup_heap
    
    # Save old ptr
    eval_expression(node[:args][0])
    @emitter.emit([0x49, 0x89, 0xc4])  # mov r12, rax (old_ptr)
    
    # Get new size
    eval_expression(node[:args][1])
    @emitter.emit([0x49, 0x89, 0xc5])  # mov r13, rax (new_size)
    
    # If old_ptr is 0, just malloc
    @emitter.emit([0x4d, 0x85, 0xe4])  # test r12, r12
    @emitter.emit([0x75, 0x08])  # jnz do_realloc
    
    # malloc(new_size)
    @emitter.emit([0x4c, 0x89, 0xe8])  # mov rax, r13
    # ... call malloc internally
    @emitter.emit([0xe9, 0x00, 0x00, 0x00, 0x00])  # jmp to malloc (simplified)
    
    # do_realloc: Get old size from header
    @emitter.emit([0x49, 0x8b, 0x44, 0x24, 0xf8])  # mov rax, [r12-8] (old size)
    @emitter.emit([0x48, 0x83, 0xe8, 0x08])  # sub rax, 8 (data size)
    @emitter.emit([0x49, 0x89, 0xc6])  # mov r14, rax (old_data_size)
    
    # Allocate new block
    @emitter.emit([0x50])  # push rax
    @emitter.emit([0x41, 0x54])  # push r12
    @emitter.emit([0x41, 0x55])  # push r13
    @emitter.emit([0x41, 0x56])  # push r14
    
    # Call malloc with r13 (new_size)
    @emitter.emit([0x4c, 0x89, 0xe8])  # mov rax, r13
    @emitter.emit([0x49, 0x89, 0xc4])  # mov r12, rax
    # ... simplified - would need proper call
    
    @emitter.emit([0x41, 0x5e])  # pop r14
    @emitter.emit([0x41, 0x5d])  # pop r13
    @emitter.emit([0x41, 0x5c])  # pop r12
    @emitter.emit([0x58])  # pop rax
    
    # Copy data, return new ptr (simplified)
    @emitter.emit([0x4c, 0x89, 0xe8])  # mov rax, r13 (return new_size for now)
  end
end
