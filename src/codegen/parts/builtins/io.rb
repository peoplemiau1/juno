# I/O built-in functions for Juno

module BuiltinIO
  def gen_output(node)
    # Generic output: try to guess if it's string or int, or just call prints
    # In Juno v2.0, we'll favor prints
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
      # Result address is in X0/RAX
    else
      eval_expression(arg)
      # Address is in X0/RAX
    end

    if @arch == :aarch64
      @emitter.mov_reg_reg(1, 0) # X1 = pathname
      @emitter.mov_rax(0xffffff9c); @emitter.mov_reg_reg(0, 0) # X0 = AT_FDCWD (-100)
      @emitter.mov_rax(0); @emitter.mov_reg_reg(2, 0) # X2 = flags (O_RDONLY)
      @emitter.mov_rax(0); @emitter.mov_reg_reg(3, 0) # X3 = mode
      emit_syscall(:open)
    else
      @emitter.mov_reg_reg(7, 0) # RDI = path
      @emitter.mov_rax(0); @emitter.mov_reg_reg(6, 0) # RSI = flags (O_RDONLY)
      @emitter.mov_rax(0); @emitter.mov_reg_reg(2, 0) # RDX = mode
      emit_syscall(:open)
    end
  end

  def gen_read(node)
    eval_expression(node[:args][0]); @emitter.push_reg(0) # fd
    eval_expression(node[:args][1]); @emitter.push_reg(0) # buf
    eval_expression(node[:args][2]); @emitter.mov_reg_reg(2, 0) # count/len
    if @arch == :aarch64
      @emitter.pop_reg(1); @emitter.pop_reg(0) # X1=buf, X0=fd
      emit_syscall(:read)
    else
      @emitter.pop_reg(6); @emitter.pop_reg(7) # RSI=buf, RDI=fd
      emit_syscall(:read)
    end
  end

  def gen_close(node)
    eval_expression(node[:args][0])
    # fd is already in X0/RAX
    if @arch == :aarch64
      emit_syscall(:close)
    else
      @emitter.mov_reg_reg(7, 0) # RDI = fd
      emit_syscall(:close)
    end
  end

  def gen_print(node)
    arg = node[:args][0]
    if arg[:type] == :string_literal
      label = @linker.add_string(arg[:value] + "\n")
      @emitter.emit_load_address(label, @linker)
      len = arg[:value].length + 1
      if @arch == :aarch64
        @emitter.mov_reg_reg(1, 0) # X1 = buf
        @emitter.mov_rax(1); @emitter.mov_reg_reg(0, 0) # X0 = stdout
        @emitter.mov_rax(len); @emitter.mov_reg_reg(2, 0) # X2 = len
        emit_syscall(:write)
      else
        @emitter.mov_reg_reg(6, 0) # RSI = buf
        @emitter.mov_rax(1); @emitter.mov_reg_reg(7, 0) # RDI = stdout
        @emitter.mov_rax(len); @emitter.mov_reg_reg(2, 0) # RDX = len
        emit_syscall(:write)
      end
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
      else eval_expression(arg); @emitter.mov_rax(8) end # Fallback
    end
  end

  def gen_syscall(node)
    args = node[:args] || []
    args.reverse_each { |a| eval_expression(a); @emitter.push_reg(0) }
    @emitter.pop_reg(0) # Syscall number or first arg?
    # Usually syscall(num, arg1, ...)
    if @arch == :aarch64
       @emitter.mov_reg_reg(8, 0) # X8 = num
       num_pop = [args.length - 1, 6].min
       num_pop.times { |i| @emitter.pop_reg(i) }
       @emitter.syscall
    else
       # RDI, RSI, RDX, R10, R8, R9
       @emitter.mov_reg_reg(0, 0) # RAX = num
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
