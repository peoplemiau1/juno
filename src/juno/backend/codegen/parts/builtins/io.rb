module BuiltinIO
  def gen_output(node)
    gen_prints(node)
  end

  def gen_output_int(node)
    eval_expression(node[:args][0])
    gen_print_int_compatibility(node)
  end

  def gen_open(node)
    arg = node[:args][0]
    if arg[:type] == :string_literal
      label = @linker.add_string(arg[:value])
      @emitter.emit_load_address(label, @linker)
    else
      eval_expression(arg)
    end

    if @arch == :aarch64
      @emitter.mov_reg_reg(1, 0)
      @emitter.mov_reg_imm(0, 0xffffffffffffff9c)
      @emitter.mov_reg_imm(2, 0)
      @emitter.mov_reg_imm(3, 0)
      emit_syscall(:openat)
    else
      @emitter.mov_reg_reg(7, 0)
      @emitter.mov_reg_imm(6, 0)
      @emitter.mov_reg_imm(2, 0)
      emit_syscall(:open)
    end
  end

  def gen_read(node)
    eval_expression(node[:args][0]); @emitter.push_reg(0)
    eval_expression(node[:args][1]); @emitter.push_reg(0)
    eval_expression(node[:args][2]); @emitter.push_reg(0)

    @emitter.pop_reg(2)
    @emitter.pop_reg(@arch == :aarch64 ? 1 : 6)
    @emitter.pop_reg(@arch == :aarch64 ? 0 : 7)
    emit_syscall(:read)
  end

  def gen_write(node)
    eval_expression(node[:args][0]); @emitter.push_reg(0)
    eval_expression(node[:args][1]); @emitter.push_reg(0)
    eval_expression(node[:args][2]); @emitter.push_reg(0)

    @emitter.pop_reg(2)
    @emitter.pop_reg(@arch == :aarch64 ? 1 : 6)
    @emitter.pop_reg(@arch == :aarch64 ? 0 : 7)
    emit_syscall(:write)
  end

  def gen_close(node)
    eval_expression(node[:args][0])
    @emitter.mov_reg_reg(@arch == :aarch64 ? 0 : 7, 0)
    emit_syscall(:close)
  end

  def gen_print(node)
    arg = node[:args][0]
    if arg[:type] == :string_literal
      label = @linker.add_string(arg[:value] + "\n")
      @emitter.emit_load_address(label, @linker)
      len = arg[:value].length + 1
      if @arch == :aarch64
        @emitter.mov_reg_reg(1, 0)
        @emitter.mov_reg_imm(0, 1)
        @emitter.mov_reg_imm(2, len)
        emit_syscall(:write)
      else
        @emitter.mov_reg_reg(6, 0)
        @emitter.mov_reg_imm(7, 1)
        @emitter.mov_reg_imm(2, len)
        emit_syscall(:write)
      end
    else
      eval_expression(arg); gen_print_int_compatibility(node)
    end
  end

  def gen_syscall(node)
    args = node[:args] || []
    args.reverse_each { |a| eval_expression(a); @emitter.push_reg(0) }
    @emitter.pop_reg(0)

    if @arch == :aarch64
       @emitter.mov_reg_reg(8, 0)
       num_pop = [args.length - 1, 6].min
       num_pop.times { |i| @emitter.pop_reg(i) }
       @emitter.syscall
    else
       @emitter.mov_reg_reg(0, 0)
       regs = [7, 6, 2, 10, 8, 9]
       num_pop = [args.length - 1, regs.length].min
       num_pop.times { |i| @emitter.pop_reg(regs[i]) }
       @emitter.syscall
    end
  end

  def gen_getbuf(node)
    @emitter.emit_load_address("file_buffer", @linker)
  end
end
