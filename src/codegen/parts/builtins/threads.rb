# Threading support for Linux x86-64
# Uses clone() syscall for threads

module BuiltinThreads
  # thread_create(fn_ptr, stack_ptr, arg) - create new thread
  # Returns thread ID (0 in child, tid in parent)
  def gen_thread_create(node)
    return unless @target_os == :linux
    
    # Allocate stack for thread (use provided stack pointer)
    eval_expression(node[:args][1]) # stack top
    @emitter.emit([0x49, 0x89, 0xc4]) # mov r12, rax (save stack)
    
    eval_expression(node[:args][2]) # arg
    @emitter.emit([0x49, 0x89, 0xc5]) # mov r13, rax (save arg)
    
    eval_expression(node[:args][0]) # fn_ptr
    @emitter.emit([0x49, 0x89, 0xc6]) # mov r14, rax (save fn)
    
    # Setup clone flags: CLONE_VM | CLONE_FS | CLONE_FILES | CLONE_SIGHAND | CLONE_THREAD | CLONE_SYSVSEM
    # = 0x100 | 0x200 | 0x400 | 0x800 | 0x10000 | 0x40000 = 0x50F00
    @emitter.emit([0x48, 0xc7, 0xc7, 0x00, 0x0f, 0x05, 0x00]) # mov rdi, 0x50F00
    
    # Stack pointer
    @emitter.emit([0x4c, 0x89, 0xe6]) # mov rsi, r12
    
    # parent_tid, child_tid, tls = 0
    @emitter.emit([0x48, 0x31, 0xd2]) # xor rdx, rdx
    @emitter.emit([0x4d, 0x31, 0xd2]) # xor r10, r10
    @emitter.emit([0x4d, 0x31, 0xc0]) # xor r8, r8
    
    @emitter.emit([0xb8, 0x38, 0x00, 0x00, 0x00]) # mov eax, 56 (clone)
    @emitter.emit([0x0f, 0x05])
    
    # Check if child (rax == 0)
    @emitter.emit([0x48, 0x85, 0xc0]) # test rax, rax
    patch_pos = @emitter.current_pos
    @emitter.emit([0x75, 0x00]) # jnz parent (patch later)
    
    # Child: call function with arg
    @emitter.emit([0x4c, 0x89, 0xef]) # mov rdi, r13 (arg)
    @emitter.emit([0x41, 0xff, 0xd6]) # call r14 (fn)
    
    # Child: exit thread
    @emitter.emit([0x48, 0x89, 0xc7]) # mov rdi, rax (exit code)
    @emitter.emit([0xb8, 0x3c, 0x00, 0x00, 0x00]) # mov eax, 60 (exit)
    @emitter.emit([0x0f, 0x05])
    
    # Patch jump
    offset = @emitter.current_pos - (patch_pos + 2)
    @emitter.bytes[patch_pos + 1] = offset & 0xFF
    
    # Parent: rax = child tid (already in rax)
  end

  # thread_exit(code) - exit current thread
  def gen_thread_exit(node)
    return unless @target_os == :linux
    eval_expression(node[:args][0])
    @emitter.emit([0x48, 0x89, 0xc7]) # mov rdi, rax
    @emitter.emit([0xb8, 0x3c, 0x00, 0x00, 0x00]) # mov eax, 60 (exit)
    @emitter.emit([0x0f, 0x05])
  end

  # usleep(microseconds) - sleep for microseconds
  def gen_usleep(node)
    return unless @target_os == :linux
    eval_expression(node[:args][0])
    
    # Convert microseconds to nanoseconds (* 1000)
    @emitter.emit([0x48, 0x69, 0xc0, 0xe8, 0x03, 0x00, 0x00]) # imul rax, 1000
    
    # Build timespec on stack: {tv_sec=0, tv_nsec=rax}
    @emitter.emit([0x48, 0x83, 0xec, 0x10]) # sub rsp, 16
    @emitter.emit([0x48, 0xc7, 0x04, 0x24, 0x00, 0x00, 0x00, 0x00]) # mov [rsp], 0 (sec)
    @emitter.emit([0x48, 0x89, 0x44, 0x24, 0x08]) # mov [rsp+8], rax (nsec)
    
    # nanosleep(&timespec, NULL)
    @emitter.emit([0x48, 0x89, 0xe7]) # mov rdi, rsp
    @emitter.emit([0x48, 0x31, 0xf6]) # xor rsi, rsi
    @emitter.emit([0xb8, 0x23, 0x00, 0x00, 0x00]) # mov eax, 35 (nanosleep)
    @emitter.emit([0x0f, 0x05])
    
    @emitter.emit([0x48, 0x83, 0xc4, 0x10]) # add rsp, 16
  end

  # sleep(seconds) - sleep for seconds
  def gen_sleep(node)
    return unless @target_os == :linux
    eval_expression(node[:args][0])
    
    # Build timespec on stack
    @emitter.emit([0x48, 0x83, 0xec, 0x10]) # sub rsp, 16
    @emitter.emit([0x48, 0x89, 0x04, 0x24]) # mov [rsp], rax (sec)
    @emitter.emit([0x48, 0xc7, 0x44, 0x24, 0x08, 0x00, 0x00, 0x00, 0x00]) # mov [rsp+8], 0 (nsec)
    
    @emitter.emit([0x48, 0x89, 0xe7]) # mov rdi, rsp
    @emitter.emit([0x48, 0x31, 0xf6]) # xor rsi, rsi
    @emitter.emit([0xb8, 0x23, 0x00, 0x00, 0x00]) # mov eax, 35 (nanosleep)
    @emitter.emit([0x0f, 0x05])
    
    @emitter.emit([0x48, 0x83, 0xc4, 0x10]) # add rsp, 16
  end

  # alloc_stack(size) - allocate thread stack using mmap
  def gen_alloc_stack(node)
    return unless @target_os == :linux
    eval_expression(node[:args][0]) # size
    @emitter.emit([0x48, 0x89, 0xc6]) # mov rsi, rax (len)
    
    # mmap(NULL, size, PROT_READ|PROT_WRITE, MAP_PRIVATE|MAP_ANONYMOUS|MAP_STACK, -1, 0)
    @emitter.emit([0x48, 0x31, 0xff]) # xor rdi, rdi (addr = NULL)
    @emitter.emit([0xba, 0x03, 0x00, 0x00, 0x00]) # mov edx, 3 (PROT_READ|PROT_WRITE)
    @emitter.emit([0x41, 0xba, 0x22, 0x01, 0x00, 0x00]) # mov r10d, 0x122 (MAP_PRIVATE|MAP_ANON|MAP_STACK)
    @emitter.emit([0x49, 0xc7, 0xc0, 0xff, 0xff, 0xff, 0xff]) # mov r8, -1
    @emitter.emit([0x4d, 0x31, 0xc9]) # xor r9, r9
    @emitter.emit([0xb8, 0x09, 0x00, 0x00, 0x00]) # mov eax, 9 (mmap)
    @emitter.emit([0x0f, 0x05])
    
    # Return pointer to TOP of stack (stack grows down)
    # rax = base, add size to get top
    @emitter.emit([0x50]) # push rax (save base)
    eval_expression(node[:args][0])
    @emitter.emit([0x5a]) # pop rdx
    @emitter.emit([0x48, 0x01, 0xd0]) # add rax, rdx
  end
  # clone(fn, stack, flags, arg) - create thread
  # Simplified version using clone syscall
  def gen_clone(node)
    return unless @target_os == :linux
    
    # flags = CLONE_VM | CLONE_FS | CLONE_FILES | CLONE_SIGHAND | CLONE_THREAD
    # = 0x100 | 0x200 | 0x400 | 0x800 | 0x10000 = 0x10F00
    eval_expression(node[:args][0]) # flags
    @emitter.emit([0x48, 0x89, 0xc7]) # mov rdi, rax
    
    eval_expression(node[:args][1]) # stack
    @emitter.emit([0x48, 0x89, 0xc6]) # mov rsi, rax
    
    # parent_tid, child_tid, tls = 0
    @emitter.emit([0x48, 0x31, 0xd2]) # xor rdx, rdx
    @emitter.emit([0x4d, 0x31, 0xd2]) # xor r10, r10
    @emitter.emit([0x4d, 0x31, 0xc0]) # xor r8, r8
    
    @emitter.emit([0xb8, 0x38, 0x00, 0x00, 0x00]) # mov eax, 56 (clone)
    @emitter.emit([0x0f, 0x05])
  end

  # futex(addr, op, val) - fast userspace mutex
  def gen_futex(node)
    return unless @target_os == :linux
    
    eval_expression(node[:args][0]) # addr
    @emitter.emit([0x48, 0x89, 0xc7]) # mov rdi, rax
    
    eval_expression(node[:args][1]) # op
    @emitter.emit([0x48, 0x89, 0xc6]) # mov rsi, rax
    
    eval_expression(node[:args][2]) # val
    @emitter.emit([0x48, 0x89, 0xc2]) # mov rdx, rax
    
    # timeout, addr2, val3 = 0
    @emitter.emit([0x4d, 0x31, 0xd2]) # xor r10, r10
    @emitter.emit([0x4d, 0x31, 0xc0]) # xor r8, r8
    @emitter.emit([0x4d, 0x31, 0xc9]) # xor r9, r9
    
    @emitter.emit([0xb8, 0xca, 0x00, 0x00, 0x00]) # mov eax, 202 (futex)
    @emitter.emit([0x0f, 0x05])
  end

  # Futex operations
  def gen_FUTEX_WAIT(node); @emitter.mov_rax(0); end
  def gen_FUTEX_WAKE(node); @emitter.mov_rax(1); end

  # atomic_load(ptr) - atomic load
  def gen_atomic_load(node)
    eval_expression(node[:args][0])
    @emitter.emit([0x48, 0x8b, 0x00]) # mov rax, [rax]
  end

  # atomic_store(ptr, val) - atomic store
  def gen_atomic_store(node)
    eval_expression(node[:args][1]) # val first
    @emitter.emit([0x49, 0x89, 0xc4]) # mov r12, rax
    eval_expression(node[:args][0]) # ptr
    @emitter.emit([0x4c, 0x89, 0x20]) # mov [rax], r12
  end

  # atomic_add(ptr, val) - atomic add, returns old value
  def gen_atomic_add(node)
    eval_expression(node[:args][1]) # val
    @emitter.emit([0x49, 0x89, 0xc4]) # mov r12, rax
    eval_expression(node[:args][0]) # ptr
    @emitter.emit([0x48, 0x89, 0xc7]) # mov rdi, rax
    @emitter.emit([0x4c, 0x89, 0xe0]) # mov rax, r12
    # lock xadd [rdi], rax
    @emitter.emit([0xf0, 0x48, 0x0f, 0xc1, 0x07])
  end

  # atomic_sub(ptr, val) - atomic subtract
  def gen_atomic_sub(node)
    eval_expression(node[:args][1]) # val
    @emitter.emit([0x48, 0xf7, 0xd8]) # neg rax
    @emitter.emit([0x49, 0x89, 0xc4]) # mov r12, rax
    eval_expression(node[:args][0]) # ptr
    @emitter.emit([0x48, 0x89, 0xc7]) # mov rdi, rax
    @emitter.emit([0x4c, 0x89, 0xe0]) # mov rax, r12
    @emitter.emit([0xf0, 0x48, 0x0f, 0xc1, 0x07]) # lock xadd
  end

  # atomic_cas(ptr, expected, desired) - compare and swap
  # Returns old value
  def gen_atomic_cas(node)
    eval_expression(node[:args][2]) # desired
    @emitter.emit([0x49, 0x89, 0xc4]) # mov r12, rax
    eval_expression(node[:args][1]) # expected -> rax
    eval_expression(node[:args][0]) # ptr
    @emitter.emit([0x48, 0x89, 0xc7]) # mov rdi, rax
    @emitter.emit([0x4c, 0x89, 0xe1]) # mov rcx, r12
    # lock cmpxchg [rdi], rcx
    @emitter.emit([0xf0, 0x48, 0x0f, 0xb1, 0x0f])
  end

  # spin_lock(ptr) - simple spinlock
  def gen_spin_lock(node)
    eval_expression(node[:args][0])
    @emitter.emit([0x48, 0x89, 0xc7]) # mov rdi, rax
    
    # retry:
    loop_start = @emitter.current_pos
    @emitter.emit([0xb8, 0x01, 0x00, 0x00, 0x00]) # mov eax, 1
    # lock xchg [rdi], eax
    @emitter.emit([0xf0, 0x87, 0x07])
    # test eax, eax
    @emitter.emit([0x85, 0xc0])
    # jnz retry
    offset = loop_start - (@emitter.current_pos + 2)
    @emitter.emit([0x75, offset & 0xFF])
    
    @emitter.emit([0x48, 0x31, 0xc0]) # xor rax, rax (return 0)
  end

  # spin_unlock(ptr) - release spinlock
  def gen_spin_unlock(node)
    eval_expression(node[:args][0])
    @emitter.emit([0x48, 0xc7, 0x00, 0x00, 0x00, 0x00, 0x00]) # mov qword [rax], 0
    @emitter.emit([0x48, 0x31, 0xc0]) # xor rax, rax
  end

  # Clone flags
  def gen_CLONE_VM(node); @emitter.mov_rax(0x100); end
  def gen_CLONE_FS(node); @emitter.mov_rax(0x200); end
  def gen_CLONE_FILES(node); @emitter.mov_rax(0x400); end
  def gen_CLONE_SIGHAND(node); @emitter.mov_rax(0x800); end
  def gen_CLONE_THREAD(node); @emitter.mov_rax(0x10000); end
end
