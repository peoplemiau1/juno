# Memory built-in functions for Juno

module BuiltinMemory
  def gen_alloc(node)
    return unless @target_os == :linux
    eval_expression(node[:args][0]); @emitter.push_reg(0) # size

    # mmap(0, size, PROT_READ|PROT_WRITE, MAP_PRIVATE|MAP_ANONYMOUS, -1, 0)
    @emitter.mov_rax(0); @emitter.push_reg(0) # offset
    @emitter.mov_rax(0); @emitter.emit_sub_rax(1); @emitter.push_reg(0) # fd = -1
    @emitter.mov_rax(0x22); @emitter.push_reg(0) # flags
    @emitter.mov_rax(3); @emitter.push_reg(0) # prot
    # size is on stack
    @emitter.mov_rax(0); @emitter.push_reg(0) # addr

    @emitter.pop_reg(@arch == :aarch64 ? 0 : 7)
    @emitter.pop_reg(@arch == :aarch64 ? 1 : 6)
    @emitter.pop_reg(@arch == :aarch64 ? 2 : 2)
    @emitter.pop_reg(@arch == :aarch64 ? 3 : 10)
    @emitter.pop_reg(@arch == :aarch64 ? 4 : 8)
    @emitter.pop_reg(@arch == :aarch64 ? 5 : 9)
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
       # Default free assumes size is at [addr-8]
       @emitter.emit_sub_rax(8)
       @emitter.push_reg(0) # save addr-8
       @emitter.mov_rax_mem(0) # rax = size
       @emitter.mov_reg_reg(@arch == :aarch64 ? 1 : 6, 0) # size
       @emitter.pop_reg(@arch == :aarch64 ? 0 : 7) # addr-8
    end
    emit_syscall(:munmap)
  end
end
