module BuiltinCollections
  def setup_collections
    return if @collections_setup
    @collections_setup = true

    @linker.add_data("vec_storage", "\x00" * 65536)
    @linker.add_data("vec_storage_ptr", [0].pack("Q<"))
  end

  def gen_vec_new(node)
    return unless @target_os == :linux
    setup_collections

    args = node[:args] || []
    if args[0]
      eval_expression(args[0])
    else
      @emitter.emit([0xb8, 0x10, 0x00, 0x00, 0x00])
    end
    @emitter.emit([0x49, 0x89, 0xc4])

    @emitter.emit([0x49, 0xc1, 0xe4, 0x03])
    @emitter.emit([0x49, 0x83, 0xc4, 0x10])

    @emitter.emit([0x48, 0x8d, 0x3d])
    @linker.add_data_patch(@emitter.current_pos, "vec_storage_ptr")
    @emitter.emit([0x00, 0x00, 0x00, 0x00])
    @emitter.emit([0x48, 0x8b, 0x07])

    @emitter.emit([0x48, 0x8d, 0x35])
    @linker.add_data_patch(@emitter.current_pos, "vec_storage")
    @emitter.emit([0x00, 0x00, 0x00, 0x00])
    @emitter.emit([0x48, 0x01, 0xf0])
    @emitter.emit([0x49, 0x89, 0xc5])

    @emitter.emit([0x48, 0x8b, 0x07])
    @emitter.emit([0x4c, 0x01, 0xe0])
    @emitter.emit([0x48, 0x89, 0x07])

    @emitter.emit([0x49, 0x83, 0xec, 0x10])
    @emitter.emit([0x49, 0xc1, 0xec, 0x03])
    @emitter.emit([0x4d, 0x89, 0x65, 0x00])
    @emitter.emit([0x49, 0xc7, 0x45, 0x08, 0x00, 0x00, 0x00, 0x00])

    @emitter.emit([0x4c, 0x89, 0xe8])
  end

  def gen_vec_push(node)
    return unless @target_os == :linux

    args = node[:args] || []
    return if args.length < 2

    eval_expression(args[0]); @emitter.push_reg(0)
    eval_expression(args[1]); @emitter.push_reg(0)

    @emitter.pop_reg(13)
    @emitter.pop_reg(12)

    @emitter.mov_rax_mem_idx(12, 8)
    @emitter.mov_rcx_mem_idx(12, 0)
    @emitter.emit([0x48, 0x39, 0xc8])
    p_skip = @emitter.jae_rel32

    @emitter.shl_rax_imm(3)
    @emitter.emit([0x48, 0x83, 0xc0, 0x10])
    @emitter.add_reg_reg(0, 12)
    @emitter.mov_mem_reg_idx(0, 0, 13)
    @emitter.emit([0x49, 0xff, 0x44, 0x24, 0x08])

    @emitter.patch_jae(p_skip, @emitter.current_pos)
    @emitter.mov_rax_from_reg(12)
  end

  def gen_vec_pop(node)
    return unless @target_os == :linux

    args = node[:args] || []
    return @emitter.emit([0x48, 0x31, 0xc0]) if args.empty?

    eval_expression(args[0])
    @emitter.emit([0x49, 0x89, 0xc4])

    @emitter.emit([0x49, 0x8b, 0x44, 0x24, 0x08])
    @emitter.emit([0x48, 0x85, 0xc0])
    p_ok = @emitter.jne_rel32
    @emitter.emit([0x48, 0x31, 0xc0])
    p_end = @emitter.jmp_rel32

    @emitter.patch_jne(p_ok, @emitter.current_pos)
    @emitter.emit([0x48, 0xff, 0xc8])
    @emitter.emit([0x49, 0x89, 0x44, 0x24, 0x08])
    @emitter.emit([0x48, 0xc1, 0xe0, 0x03])
    @emitter.emit([0x48, 0x83, 0xc0, 0x10])
    @emitter.emit([0x4c, 0x01, 0xe0])
    @emitter.emit([0x48, 0x8b, 0x00])

    @emitter.patch_jmp(p_end, @emitter.current_pos)
  end

  def gen_vec_get(node)
    return unless @target_os == :linux

    args = node[:args] || []
    return @emitter.emit([0x48, 0x31, 0xc0]) if args.length < 2

    eval_expression(args[0]); @emitter.push_reg(0)
    eval_expression(args[1]); @emitter.push_reg(0)

    @emitter.pop_reg(13)
    @emitter.pop_reg(12)

    @emitter.emit([0x49, 0x8b, 0x4c, 0x24, 0x08])
    @emitter.emit([0x4c, 0x39, 0xe9])
    p_ok = @emitter.ja_rel32
    @emitter.emit([0x48, 0x31, 0xc0])
    p_end = @emitter.jmp_rel32

    @emitter.patch_ja(p_ok, @emitter.current_pos)
    @emitter.emit([0x4c, 0x89, 0xe8])
    @emitter.emit([0x48, 0xc1, 0xe0, 0x03])
    @emitter.emit([0x48, 0x83, 0xc0, 0x10])
    @emitter.emit([0x4c, 0x01, 0xe0])
    @emitter.emit([0x48, 0x8b, 0x00])

    @emitter.patch_jmp(p_end, @emitter.current_pos)
  end

  def gen_vec_set(node)
    return unless @target_os == :linux

    args = node[:args] || []
    return if args.length < 3

    eval_expression(args[0]); @emitter.push_reg(0)
    eval_expression(args[1]); @emitter.push_reg(0)
    eval_expression(args[2]); @emitter.push_reg(0)

    @emitter.pop_reg(14)
    @emitter.pop_reg(13)
    @emitter.pop_reg(12)

    @emitter.emit([0x4c, 0x89, 0xe8])
    @emitter.emit([0x48, 0xc1, 0xe0, 0x03])
    @emitter.emit([0x48, 0x83, 0xc0, 0x10])
    @emitter.emit([0x4c, 0x01, 0xe0])
    @emitter.emit([0x4c, 0x89, 0x30])
    @emitter.emit([0x4c, 0x89, 0xe0])
  end

  def gen_vec_len(node)
    return unless @target_os == :linux

    args = node[:args] || []
    return @emitter.emit([0x48, 0x31, 0xc0]) if args.empty?

    eval_expression(args[0])
    @emitter.emit([0x48, 0x8b, 0x40, 0x08])
  end

  def gen_vec_cap(node)
    return unless @target_os == :linux

    args = node[:args] || []
    return @emitter.emit([0x48, 0x31, 0xc0]) if args.empty?

    eval_expression(args[0])
    @emitter.emit([0x48, 0x8b, 0x00])
  end

  def gen_vec_clear(node)
    return unless @target_os == :linux

    args = node[:args] || []
    return @emitter.emit([0x48, 0x31, 0xc0]) if args.empty?

    eval_expression(args[0])
    @emitter.emit([0x48, 0xc7, 0x40, 0x08, 0x00, 0x00, 0x00, 0x00])
  end
end
