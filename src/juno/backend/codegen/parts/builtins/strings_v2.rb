module BuiltinStringsV2
  def setup_strings_v2
    return if @strings_v2_setup
    @strings_v2_setup = true

    @linker.add_data("str_buf_1", "\x00" * 4096)
    @linker.add_data("str_buf_2", "\x00" * 4096)
    @linker.add_data("str_buf_3", "\x00" * 4096)
    @linker.add_data("itoa_buffer", "\x00" * 32)
    @linker.add_data("str_buf_idx", [0].pack("Q<"))
  end

  def gen_str_len(node)
    return unless @target_os == :linux

    eval_expression(node[:args][0])
    @emitter.emit([0x48, 0x89, 0xc7])
    @emitter.emit([0x48, 0x31, 0xc0])

    l_loop = @emitter.current_pos
    @emitter.emit([0x80, 0x3c, 0x07, 0x00])
    p_done = @emitter.je_rel32
    @emitter.emit([0x48, 0xff, 0xc0])
    p_loop = @emitter.jmp_rel32
    @emitter.patch_jmp(p_loop, l_loop)
    @emitter.patch_je(p_done, @emitter.current_pos)
  end

  def gen_str_copy(node)
    return unless @target_os == :linux

    eval_expression(node[:args][0]); @emitter.push_reg(0)
    eval_expression(node[:args][1])
    @emitter.mov_reg_reg(6, 0)
    @emitter.pop_reg(7)
    @emitter.push_reg(7)

    l_loop = @emitter.current_pos
    @emitter.emit([0x8a, 0x06])
    @emitter.emit([0x88, 0x07])
    @emitter.emit([0x84, 0xc0])
    p_done = @emitter.je_rel32
    @emitter.emit([0x48, 0xff, 0xc6])
    @emitter.emit([0x48, 0xff, 0xc7])
    p_loop = @emitter.jmp_rel32
    @emitter.patch_jmp(p_loop, l_loop)
    @emitter.patch_je(p_done, @emitter.current_pos)

    @emitter.pop_reg(0)
  end

  def gen_str_cat(node)
    return unless @target_os == :linux

    eval_expression(node[:args][0]); @emitter.push_reg(0)
    eval_expression(node[:args][1]); @emitter.push_reg(0)
    @emitter.pop_reg(6)
    @emitter.pop_reg(7)
    @emitter.push_reg(7)

    l_find = @emitter.current_pos
    @emitter.emit([0x80, 0x3f, 0x00])
    p_found = @emitter.je_rel32
    @emitter.emit([0x48, 0xff, 0xc7])
    p_find_loop = @emitter.jmp_rel32
    @emitter.patch_jmp(p_find_loop, l_find)
    @emitter.patch_je(p_found, @emitter.current_pos)

    l_copy = @emitter.current_pos
    @emitter.emit([0x8a, 0x06])
    @emitter.emit([0x88, 0x07])
    @emitter.emit([0x84, 0xc0])
    p_done = @emitter.je_rel32
    @emitter.emit([0x48, 0xff, 0xc6])
    @emitter.emit([0x48, 0xff, 0xc7])
    p_copy_loop = @emitter.jmp_rel32
    @emitter.patch_jmp(p_copy_loop, l_copy)
    @emitter.patch_je(p_done, @emitter.current_pos)

    @emitter.pop_reg(0)
  end

  def gen_str_cmp(node)
    return unless @target_os == :linux

    eval_expression(node[:args][0]); @emitter.push_reg(0)
    eval_expression(node[:args][1])
    @emitter.mov_reg_reg(6, 0)
    @emitter.pop_reg(7)

    l_loop = @emitter.current_pos
    @emitter.emit([0x8a, 0x07])
    @emitter.emit([0x44, 0x8a, 0x16])
    @emitter.emit([0x44, 0x38, 0xd0])
    p_ne = @emitter.jne_rel32
    @emitter.emit([0x84, 0xc0])
    p_eq = @emitter.je_rel32
    @emitter.emit([0x48, 0xff, 0xc7])
    @emitter.emit([0x48, 0xff, 0xc6])
    p_loop = @emitter.jmp_rel32
    @emitter.patch_jmp(p_loop, l_loop)

    @emitter.patch_jne(p_ne, @emitter.current_pos)
    @emitter.emit([0x0f, 0xb6, 0xc0])
    @emitter.emit([0x45, 0x0f, 0xb6, 0xd2])
    @emitter.emit([0x44, 0x29, 0xd0])
    p_done = @emitter.jmp_rel32

    @emitter.patch_je(p_eq, @emitter.current_pos)
    @emitter.emit([0x31, 0xc0])

    @emitter.patch_jmp(p_done, @emitter.current_pos)
  end

  def gen_str_find(node)
    return unless @target_os == :linux

    args = node[:args] || []
    if args.length < 2
      @emitter.emit([0x48, 0xc7, 0xc0, 0xff, 0xff, 0xff, 0xff])
      return
    end

    eval_expression(args[0])
    @emitter.emit([0x50])

    eval_expression(args[1])
    @emitter.emit([0x0f, 0xb6, 0x08])

    @emitter.emit([0x5e])
    @emitter.emit([0x48, 0xc7, 0xc0, 0xff, 0xff, 0xff, 0xff])
    @emitter.emit([0x48, 0x31, 0xff])

    l_loop = @emitter.current_pos
    @emitter.emit([0x44, 0x0f, 0xb6, 0x14, 0x3e])
    @emitter.emit([0x45, 0x85, 0xd2])
    p_end = @emitter.je_rel32
    @emitter.emit([0x44, 0x39, 0xca])
    p_found = @emitter.je_rel32
    @emitter.emit([0x48, 0xff, 0xc7])
    p_loop = @emitter.jmp_rel32
    @emitter.patch_jmp(p_loop, l_loop)

    @emitter.patch_je(p_found, @emitter.current_pos)
    @emitter.emit([0x48, 0x89, 0xf8])

    @emitter.patch_je(p_end, @emitter.current_pos)
  end

  def gen_str_to_int(node)
    return unless @target_os == :linux

    args = node[:args] || []
    return @emitter.emit([0x48, 0x31, 0xc0]) if args.empty?

    eval_expression(args[0])
    @emitter.emit([0x48, 0x89, 0xc6])
    @emitter.emit([0x48, 0x31, 0xc0])
    @emitter.emit([0x48, 0x31, 0xc9])

    @emitter.emit([0x80, 0x3e, 0x2d])
    p_parse = @emitter.jne_rel32
    @emitter.emit([0x48, 0xff, 0xc1])
    @emitter.emit([0x48, 0xff, 0xc6])

    @emitter.patch_jne(p_parse, @emitter.current_pos)
    l_loop = @emitter.current_pos
    @emitter.emit([0x44, 0x0f, 0xb6, 0x16])
    @emitter.emit([0x41, 0x80, 0xfa, 0x30])
    p_done1 = @emitter.jl_rel32
    @emitter.emit([0x41, 0x80, 0xfa, 0x39])
    p_done2 = @emitter.jg_rel32

    @emitter.emit([0x41, 0x80, 0xea, 0x30])
    @emitter.emit([0x48, 0x6b, 0xc0, 0x0a])
    @emitter.emit([0x4c, 0x01, 0xd0])
    @emitter.emit([0x48, 0xff, 0xc6])
    p_loop = @emitter.jmp_rel32
    @emitter.patch_jmp(p_loop, l_loop)

    @emitter.patch_jl(p_done1, @emitter.current_pos)
    @emitter.patch_jg(p_done2, @emitter.current_pos)
    @emitter.emit([0x48, 0x85, 0xc9])
    p_pos = @emitter.je_rel32
    @emitter.emit([0x48, 0xf7, 0xd8])
    @emitter.patch_je(p_pos, @emitter.current_pos)
  end

  def gen_int_to_str(node)
    return unless @target_os == :linux
    setup_strings_v2

    args = node[:args] || []
    if args.empty?
      @emitter.emit([0x48, 0x31, 0xc0])
      return
    end

    eval_expression(args[0])

    @emitter.emit([0x4c, 0x8d, 0x15])
    @linker.add_data_patch(@emitter.current_pos, "itoa_buffer")
    @emitter.emit([0x00, 0x00, 0x00, 0x00])
    @emitter.emit([0x49, 0x83, 0xc2, 0x1f])
    @emitter.emit([0x41, 0xc6, 0x02, 0x00])
    @emitter.emit([0x4d, 0x89, 0xd0])

    @emitter.emit([0x48, 0x85, 0xc0])
    p_nz = @emitter.jne_rel32
    @emitter.emit([0x49, 0xff, 0xca])
    @emitter.emit([0x41, 0xc6, 0x02, 0x30])
    p_done = @emitter.jmp_rel32

    @emitter.patch_jne(p_nz, @emitter.current_pos)
    @emitter.emit([0xb9, 0x0a, 0x00, 0x00, 0x00])
    l_loop = @emitter.current_pos
    @emitter.emit([0x48, 0x31, 0xd2])
    @emitter.emit([0x48, 0xf7, 0xf1])
    @emitter.emit([0x80, 0xc2, 0x30])
    @emitter.emit([0x49, 0xff, 0xca])
    @emitter.emit([0x41, 0x88, 0x12])
    @emitter.emit([0x48, 0x85, 0xc0])
    p_loop = @emitter.jne_rel32
    @emitter.patch_jne(p_loop, l_loop)

    @emitter.patch_jmp(p_done, @emitter.current_pos)
    @emitter.emit([0x4c, 0x89, 0xd0])
  end

  def gen_str_upper(node)
    return unless @target_os == :linux

    eval_expression(node[:args][0])
    @emitter.emit([0x48, 0x89, 0xc7])
    @emitter.emit([0x49, 0x89, 0xfb])

    l_loop = @emitter.current_pos
    @emitter.emit([0x8a, 0x07])
    @emitter.emit([0x84, 0xc0])
    p_end = @emitter.je_rel32

    @emitter.emit([0x3c, 0x61])
    p_next1 = @emitter.jl_rel32
    @emitter.emit([0x3c, 0x7a])
    p_next2 = @emitter.jg_rel32

    @emitter.emit([0x2c, 0x20])
    @emitter.emit([0x88, 0x07])

    @emitter.patch_jl(p_next1, @emitter.current_pos)
    @emitter.patch_jg(p_next2, @emitter.current_pos)
    @emitter.emit([0x48, 0xff, 0xc7])
    p_loop = @emitter.jmp_rel32
    @emitter.patch_jmp(p_loop, l_loop)

    @emitter.patch_je(p_end, @emitter.current_pos)
    @emitter.emit([0x4c, 0x89, 0xd8])
  end

  def gen_str_lower(node)
    return unless @target_os == :linux

    eval_expression(node[:args][0])
    @emitter.emit([0x48, 0x89, 0xc7])
    @emitter.emit([0x49, 0x89, 0xfb])

    l_loop = @emitter.current_pos
    @emitter.emit([0x8a, 0x07])
    @emitter.emit([0x84, 0xc0])
    p_end = @emitter.je_rel32

    @emitter.emit([0x3c, 0x41])
    p_next1 = @emitter.jl_rel32
    @emitter.emit([0x3c, 0x5a])
    p_next2 = @emitter.jg_rel32

    @emitter.emit([0x04, 0x20])
    @emitter.emit([0x88, 0x07])

    @emitter.patch_jl(p_next1, @emitter.current_pos)
    @emitter.patch_jg(p_next2, @emitter.current_pos)
    @emitter.emit([0x48, 0xff, 0xc7])
    p_loop = @emitter.jmp_rel32
    @emitter.patch_jmp(p_loop, l_loop)

    @emitter.patch_je(p_end, @emitter.current_pos)
    @emitter.emit([0x4c, 0x89, 0xd8])
  end

  def gen_str_trim(node)
    return unless @target_os == :linux

    eval_expression(node[:args][0])
    @emitter.test_rax_rax
    p_null = @emitter.je_rel32

    @emitter.mov_reg_reg(7, 0)

    l_loop = @emitter.current_pos
    @emitter.emit([0x0f, 0xb6, 0x07])
    @emitter.emit([0x3c, 0x20])
    p_s1 = @emitter.je_rel32
    @emitter.emit([0x3c, 0x09])
    p_s2 = @emitter.je_rel32
    @emitter.emit([0x3c, 0x0a])
    p_s3 = @emitter.je_rel32

    p_scan = @emitter.jmp_rel32

    @emitter.patch_je(p_s1, @emitter.current_pos)
    @emitter.patch_je(p_s2, @emitter.current_pos)
    @emitter.patch_je(p_s3, @emitter.current_pos)

    @emitter.emit([0x48, 0xff, 0xc7])
    p_loop = @emitter.jmp_rel32
    @emitter.patch_jmp(p_loop, l_loop)

    @emitter.patch_jmp(p_scan, @emitter.current_pos)

    @emitter.mov_reg_reg(6, 7)
    l_scan = @emitter.current_pos
    @emitter.emit([0x0f, 0xb6, 0x0e])
    @emitter.emit([0x84, 0xc9])
    p_end_scan = @emitter.je_rel32
    @emitter.emit([0x80, 0xf9, 0x0a])
    p_chomp1 = @emitter.je_rel32
    @emitter.emit([0x80, 0xf9, 0x0d])
    p_chomp2 = @emitter.je_rel32

    @emitter.emit([0x48, 0xff, 0xc6])
    p_next_scan = @emitter.jmp_rel32
    @emitter.patch_jmp(p_next_scan, l_scan)

    @emitter.patch_je(p_chomp1, @emitter.current_pos)
    @emitter.patch_je(p_chomp2, @emitter.current_pos)
    @emitter.emit([0xc6, 0x06, 0x00])

    @emitter.patch_je(p_end_scan, @emitter.current_pos)

    @emitter.mov_reg_reg(0, 7)
    @emitter.patch_je(p_null, @emitter.current_pos)
  end

  def gen_byte_at(node)
    eval_expression(node[:args][0]); @emitter.push_reg(0)
    eval_expression(node[:args][1])
    @emitter.pop_reg(2)
    @emitter.emit([0x0f, 0xb6, 0x04, 0x02])
  end

  def gen_byte_set(node)
    eval_expression(node[:args][0]); @emitter.push_reg(0)
    eval_expression(node[:args][1]); @emitter.push_reg(0)
    eval_expression(node[:args][2])
    @emitter.pop_reg(1)
    @emitter.pop_reg(2)
    @emitter.emit([0x88, 0x04, 0x0a])
  end
end
