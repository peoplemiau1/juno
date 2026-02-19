module SyscallMapper
  SYSCALLS = {
    read:     { x86_64: 0,   aarch64: 63  },
    write:    { x86_64: 1,   aarch64: 64  },
    open:     { x86_64: 2,   aarch64: 56  }, # openat on arm
    openat:   { x86_64: 257, aarch64: 56  },
    close:    { x86_64: 3,   aarch64: 57  },
    stat:     { x86_64: 4,   aarch64: 79  }, # newfstatat on arm
    fstat:    { x86_64: 5,   aarch64: 80  },
    access:   { x86_64: 21,  aarch64: 33  }, # faccessat on arm
    lseek:    { x86_64: 8,   aarch64: 62  },
    mmap:     { x86_64: 9,   aarch64: 222 },
    munmap:   { x86_64: 11,  aarch64: 215 },
    rt_sigaction: { x86_64: 13, aarch64: 134 },
    rt_sigreturn: { x86_64: 15, aarch64: 139 },
    ioctl:    { x86_64: 16,  aarch64: 29  },
    pipe:     { x86_64: 22,  aarch64: 59  }, # pipe2 on arm
    dup:      { x86_64: 32,  aarch64: 23  },
    dup2:     { x86_64: 33,  aarch64: 24  },
    nanosleep:{ x86_64: 35,  aarch64: 101 },
    getpid:   { x86_64: 39,  aarch64: 172 },
    socket:   { x86_64: 41,  aarch64: 198 },
    connect:  { x86_64: 42,  aarch64: 203 },
    accept:   { x86_64: 43,  aarch64: 202 },
    sendto:   { x86_64: 44,  aarch64: 206 },
    recvfrom: { x86_64: 45,  aarch64: 207 },
    bind:     { x86_64: 49,  aarch64: 200 },
    listen:   { x86_64: 50,  aarch64: 201 },
    fork:     { x86_64: 57,  aarch64: 220 }, # clone on arm
    execve:   { x86_64: 59,  aarch64: 221 },
    exit:     { x86_64: 60,  aarch64: 93  },
    kill:     { x86_64: 62,  aarch64: 129 },
    uname:    { x86_64: 63,  aarch64: 160 },
    mkdir:    { x86_64: 83,  aarch64: 34  }, # mkdirat on arm
    mkdirat:  { x86_64: 258, aarch64: 34  },
    rmdir:    { x86_64: 84,  aarch64: 35  }, # unlinkat on arm (with flag)
    unlink:   { x86_64: 87,  aarch64: 35  }, # unlinkat on arm
    unlinkat: { x86_64: 263, aarch64: 35  },
    wait4:    { x86_64: 61,  aarch64: 260 },
    wait:     { x86_64: 61,  aarch64: 260 },
    getuid:   { x86_64: 102, aarch64: 174 },
    getgid:   { x86_64: 104, aarch64: 176 },
    getppid:  { x86_64: 110, aarch64: 173 },
    getcwd:   { x86_64: 79,  aarch64: 17  },
    time:     { x86_64: 201, aarch64: 169 }, # 169 is gettimeofday on arm
    memfd_create: { x86_64: 319, aarch64: 279 }
  }

  def sys_id(name)
    id = SYSCALLS[name]
    unless id
      raise "Unknown syscall: #{name}"
    end
    id[@arch] || id[:x86_64]
  end

  def emit_syscall(name)
    id = sys_id(name)
    if @arch == :aarch64
      @emitter.mov_x8(id)
      @emitter.syscall
    else
      @emitter.emit([0xb8] + [id].pack("L<").bytes) # mov eax, id
      @emitter.syscall
    end
  end
end
