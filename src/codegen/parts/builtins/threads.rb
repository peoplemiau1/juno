# Threading support for Linux

module BuiltinThreads
  def gen_thread_create(node)
    return unless @target_os == :linux
    eval_expression(node[:args][0]); @emitter.push_reg(0)
    eval_expression(node[:args][1]); @emitter.push_reg(0)
    eval_expression(node[:args][2]); @emitter.push_reg(0)
    if @arch == :aarch64
       @emitter.pop_reg(2); @emitter.pop_reg(1); @emitter.pop_reg(0); @emitter.mov_rax(0)
    else
       @emitter.push_reg(12); @emitter.push_reg(13); @emitter.push_reg(14)
       @emitter.emit([0x4c, 0x8b, 0x6c, 0x24, 0x18, 0x4c, 0x8b, 0x64, 0x24, 0x20, 0x4c, 0x8b, 0x74, 0x24, 0x28])
       @emitter.mov_rax(0x50f00); @emitter.mov_reg_reg(7, 0); @emitter.mov_reg_reg(6, 12); @emitter.mov_rax(56); @emitter.emit([0x0f, 0x05])
       @emitter.emit([0x48, 0x85, 0xc0]); jz_pos = @emitter.current_pos; @emitter.emit([0x75, 0x00])
       @emitter.mov_reg_reg(7, 13); @emitter.emit([0x41, 0xff, 0xd6])
       @emitter.mov_reg_reg(7, 0); @emitter.mov_rax(60); @emitter.emit([0x0f, 0x05])
       target = @emitter.current_pos; @emitter.bytes[jz_pos+1] = (target-(jz_pos+2)) & 0xFF
       @emitter.pop_reg(14); @emitter.pop_reg(13); @emitter.pop_reg(12); @emitter.emit([0x48, 0x83, 0xc4, 24])
    end
  end

  def gen_thread_exit(node)
    eval_expression(node[:args][0]); @emitter.mov_reg_reg(0, 0)
    if @arch == :aarch64 then @emitter.mov_rax(93); @emitter.mov_reg_reg(8, 0); @emitter.emit32(0xd4000001)
    else @emitter.mov_reg_reg(7, 0); @emitter.mov_rax(60); @emitter.emit([0x0f, 0x05]) end
  end

  def gen_alloc_stack(node)
    eval_expression(node[:args][0]); @emitter.push_reg(0)
    if @arch == :aarch64
      @emitter.pop_reg(1); @emitter.mov_rax(0); @emitter.mov_reg_reg(0, 0); @emitter.mov_rax(3); @emitter.mov_reg_reg(2, 0)
      @emitter.mov_rax(0x22); @emitter.mov_reg_reg(3, 0); @emitter.mov_rax(0xFFFFFFFFFFFFFFFF); @emitter.mov_reg_reg(4, 0)
      @emitter.mov_rax(0); @emitter.mov_reg_reg(5, 0); @emitter.mov_rax(222); @emitter.mov_reg_reg(8, 0); @emitter.emit32(0xd4000001)
      @emitter.push_reg(0); eval_expression(node[:args][0]); @emitter.mov_reg_reg(1, 0); @emitter.pop_reg(0); @emitter.emit32(0x8b010000)
    else
      @emitter.pop_reg(6); @emitter.mov_rax(0); @emitter.mov_reg_reg(7, 0); @emitter.mov_rax(3); @emitter.mov_reg_reg(2, 0)
      @emitter.mov_rax(0x22); @emitter.mov_reg_reg(10, 0); @emitter.mov_rax(0xFFFFFFFFFFFFFFFF); @emitter.mov_reg_reg(8, 0)
      @emitter.mov_rax(0); @emitter.mov_reg_reg(9, 0); @emitter.mov_rax(9); @emitter.emit([0x0f, 0x05])
      @emitter.push_reg(0); eval_expression(node[:args][0]); @emitter.mov_reg_reg(2, 0); @emitter.pop_reg(0); @emitter.add_rax_rdx
    end
  end

  def gen_usleep(node)
    eval_expression(node[:args][0])
    if @arch == :x86_64
      @emitter.emit([0x48, 0x69, 0xc0, 0xe8, 0x03, 0, 0, 0x48, 0x83, 0xec, 16, 0x48, 0xc7, 0x04, 0x24, 0,0,0,0, 0x48, 0x89, 0x44, 0x24, 0x08])
      @emitter.mov_reg_reg(7, 4); @emitter.mov_rax(0); @emitter.mov_reg_reg(6, 0); @emitter.mov_rax(35); @emitter.emit([0x0f, 0x05, 0x48, 0x83, 0xc4, 16])
    end
  end

  def gen_atomic_load(node); eval_expression(node[:args][0]); @emitter.mov_rax_mem(0); end
  def gen_atomic_store(node)
    eval_expression(node[:args][1]); @emitter.push_reg(0); eval_expression(node[:args][0]); @emitter.pop_reg(11)
    if @arch == :x86_64 then @emitter.mov_mem_r11(0) end
  end
  def gen_atomic_add(node)
    eval_expression(node[:args][1]); @emitter.push_reg(0) # val
    eval_expression(node[:args][0]); @emitter.pop_reg(2)  # ptr -> rdx
    if @arch == :x86_64
      @emitter.emit([0xf0, 0x48, 0x0f, 0xc1, 0x10]) # lock xadd [rax], rdx
      @emitter.mov_rax_from_reg(2) # return old value (from rdx)
    end
  end
  def gen_atomic_sub(node)
    eval_expression(node[:args][1]); @emitter.emit([0x48, 0xf7, 0xd8, 0x50]); eval_expression(node[:args][0]); @emitter.pop_reg(2)
    if @arch == :x86_64 then @emitter.emit([0xf0, 0x48, 0x0f, 0xc1, 0x10]) end
  end
  def gen_atomic_cas(node); @emitter.mov_rax(0); end
  def gen_spin_lock(node)
    eval_expression(node[:args][0]); @emitter.mov_reg_reg(7, 0)
    if @arch == :x86_64
      l = @emitter.current_pos; @emitter.mov_rax(1); @emitter.emit([0xf0, 0x87, 0x07, 0x85, 0xc0])
      @emitter.emit([0x75, (l - (@emitter.current_pos + 2)) & 0xFF])
    end
  end
  def gen_spin_unlock(node)
    eval_expression(node[:args][0]) # rax = ptr
    if @arch == :x86_64
      @emitter.mov_reg_reg(7, 0) # rdi = rax
      @emitter.mov_rax(0)
      @emitter.emit([0x48, 0x89, 0x07]) # mov [rdi], rax
    end
  end
  def gen_CLONE_VM(node); @emitter.mov_rax(0x100); end
  def gen_CLONE_FS(node); @emitter.mov_rax(0x200); end
  def gen_CLONE_FILES(node); @emitter.mov_rax(0x400); end
  def gen_CLONE_SIGHAND(node); @emitter.mov_rax(0x800); end
  def gen_CLONE_THREAD(node); @emitter.mov_rax(0x10000); end
end
