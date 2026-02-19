# Threading support for Linux
# Architecture-neutral implementation for x86-64 and AArch64

module BuiltinThreads
  def gen_thread_create(node)
    return unless @target_os == :linux
    # thread_create(flags, stack, func, arg)
    args = node[:args]
    if args.length == 3
      eval_expression(args[2]); @emitter.push_reg(0) # arg
      eval_expression(args[0]); @emitter.push_reg(0) # func
      eval_expression(args[1]); @emitter.push_reg(0) # stack
      @emitter.mov_rax(0x10F00); @emitter.push_reg(0) # flags
    else
      eval_expression(args[3]); @emitter.push_reg(0)
      eval_expression(args[2]); @emitter.push_reg(0)
      eval_expression(args[1]); @emitter.push_reg(0)
      eval_expression(args[0]); @emitter.push_reg(0)
    end

    # Pop into safe scratch/argument registers
    @emitter.pop_reg(@arch == :aarch64 ? 4 : 7) # flags (X4 or RDI)
    @emitter.pop_reg(@arch == :aarch64 ? 5 : 6) # stack (X5 or RSI)
    @emitter.pop_reg(@arch == :aarch64 ? 6 : 2) # func (X6 or RDX)
    @emitter.pop_reg(@arch == :aarch64 ? 7 : 10) # arg (X7 or R10)

    if @arch == :aarch64
       # clone(flags, stack, ...)
       @emitter.mov_reg_reg(0, 4)
       @emitter.mov_reg_reg(1, 5)
       @emitter.mov_reg_imm(2, 0)
       @emitter.mov_reg_imm(3, 0)
       @emitter.mov_reg_imm(4, 0)
       @emitter.mov_x8(220)
       @emitter.syscall

       @emitter.test_rax_rax
       p_parent = @emitter.jne_rel32

       # Child
       @emitter.mov_reg_reg(0, 7) # arg
       @emitter.call_reg(6) # func
       @emitter.mov_reg_imm(0, 0)
       @emitter.mov_x8(93)
       @emitter.syscall
       @emitter.patch_jne(p_parent, @emitter.current_pos)
    else
       # x86_64 clone(flags, stack, ...)
       # Prepare child stack
       @emitter.mov_reg_reg(11, 6) # R11 = stack top
       @emitter.sub_reg_imm(11, 16)
       @emitter.mov_mem_reg_idx(11, 0, 2, 8) # [stack-16] = func
       @emitter.mov_mem_reg_idx(11, 8, 10, 8) # [stack-8] = arg

       @emitter.mov_reg_reg(7, 4) # RDI = flags
       @emitter.mov_reg_reg(6, 11) # RSI = stack
       @emitter.mov_reg_imm(2, 0) # RDX = ptid
       @emitter.mov_reg_imm(10, 0) # R10 = ctid
       @emitter.mov_reg_imm(8, 0) # R8 = tls

       @emitter.mov_rax(56)
       @emitter.syscall

       @emitter.test_rax_rax
       p_parent = @emitter.jne_rel32

       # Child
       @emitter.mov_reg_mem_idx(7, 4, 8, 8) # RDI = arg
       @emitter.mov_reg_mem_idx(11, 4, 0, 8) # R11 = func
       @emitter.call_reg(11)

       @emitter.mov_reg_imm(0, 0)
       @emitter.mov_rax(60)
       @emitter.mov_reg_imm(7, 0)
       @emitter.syscall
       @emitter.patch_jne(p_parent, @emitter.current_pos)
    end
  end

  def gen_thread_exit(node)
    eval_expression(node[:args][0])
    @emitter.mov_reg_reg(@arch == :aarch64 ? 0 : 7, 0)
    emit_syscall(:exit)
  end

  def gen_alloc_stack(node)
    eval_expression(node[:args][0]); @emitter.push_reg(0) # size
    @emitter.mov_reg_imm(0, 0); @emitter.push_reg(0) # offset
    @emitter.mov_rax(0); @emitter.sub_reg_imm(0, 1); @emitter.push_reg(0) # fd = -1
    @emitter.mov_reg_imm(0, 0x22 | 0x20000); @emitter.push_reg(0) # flags
    @emitter.mov_reg_imm(0, 3); @emitter.push_reg(0) # prot
    @emitter.mov_reg_imm(0, 0); @emitter.push_reg(0) # addr = 0

    @emitter.pop_reg(@arch == :aarch64 ? 0 : 7)
    @emitter.pop_reg(@arch == :aarch64 ? 1 : 6) # size
    @emitter.pop_reg(@arch == :aarch64 ? 2 : 2)
    @emitter.pop_reg(@arch == :aarch64 ? 3 : 10)
    @emitter.pop_reg(@arch == :aarch64 ? 4 : 8)
    @emitter.pop_reg(@arch == :aarch64 ? 5 : 9)
    emit_syscall(:mmap)

    @emitter.push_reg(0) # base addr
    eval_expression(node[:args][0])
    @emitter.mov_reg_reg(2, 0) # size
    @emitter.pop_reg(0) # base
    @emitter.add_rax_rdx # top
  end

  def gen_usleep(node)
    eval_expression(node[:args][0])
    @emitter.push_reg(0) # usec
    @emitter.mov_reg_imm(2, 1000000)
    @emitter.div_rax_by_rdx # rax = sec
    @emitter.push_reg(0) # tv_sec

    @emitter.pop_reg(0) # sec
    @emitter.pop_reg(0) # usec
    @emitter.push_reg(0)
    @emitter.mov_reg_imm(2, 1000000)
    @emitter.mod_rax_by_rdx # rax = rem
    @emitter.mov_reg_imm(2, 1000)
    @emitter.imul_rax_rdx # nsec
    @emitter.push_reg(0) # tv_nsec

    @emitter.emit_sub_rsp(16)
    @emitter.pop_reg(0); @emitter.mov_mem_reg_idx(@arch == :aarch64 ? 31 : 4, 8, 0, 8)
    @emitter.pop_reg(0); @emitter.mov_mem_reg_idx(@arch == :aarch64 ? 31 : 4, 0, 0, 8)

    @emitter.mov_reg_sp(@arch == :aarch64 ? 0 : 7)
    @emitter.mov_reg_imm(@arch == :aarch64 ? 1 : 6, 0)
    emit_syscall(:nanosleep)
    @emitter.emit_add_rsp(16)
  end

  def gen_atomic_load(node); eval_expression(node[:args][0]); @emitter.mov_rax_mem(0); end

  def gen_atomic_add(node)
    eval_expression(node[:args][1]); @emitter.push_reg(0) # val
    eval_expression(node[:args][0]) # ptr (RAX)
    @emitter.mov_reg_reg(@arch == :aarch64 ? 2 : 7, 0) # RDI or X2 = ptr
    @emitter.pop_reg(0) # RAX = val

    if @arch == :aarch64
       l = @emitter.current_pos
       @emitter.emit32(0xc85f7c41) # ldxr x1, [x2]
       @emitter.add_reg_reg(1, 0) # x1 = x1 + x0
       @emitter.emit32(0xc8037c41) # stxr w3, x1, [x2]
       @emitter.mov_rax_from_reg(3)
       @emitter.test_rax_rax
       p = @emitter.jne_rel32; @emitter.patch_jne(p, l)
       @emitter.emit32(0xd1000420) # sub x0, x1, x0 (return old value)
    else
       @emitter.emit([0xf0, 0x48, 0x0f, 0xc1, 0x07]) # lock xadd [rdi], rax
    end
  end

  def gen_atomic_store(node)
    eval_expression(node[:args][1]); @emitter.push_reg(0)
    eval_expression(node[:args][0]); @emitter.pop_reg(1)
    @emitter.mov_mem_reg_idx(0, 0, 1, 8)
  end

  def gen_spin_lock(node)
    eval_expression(node[:args][0]); @emitter.mov_reg_reg(@arch == :aarch64 ? 2 : 7, 0)
    l = @emitter.current_pos
    @emitter.mov_reg_imm(0, 1)
    if @arch == :aarch64
       @emitter.emit32(0xc85f7c40) # ldxr x0, [x2]
       @emitter.test_rax_rax
       p1 = @emitter.jne_rel32
       @emitter.mov_reg_imm(1, 1)
       @emitter.emit32(0xc8017c41) # stxr w1, x1, [x2]
       @emitter.mov_rax_from_reg(1)
       @emitter.test_rax_rax
       p2 = @emitter.jne_rel32
       @emitter.patch_jne(p1, l); @emitter.patch_jne(p2, l)
    else
       @emitter.emit([0xf0, 0x87, 0x07]) # lock xchg [rdi], eax
       @emitter.test_rax_rax
       p = @emitter.jne_rel32; @emitter.patch_jne(p, l)
    end
  end

  def gen_spin_unlock(node)
    eval_expression(node[:args][0]); @emitter.mov_reg_reg(@arch == :aarch64 ? 2 : 7, 0)
    @emitter.mov_reg_imm(0, 0)
    @emitter.mov_mem_reg_idx(@arch == :aarch64 ? 2 : 7, 0, 0, 8)
  end

  def gen_CLONE_VM(node); @emitter.mov_rax(0x100); end
  def gen_CLONE_FS(node); @emitter.mov_rax(0x200); end
  def gen_CLONE_FILES(node); @emitter.mov_rax(0x400); end
  def gen_CLONE_SIGHAND(node); @emitter.mov_rax(0x800); end
  def gen_CLONE_THREAD(node); @emitter.mov_rax(0x10000); end
end
