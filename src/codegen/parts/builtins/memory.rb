# Memory built-in functions for Juno

module BuiltinMemory
  def gen_alloc(node)
    return unless @target_os == :linux
    # mmap(addr, size, prot, flags, fd, offset)
    @emitter.mov_reg_imm(0, 0); @emitter.push_reg(0) # offset
    @emitter.mov_reg_imm(0, 0); @emitter.emit_sub_rax(1); @emitter.push_reg(0) # fd = -1
    @emitter.mov_reg_imm(0, 0x22); @emitter.push_reg(0) # flags
    @emitter.mov_reg_imm(0, 3); @emitter.push_reg(0) # prot
    eval_expression(node[:args][0]); @emitter.push_reg(0) # size
    @emitter.mov_reg_imm(0, 0) # addr = 0

    @emitter.pop_reg(@arch == :aarch64 ? 1 : 6)  # size
    @emitter.pop_reg(@arch == :aarch64 ? 2 : 2)  # prot
    @emitter.pop_reg(@arch == :aarch64 ? 3 : 10) # flags
    @emitter.pop_reg(@arch == :aarch64 ? 4 : 8)  # fd
    @emitter.pop_reg(@arch == :aarch64 ? 5 : 9)  # offset
    @emitter.mov_reg_reg(@arch == :aarch64 ? 0 : 7, 0) if @arch == :x86_64

    emit_syscall(:mmap)
  end

  def gen_free(node)
    return unless @target_os == :linux
    args = node[:args] || []
    return if args.empty?

    if args.length >= 2
       eval_expression(args[1]); @emitter.push_reg(0) # size
       eval_expression(args[0]) # addr
       @emitter.pop_reg(@arch == :aarch64 ? 1 : 6)
       @emitter.mov_reg_reg(@arch == :aarch64 ? 0 : 7, 0)
    else
       eval_expression(args[0])
       @emitter.emit_sub_rax(8)
       @emitter.push_reg(0) # save addr-8
       @emitter.mov_rax_mem(0) # size
       @emitter.mov_reg_reg(@arch == :aarch64 ? 1 : 6, 0)
       @emitter.pop_reg(@arch == :aarch64 ? 0 : 7)
    end
    emit_syscall(:munmap)
  end
end
