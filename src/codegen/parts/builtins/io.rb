# I/O built-in functions for Juno

module BuiltinIO
  def gen_open(node)
    arg = node[:args][0]
    if arg[:type] == :string_literal
      @emitter.emit_load_address(@linker.add_string(arg[:value]), @linker)
      @emitter.mov_reg_reg(@arch == :aarch64 ? 0 : 7, 0)
    else
      eval_expression(arg); @emitter.mov_reg_reg(@arch == :aarch64 ? 0 : 7, 0)
    end
    if @arch == :aarch64 then @emitter.mov_rax(0); @emitter.mov_reg_reg(1, 0); @emitter.mov_rax(0); @emitter.mov_reg_reg(2, 0); @emitter.mov_rax(56); @emitter.mov_reg_reg(8, 0); @emitter.emit32(0xd4000001)
    else @emitter.mov_rax(2); @emitter.mov_reg_reg(6, 0); @emitter.mov_reg_reg(2, 0); @emitter.emit([0x0f, 0x05]) end
  end

  def gen_read(node)
    eval_expression(node[:args][0]); @emitter.push_reg(0)
    eval_expression(node[:args][1]); @emitter.push_reg(0)
    eval_expression(node[:args][2]); @emitter.mov_reg_reg(2, 0)
    if @arch == :aarch64 then @emitter.pop_reg(1); @emitter.pop_reg(0); @emitter.mov_rax(63); @emitter.mov_reg_reg(8, 0); @emitter.emit32(0xd4000001)
    else @emitter.pop_reg(6); @emitter.pop_reg(7); @emitter.mov_rax(0); @emitter.emit([0x0f, 0x05]) end
  end

  def gen_close(node)
    eval_expression(node[:args][0]); @emitter.mov_reg_reg(0, 0)
    if @arch == :aarch64 then @emitter.mov_rax(57); @emitter.mov_reg_reg(8, 0); @emitter.emit32(0xd4000001)
    else @emitter.mov_reg_reg(7, 0); @emitter.mov_rax(3); @emitter.emit([0x0f, 0x05]) end
  end

  def gen_print(node)
    arg = node[:args][0]
    if arg[:type] == :string_literal
      label = @linker.add_string(arg[:value] + "\n")
      @emitter.emit_load_address(label, @linker)
      len = arg[:value].length + 1
      if @arch == :aarch64 then @emitter.mov_reg_reg(1, 0); @emitter.mov_rax(1); @emitter.mov_reg_reg(0, 0); @emitter.mov_rax(len); @emitter.mov_reg_reg(2, 0); @emitter.mov_rax(64); @emitter.mov_reg_reg(8, 0); @emitter.emit32(0xd4000001)
      else @emitter.mov_reg_reg(6, 0); @emitter.mov_rax(1); @emitter.mov_reg_reg(7, 0); @emitter.mov_rax(len); @emitter.mov_reg_reg(2, 0); @emitter.mov_rax(1); @emitter.emit([0x0f, 0x05]) end
    else
      eval_expression(arg); gen_print_int_compatibility(node)
    end
  end

  def gen_len(node)
    arg = node[:args][0]
    if arg[:type] == :string_literal then @emitter.mov_rax(arg[:value].length)
    elsif arg[:type] == :variable
      arr = @ctx.get_array(arg[:name])
      if arr then @emitter.mov_rax(arr[:size])
      else eval_expression(arg); @emitter.mov_rax(8) end
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
       @emitter.emit32(0xd4000001)
    else
       regs = [7, 6, 2, 10, 8, 9]
       num_pop = [args.length - 1, regs.length].min
       num_pop.times { |i| @emitter.pop_reg(regs[i]) }
       @emitter.emit([0x0f, 0x05])
    end
  end

  def gen_getbuf(node)
    @emitter.emit_load_address("file_buffer", @linker)
  end
end
