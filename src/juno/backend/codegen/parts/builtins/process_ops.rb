module BuiltinProcess
  def gen_fork(node)
    emit_syscall(:fork)
  end

  def gen_execve(node)
    eval_expression(node[:args][2]); @emitter.push_reg(0)
    eval_expression(node[:args][1]); @emitter.push_reg(0)
    eval_expression(node[:args][0])
    @emitter.pop_reg(@arch == :aarch64 ? 1 : 6)
    @emitter.pop_reg(@arch == :aarch64 ? 2 : 2)
    @emitter.mov_reg_reg(@arch == :aarch64 ? 0 : 7, 0)
    emit_syscall(:execve)
  end

  def gen_wait(node)
    @emitter.mov_reg_imm(0, 0); @emitter.emit_sub_rax(1); @emitter.push_reg(0)
    if node[:args] && node[:args][0] then eval_expression(node[:args][0]) else @emitter.mov_rax(0) end
    @emitter.push_reg(0)
    @emitter.mov_reg_imm(0, 0); @emitter.push_reg(0)
    @emitter.mov_reg_imm(0, 0); @emitter.push_reg(0)

    @emitter.pop_reg(@arch == :aarch64 ? 3 : 10)
    @emitter.pop_reg(@arch == :aarch64 ? 2 : 2)
    @emitter.pop_reg(@arch == :aarch64 ? 1 : 6)
    @emitter.pop_reg(@arch == :aarch64 ? 0 : 7)
    emit_syscall(:wait4)
  end

  def gen_kill(node)
    eval_expression(node[:args][0]); @emitter.push_reg(0)
    eval_expression(node[:args][1]); @emitter.mov_reg_reg(@arch == :aarch64 ? 1 : 6, 0)
    @emitter.pop_reg(@arch == :aarch64 ? 0 : 7)
    emit_syscall(:kill)
  end

  def gen_getpid(node); emit_syscall(:getpid); end
  def gen_getppid(node); emit_syscall(:getppid); end
  def gen_getuid(node); emit_syscall(:getuid); end
  def gen_getgid(node); emit_syscall(:getgid); end
end
