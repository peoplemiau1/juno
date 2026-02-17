# fs_ops.rb - File system related syscalls

module BuiltinFS
  def gen_mkdir(node)
    if node[:args][1] then eval_expression(node[:args][1]) else @emitter.mov_rax(0o755) end
    @emitter.push_reg(0) # mode
    eval_expression(node[:args][0]) # path

    if @arch == :aarch64
       @emitter.pop_reg(2) # mode
       @emitter.mov_reg_reg(1, 0) # path
       @emitter.mov_reg_imm(0, 0xffffff9c) # AT_FDCWD
       emit_syscall(:mkdirat)
    else
       @emitter.pop_reg(6) # rsi = mode
       @emitter.mov_reg_reg(7, 0) # rdi = path
       emit_syscall(:mkdir)
    end
  end

  def gen_rmdir(node)
    eval_expression(node[:args][0])
    if @arch == :aarch64
       @emitter.mov_reg_reg(1, 0) # path
       @emitter.mov_reg_imm(0, 0xffffff9c) # AT_FDCWD
       @emitter.mov_reg_imm(2, 0x200) # AT_REMOVEDIR
       emit_syscall(:unlinkat)
    else
       @emitter.mov_reg_reg(7, 0)
       emit_syscall(:rmdir)
    end
  end

  def gen_unlink(node)
    eval_expression(node[:args][0])
    if @arch == :aarch64
       @emitter.mov_reg_reg(1, 0) # path
       @emitter.mov_reg_imm(0, 0xffffff9c) # AT_FDCWD
       @emitter.mov_reg_imm(2, 0) # flags=0
       emit_syscall(:unlinkat)
    else
       @emitter.mov_reg_reg(7, 0)
       emit_syscall(:unlink)
    end
  end

  def gen_chmod(node)
    eval_expression(node[:args][1]); @emitter.push_reg(0) # mode
    eval_expression(node[:args][0]) # path
    if @arch == :aarch64
       @emitter.pop_reg(2) # mode
       @emitter.mov_reg_reg(1, 0) # path
       @emitter.mov_reg_imm(0, 0xffffff9c) # AT_FDCWD
       # fchmodat
       @emitter.mov_x8(34); @emitter.syscall
    else
       @emitter.pop_reg(6)
       @emitter.mov_reg_reg(7, 0)
       emit_syscall(:chmod)
    end
  end

  def gen_chdir(node)
    eval_expression(node[:args][0])
    @emitter.mov_reg_reg(@arch == :aarch64 ? 0 : 7, 0)
    emit_syscall(:chdir)
  end

  def gen_getcwd(node)
    eval_expression(node[:args][1]); @emitter.push_reg(0) # size
    eval_expression(node[:args][0]) # buf
    @emitter.pop_reg(@arch == :aarch64 ? 1 : 6)
    @emitter.mov_reg_reg(@arch == :aarch64 ? 0 : 7, 0)
    emit_syscall(:getcwd)
  end
end
