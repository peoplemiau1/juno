# Memory built-in functions for Juno
module BuiltinMemory
  # alloc(size) - allocate via mmap
  def gen_alloc(node)
    return unless @target_os == :linux

    eval_expression(node[:args][0])
    @emitter.mov_reg_reg(@emitter.class::REG_RSI, @emitter.class::REG_RAX) # mov rsi, rax (size)

    if @arch == :aarch64
      # mmap(addr, size, prot, flags, fd, offset)
      # X0, X1, X2, X3, X4, X5
      @emitter.mov_rax(0)
      @emitter.mov_reg_reg(0, 0) # X0 = NULL
      # X1 already has size
      @emitter.mov_rax(3)
      @emitter.mov_reg_reg(2, 0) # X2 = prot
      @emitter.mov_rax(0x22)
      @emitter.mov_reg_reg(3, 0) # X3 = flags
      @emitter.mov_rax(0xFFFFFFFFFFFFFFFF)
      @emitter.mov_reg_reg(4, 0) # X4 = fd
      @emitter.mov_rax(0)
      @emitter.mov_reg_reg(5, 0) # X5 = offset
      @emitter.mov_rax(222) # mmap on aarch64
      @emitter.emit32(0xd4000001) # svc #0
    else
      @emitter.emit([0x48, 0x31, 0xff])
      @emitter.emit([0xba, 0x03, 0x00, 0x00, 0x00])
      @emitter.emit([0x41, 0xba, 0x22, 0x00, 0x00, 0x00])
      @emitter.emit([0x49, 0x83, 0xc8, 0xff])
      @emitter.emit([0x4d, 0x31, 0xc9])
      @emitter.emit([0xb8, 0x09, 0x00, 0x00, 0x00])
      @emitter.emit([0x0f, 0x05])
    end
  end

  # free(ptr) or free(ptr, size) - deallocate
  def gen_free(node)
    return unless @target_os == :linux

    args = node[:args] || []
    return if args.empty?

    eval_expression(args[0])

    if args.length >= 2
      @emitter.push_reg(@emitter.class::REG_RAX)
      eval_expression(args[1])
      @emitter.mov_reg_reg(@emitter.class::REG_RSI, @emitter.class::REG_RAX)
      @emitter.pop_reg(@emitter.class::REG_RDI)
      if @arch == :aarch64
        @emitter.mov_rax(215) # munmap on aarch64
        @emitter.emit32(0xd4000001)
      else
        @emitter.emit([0xb8, 0x0b, 0x00, 0x00, 0x00])
        @emitter.emit([0x0f, 0x05])
      end
    else
      # Simple free
      if @arch == :aarch64
        @emitter.emit32(0xd1002000) # sub x0, x0, #8
        @emitter.mov_reg_reg(4, 0)  # x4 = rdi = x0
        @emitter.mov_rax_mem(0)     # x0 = [x0] (size)
        @emitter.mov_reg_reg(1, 0)  # x1 = rsi = x0 (size)
        @emitter.mov_reg_reg(0, 4)  # x0 = rdi = x4 (ptr)
        @emitter.mov_rax(215)
        @emitter.emit32(0xd4000001)
      else
        @emitter.emit([0x48, 0x83, 0xe8, 0x08])
        @emitter.emit([0x48, 0x89, 0xc7])
        @emitter.emit([0x48, 0x8b, 0x37])
        @emitter.emit([0xb8, 0x0b, 0x00, 0x00, 0x00])
        @emitter.emit([0x0f, 0x05])
      end
    end
  end

  # ptr_add(ptr, offset)
  def gen_ptr_add(node)
    eval_expression(node[:args][0])
    @emitter.push_reg(@emitter.class::REG_RAX)
    eval_expression(node[:args][1])
    @emitter.mov_reg_reg(@emitter.class::REG_RDX, @emitter.class::REG_RAX)
    @emitter.pop_reg(@emitter.class::REG_RAX)
    @emitter.add_rax_rdx
  end

  # ptr_sub(ptr, offset)
  def gen_ptr_sub(node)
    eval_expression(node[:args][0])
    @emitter.push_reg(@emitter.class::REG_RAX)
    eval_expression(node[:args][1])
    @emitter.mov_reg_reg(@emitter.class::REG_RDX, @emitter.class::REG_RAX)
    @emitter.pop_reg(@emitter.class::REG_RAX)
    @emitter.sub_rax_rdx
  end

  # ptr_diff(ptr1, ptr2)
  def gen_ptr_diff(node)
    eval_expression(node[:args][0])
    @emitter.push_reg(@emitter.class::REG_RAX)
    eval_expression(node[:args][1])
    @emitter.mov_reg_reg(@emitter.class::REG_RDX, @emitter.class::REG_RAX)
    @emitter.pop_reg(@emitter.class::REG_RAX)
    @emitter.sub_rax_rdx
    # Divide by 8 to get number of elements
    @emitter.shr_rax_imm(3)
  end
end
