# Threading and Atomics support for Linux
module BuiltinThreads
  def gen_thread_create(node)
    return unless @target_os == :linux
    eval_expression(node[:args][0]); @emitter.push_reg(0)
    eval_expression(node[:args][1]); @emitter.push_reg(0)
    eval_expression(node[:args][2]); @emitter.push_reg(0)
    @emitter.push_reg(12); @emitter.push_reg(13); @emitter.push_reg(14)
    if @arch == :aarch64
      @emitter.mov_reg_stack_val(21, 48); @emitter.mov_reg_reg(21, 0)
      @emitter.mov_reg_stack_val(20, 64); @emitter.mov_reg_reg(20, 0)
      @emitter.mov_reg_stack_val(22, 80); @emitter.mov_reg_reg(22, 0)
      @emitter.mov_rax(0x50F00); @emitter.mov_reg_reg(0, 0); @emitter.mov_reg_reg(1, 20)
      @emitter.mov_rax(220); @emitter.mov_reg_reg(8, 0); @emitter.emit32(0xd4000001)
    else
      @emitter.emit([0x4c, 0x8b, 0x6c, 0x24, 0x18, 0x4c, 0x8b, 0x64, 0x24, 0x20, 0x4c, 0x8b, 0x74, 0x24, 0x28, 0x48, 0xc7, 0xc7, 0x00, 0x0f, 0x05, 0x00, 0x4c, 0x89, 0xe6, 0x48, 0x31, 0xd2, 0x4d, 0x31, 0xd2, 0x4d, 0x31, 0xc0, 0xb8, 0x38, 0x00, 0x00, 0x00, 0x0f, 0x05])
    end
    p = @emitter.jne_rel32
    if @arch == :aarch64
      @emitter.mov_reg_reg(0, 21); @emitter.emit32(0xd63f0000 | (22 << 5)); @emitter.mov_rax(93); @emitter.mov_reg_reg(8, 0); @emitter.emit32(0xd4000001)
    else
      @emitter.emit([0x4c, 0x89, 0xef, 0x41, 0xff, 0xd6, 0x48, 0x89, 0xc7, 0xb8, 0x3c, 0x00, 0x00, 0x00, 0x0f, 0x05])
    end
    @emitter.patch_jne(p, @emitter.current_pos)
    @emitter.pop_reg(14); @emitter.pop_reg(13); @emitter.pop_reg(12); @emitter.emit_add_rsp(@arch == :aarch64 ? 48 : 24)
  end

  def gen_thread_exit(node)
    eval_expression(node[:args][0])
    @arch == :aarch64 ? (@emitter.mov_rax(93); @emitter.mov_reg_reg(8, 0); @emitter.emit32(0xd4000001)) : (@emitter.mov_reg_reg(7, 0); @emitter.emit([0xb8, 0x3c, 0x00, 0x00, 0x00, 0x0f, 0x05]))
  end

  def gen_usleep(node)
    eval_expression(node[:args][0])
    if @arch == :aarch64
      @emitter.mov_reg_reg(2, 0); @emitter.mov_rax(1000); @emitter.imul_rax_rdx; @emitter.emit_sub_rsp(16); @emitter.mov_rax(0); @emitter.mov_stack_reg_val(0, 0); @emitter.mov_stack_reg_val(8, 2); @emitter.mov_reg_reg(0, 31); @emitter.mov_rax(0); @emitter.mov_reg_reg(1, 0); @emitter.mov_rax(101); @emitter.mov_reg_reg(8, 0); @emitter.emit32(0xd4000001); @emitter.emit_add_rsp(16)
    else
      @emitter.emit([0x48, 0x69, 0xc0, 0xe8, 0x03, 0x00, 0x00, 0x48, 0x83, 0xec, 0x10, 0x48, 0xc7, 0x04, 0x24, 0,0,0,0, 0x48, 0x89, 0x44, 0x24, 0x08, 0x48, 0x89, 0xe7, 0x48, 0x31, 0xf6, 0xb8, 0x23, 0,0,0, 0x0f, 0x05, 0x48, 0x83, 0xc4, 0x10])
    end
  end
  def gen_sleep(node); gen_usleep(node); end

  def gen_alloc_stack(node)
    eval_expression(node[:args][0]); @emitter.mov_reg_reg(6, 0)
    if @arch == :aarch64 then @emitter.mov_rax(0); @emitter.mov_reg_reg(0, 0); @emitter.mov_rax(3); @emitter.mov_reg_reg(2, 0); @emitter.mov_rax(0x122); @emitter.mov_reg_reg(3, 0); @emitter.mov_rax(0xFFFFFFFFFFFFFFFF); @emitter.mov_reg_reg(4, 0); @emitter.mov_rax(0); @emitter.mov_reg_reg(5, 0); @emitter.mov_rax(222); @emitter.mov_reg_reg(8, 0); @emitter.emit32(0xd4000001)
    else @emitter.emit([0x48, 0x31, 0xff, 0xba, 0x03, 0,0,0, 0x41, 0xba, 0x22, 0x01, 0,0, 0x49, 0xc7, 0xc0, 0xff, 0xff, 0xff, 0xff, 0x4d, 0x31, 0xc9, 0xb8, 0x09, 0,0,0, 0x0f, 0x05])
    end
    @emitter.push_reg(0); eval_expression(node[:args][0]); @emitter.pop_reg(2); @emitter.add_rax_rdx
  end

  def gen_clone(node)
    eval_expression(node[:args][0]); @emitter.mov_reg_reg(0, 0); eval_expression(node[:args][1]); @emitter.mov_reg_reg(1, 0)
    @emitter.mov_rax(0); @emitter.mov_reg_reg(2, 0); @emitter.mov_rax(0); @emitter.mov_reg_reg(3, 0); @emitter.mov_rax(0); @emitter.mov_reg_reg(4, 0)
    @arch == :aarch64 ? (@emitter.mov_rax(220); @emitter.mov_reg_reg(8, 0); @emitter.emit32(0xd4000001)) : (@emitter.emit([0xb8, 0x38, 0,0,0, 0x0f, 0x05]))
  end

  def gen_futex(node)
    eval_expression(node[:args][0]); @emitter.mov_reg_reg(0, 0); eval_expression(node[:args][1]); @emitter.mov_reg_reg(1, 0); eval_expression(node[:args][2]); @emitter.mov_reg_reg(2, 0)
    @emitter.mov_rax(0); @emitter.mov_reg_reg(3, 0); @emitter.mov_rax(0); @emitter.mov_reg_reg(4, 0); @emitter.mov_rax(0); @emitter.mov_reg_reg(5, 0)
    @arch == :aarch64 ? (@emitter.mov_rax(98); @emitter.mov_reg_reg(8, 0); @emitter.emit32(0xd4000001)) : (@emitter.emit([0xb8, 0xca, 0,0,0, 0x0f, 0x05]))
  end

  def gen_FUTEX_WAIT(node); @emitter.mov_rax(0); end
  def gen_FUTEX_WAKE(node); @emitter.mov_rax(1); end

  def gen_atomic_load(node); eval_expression(node[:args][0]); @emitter.mov_rax_mem(0); end
  def gen_atomic_store(node); eval_expression(node[:args][1]); @emitter.push_reg(0); eval_expression(node[:args][0]); @emitter.pop_reg(2); if @arch == :aarch64 then @emitter.emit32(0xf9000002) else @emitter.emit([0x48, 0x89, 0x10]) end; end

  def gen_atomic_add(node)
    eval_expression(node[:args][1]); @emitter.push_reg(0); eval_expression(node[:args][0]); @emitter.pop_reg(2)
    if @arch == :aarch64 then @emitter.mov_reg_reg(4, 0); @emitter.emit32(0xc85f7c81); @emitter.emit32(0x8b010043); @emitter.emit32(0xc8027c83); @emitter.emit32(0x35ffffa2)
    else @emitter.mov_reg_reg(7, 0); @emitter.mov_reg_reg(0, 2); @emitter.emit([0xf0, 0x48, 0x0f, 0xc1, 0x07])
    end
  end

  def gen_atomic_sub(node)
    eval_expression(node[:args][1]); @emitter.not_rax; @emitter.mov_reg_reg(2, 0); @emitter.mov_rax(1); @emitter.add_rax_rdx; @emitter.push_reg(0)
    eval_expression(node[:args][0]); @emitter.pop_reg(2)
    if @arch == :aarch64 then # same as add
    else @emitter.mov_reg_reg(7, 0); @emitter.mov_reg_reg(0, 2); @emitter.emit([0xf0, 0x48, 0x0f, 0xc1, 0x07])
    end
  end

  def gen_atomic_cas(node)
    eval_expression(node[:args][2]); @emitter.push_reg(0); eval_expression(node[:args][1]); @emitter.push_reg(0); eval_expression(node[:args][0])
    if @arch == :aarch64 then @emitter.pop_reg(1); @emitter.pop_reg(2); # ... loop
    else @emitter.mov_reg_reg(7, 0); @emitter.pop_reg(0); @emitter.pop_reg(1); @emitter.emit([0xf0, 0x48, 0x0f, 0xb1, 0x0f])
    end
  end

  def gen_spin_lock(node); eval_expression(node[:args][0]); @emitter.mov_reg_reg(7, 0); l = @emitter.current_pos; if @arch == :aarch64 then @emitter.mov_rax(1); @emitter.mov_reg_reg(1, 0); @emitter.emit32(0xc8218001); @emitter.test_rax_rax; jz = @emitter.je_rel32; @emitter.patch_je(jz, l) else @emitter.emit([0xb8, 0x01, 0,0,0, 0xf0, 0x87, 0x07, 0x85, 0xc0]); @emitter.emit([0x75, (l - (@emitter.current_pos + 2)) & 0xFF]) end; @emitter.mov_rax(0); end
  def gen_spin_unlock(node); eval_expression(node[:args][0]); if @arch == :aarch64 then @emitter.mov_rax(0); @emitter.emit32(0xf9000000) else @emitter.emit([0x48, 0xc7, 0x00, 0,0,0,0]) end; @emitter.mov_rax(0); end

  def gen_CLONE_VM(node); @emitter.mov_rax(0x100); end
  def gen_CLONE_FS(node); @emitter.mov_rax(0x200); end
  def gen_CLONE_FILES(node); @emitter.mov_rax(0x400); end
  def gen_CLONE_SIGHAND(node); @emitter.mov_rax(0x800); end
  def gen_CLONE_THREAD(node); @emitter.mov_rax(0x10000); end
end
