# I/O built-in functions for Juno
module BuiltinIO
  # open(path)
  def gen_open(node)
    return unless @target_os == :linux
    arg = node[:args][0]

    if @arch == :aarch64
      # openat(AT_FDCWD, path, flags, mode)
      @emitter.mov_rax(0xFFFFFFFFFFFFFF9C) # -100 (AT_FDCWD)
      @emitter.mov_reg_reg(0, 0) # X0

      if arg[:type] == :string_literal
        label = @linker.add_string(arg[:value])
        @emitter.emit32(0x58000000); @linker.add_data_patch(@emitter.current_pos - 4, label)
      else
        eval_expression(arg); @emitter.mov_reg_reg(1, 0)
      end

      @emitter.mov_rax(0); @emitter.mov_reg_reg(2, 0) # flags
      @emitter.mov_rax(0); @emitter.mov_reg_reg(3, 0) # mode
      @emitter.mov_rax(56); @emitter.mov_reg_reg(8, 0) # X8 = 56
      @emitter.emit32(0xd4000001)
    else
      if arg[:type] == :string_literal
        label = @linker.add_string(arg[:value])
        @emitter.emit([0x48, 0x8d, 0x3d]); @linker.add_data_patch(@emitter.current_pos, label); @emitter.emit([0x00, 0x00, 0x00, 0x00])
      else
        eval_expression(arg); @emitter.mov_reg_reg(CodeEmitter::REG_RDI, CodeEmitter::REG_RAX)
      end
      @emitter.emit([0x48, 0x31, 0xf6, 0x48, 0x31, 0xd2, 0x48, 0xc7, 0xc0, 2, 0, 0, 0, 0x0f, 0x05])
    end
  end

  # read(fd, buf, size)
  def gen_read(node)
    return unless @target_os == :linux
    eval_expression(node[:args][0]); @emitter.push_reg(@emitter.class::REG_RAX)
    eval_expression(node[:args][1]); @emitter.push_reg(@emitter.class::REG_RAX)
    eval_expression(node[:args][2]); @emitter.mov_reg_reg(@emitter.class::REG_RDX, @emitter.class::REG_RAX)
    @emitter.pop_reg(@emitter.class::REG_RSI); @emitter.pop_reg(@emitter.class::REG_RDI)

    if @arch == :aarch64
      @emitter.mov_reg_reg(0, 4) # X0 = RDI equivalent
      @emitter.mov_reg_reg(1, 3) # X1 = RSI
      @emitter.mov_reg_reg(2, 2) # X2 = RDX
      @emitter.mov_rax(63); @emitter.mov_reg_reg(8, 0)
      @emitter.emit32(0xd4000001)
    else
      @emitter.emit([0x48, 0xc7, 0xc0, 0, 0, 0, 0, 0x0f, 0x05])
    end
  end

  # close(fd)
  def gen_close(node)
    return unless @target_os == :linux
    eval_expression(node[:args][0])
    if @arch == :aarch64
      @emitter.mov_rax(57); @emitter.mov_reg_reg(8, 0)
      @emitter.emit32(0xd4000001)
    else
      @emitter.mov_reg_reg(CodeEmitter::REG_RDI, CodeEmitter::REG_RAX)
      @emitter.emit([0x48, 0xc7, 0xc0, 3, 0, 0, 0, 0x0f, 0x05])
    end
  end

  # syscall(num, arg1, ...)
  def gen_syscall(node)
    return unless @target_os == :linux
    args = node[:args] || []; num_args = args.length

    regs = @arch == :aarch64 ? [0, 1, 2, 3, 4, 5] : [7, 6, 2, 10, 8, 9] # X0-X5 or RDI, RSI, RDX, R10, R8, R9

    args.reverse_each { |arg| eval_expression(arg); @emitter.push_reg(@emitter.class::REG_RAX) }
    @emitter.pop_reg(@emitter.class::REG_RAX) # Syscall num

    num_pops = [num_args - 1, regs.length].min
    num_pops.times do |i|
      @emitter.pop_reg(@emitter.class::REG_R11)
      @emitter.mov_reg_reg(regs[i], @emitter.class::REG_R11)
    end

    if @arch == :aarch64
      @emitter.mov_reg_reg(8, 0) # X8 = syscall num
      @emitter.emit32(0xd4000001)
    else
      @emitter.emit([0x0f, 0x05])
    end
  end

  # getbuf()
  def gen_getbuf(node)
    if @arch == :aarch64
       @emitter.emit32(0x58000000); @linker.add_data_patch(@emitter.current_pos - 4, "file_buffer")
    else
       @emitter.emit([0x48, 0x8d, 0x05]); @linker.add_data_patch(@emitter.current_pos, "file_buffer"); @emitter.emit([0x00, 0x00, 0x00, 0x00])
    end
  end
end
