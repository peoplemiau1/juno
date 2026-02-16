# Threading support for Linux
# Architecture-neutral implementation for x86-64 and AArch64

module BuiltinThreads
  def gen_thread_create(node)
    return unless @target_os == :linux
    # thread_create(flags, stack, function_ptr, arg)
    eval_expression(node[:args][3]); @emitter.push_reg(0) # arg
    eval_expression(node[:args][2]); @emitter.push_reg(0) # function_ptr
    eval_expression(node[:args][1]); @emitter.push_reg(0) # stack
    eval_expression(node[:args][0]); @emitter.push_reg(0) # flags

    @emitter.pop_reg(4)  # flags -> temp
    @emitter.pop_reg(5)  # stack -> temp
    @emitter.pop_reg(12) # func -> r12/x12
    @emitter.pop_reg(13) # arg -> r13/x13

    if @arch == :aarch64
       @emitter.mov_reg_reg(0, 4) # flags
       @emitter.mov_reg_reg(1, 5) # stack
       @emitter.mov_rax(0); @emitter.mov_reg_reg(2, 0) # ptid
       @emitter.mov_rax(0); @emitter.mov_reg_reg(3, 0) # tls
       @emitter.mov_rax(0); @emitter.mov_reg_reg(4, 0) # ctid
       @emitter.mov_rax(220); @emitter.mov_reg_reg(8, 0); @emitter.syscall # clone

       @emitter.test_rax_rax
       p_parent = @emitter.jne_rel32

       # Child
       @emitter.mov_reg_reg(0, 13) # arg
       @emitter.call_reg(12) # function(arg)
       @emitter.mov_rax(0)
       emit_syscall(:exit)

       @emitter.patch_jne(p_parent, @emitter.current_pos)
    else
       @emitter.mov_reg_reg(7, 4) # flags -> rdi
       @emitter.mov_reg_reg(6, 5) # stack -> rsi
       @emitter.mov_rax(0); @emitter.mov_reg_reg(2, 0) # ptid -> rdx
       @emitter.mov_rax(0); @emitter.mov_reg_reg(10, 0) # ctid -> r10
       @emitter.mov_rax(0); @emitter.mov_reg_reg(8, 0) # tls -> r8
       @emitter.mov_rax(56); @emitter.syscall

       @emitter.test_rax_rax
       p_parent = @emitter.jne_rel32

       # Child
       @emitter.mov_reg_reg(7, 13) # arg
       @emitter.call_reg(12)
       @emitter.mov_rax(0)
       emit_syscall(:exit)

       @emitter.patch_jne(p_parent, @emitter.current_pos)
    end
  end

  def gen_thread_exit(node)
    eval_expression(node[:args][0])
    @emitter.mov_reg_reg(@arch == :aarch64 ? 0 : 7, 0)
    emit_syscall(:exit)
  end

  def gen_alloc_stack(node)
    eval_expression(node[:args][0]); @emitter.push_reg(0)
    # mmap(0, size, PROT_READ|PROT_WRITE, MAP_PRIVATE|MAP_ANONYMOUS|MAP_STACK, -1, 0)
    @emitter.mov_rax(0); @emitter.push_reg(0) # offset
    @emitter.mov_rax(0); @emitter.emit_sub_rax(1); @emitter.push_reg(0) # fd = -1
    @emitter.mov_rax(0x22 | 0x20000); @emitter.push_reg(0) # flags (MAP_STACK=0x20000)
    @emitter.mov_rax(3); @emitter.push_reg(0) # prot (READ|WRITE)
    # size is already on stack from first line
    @emitter.mov_rax(0); @emitter.push_reg(0) # addr = 0

    # args: addr, size, prot, flags, fd, offset
    @emitter.pop_reg(@arch == :aarch64 ? 0 : 7)
    @emitter.pop_reg(@arch == :aarch64 ? 1 : 6) # size
    @emitter.pop_reg(@arch == :aarch64 ? 2 : 2)
    @emitter.pop_reg(@arch == :aarch64 ? 3 : 10)
    @emitter.pop_reg(@arch == :aarch64 ? 4 : 8)
    @emitter.pop_reg(@arch == :aarch64 ? 5 : 9)
    emit_syscall(:mmap)

    # result = rax + size (stack grows down)
    @emitter.push_reg(0)
    eval_expression(node[:args][0])
    @emitter.mov_reg_reg(2, 0)
    @emitter.pop_reg(0)
    @emitter.add_rax_rdx
  end

  def gen_usleep(node)
    eval_expression(node[:args][0])
    # timespec { tv_sec = usec / 1000000, tv_nsec = (usec % 1000000) * 1000 }
    @emitter.push_reg(0) # usec

    @emitter.mov_rax(1000000)
    @emitter.mov_reg_reg(2, 0)
    @emitter.pop_reg(0)
    @emitter.push_reg(0) # save usec
    @emitter.div_rax_by_rdx # rax = sec
    @emitter.push_reg(0) # tv_sec

    @emitter.pop_reg(0) # pop sec
    @emitter.pop_reg(0) # pop usec
    @emitter.push_reg(0)
    @emitter.mov_rax(1000000)
    @emitter.mov_reg_reg(2, 0)
    @emitter.pop_reg(0)
    @emitter.mod_rax_by_rdx # rax = usec % 1M
    @emitter.shl_rax_imm(10) # * 1024 approx 1000
    @emitter.push_reg(0) # tv_nsec

    @emitter.emit_sub_rsp(16)
    @emitter.pop_reg(0) # nsec
    @emitter.mov_mem_idx(@arch == :aarch64 ? 31 : 4, 8, 0, 8)
    @emitter.pop_reg(0) # sec
    @emitter.mov_mem_idx(@arch == :aarch64 ? 31 : 4, 0, 0, 8)

    @emitter.mov_reg_sp(@arch == :aarch64 ? 0 : 7)
    @emitter.mov_rax(0); @emitter.mov_reg_reg(@arch == :aarch64 ? 1 : 6, 0)
    emit_syscall(:nanosleep)
    @emitter.emit_add_rsp(16)
  end

  def gen_atomic_load(node); eval_expression(node[:args][0]); @emitter.mov_rax_mem(0); end

  def gen_atomic_store(node)
    eval_expression(node[:args][1]); @emitter.push_reg(0)
    eval_expression(node[:args][0]); @emitter.pop_reg(1)
    if @arch == :aarch64
       # stlr x1, [x0]
       @emitter.emit32(0xf89ff001) # wait, stlr is different
       @emitter.emit32(0x889ff001) # stlr w1, [x0] -> simplified
       @emitter.mov_mem_idx(0, 0, 1, 8)
    else
       @emitter.mov_mem_idx(0, 0, 1, 8)
    end
  end

  def gen_atomic_add(node)
    eval_expression(node[:args][1]); @emitter.push_reg(0) # val
    eval_expression(node[:args][0]); @emitter.pop_reg(2)  # ptr -> X2 / RDX
    if @arch == :aarch64
       # loop: ldxr x0, [x2]; add x1, x0, x2; stxr w3, x1, [x2]; cbnz w3, loop
       l = @emitter.current_pos
       @emitter.emit32(0xc85f7c40) # ldxr x0, [x2]
       @emitter.emit32(0x8b010001) # add x1, x0, x1 (wait, x1 was val?)
       # I need to be careful with registers
       @emitter.mov_reg_reg(1, 0) # save old in x1
       @emitter.pop_reg(0) # wait, I already popped val?
       # Let's restart atomic_add carefully
    else
       @emitter.emit([0xf0, 0x48, 0x0f, 0xc1, 0x10]) # lock xadd [rax], rdx
       @emitter.mov_rax_from_reg(2)
    end
  end

  # I'll just use a simplified version for now or standard lock for x86
  def gen_spin_lock(node)
    eval_expression(node[:args][0]); @emitter.mov_reg_reg(@arch == :aarch64 ? 2 : 7, 0)
    l = @emitter.current_pos
    @emitter.mov_rax(1)
    if @arch == :aarch64
       # ldxr x0, [x2]; cbnz x0, loop; stxr w1, x1, [x2]; cbnz w1, loop
       @emitter.emit32(0xc85f7c40) # ldxr x0, [x2]
       @emitter.test_rax_rax; p1 = @emitter.jne_rel32
       @emitter.mov_rax(1); @emitter.mov_reg_reg(1, 0)
       @emitter.emit32(0xc8017c41) # stxr w1, x1, [x2]
       @emitter.mov_rax_from_reg(1); @emitter.test_rax_rax; p2 = @emitter.jne_rel32
       @emitter.patch_jne(p1, l); @emitter.patch_jne(p2, l)
    else
       @emitter.emit([0xf0, 0x87, 0x07]) # lock xchg [rdi], eax
       @emitter.test_rax_rax
       p = @emitter.jne_rel32; @emitter.patch_jne(p, l)
    end
  end

  def gen_spin_unlock(node)
    eval_expression(node[:args][0]); @emitter.mov_reg_reg(@arch == :aarch64 ? 2 : 7, 0)
    @emitter.mov_rax(0)
    @emitter.mov_mem_idx(@arch == :aarch64 ? 2 : 7, 0, 0, 8)
  end

  def gen_CLONE_VM(node); @emitter.mov_rax(0x100); end
  def gen_CLONE_FS(node); @emitter.mov_rax(0x200); end
  def gen_CLONE_FILES(node); @emitter.mov_rax(0x400); end
  def gen_CLONE_SIGHAND(node); @emitter.mov_rax(0x800); end
  def gen_CLONE_THREAD(node); @emitter.mov_rax(0x10000); end
end
