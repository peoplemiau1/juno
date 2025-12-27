# Threading support for Linux x86-64
# Uses clone() syscall for threads

module BuiltinThreads
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
