# System calls for Linux x86-64
# Provides low-level OS access

module BuiltinSyscalls
  # fork() - create child process
  # Returns: 0 in child, child PID in parent, -1 on error
  def gen_fork(node)
    return unless @target_os == :linux
    if @arch == :aarch64
      # On ARM64 fork is often implemented via clone
      # clone(SIGCHLD, 0, 0, 0, 0)
      @emitter.mov_rax(17) # SIGCHLD
      @emitter.mov_reg_reg(0, 0) # x0
      @emitter.mov_rax(0)
      @emitter.mov_reg_reg(1, 0); @emitter.mov_reg_reg(2, 0); @emitter.mov_reg_reg(3, 0); @emitter.mov_reg_reg(4, 0)
      emit_syscall(:fork)
    else
      emit_syscall(:fork)
    end
  end

  # getpid() - get process ID
  def gen_getpid(node)
    return unless @target_os == :linux
    emit_syscall(:getpid)
  end

  # getuid() - get user ID
  def gen_getuid(node)
    return unless @target_os == :linux
    emit_syscall(:getuid)
  end

  # getppid() - get parent process ID
  def gen_getppid(node)
    return unless @target_os == :linux
    emit_syscall(:getppid)
  end

  # getgid() - get group ID
  def gen_getgid(node)
    return unless @target_os == :linux
    emit_syscall(:getgid)
  end

  # kill(pid, sig) - send signal to process
  def gen_kill(node)
    return unless @target_os == :linux
    eval_expression(node[:args][0]); @emitter.push_reg(0)
    eval_expression(node[:args][1]); @emitter.mov_reg_reg(@arch == :aarch64 ? 1 : 6, 0)
    @emitter.pop_reg(@arch == :aarch64 ? 0 : 7)
    emit_syscall(:kill)
  end

  # wait(status_ptr) - wait for child process
  # Returns: PID of terminated child
  def gen_wait(node)
    return unless @target_os == :linux
    # wait4(-1, status, 0, NULL)
    @emitter.mov_rax(0); @emitter.emit_sub_rax(1); @emitter.push_reg(0) # rdi = -1
    if node[:args] && node[:args][0]
      eval_expression(node[:args][0])
    else
      @emitter.mov_rax(0)
    end
    @emitter.push_reg(0) # rsi = status
    @emitter.mov_rax(0); @emitter.push_reg(0) # rdx = options=0
    @emitter.mov_rax(0); @emitter.push_reg(0) # r10 = rusage=NULL

    @emitter.pop_reg(@arch == :aarch64 ? 3 : 10) # arg 4
    @emitter.pop_reg(@arch == :aarch64 ? 2 : 2)  # arg 3
    @emitter.pop_reg(@arch == :aarch64 ? 1 : 6)  # arg 2
    @emitter.pop_reg(@arch == :aarch64 ? 0 : 7)  # arg 1
    emit_syscall(:wait4)
  end

  # pipe(fds) - create pipe
  # fds is array of 2 ints: fds[0]=read, fds[1]=write
  def gen_pipe(node)
    return unless @target_os == :linux
    eval_expression(node[:args][0])
    if @arch == :aarch64
       @emitter.mov_reg_reg(0, 0)
       @emitter.mov_rax(0); @emitter.mov_reg_reg(1, 0) # flags=0
       emit_syscall(:pipe2)
    else
       @emitter.mov_reg_reg(7, 0)
       emit_syscall(:pipe)
    end
  end

  # dup(fd) - duplicate file descriptor
  def gen_dup(node)
    return unless @target_os == :linux
    eval_expression(node[:args][0])
    @emitter.mov_reg_reg(@arch == :aarch64 ? 0 : 7, 0)
    emit_syscall(:dup)
  end

  # dup2(oldfd, newfd) - duplicate to specific fd
  def gen_dup2(node)
    return unless @target_os == :linux
    eval_expression(node[:args][1]); @emitter.push_reg(0)
    eval_expression(node[:args][0])
    @emitter.pop_reg(@arch == :aarch64 ? 1 : 6)
    @emitter.mov_reg_reg(@arch == :aarch64 ? 0 : 7, 0)
    emit_syscall(:dup2)
  end

  # mkdir(path, mode) - create directory
  def gen_mkdir(node)
    return unless @target_os == :linux
    if node[:args][1]
      eval_expression(node[:args][1])
    else
      @emitter.mov_rax(0o755)
    end
    @emitter.push_reg(0) # mode
    eval_expression(node[:args][0]) # path

    if @arch == :aarch64
       @emitter.pop_reg(2) # mode
       @emitter.mov_reg_reg(1, 0) # path
       @emitter.mov_rax(0xffffff9c); @emitter.mov_reg_reg(0, 0) # AT_FDCWD
       emit_syscall(:mkdirat)
    else
       @emitter.pop_reg(6)
       @emitter.mov_reg_reg(7, 0)
       emit_syscall(:mkdir)
    end
  end

  # rmdir(path) - remove directory
  def gen_rmdir(node)
    return unless @target_os == :linux
    eval_expression(node[:args][0])
    if @arch == :aarch64
       @emitter.mov_reg_reg(1, 0) # path
       @emitter.mov_rax(0xffffff9c); @emitter.mov_reg_reg(0, 0) # AT_FDCWD
       @emitter.mov_rax(0x200); @emitter.mov_reg_reg(2, 0) # AT_REMOVEDIR
       emit_syscall(:unlinkat)
    else
       @emitter.mov_reg_reg(7, 0)
       emit_syscall(:rmdir)
    end
  end

  # unlink(path) - delete file
  def gen_unlink(node)
    return unless @target_os == :linux
    eval_expression(node[:args][0])
    if @arch == :aarch64
       @emitter.mov_reg_reg(1, 0) # path
       @emitter.mov_rax(0xffffff9c); @emitter.mov_reg_reg(0, 0) # AT_FDCWD
       @emitter.mov_rax(0); @emitter.mov_reg_reg(2, 0) # flags=0
       emit_syscall(:unlinkat)
    else
       @emitter.mov_reg_reg(7, 0)
       emit_syscall(:unlink)
    end
  end

  # chmod(path, mode) - change file permissions
  def gen_chmod(node)
    return unless @target_os == :linux
    eval_expression(node[:args][1]); @emitter.push_reg(0)
    eval_expression(node[:args][0])
    if @arch == :aarch64
       @emitter.pop_reg(2) # mode
       @emitter.mov_reg_reg(1, 0) # path
       @emitter.mov_rax(0xffffff9c); @emitter.mov_reg_reg(0, 0) # AT_FDCWD
       # arm64 uses fchmodat
       @emitter.mov_x8(34); @emitter.syscall # fchmodat
    else
       @emitter.pop_reg(6)
       @emitter.mov_reg_reg(7, 0)
       emit_syscall(:chmod)
    end
  end

  # chdir(path) - change directory
  def gen_chdir(node)
    return unless @target_os == :linux
    eval_expression(node[:args][0])
    @emitter.mov_reg_reg(@arch == :aarch64 ? 0 : 7, 0)
    emit_syscall(:chdir)
  end

  # getcwd(buf, size) - get current directory
  def gen_getcwd(node)
    return unless @target_os == :linux
    eval_expression(node[:args][1]); @emitter.push_reg(0)
    eval_expression(node[:args][0])
    @emitter.pop_reg(@arch == :aarch64 ? 1 : 6)
    @emitter.mov_reg_reg(@arch == :aarch64 ? 0 : 7, 0)
    emit_syscall(:getcwd)
  end

  # mmap(addr, len, prot, flags, fd, offset) - map memory
  # Common use: mmap(0, size, PROT_READ|PROT_WRITE, MAP_PRIVATE|MAP_ANONYMOUS, -1, 0)
  def gen_mmap(node)
    return unless @target_os == :linux
    
    # args: RDI, RSI, RDX, R10, R8, R9 (x86)
    # args: X0, X1, X2, X3, X4, X5 (ARM)
    eval_expression(node[:args][5]); @emitter.push_reg(0)
    eval_expression(node[:args][4]); @emitter.push_reg(0)
    eval_expression(node[:args][3]); @emitter.push_reg(0)
    eval_expression(node[:args][2]); @emitter.push_reg(0)
    eval_expression(node[:args][1]); @emitter.push_reg(0)
    eval_expression(node[:args][0])
    
    if @arch == :aarch64
       @emitter.pop_reg(1) # len
       @emitter.pop_reg(2) # prot
       @emitter.pop_reg(3) # flags
       @emitter.pop_reg(4) # fd
       @emitter.pop_reg(5) # offset
       # addr is already in X0
    else
       @emitter.pop_reg(6)  # rsi = len
       @emitter.pop_reg(2)  # rdx = prot
       @emitter.pop_reg(10) # r10 = flags
       @emitter.pop_reg(8)  # r8  = fd
       @emitter.pop_reg(9)  # r9  = offset
       @emitter.mov_reg_reg(7, 0) # rdi = addr
    end
    
    emit_syscall(:mmap)
  end

  # munmap(addr, len) - unmap memory
  def gen_munmap(node)
    return unless @target_os == :linux
    eval_expression(node[:args][0]); @emitter.push_reg(0)
    eval_expression(node[:args][1]); @emitter.mov_reg_reg(@arch == :aarch64 ? 1 : 6, 0)
    @emitter.pop_reg(@arch == :aarch64 ? 0 : 7)
    emit_syscall(:munmap)
  end

  # memcpy(dest, src, n) - copy memory
  def gen_memcpy(node)
    eval_expression(node[:args][2]); @emitter.push_reg(0) # n
    eval_expression(node[:args][1]); @emitter.push_reg(0) # src
    eval_expression(node[:args][0]) # dest
    @emitter.push_reg(0) # save dest for return
    @emitter.pop_reg(@arch == :aarch64 ? 0 : 7) # dest
    @emitter.pop_reg(@arch == :aarch64 ? 1 : 6) # src
    @emitter.pop_reg(@arch == :aarch64 ? 2 : 2) # n
    @emitter.memcpy
    @emitter.pop_reg(0) # return dest
  end

  # memset(dest, val, n) - set memory
  def gen_memset(node)
    eval_expression(node[:args][2]); @emitter.push_reg(0) # n
    eval_expression(node[:args][1]); @emitter.push_reg(0) # val
    eval_expression(node[:args][0]) # dest
    @emitter.push_reg(0) # save dest for return
    @emitter.pop_reg(@arch == :aarch64 ? 0 : 7) # dest
    @emitter.pop_reg(@arch == :aarch64 ? 1 : 0) # val
    @emitter.pop_reg(@arch == :aarch64 ? 2 : 2) # n
    @emitter.memset
    @emitter.pop_reg(0) # return dest
  end

  # execve(path, argv, envp) - execute program
  def gen_execve(node)
    return unless @target_os == :linux
    eval_expression(node[:args][2]); @emitter.push_reg(0)
    eval_expression(node[:args][1]); @emitter.push_reg(0)
    eval_expression(node[:args][0])
    @emitter.pop_reg(@arch == :aarch64 ? 1 : 6) # argv
    @emitter.pop_reg(@arch == :aarch64 ? 2 : 2) # envp
    @emitter.mov_reg_reg(@arch == :aarch64 ? 0 : 7, 0) # path
    emit_syscall(:execve)
  end

  # lseek(fd, offset, whence) - reposition file offset
  # whence: SEEK_SET=0, SEEK_CUR=1, SEEK_END=2
  def gen_lseek(node)
    return unless @target_os == :linux
    eval_expression(node[:args][2]); @emitter.push_reg(0)
    eval_expression(node[:args][1]); @emitter.push_reg(0)
    eval_expression(node[:args][0])
    @emitter.pop_reg(@arch == :aarch64 ? 1 : 6) # offset
    @emitter.pop_reg(@arch == :aarch64 ? 2 : 2) # whence
    @emitter.mov_reg_reg(@arch == :aarch64 ? 0 : 7, 0) # fd
    emit_syscall(:lseek)
  end

  # lseek whence constants
  def gen_SEEK_SET(node); @emitter.mov_rax(0); end
  def gen_SEEK_CUR(node); @emitter.mov_rax(1); end
  def gen_SEEK_END(node); @emitter.mov_rax(2); end

  # memfd_create(name, flags) - create anonymous file in memory
  # Returns: file descriptor on success, -1 on error
  # Flags: MFD_CLOEXEC = 1, MFD_ALLOW_SEALING = 2
  def gen_memfd_create(node)
    return unless @target_os == :linux
    
    args = node[:args] || []
    
    # name
    if args[0]
      eval_expression(args[0])
    else
      @emitter.mov_rax(0)
    end
    @emitter.push_reg(0) # arg1
    
    # flags
    if args[1]
      eval_expression(args[1])
    else
      @emitter.mov_rax(0)
    end
    @emitter.mov_reg_reg(@arch == :aarch64 ? 1 : 6, 0) # arg2
    @emitter.pop_reg(@arch == :aarch64 ? 0 : 7) # arg1
    
    emit_syscall(:memfd_create)
  end

  # memfd_create flags
  def gen_MFD_CLOEXEC(node); @emitter.mov_rax(1); end
  def gen_MFD_ALLOW_SEALING(node); @emitter.mov_rax(2); end

  # PROT_READ = 1, PROT_WRITE = 2, PROT_EXEC = 4
  # MAP_PRIVATE = 2, MAP_ANONYMOUS = 32
  def gen_PROT_READ(node); @emitter.mov_rax(1); end
  def gen_PROT_WRITE(node); @emitter.mov_rax(2); end
  def gen_PROT_EXEC(node); @emitter.mov_rax(4); end
  def gen_MAP_PRIVATE(node); @emitter.mov_rax(2); end
  def gen_MAP_ANONYMOUS(node); @emitter.mov_rax(32); end
  def gen_MAP_ANON(node); @emitter.mov_rax(32); end

  # Signal constants
  def gen_SIGTERM(node); @emitter.mov_rax(15); end
  def gen_SIGKILL(node); @emitter.mov_rax(9); end
  def gen_SIGINT(node); @emitter.mov_rax(2); end
  def gen_SIGUSR1(node); @emitter.mov_rax(10); end
  def gen_SIGUSR2(node); @emitter.mov_rax(12); end
end
