module BuiltinFileAPI
  def setup_file_api
    return if @file_api_setup
    @file_api_setup = true
    @linker.add_data("file_read_buf", "\x00" * 65536)
  end

  def gen_file_open(node)
    return unless @target_os == :linux

    eval_expression(node[:args][1]); @emitter.push_reg(0)
    eval_expression(node[:args][0])

    @emitter.mov_reg_reg(@arch == :aarch64 ? 4 : 12, 0)
    @emitter.pop_reg(@arch == :aarch64 ? 1 : 2)

    mode_reg = (@arch == :aarch64 ? 1 : 2)
    @emitter.mov_rax(0)
    @emitter.cmp_reg_imm(mode_reg, 0)
    p1 = @emitter.je_rel32
    @emitter.cmp_reg_imm(mode_reg, 1)
    p2 = @emitter.je_rel32
    @emitter.mov_rax(0x441)
    p3 = @emitter.jmp_rel32
    @emitter.patch_je(p2, @emitter.current_pos)
    @emitter.mov_rax(0x241)
    p4 = @emitter.jmp_rel32
    @emitter.patch_je(p1, @emitter.current_pos)
    @emitter.patch_jmp(p3, @emitter.current_pos)
    @emitter.patch_jmp(p4, @emitter.current_pos)

    if @arch == :aarch64
       @emitter.mov_reg_reg(2, 0)
       @emitter.mov_reg_reg(1, 4)
       @emitter.mov_rax(0o666); @emitter.mov_reg_reg(3, 0)
       @emitter.mov_rax(0xffffff9c); @emitter.mov_reg_reg(0, 0)
       emit_syscall(:openat)
    else
       @emitter.mov_reg_reg(6, 0)
       @emitter.mov_reg_reg(7, 12)
       @emitter.mov_rax(0o666); @emitter.mov_reg_reg(2, 0)
       emit_syscall(:open)
    end
  end

  def gen_file_close(node)
    return unless @target_os == :linux
    eval_expression(node[:args][0])
    @emitter.mov_reg_reg(@arch == :aarch64 ? 0 : 7, 0)
    emit_syscall(:close)
  end

  def gen_file_read(node)
    return unless @target_os == :linux
    eval_expression(node[:args][2]); @emitter.push_reg(0)
    eval_expression(node[:args][1]); @emitter.push_reg(0)
    eval_expression(node[:args][0])
    @emitter.pop_reg(@arch == :aarch64 ? 1 : 6)
    @emitter.pop_reg(@arch == :aarch64 ? 2 : 2)
    @emitter.mov_reg_reg(@arch == :aarch64 ? 0 : 7, 0)
    emit_syscall(:read)
  end

  def gen_file_write(node)
    return unless @target_os == :linux
    eval_expression(node[:args][2]); @emitter.push_reg(0)
    eval_expression(node[:args][1]); @emitter.push_reg(0)
    eval_expression(node[:args][0])
    @emitter.pop_reg(@arch == :aarch64 ? 1 : 6)
    @emitter.pop_reg(@arch == :aarch64 ? 2 : 2)
    @emitter.mov_reg_reg(@arch == :aarch64 ? 0 : 7, 0)
    emit_syscall(:write)
  end

  def gen_file_writeln(node)
    return unless @target_os == :linux
    eval_expression(node[:args][1]); @emitter.push_reg(0)
    eval_expression(node[:args][0]); @emitter.push_reg(0)

    @emitter.pop_reg(@arch == :aarch64 ? 4 : 12)
    @emitter.pop_reg(@arch == :aarch64 ? 5 : 13)

    @emitter.mov_rax(0)
    @emitter.mov_reg_reg(@arch == :aarch64 ? 6 : 14, @arch == :aarch64 ? 5 : 13)
    ls = @emitter.current_pos
    @emitter.mov_rax_mem_idx(@arch == :aarch64 ? 6 : 14, 0, 1)
    @emitter.test_rax_rax
    le = @emitter.je_rel32
    @emitter.emit_add_imm(@arch == :aarch64 ? 6 : 14, @arch == :aarch64 ? 6 : 14, 1)
    lj = @emitter.jmp_rel32
    @emitter.patch_jmp(lj, ls)
    @emitter.patch_je(le, @emitter.current_pos)

    @emitter.mov_reg_reg(0, @arch == :aarch64 ? 6 : 14)
    if @arch == :aarch64
       @emitter.emit32(0xcb050000)
    else
       @emitter.emit([0x4c, 0x29, 0xe8])
    end

    @emitter.mov_reg_reg(@arch == :aarch64 ? 2 : 2, 0)
    @emitter.mov_reg_reg(@arch == :aarch64 ? 1 : 6, @arch == :aarch64 ? 5 : 13)
    @emitter.mov_reg_reg(@arch == :aarch64 ? 0 : 7, @arch == :aarch64 ? 4 : 12)
    emit_syscall(:write)

    @linker.add_data("newline_char", "\n")
    @emitter.mov_reg_reg(@arch == :aarch64 ? 0 : 7, @arch == :aarch64 ? 4 : 12)
    @emitter.emit_load_address("newline_char", @linker)
    @emitter.mov_reg_reg(@arch == :aarch64 ? 1 : 6, 0)
    @emitter.mov_rax(1); @emitter.mov_reg_reg(@arch == :aarch64 ? 2 : 2, 0)
    emit_syscall(:write)
  end

  def gen_file_read_all(node)
    return unless @target_os == :linux
    setup_file_api
    args = node[:args] || []
    return @emitter.mov_rax(0) if args.empty?

    eval_expression(args[0])
    @emitter.mov_reg_reg(@arch == :aarch64 ? 4 : 12, 0)

    @emitter.mov_reg_reg(@arch == :aarch64 ? 1 : 7, @arch == :aarch64 ? 4 : 12)
    @emitter.mov_rax(0); @emitter.mov_reg_reg(@arch == :aarch64 ? 2 : 6, 0)
    @emitter.mov_rax(0); @emitter.mov_reg_reg(@arch == :aarch64 ? 3 : 2, 0)
    if @arch == :aarch64
       @emitter.mov_rax(0xffffff9c); @emitter.mov_reg_reg(0, 0)
       emit_syscall(:openat)
    else
       emit_syscall(:open)
    end

    @emitter.mov_reg_reg(@arch == :aarch64 ? 5 : 13, 0)

    @emitter.emit_load_address("file_buffer", @linker)
    @emitter.mov_reg_reg(@arch == :aarch64 ? 6 : 14, 0)

    @emitter.mov_reg_imm(@arch == :aarch64 ? 2 : 2, 65535)
    @emitter.mov_reg_reg(@arch == :aarch64 ? 1 : 6, @arch == :aarch64 ? 6 : 14)
    @emitter.mov_reg_reg(@arch == :aarch64 ? 0 : 7, @arch == :aarch64 ? 5 : 13)
    emit_syscall(:read)

    @emitter.mov_reg_reg(@arch == :aarch64 ? 9 : 15, 0)

    @emitter.mov_reg_reg(0, @arch == :aarch64 ? 6 : 14)
    @emitter.mov_reg_reg(2, @arch == :aarch64 ? 9 : 15)
    if @arch == :aarch64
      @emitter.add_rax_reg(2)
    else
      @emitter.add_rax_rdx
    end
    @emitter.mov_reg_reg(7, 0)
    @emitter.mov_rax(0)
    @emitter.mov_mem_rax_sized(1)

    @emitter.mov_reg_reg(@arch == :aarch64 ? 0 : 7, @arch == :aarch64 ? 5 : 13)
    emit_syscall(:close)

    @emitter.mov_reg_reg(0, @arch == :aarch64 ? 6 : 14)
  end

  def gen_file_read_all_v2(node)
    return unless @target_os == :linux
    setup_file_api
    args = node[:args] || []
    return @emitter.mov_rax(0) if args.empty?

    eval_expression(args[0])
    @emitter.mov_reg_reg(@arch == :aarch64 ? 4 : 12, 0)

    if @arch == :aarch64
       @emitter.mov_reg_reg(1, 4)
       @emitter.mov_rax(0); @emitter.mov_reg_reg(2, 0)
       @emitter.mov_rax(0); @emitter.mov_reg_reg(3, 0)
       @emitter.mov_rax(0xffffff9c); @emitter.mov_reg_reg(0, 0)
       emit_syscall(:openat)
    else
       @emitter.mov_reg_reg(7, 12)
       @emitter.mov_rax(0); @emitter.mov_reg_reg(6, 0)
       @emitter.mov_rax(0); @emitter.mov_reg_reg(2, 0)
       emit_syscall(:open)
    end

    @emitter.mov_reg_reg(@arch == :aarch64 ? 5 : 13, 0)

    @emitter.emit_load_address("file_buffer_2", @linker)
    @emitter.mov_reg_reg(@arch == :aarch64 ? 6 : 14, 0)

    @emitter.mov_reg_imm(@arch == :aarch64 ? 2 : 2, 65535)
    @emitter.mov_reg_reg(@arch == :aarch64 ? 1 : 6, @arch == :aarch64 ? 6 : 14)
    @emitter.mov_reg_reg(@arch == :aarch64 ? 0 : 7, @arch == :aarch64 ? 5 : 13)
    emit_syscall(:read)

    @emitter.mov_reg_reg(@arch == :aarch64 ? 9 : 15, 0)

    @emitter.mov_reg_reg(0, @arch == :aarch64 ? 6 : 14)
    @emitter.mov_reg_reg(2, @arch == :aarch64 ? 9 : 15)
    if @arch == :aarch64
      @emitter.add_rax_reg(2)
    else
      @emitter.add_rax_rdx
    end
    @emitter.mov_reg_reg(7, 0)
    @emitter.mov_rax(0)
    @emitter.mov_mem_rax_sized(1)

    @emitter.mov_reg_reg(@arch == :aarch64 ? 0 : 7, @arch == :aarch64 ? 5 : 13)
    emit_syscall(:close)

    @emitter.mov_reg_reg(0, @arch == :aarch64 ? 6 : 14)
  end

  def gen_file_exists(node)
    return unless @target_os == :linux
    eval_expression(node[:args][0])
    if @arch == :aarch64
       @emitter.mov_reg_reg(1, 0)
       @emitter.mov_rax(0xffffff9c); @emitter.mov_reg_reg(0, 0)
       @emitter.mov_rax(0); @emitter.mov_reg_reg(2, 0)
       @emitter.mov_rax(0); @emitter.mov_reg_reg(3, 0)
       emit_syscall(:access)
    else
       @emitter.mov_reg_reg(7, 0)
       @emitter.mov_rax(0); @emitter.mov_reg_reg(6, 0)
       emit_syscall(:access)
    end

    @emitter.test_rax_rax
    p1 = @emitter.je_rel32
    @emitter.mov_rax(0)
    p2 = @emitter.jmp_rel32
    @emitter.patch_je(p1, @emitter.current_pos)
    @emitter.mov_rax(1)
    @emitter.patch_jmp(p2, @emitter.current_pos)
  end

  def gen_file_size(node)
    return unless @target_os == :linux
    eval_expression(node[:args][0])
    @emitter.mov_reg_reg(@arch == :aarch64 ? 4 : 12, 0)

    @emitter.emit_sub_rsp(160)
    if @arch == :aarch64
       @emitter.mov_reg_reg(1, 4)
       @emitter.mov_reg_sp(2)
       @emitter.mov_rax(0xffffff9c); @emitter.mov_reg_reg(0, 0)
       @emitter.mov_rax(0); @emitter.mov_reg_reg(3, 0)
       emit_syscall(:stat)
    else
       @emitter.mov_reg_reg(7, 12)
       @emitter.mov_reg_sp(6)
       emit_syscall(:stat)
    end

    @emitter.mov_rax_mem_idx(@arch == :aarch64 ? 31 : 4, 48, 8)
    @emitter.emit_add_rsp(160)
  end
end
