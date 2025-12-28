# System calls for Linux x86-64
# Provides low-level OS access

module BuiltinSyscalls
  # fork() - create child process
  # Returns: 0 in child, child PID in parent, -1 on error
  def gen_fork(node)
    return unless @target_os == :linux
    @emitter.emit([0xb8, 0x39, 0x00, 0x00, 0x00]) # mov eax, 57 (fork)
    @emitter.emit([0x0f, 0x05]) # syscall
  end

  # getpid() - get process ID
  def gen_getpid(node)
    return unless @target_os == :linux
    @emitter.emit([0xb8, 0x27, 0x00, 0x00, 0x00]) # mov eax, 39 (getpid)
    @emitter.emit([0x0f, 0x05])
  end

  # getuid() - get user ID
  def gen_getuid(node)
    return unless @target_os == :linux
    @emitter.emit([0xb8, 0x66, 0x00, 0x00, 0x00]) # mov eax, 102 (getuid)
    @emitter.emit([0x0f, 0x05])
  end

  # getppid() - get parent process ID
  def gen_getppid(node)
    return unless @target_os == :linux
    @emitter.emit([0xb8, 0x6e, 0x00, 0x00, 0x00]) # mov eax, 110 (getppid)
    @emitter.emit([0x0f, 0x05])
  end

  # getgid() - get group ID
  def gen_getgid(node)
    return unless @target_os == :linux
    @emitter.emit([0xb8, 0x68, 0x00, 0x00, 0x00]) # mov eax, 104 (getgid)
    @emitter.emit([0x0f, 0x05])
  end

  # kill(pid, sig) - send signal to process
  def gen_kill(node)
    return unless @target_os == :linux
    eval_expression(node[:args][0])
    @emitter.emit([0x48, 0x89, 0xc7]) # mov rdi, rax (pid)
    eval_expression(node[:args][1])
    @emitter.emit([0x48, 0x89, 0xc6]) # mov rsi, rax (sig)
    @emitter.emit([0xb8, 0x3e, 0x00, 0x00, 0x00]) # mov eax, 62 (kill)
    @emitter.emit([0x0f, 0x05])
  end

  # wait(status_ptr) - wait for child process
  # Returns: PID of terminated child
  def gen_wait(node)
    return unless @target_os == :linux
    # wait4(-1, status, 0, NULL)
    @emitter.emit([0x48, 0xc7, 0xc7, 0xff, 0xff, 0xff, 0xff]) # mov rdi, -1
    if node[:args] && node[:args][0]
      eval_expression(node[:args][0])
      @emitter.emit([0x48, 0x89, 0xc6]) # mov rsi, rax
    else
      @emitter.emit([0x48, 0x31, 0xf6]) # xor rsi, rsi
    end
    @emitter.emit([0x48, 0x31, 0xd2]) # xor rdx, rdx (options=0)
    @emitter.emit([0x4d, 0x31, 0xd2]) # xor r10, r10 (rusage=NULL)
    @emitter.emit([0xb8, 0x3d, 0x00, 0x00, 0x00]) # mov eax, 61 (wait4)
    @emitter.emit([0x0f, 0x05])
  end

  # pipe(fds) - create pipe
  # fds is array of 2 ints: fds[0]=read, fds[1]=write
  def gen_pipe(node)
    return unless @target_os == :linux
    eval_expression(node[:args][0])
    @emitter.emit([0x48, 0x89, 0xc7]) # mov rdi, rax
    @emitter.emit([0xb8, 0x16, 0x00, 0x00, 0x00]) # mov eax, 22 (pipe)
    @emitter.emit([0x0f, 0x05])
  end

  # dup(fd) - duplicate file descriptor
  def gen_dup(node)
    return unless @target_os == :linux
    eval_expression(node[:args][0])
    @emitter.emit([0x48, 0x89, 0xc7]) # mov rdi, rax
    @emitter.emit([0xb8, 0x20, 0x00, 0x00, 0x00]) # mov eax, 32 (dup)
    @emitter.emit([0x0f, 0x05])
  end

  # dup2(oldfd, newfd) - duplicate to specific fd
  def gen_dup2(node)
    return unless @target_os == :linux
    eval_expression(node[:args][0])
    @emitter.emit([0x48, 0x89, 0xc7]) # mov rdi, rax
    eval_expression(node[:args][1])
    @emitter.emit([0x48, 0x89, 0xc6]) # mov rsi, rax
    @emitter.emit([0xb8, 0x21, 0x00, 0x00, 0x00]) # mov eax, 33 (dup2)
    @emitter.emit([0x0f, 0x05])
  end

  # mkdir(path, mode) - create directory
  def gen_mkdir(node)
    return unless @target_os == :linux
    eval_expression(node[:args][0])
    @emitter.emit([0x48, 0x89, 0xc7]) # mov rdi, rax (path)
    if node[:args][1]
      eval_expression(node[:args][1])
    else
      @emitter.mov_rax(0o755)
    end
    @emitter.emit([0x48, 0x89, 0xc6]) # mov rsi, rax (mode)
    @emitter.emit([0xb8, 0x53, 0x00, 0x00, 0x00]) # mov eax, 83 (mkdir)
    @emitter.emit([0x0f, 0x05])
  end

  # rmdir(path) - remove directory
  def gen_rmdir(node)
    return unless @target_os == :linux
    eval_expression(node[:args][0])
    @emitter.emit([0x48, 0x89, 0xc7]) # mov rdi, rax
    @emitter.emit([0xb8, 0x54, 0x00, 0x00, 0x00]) # mov eax, 84 (rmdir)
    @emitter.emit([0x0f, 0x05])
  end

  # unlink(path) - delete file
  def gen_unlink(node)
    return unless @target_os == :linux
    eval_expression(node[:args][0])
    @emitter.emit([0x48, 0x89, 0xc7]) # mov rdi, rax
    @emitter.emit([0xb8, 0x57, 0x00, 0x00, 0x00]) # mov eax, 87 (unlink)
    @emitter.emit([0x0f, 0x05])
  end

  # chmod(path, mode) - change file permissions
  def gen_chmod(node)
    return unless @target_os == :linux
    eval_expression(node[:args][0])
    @emitter.emit([0x48, 0x89, 0xc7]) # mov rdi, rax
    eval_expression(node[:args][1])
    @emitter.emit([0x48, 0x89, 0xc6]) # mov rsi, rax
    @emitter.emit([0xb8, 0x5a, 0x00, 0x00, 0x00]) # mov eax, 90 (chmod)
    @emitter.emit([0x0f, 0x05])
  end

  # chdir(path) - change directory
  def gen_chdir(node)
    return unless @target_os == :linux
    eval_expression(node[:args][0])
    @emitter.emit([0x48, 0x89, 0xc7]) # mov rdi, rax
    @emitter.emit([0xb8, 0x50, 0x00, 0x00, 0x00]) # mov eax, 80 (chdir)
    @emitter.emit([0x0f, 0x05])
  end

  # getcwd(buf, size) - get current directory
  def gen_getcwd(node)
    return unless @target_os == :linux
    eval_expression(node[:args][0])
    @emitter.emit([0x48, 0x89, 0xc7]) # mov rdi, rax
    eval_expression(node[:args][1])
    @emitter.emit([0x48, 0x89, 0xc6]) # mov rsi, rax
    @emitter.emit([0xb8, 0x4f, 0x00, 0x00, 0x00]) # mov eax, 79 (getcwd)
    @emitter.emit([0x0f, 0x05])
  end

  # mmap(addr, len, prot, flags, fd, offset) - map memory
  # Common use: mmap(0, size, PROT_READ|PROT_WRITE, MAP_PRIVATE|MAP_ANONYMOUS, -1, 0)
  def gen_mmap(node)
    return unless @target_os == :linux
    
    # addr
    eval_expression(node[:args][0])
    @emitter.emit([0x48, 0x89, 0xc7]) # mov rdi, rax
    
    # len
    eval_expression(node[:args][1])
    @emitter.emit([0x48, 0x89, 0xc6]) # mov rsi, rax
    
    # prot
    eval_expression(node[:args][2])
    @emitter.emit([0x48, 0x89, 0xc2]) # mov rdx, rax
    
    # flags
    eval_expression(node[:args][3])
    @emitter.emit([0x49, 0x89, 0xc2]) # mov r10, rax
    
    # fd
    eval_expression(node[:args][4])
    @emitter.emit([0x49, 0x89, 0xc0]) # mov r8, rax
    
    # offset
    eval_expression(node[:args][5])
    @emitter.emit([0x49, 0x89, 0xc1]) # mov r9, rax
    
    @emitter.emit([0xb8, 0x09, 0x00, 0x00, 0x00]) # mov eax, 9 (mmap)
    @emitter.emit([0x0f, 0x05])
  end

  # munmap(addr, len) - unmap memory
  def gen_munmap(node)
    return unless @target_os == :linux
    eval_expression(node[:args][0])
    @emitter.emit([0x48, 0x89, 0xc7]) # mov rdi, rax
    eval_expression(node[:args][1])
    @emitter.emit([0x48, 0x89, 0xc6]) # mov rsi, rax
    @emitter.emit([0xb8, 0x0b, 0x00, 0x00, 0x00]) # mov eax, 11 (munmap)
    @emitter.emit([0x0f, 0x05])
  end

  # memcpy(dest, src, n) - copy memory
  def gen_memcpy(node)
    eval_expression(node[:args][0])
    @emitter.emit([0x48, 0x89, 0xc7]) # mov rdi, rax (dest)
    eval_expression(node[:args][1])
    @emitter.emit([0x48, 0x89, 0xc6]) # mov rsi, rax (src)
    eval_expression(node[:args][2])
    @emitter.emit([0x48, 0x89, 0xc1]) # mov rcx, rax (count)
    
    # Save dest for return value
    @emitter.emit([0x57]) # push rdi
    
    # rep movsb
    @emitter.emit([0xf3, 0xa4])
    
    # Return dest
    @emitter.emit([0x58]) # pop rax
  end

  # memset(dest, val, n) - set memory
  def gen_memset(node)
    eval_expression(node[:args][0])
    @emitter.emit([0x48, 0x89, 0xc7]) # mov rdi, rax (dest)
    eval_expression(node[:args][1])
    @emitter.emit([0x48, 0x89, 0xc6]) # mov rsi, rax (val) - save
    eval_expression(node[:args][2])
    @emitter.emit([0x48, 0x89, 0xc1]) # mov rcx, rax (count)
    @emitter.emit([0x48, 0x89, 0xf0]) # mov rax, rsi (val to al)
    
    # Save dest for return value
    @emitter.emit([0x57]) # push rdi
    
    # rep stosb
    @emitter.emit([0xf3, 0xaa])
    
    # Return dest
    @emitter.emit([0x58]) # pop rax
  end

  # execve(path, argv, envp) - execute program
  def gen_execve(node)
    return unless @target_os == :linux
    eval_expression(node[:args][0])
    @emitter.emit([0x48, 0x89, 0xc7]) # mov rdi, rax (path)
    eval_expression(node[:args][1])
    @emitter.emit([0x48, 0x89, 0xc6]) # mov rsi, rax (argv)
    eval_expression(node[:args][2])
    @emitter.emit([0x48, 0x89, 0xc2]) # mov rdx, rax (envp)
    @emitter.emit([0xb8, 0x3b, 0x00, 0x00, 0x00]) # mov eax, 59 (execve)
    @emitter.emit([0x0f, 0x05])
  end

  # Constants for mmap
  # lseek(fd, offset, whence) - reposition file offset
  # whence: SEEK_SET=0, SEEK_CUR=1, SEEK_END=2
  def gen_lseek(node)
    return unless @target_os == :linux
    eval_expression(node[:args][0])
    @emitter.emit([0x48, 0x89, 0xc7])  # mov rdi, rax (fd)
    eval_expression(node[:args][1])
    @emitter.emit([0x48, 0x89, 0xc6])  # mov rsi, rax (offset)
    eval_expression(node[:args][2])
    @emitter.emit([0x48, 0x89, 0xc2])  # mov rdx, rax (whence)
    @emitter.emit([0xb8, 0x08, 0x00, 0x00, 0x00])  # mov eax, 8 (lseek)
    @emitter.emit([0x0f, 0x05])
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
    
    # name (can be empty string)
    if args[0]
      eval_expression(args[0])
      @emitter.emit([0x48, 0x89, 0xc7])  # mov rdi, rax
    else
      @emitter.emit([0x48, 0x31, 0xff])  # xor rdi, rdi
    end
    
    # flags
    if args[1]
      eval_expression(args[1])
      @emitter.emit([0x48, 0x89, 0xc6])  # mov rsi, rax
    else
      @emitter.emit([0x48, 0x31, 0xf6])  # xor rsi, rsi
    end
    
    @emitter.emit([0xb8, 0x3f, 0x01, 0x00, 0x00])  # mov eax, 319 (memfd_create)
    @emitter.emit([0x0f, 0x05])  # syscall
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
