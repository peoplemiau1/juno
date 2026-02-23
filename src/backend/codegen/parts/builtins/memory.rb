# Memory built-in functions for Juno

module BuiltinMemory
  def gen_alloc(node)
    return unless @target_os == :linux
    eval_expression(node[:args][0])
    if @arch == :aarch64
      @emitter.mov_reg_reg(1, 0)             # X1 = length (from X0)
      @emitter.mov_reg_imm(0, 0)             # X0 = addr
      @emitter.mov_reg_imm(2, 3)             # X2 = prot (PROT_READ|PROT_WRITE)
      @emitter.mov_reg_imm(3, 0x22)          # X3 = flags (MAP_PRIVATE|MAP_ANONYMOUS)
      @emitter.mov_reg_imm(4, 0xffffffffffffffff) # X4 = fd (-1)
      @emitter.mov_reg_imm(5, 0)             # X5 = offset
      @emitter.mov_x8(222)                   # X8 = syscall mmap
      @emitter.syscall
    else
      @emitter.mov_reg_reg(6, 0); @emitter.mov_rax(0); @emitter.mov_reg_reg(7, 0)
      @emitter.mov_rax(3); @emitter.mov_reg_reg(2, 0); @emitter.mov_rax(0x22); @emitter.mov_reg_reg(10, 0)
      @emitter.mov_rax(0xFFFFFFFFFFFFFFFF); @emitter.mov_reg_reg(8, 0); @emitter.mov_rax(0); @emitter.mov_reg_reg(9, 0)
      @emitter.mov_rax(9); @emitter.emit([0x0f, 0x05])
    end
  end

  def gen_free(node)
    return unless @target_os == :linux
    args = node[:args] || []
    return if args.empty?
    eval_expression(args[0])
    if @arch == :aarch64
       # munmap(addr, len)
       @emitter.mov_reg_reg(0, 0) # X0 = addr (already in X0)
       if args.length >= 2
         @emitter.push_reg(0)
         eval_expression(args[1])
         @emitter.mov_reg_reg(1, 0) # X1 = len
         @emitter.pop_reg(0)        # X0 = addr
       else
         # If len not provided, we might have stored it in a header?
         # Juno's malloc adds 8 bytes header.
         @emitter.sub_reg_imm(0, 8)
         @emitter.mov_reg_reg(11, 0) # save addr+header
         @emitter.mov_rax_mem(0)     # load size
         @emitter.mov_reg_reg(1, 0)  # X1 = size
         @emitter.mov_reg_reg(0, 11) # X0 = addr
       end
       @emitter.mov_x8(215) # munmap
       @emitter.syscall
    else
       if args.length >= 2
         @emitter.push_reg(0); eval_expression(args[1]); @emitter.mov_reg_reg(6, 0); @emitter.pop_reg(7)
         @emitter.mov_rax(11); @emitter.emit([0x0f, 0x05])
       else
         @emitter.emit([0x48, 0x83, 0xe8, 0x08, 0x48, 0x89, 0xc7, 0x48, 0x8b, 0x37, 0xb8, 11, 0, 0, 0, 0x0f, 0x05])
       end
    end
  end
end
