# I/O built-in functions for Juno
module BuiltinIO
  # open(path)
  def gen_open(node)
    return unless @target_os == :linux

    arg = node[:args][0]

    if arg[:type] == :string_literal
      label = @linker.add_string(arg[:value])
      @emitter.emit([0x48, 0x8d, 0x3d])
      @linker.add_data_patch(@emitter.current_pos, label)
      @emitter.emit([0x00, 0x00, 0x00, 0x00])
    else
      eval_expression(arg)
      @emitter.mov_reg_reg(CodeEmitter::REG_RDI, CodeEmitter::REG_RAX)
    end

    @emitter.emit([0x48, 0x31, 0xf6])
    @emitter.emit([0x48, 0x31, 0xd2])
    @emitter.emit([0x48, 0xc7, 0xc0, 2, 0, 0, 0])
    @emitter.emit([0x0f, 0x05])
  end

  # read(fd, buf, size)
  def gen_read(node)
    return unless @target_os == :linux

    eval_expression(node[:args][0])
    @emitter.emit([0x50])

    eval_expression(node[:args][1])
    @emitter.emit([0x50])

    eval_expression(node[:args][2])
    @emitter.mov_reg_reg(CodeEmitter::REG_RDX, CodeEmitter::REG_RAX)

    @emitter.emit([0x5e, 0x5f])
    @emitter.emit([0x48, 0xc7, 0xc0, 0, 0, 0, 0])
    @emitter.emit([0x0f, 0x05])
  end

  # close(fd)
  def gen_close(node)
    return unless @target_os == :linux

    eval_expression(node[:args][0])
    @emitter.mov_reg_reg(CodeEmitter::REG_RDI, CodeEmitter::REG_RAX)
    @emitter.emit([0x48, 0xc7, 0xc0, 3, 0, 0, 0])
    @emitter.emit([0x0f, 0x05])
  end

  # syscall(num, arg1, arg2, arg3, arg4, arg5, arg6)
  def gen_syscall(node)
    return unless @target_os == :linux

    args = node[:args] || []
    num_args = args.length

    # Linux x86-64 syscall registers:
    # num: RAX
    # args: RDI, RSI, RDX, R10, R8, R9
    regs = [
      CodeEmitter::REG_RDI,
      CodeEmitter::REG_RSI,
      CodeEmitter::REG_RDX,
      CodeEmitter::REG_R10,
      CodeEmitter::REG_R8,
      CodeEmitter::REG_R9
    ]

    # 1. Evaluate and push ALL arguments (including syscall num)
    args.reverse_each do |arg|
      eval_expression(arg)
      @emitter.push_reg(CodeEmitter::REG_RAX)
    end

    # 2. Pop syscall number into RAX
    @emitter.pop_reg(CodeEmitter::REG_RAX)

    # 3. Pop arguments into registers
    num_pops = [num_args - 1, regs.length].min
    num_pops.times do |i|
      @emitter.pop_reg(CodeEmitter::REG_R11) # use R11 as safe temp
      @emitter.mov_reg_reg(regs[i], CodeEmitter::REG_R11)
    end

    # 4. Trigger syscall
    @emitter.emit([0x0f, 0x05])
  end

  # getbuf()
  def gen_getbuf(node)
    @emitter.emit([0x48, 0x8d, 0x05])
    @linker.add_data_patch(@emitter.current_pos, "file_buffer")
    @emitter.emit([0x00, 0x00, 0x00, 0x00])
  end
end
