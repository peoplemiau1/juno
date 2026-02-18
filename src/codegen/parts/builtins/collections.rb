# Collections - dynamic arrays (vectors)
# vec_new, vec_push, vec_pop, vec_get, vec_set, vec_len

module BuiltinCollections
  def setup_collections
    return if @collections_setup
    @collections_setup = true

    @linker.add_data("vec_storage", "\x00" * 65536)
    @linker.add_data("vec_storage_ptr", [0].pack("Q<"))
  end

  # vec_new(capacity) - Create new vector
  def gen_vec_new(node)
    return unless @target_os == :linux
    setup_collections

    args = node[:args] || []
    if args[0]
      eval_expression(args[0])
    else
      @emitter.emit([0xb8, 0x10, 0x00, 0x00, 0x00])  # mov eax, 16
    end
    @emitter.emit([0x49, 0x89, 0xc4])  # mov r12, rax (capacity)

    # Total size = 16 + capacity*8
    @emitter.emit([0x49, 0xc1, 0xe4, 0x03])  # shl r12, 3
    @emitter.emit([0x49, 0x83, 0xc4, 0x10])  # add r12, 16

    # Get storage pointer address
    @emitter.emit([0x48, 0x8d, 0x3d])  # lea rdi, [rip+offset]
    @linker.add_data_patch(@emitter.current_pos, "vec_storage_ptr")
    @emitter.emit([0x00, 0x00, 0x00, 0x00])
    @emitter.emit([0x48, 0x8b, 0x07])  # mov rax, [rdi]

    # Get storage base
    @emitter.emit([0x48, 0x8d, 0x35])  # lea rsi, [rip+offset]
    @linker.add_data_patch(@emitter.current_pos, "vec_storage")
    @emitter.emit([0x00, 0x00, 0x00, 0x00])
    @emitter.emit([0x48, 0x01, 0xf0])  # add rax, rsi
    @emitter.emit([0x49, 0x89, 0xc5])  # mov r13, rax (vec ptr)

    # Update pointer
    @emitter.emit([0x48, 0x8b, 0x07])  # mov rax, [rdi]
    @emitter.emit([0x4c, 0x01, 0xe0])  # add rax, r12
    @emitter.emit([0x48, 0x89, 0x07])  # mov [rdi], rax

    # Init capacity
    @emitter.emit([0x49, 0x83, 0xec, 0x10])
    @emitter.emit([0x49, 0xc1, 0xec, 0x03])
    @emitter.emit([0x4d, 0x89, 0x65, 0x00])  # [r13] = r12 (cap)
    @emitter.emit([0x49, 0xc7, 0x45, 0x08, 0x00, 0x00, 0x00, 0x00])  # [r13+8] = 0 (len)

    @emitter.emit([0x4c, 0x89, 0xe8])  # mov rax, r13
  end

  # vec_push(vec, value)
  def gen_vec_push(node)
    return unless @target_os == :linux

    args = node[:args] || []
    return if args.length < 2

    eval_expression(args[0]); @emitter.push_reg(0) # vec
    eval_expression(args[1]); @emitter.push_reg(0) # value

    @emitter.pop_reg(13) # value (R13)
    @emitter.pop_reg(12) # vec (R12)

    # Get len, check capacity
    @emitter.mov_rax_mem_idx(12, 8) # mov rax, [r12+8] (len)
    @emitter.mov_rcx_mem_idx(12, 0) # mov rcx, [r12] (cap)
    @emitter.emit([0x48, 0x39, 0xc8])  # cmp rax, rcx
    p_skip = @emitter.je_rel32 # actually jae, but we use rel32 for safety

    # Store at 16 + len*8
    @emitter.shl_rax_imm(3)
    @emitter.emit([0x48, 0x83, 0xc0, 0x10]) # add rax, 16
    @emitter.add_rax_reg(12) # add rax, r12
    @emitter.mov_mem_reg_idx(0, 0, 13) # [rax] = r13
    @emitter.emit([0x49, 0xff, 0x44, 0x24, 0x08]) # inc [r12+8] (len)

    @emitter.patch_je(p_skip, @emitter.current_pos)
    @emitter.mov_rax_from_reg(12) # mov rax, r12
  end

  # vec_pop(vec)
  def gen_vec_pop(node)
    return unless @target_os == :linux

    args = node[:args] || []
    return @emitter.emit([0x48, 0x31, 0xc0]) if args.empty?

    eval_expression(args[0])
    @emitter.emit([0x49, 0x89, 0xc4])  # r12 = vec

    @emitter.emit([0x49, 0x8b, 0x44, 0x24, 0x08])  # rax = len
    @emitter.emit([0x48, 0x85, 0xc0])  # test
    @emitter.emit([0x75, 0x05])  # jnz ok
    @emitter.emit([0x48, 0x31, 0xc0])  # return 0
    @emitter.emit([0xeb, 0x13])  # jmp end

    # Decrement len, get value
    @emitter.emit([0x48, 0xff, 0xc8])  # dec rax
    @emitter.emit([0x49, 0x89, 0x44, 0x24, 0x08])  # [r12+8] = rax
    @emitter.emit([0x48, 0xc1, 0xe0, 0x03])
    @emitter.emit([0x48, 0x83, 0xc0, 0x10])
    @emitter.emit([0x4c, 0x01, 0xe0])
    @emitter.emit([0x48, 0x8b, 0x00])  # rax = [rax]
    # end
  end

  # vec_get(vec, index)
  def gen_vec_get(node)
    return unless @target_os == :linux

    args = node[:args] || []
    return @emitter.emit([0x48, 0x31, 0xc0]) if args.length < 2

    eval_expression(args[0]); @emitter.push_reg(0) # vec
    eval_expression(args[1]); @emitter.push_reg(0) # index

    @emitter.pop_reg(13) # index (R13)
    @emitter.pop_reg(12) # vec (R12)

    # Bounds check
    @emitter.emit([0x49, 0x8b, 0x4c, 0x24, 0x08])  # rcx = len
    @emitter.emit([0x4c, 0x39, 0xe9])  # cmp rcx, r13
    @emitter.emit([0x77, 0x05])  # ja ok
    @emitter.emit([0x48, 0x31, 0xc0])  # return 0
    @emitter.emit([0xeb, 0x0c])  # jmp end

    # Get value at 16 + index*8
    @emitter.emit([0x4c, 0x89, 0xe8])  # rax = r13
    @emitter.emit([0x48, 0xc1, 0xe0, 0x03])
    @emitter.emit([0x48, 0x83, 0xc0, 0x10])
    @emitter.emit([0x4c, 0x01, 0xe0])
    @emitter.emit([0x48, 0x8b, 0x00])
    # end
  end

  # vec_set(vec, index, value)
  def gen_vec_set(node)
    return unless @target_os == :linux

    args = node[:args] || []
    return if args.length < 3

    eval_expression(args[0]); @emitter.push_reg(0) # vec
    eval_expression(args[1]); @emitter.push_reg(0) # index
    eval_expression(args[2]); @emitter.push_reg(0) # value

    @emitter.pop_reg(14) # value (R14)
    @emitter.pop_reg(13) # index (R13)
    @emitter.pop_reg(12) # vec (R12)

    # Calculate offset
    @emitter.emit([0x4c, 0x89, 0xe8])
    @emitter.emit([0x48, 0xc1, 0xe0, 0x03])
    @emitter.emit([0x48, 0x83, 0xc0, 0x10])
    @emitter.emit([0x4c, 0x01, 0xe0])
    @emitter.emit([0x4c, 0x89, 0x30])  # [rax] = r14
    @emitter.emit([0x4c, 0x89, 0xe0])
  end

  # vec_len(vec)
  def gen_vec_len(node)
    return unless @target_os == :linux

    args = node[:args] || []
    return @emitter.emit([0x48, 0x31, 0xc0]) if args.empty?

    eval_expression(args[0])
    @emitter.emit([0x48, 0x8b, 0x40, 0x08])  # rax = [rax+8]
  end

  # vec_cap(vec)
  def gen_vec_cap(node)
    return unless @target_os == :linux

    args = node[:args] || []
    return @emitter.emit([0x48, 0x31, 0xc0]) if args.empty?

    eval_expression(args[0])
    @emitter.emit([0x48, 0x8b, 0x00])  # rax = [rax]
  end

  # vec_clear(vec)
  def gen_vec_clear(node)
    return unless @target_os == :linux

    args = node[:args] || []
    return @emitter.emit([0x48, 0x31, 0xc0]) if args.empty?

    eval_expression(args[0])
    @emitter.emit([0x48, 0xc7, 0x40, 0x08, 0x00, 0x00, 0x00, 0x00])
  end
end
