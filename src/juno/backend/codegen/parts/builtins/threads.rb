module BuiltinThreads
  def gen_thread_create(node)
    return unless @target_os == :linux
    args = node[:args]
    if args.length == 2
      eval_expression(args[1]); @emitter.push_reg(0)
      eval_expression(args[0]); @emitter.push_reg(0)

      @emitter.mov_reg_imm(0, 65536); @emitter.push_reg(0)
      gen_alloc_stack({args: [{type: :literal, value: 65536}]})
      @emitter.push_reg(0)

      @emitter.mov_rax(0x10F00); @emitter.push_reg(0)
    elsif args.length == 3
      eval_expression(args[2]); @emitter.push_reg(0)
      eval_expression(args[0]); @emitter.push_reg(0)
      eval_expression(args[1]); @emitter.push_reg(0)
      @emitter.mov_rax(0x10F00); @emitter.push_reg(0)
    else
      eval_expression(args[3]); @emitter.push_reg(0)
      eval_expression(args[2]); @emitter.push_reg(0)
      eval_expression(args[1]); @emitter.push_reg(0)
      eval_expression(args[0]); @emitter.push_reg(0)
    end

    @emitter.pop_reg(@arch == :aarch64 ? 4 : 7)
    @emitter.pop_reg(@arch == :aarch64 ? 5 : 6)
    @emitter.pop_reg(@arch == :aarch64 ? 6 : 2)
    @emitter.pop_reg(@arch == :aarch64 ? 7 : 10)

    if @arch == :aarch64
       @emitter.mov_reg_reg(0, 4)
       @emitter.mov_reg_reg(1, 5)
       @emitter.mov_reg_imm(2, 0)
       @emitter.mov_reg_imm(3, 0)
       @emitter.mov_reg_imm(4, 0)
       @emitter.mov_x8(220)
       @emitter.syscall

       @emitter.test_rax_rax
       p_parent = @emitter.jne_rel32

       @emitter.mov_reg_reg(0, 7)
       @emitter.call_reg(6)
       @emitter.mov_reg_imm(0, 0)
       @emitter.mov_x8(93)
       @emitter.syscall
       @emitter.patch_jne(p_parent, @emitter.current_pos)
    else
       @emitter.mov_reg_reg(11, 6)
       @emitter.sub_reg_imm(11, 16)
       @emitter.mov_mem_reg_idx(11, 0, 2, 8)
       @emitter.mov_mem_reg_idx(11, 8, 10, 8)

       @emitter.mov_reg_reg(6, 11)
       @emitter.mov_reg_imm(2, 0)
       @emitter.mov_reg_imm(10, 0)
       @emitter.mov_reg_imm(8, 0)

       @emitter.mov_rax(56)
       @emitter.syscall

       @emitter.test_rax_rax
       p_parent = @emitter.jne_rel32

       @emitter.pop_reg(11)
       @emitter.pop_reg(7)
       @emitter.call_reg(11)

       @emitter.mov_reg_imm(0, 0)
       @emitter.mov_rax(60)
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
    eval_expression(node[:args][0]); @emitter.push_reg(0)
    @emitter.mov_reg_imm(0, 0); @emitter.push_reg(0)
    @emitter.mov_rax(0); @emitter.sub_reg_imm(0, 1); @emitter.push_reg(0)
    @emitter.mov_reg_imm(0, 0x22 | 0x20000); @emitter.push_reg(0)
    @emitter.mov_reg_imm(0, 3); @emitter.push_reg(0)
    @emitter.mov_reg_imm(0, 0); @emitter.push_reg(0)

    @emitter.pop_reg(@arch == :aarch64 ? 0 : 7)
    @emitter.pop_reg(@arch == :aarch64 ? 2 : 2)
    @emitter.pop_reg(@arch == :aarch64 ? 3 : 10)
    @emitter.pop_reg(@arch == :aarch64 ? 4 : 8)
    @emitter.pop_reg(@arch == :aarch64 ? 5 : 9)
    @emitter.pop_reg(@arch == :aarch64 ? 1 : 6)
    emit_syscall(:mmap)

    @emitter.push_reg(0)
    eval_expression(node[:args][0])
    @emitter.mov_reg_reg(2, 0)
    @emitter.pop_reg(0)
    @emitter.add_rax_rdx
  end

  def gen_usleep(node)
    eval_expression(node[:args][0])
    @emitter.mov_reg_reg(2, 0)
    @emitter.mov_reg_imm(1, 1000000)
    @emitter.mov_reg_reg(0, 2)
    @emitter.div_rax_by_rdx

    @emitter.push_reg(0)
    @emitter.mov_reg_imm(2, 1000000)
    @emitter.div_rax_by_rdx
    @emitter.push_reg(0)

    @emitter.pop_reg(0)
    @emitter.pop_reg(0)
    @emitter.push_reg(0)
    @emitter.mov_reg_imm(2, 1000000)
    @emitter.mod_rax_by_rdx
    @emitter.mov_reg_imm(2, 1000)
    @emitter.imul_rax_rdx
    @emitter.push_reg(0)

    @emitter.mov_reg_sp(@arch == :aarch64 ? 0 : 7)
    @emitter.mov_reg_imm(@arch == :aarch64 ? 1 : 6, 0)
    emit_syscall(:nanosleep)
    @emitter.emit_add_rsp(16)
  end

  def gen_atomic_load(node); eval_expression(node[:args][0]); @emitter.mov_rax_mem(0); end

  def gen_atomic_add(node)
    eval_expression(node[:args][1]); @emitter.push_reg(0)
    eval_expression(node[:args][0])
    @emitter.mov_reg_reg(@arch == :aarch64 ? 2 : 7, 0)
    @emitter.pop_reg(0)

    if @arch == :aarch64
       l = @emitter.current_pos
       @emitter.emit32(0xc85f7c41)
       @emitter.add_reg_reg(1, 0)
       @emitter.emit32(0xc8037c41)
       @emitter.mov_rax_from_reg(3)
       @emitter.test_rax_rax
       p = @emitter.jne_rel32; @emitter.patch_jne(p, l)
       @emitter.emit32(0xd1000420)
    else
       @emitter.emit([0xf0, 0x48, 0x0f, 0xc1, 0x07])
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
       @emitter.emit32(0xc85f7c40)
       @emitter.test_rax_rax
       p1 = @emitter.jne_rel32
       @emitter.mov_reg_imm(1, 1)
       @emitter.emit32(0xc8017c41)
       @emitter.mov_rax_from_reg(1)
       @emitter.test_rax_rax
       p2 = @emitter.jne_rel32
       @emitter.patch_jne(p1, l); @emitter.patch_jne(p2, l)
    else
       @emitter.emit([0xf0, 0x87, 0x07])
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
