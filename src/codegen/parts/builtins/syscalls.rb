# syscalls.rb - Direct syscall wrappers

module BuiltinSyscalls
  def gen_mmap(node)
    return unless @target_os == :linux
    # args: addr, len, prot, flags, fd, offset
    eval_expression(node[:args][5]); @emitter.push_reg(0)
    eval_expression(node[:args][4]); @emitter.push_reg(0)
    eval_expression(node[:args][3]); @emitter.push_reg(0)
    eval_expression(node[:args][2]); @emitter.push_reg(0)
    eval_expression(node[:args][1]); @emitter.push_reg(0)
    eval_expression(node[:args][0])
    
    if @arch == :aarch64
       @emitter.pop_reg(1); @emitter.pop_reg(2); @emitter.pop_reg(3)
       @emitter.pop_reg(4); @emitter.pop_reg(5)
    else
       @emitter.pop_reg(6); @emitter.pop_reg(2); @emitter.pop_reg(10)
       @emitter.pop_reg(8); @emitter.pop_reg(9); @emitter.mov_reg_reg(7, 0)
    end
    emit_syscall(:mmap)
  end

  def gen_munmap(node)
    eval_expression(node[:args][0]); @emitter.push_reg(0)
    eval_expression(node[:args][1]); @emitter.mov_reg_reg(@arch == :aarch64 ? 1 : 6, 0)
    @emitter.pop_reg(@arch == :aarch64 ? 0 : 7)
    emit_syscall(:munmap)
  end

  def gen_memcpy(node)
    eval_expression(node[:args][2]); @emitter.push_reg(0)
    eval_expression(node[:args][1]); @emitter.push_reg(0)
    eval_expression(node[:args][0])
    @emitter.push_reg(0)
    @emitter.pop_reg(@arch == :aarch64 ? 0 : 7) # RDI or X0
    @emitter.pop_reg(@arch == :aarch64 ? 1 : 6) # RSI or X1
    @emitter.pop_reg(@arch == :aarch64 ? 2 : 1) # RCX or X2
    if @arch == :x86_64 then @emitter.emit([0xfc]) end # cld
    @emitter.memcpy
    @emitter.pop_reg(0)
  end

  def gen_memset(node)
    eval_expression(node[:args][2]); @emitter.push_reg(0)
    eval_expression(node[:args][1]); @emitter.push_reg(0)
    eval_expression(node[:args][0])
    @emitter.push_reg(0)
    @emitter.pop_reg(@arch == :aarch64 ? 0 : 7)
    @emitter.pop_reg(@arch == :aarch64 ? 1 : 0)
    @emitter.pop_reg(@arch == :aarch64 ? 2 : 1) # RCX on x86, X2 on arm
    @emitter.memset
    @emitter.pop_reg(0)
  end

  def gen_lseek(node)
    eval_expression(node[:args][2]); @emitter.push_reg(0)
    eval_expression(node[:args][1]); @emitter.push_reg(0)
    eval_expression(node[:args][0])
    @emitter.pop_reg(@arch == :aarch64 ? 1 : 6)
    @emitter.pop_reg(@arch == :aarch64 ? 2 : 2)
    @emitter.mov_reg_reg(@arch == :aarch64 ? 0 : 7, 0)
    emit_syscall(:lseek)
  end

  def gen_memfd_create(node)
    args = node[:args] || []
    if args[0] then eval_expression(args[0]) else @emitter.mov_rax(0) end
    @emitter.push_reg(0)
    if args[1] then eval_expression(args[1]) else @emitter.mov_rax(0) end
    @emitter.mov_reg_reg(@arch == :aarch64 ? 1 : 6, 0)
    @emitter.pop_reg(@arch == :aarch64 ? 0 : 7)
    emit_syscall(:memfd_create)
  end

  def gen_SEEK_SET(node); @emitter.mov_rax(0); end
  def gen_SEEK_CUR(node); @emitter.mov_rax(1); end
  def gen_SEEK_END(node); @emitter.mov_rax(2); end
  def gen_SIGTERM(node); @emitter.mov_rax(15); end
  def gen_SIGKILL(node); @emitter.mov_rax(9); end
end
