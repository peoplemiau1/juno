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

    @emitter.pop_reg(4)  # flags
    @emitter.pop_reg(5)  # stack
    @emitter.pop_reg(12) # func
    @emitter.pop_reg(13) # arg

    if @arch == :aarch64
       @emitter.mov_reg_reg(0, 4) # flags
       @emitter.mov_reg_reg(1, 5) # stack
       @emitter.mov_reg_imm(2, 0) # ptid
       @emitter.mov_reg_imm(3, 0) # tls
       @emitter.mov_reg_imm(4, 0) # ctid
       @emitter.mov_x8(220) # clone
       @emitter.syscall

       @emitter.test_rax_rax
       p_parent = @emitter.jne_rel32

       # Child
       @emitter.mov_reg_reg(0, 13) # arg
       @emitter.call_reg(12) # function(arg)
       @emitter.mov_reg_imm(0, 0)
       @emitter.mov_x8(93) # exit
       @emitter.syscall

       @emitter.patch_jne(p_parent, @emitter.current_pos)
    else
       @emitter.mov_reg_reg(7, 4) # flags -> rdi
       @emitter.mov_reg_reg(6, 5) # stack -> rsi
       @emitter.mov_reg_imm(2, 0) # ptid -> rdx
       @emitter.mov_reg_imm(10, 0) # ctid -> r10
       @emitter.mov_reg_imm(8, 0) # tls -> r8
       @emitter.mov_reg_imm(0, 56) # clone
       @emitter.syscall

       @emitter.test_rax_rax
       p_parent = @emitter.jne_rel32

       # Child
       @emitter.mov_reg_reg(7, 13) # arg
       @emitter.call_reg(12)
       @emitter.mov_reg_imm(0, 0)
       @emitter.mov_reg_imm(0, 60) # exit
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
    @emitter.mov_reg_imm(0, 0); @emitter.push_reg(0) # offset
    @emitter.mov_reg_imm(0, 0); @emitter.emit_sub_rax(1); @emitter.push_reg(0) # fd = -1
    @emitter.mov_reg_imm(0, 0x22 | 0x20000); @emitter.push_reg(0) # flags
    @emitter.mov_reg_imm(0, 3); @emitter.push_reg(0) # prot
    eval_expression(node[:args][0]); @emitter.push_reg(0) # size
    @emitter.mov_reg_imm(0, 0) # addr = 0

    @emitter.pop_reg(@arch == :aarch64 ? 1 : 6)  # size
    @emitter.pop_reg(@arch == :aarch64 ? 2 : 2)  # prot
    @emitter.pop_reg(@arch == :aarch64 ? 3 : 10) # flags
    @emitter.pop_reg(@arch == :aarch64 ? 4 : 8)  # fd
    @emitter.pop_reg(@arch == :aarch64 ? 5 : 9)  # offset
    @emitter.mov_reg_reg(@arch == :aarch64 ? 0 : 7, 0) if @arch == :x86_64
    emit_syscall(:mmap)

    @emitter.push_reg(0)
    eval_expression(node[:args][0])
    @emitter.mov_reg_reg(2, 0)
    @emitter.pop_reg(0)
    @emitter.add_rax_rdx
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
    @emitter.pop_reg(0); @emitter.mov_mem_idx(@arch == :aarch64 ? 31 : 4, 8, 0, 8)
    @emitter.pop_reg(0); @emitter.mov_mem_idx(@arch == :aarch64 ? 31 : 4, 0, 0, 8)

    @emitter.mov_reg_sp(@arch == :aarch64 ? 0 : 7)
    @emitter.mov_reg_imm(@arch == :aarch64 ? 1 : 6, 0)
    emit_syscall(:nanosleep)
    @emitter.emit_add_rsp(16)
  end

  def gen_atomic_load(node); eval_expression(node[:args][0]); @emitter.mov_rax_mem(0); end

  def gen_atomic_store(node)
    eval_expression(node[:args][1]); @emitter.push_reg(0)
    eval_expression(node[:args][0]); @emitter.pop_reg(1)
    @emitter.mov_mem_idx(0, 0, 1, 8)
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
    @emitter.mov_mem_idx(@arch == :aarch64 ? 2 : 7, 0, 0, 8)
  end

  def gen_CLONE_VM(node); @emitter.mov_rax(0x100); end
  def gen_CLONE_FS(node); @emitter.mov_rax(0x200); end
  def gen_CLONE_FILES(node); @emitter.mov_rax(0x400); end
  def gen_CLONE_SIGHAND(node); @emitter.mov_rax(0x800); end
  def gen_CLONE_THREAD(node); @emitter.mov_rax(0x10000); end
end
