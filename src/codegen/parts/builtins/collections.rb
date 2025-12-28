# Collections - dynamic arrays (vectors)
# vec_new, vec_push, vec_pop, vec_get, vec_set, vec_len

module BuiltinCollections
  def setup_collections
    return if @collections_setup
    @collections_setup = true
    
    # Pre-allocated vector storage (simple approach)
    # Format: [capacity:8][length:8][data...]
    @linker.add_data("vec_storage", "\x00" * 65536)  # 64KB for vectors
    @linker.add_data("vec_storage_ptr", [0].pack("Q<"))  # Current offset
  end

  # vec_new(capacity) - Create new vector
  # Returns pointer to vector struct
  # Vector layout: [capacity:8][length:8][data:capacity*8]
  def gen_vec_new(node)
    return unless @target_os == :linux
    setup_collections
    
    if node[:args] && node[:args][0]
      eval_expression(node[:args][0])
    else
      @emitter.emit([0x48, 0xc7, 0xc0, 0x10, 0x00, 0x00, 0x00])  # default capacity 16
    end
    @emitter.emit([0x49, 0x89, 0xc4])  # mov r12, rax (capacity)
    
    # Calculate total size: 16 + capacity*8
    @emitter.emit([0x49, 0xc1, 0xe4, 0x03])  # shl r12, 3 (capacity * 8)
    @emitter.emit([0x49, 0x83, 0xc4, 0x10])  # add r12, 16 (header)
    
    # Get storage pointer
    @linker.add_data_patch(@emitter.current_pos + 2, "vec_storage_ptr")
    @emitter.emit([0x48, 0xbf] + [0] * 8)  # mov rdi, vec_storage_ptr
    @emitter.emit([0x48, 0x8b, 0x07])  # mov rax, [rdi] (current offset)
    
    @linker.add_data_patch(@emitter.current_pos + 2, "vec_storage")
    @emitter.emit([0x48, 0xbe] + [0] * 8)  # mov rsi, vec_storage
    @emitter.emit([0x48, 0x01, 0xf0])  # add rax, rsi (ptr = storage + offset)
    @emitter.emit([0x49, 0x89, 0xc5])  # mov r13, rax (save vec ptr)
    
    # Update storage pointer
    @emitter.emit([0x48, 0x8b, 0x07])  # mov rax, [rdi]
    @emitter.emit([0x4c, 0x01, 0xe0])  # add rax, r12
    @emitter.emit([0x48, 0x89, 0x07])  # mov [rdi], rax
    
    # Initialize vector
    # Restore capacity
    @emitter.emit([0x49, 0x83, 0xec, 0x10])  # sub r12, 16
    @emitter.emit([0x49, 0xc1, 0xec, 0x03])  # shr r12, 3 (restore capacity)
    
    @emitter.emit([0x4d, 0x89, 0x65, 0x00])  # mov [r13], r12 (capacity)
    @emitter.emit([0x49, 0xc7, 0x45, 0x08, 0x00, 0x00, 0x00, 0x00])  # mov qword [r13+8], 0 (length)
    
    @emitter.emit([0x4c, 0x89, 0xe8])  # mov rax, r13 (return vec ptr)
  end

  # vec_push(vec, value) - Push value to end
  def gen_vec_push(node)
    return unless @target_os == :linux
    setup_collections
    
    eval_expression(node[:args][0])
    @emitter.emit([0x49, 0x89, 0xc4])  # mov r12, rax (vec)
    
    eval_expression(node[:args][1])
    @emitter.emit([0x49, 0x89, 0xc5])  # mov r13, rax (value)
    
    # Get length and capacity
    @emitter.emit([0x49, 0x8b, 0x44, 0x24, 0x08])  # mov rax, [r12+8] (length)
    @emitter.emit([0x49, 0x8b, 0x0c, 0x24])  # mov rcx, [r12] (capacity)
    
    # Check if full
    @emitter.emit([0x48, 0x39, 0xc8])  # cmp rax, rcx
    @emitter.emit([0x73, 0x15])  # jae full (return without adding)
    
    # Calculate data offset: 16 + length*8
    @emitter.emit([0x48, 0xc1, 0xe0, 0x03])  # shl rax, 3
    @emitter.emit([0x48, 0x83, 0xc0, 0x10])  # add rax, 16
    
    # Store value
    @emitter.emit([0x4c, 0x01, 0xe0])  # add rax, r12
    @emitter.emit([0x4c, 0x89, 0x28])  # mov [rax], r13
    
    # Increment length
    @emitter.emit([0x49, 0xff, 0x44, 0x24, 0x08])  # inc qword [r12+8]
    
    # full:
    @emitter.emit([0x4c, 0x89, 0xe0])  # mov rax, r12 (return vec)
  end

  # vec_pop(vec) - Pop and return last value
  def gen_vec_pop(node)
    return unless @target_os == :linux
    setup_collections
    
    eval_expression(node[:args][0])
    @emitter.emit([0x49, 0x89, 0xc4])  # mov r12, rax (vec)
    
    # Get length
    @emitter.emit([0x49, 0x8b, 0x44, 0x24, 0x08])  # mov rax, [r12+8]
    
    # Check if empty
    @emitter.emit([0x48, 0x85, 0xc0])  # test rax, rax
    @emitter.emit([0x75, 0x05])  # jnz not_empty
    @emitter.emit([0x48, 0x31, 0xc0])  # xor rax, rax (return 0)
    @emitter.emit([0xeb, 0x15])  # jmp end
    
    # Decrement length
    @emitter.emit([0x48, 0xff, 0xc8])  # dec rax
    @emitter.emit([0x49, 0x89, 0x44, 0x24, 0x08])  # mov [r12+8], rax
    
    # Get value at index
    @emitter.emit([0x48, 0xc1, 0xe0, 0x03])  # shl rax, 3
    @emitter.emit([0x48, 0x83, 0xc0, 0x10])  # add rax, 16
    @emitter.emit([0x4c, 0x01, 0xe0])  # add rax, r12
    @emitter.emit([0x48, 0x8b, 0x00])  # mov rax, [rax]
    # end
  end

  # vec_get(vec, index) - Get value at index
  def gen_vec_get(node)
    return unless @target_os == :linux
    setup_collections
    
    eval_expression(node[:args][0])
    @emitter.emit([0x49, 0x89, 0xc4])  # mov r12, rax (vec)
    
    eval_expression(node[:args][1])
    @emitter.emit([0x49, 0x89, 0xc5])  # mov r13, rax (index)
    
    # Bounds check
    @emitter.emit([0x49, 0x8b, 0x44, 0x24, 0x08])  # mov rax, [r12+8] (length)
    @emitter.emit([0x4c, 0x39, 0xe8])  # cmp rax, r13
    @emitter.emit([0x77, 0x05])  # ja ok
    @emitter.emit([0x48, 0x31, 0xc0])  # xor rax, rax (return 0 if out of bounds)
    @emitter.emit([0xeb, 0x0c])  # jmp end
    
    # Calculate offset
    @emitter.emit([0x4c, 0x89, 0xe8])  # mov rax, r13
    @emitter.emit([0x48, 0xc1, 0xe0, 0x03])  # shl rax, 3
    @emitter.emit([0x48, 0x83, 0xc0, 0x10])  # add rax, 16
    @emitter.emit([0x4c, 0x01, 0xe0])  # add rax, r12
    @emitter.emit([0x48, 0x8b, 0x00])  # mov rax, [rax]
    # end
  end

  # vec_set(vec, index, value) - Set value at index
  def gen_vec_set(node)
    return unless @target_os == :linux
    setup_collections
    
    eval_expression(node[:args][0])
    @emitter.emit([0x49, 0x89, 0xc4])  # mov r12, rax (vec)
    
    eval_expression(node[:args][1])
    @emitter.emit([0x49, 0x89, 0xc5])  # mov r13, rax (index)
    
    eval_expression(node[:args][2])
    @emitter.emit([0x49, 0x89, 0xc6])  # mov r14, rax (value)
    
    # Calculate offset
    @emitter.emit([0x4c, 0x89, 0xe8])  # mov rax, r13
    @emitter.emit([0x48, 0xc1, 0xe0, 0x03])  # shl rax, 3
    @emitter.emit([0x48, 0x83, 0xc0, 0x10])  # add rax, 16
    @emitter.emit([0x4c, 0x01, 0xe0])  # add rax, r12
    @emitter.emit([0x4c, 0x89, 0x30])  # mov [rax], r14
    
    @emitter.emit([0x4c, 0x89, 0xe0])  # mov rax, r12 (return vec)
  end

  # vec_len(vec) - Get vector length
  def gen_vec_len(node)
    return unless @target_os == :linux
    setup_collections
    
    eval_expression(node[:args][0])
    @emitter.emit([0x48, 0x8b, 0x40, 0x08])  # mov rax, [rax+8]
  end

  # vec_cap(vec) - Get vector capacity
  def gen_vec_cap(node)
    return unless @target_os == :linux
    setup_collections
    
    eval_expression(node[:args][0])
    @emitter.emit([0x48, 0x8b, 0x00])  # mov rax, [rax]
  end

  # vec_clear(vec) - Clear vector (set length to 0)
  def gen_vec_clear(node)
    return unless @target_os == :linux
    setup_collections
    
    eval_expression(node[:args][0])
    @emitter.emit([0x48, 0xc7, 0x40, 0x08, 0x00, 0x00, 0x00, 0x00])  # mov qword [rax+8], 0
  end
end
