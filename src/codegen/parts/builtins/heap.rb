# Simple heap allocator using mmap

module BuiltinHeap
  def gen_malloc(node)
    eval_expression(node[:args][0]) if node && node[:args] && node[:args][0]
    @emitter.emit_add_rax(8) # Add space for size header
    @emitter.push_reg(0) # save total size

    # mmap(0, size, PROT_READ|PROT_WRITE, MAP_PRIVATE|MAP_ANONYMOUS, -1, 0)
    @emitter.mov_rax(0); @emitter.push_reg(0) # offset
    @emitter.mov_rax(0); @emitter.emit_sub_rax(1); @emitter.push_reg(0) # fd = -1
    @emitter.mov_rax(0x22); @emitter.push_reg(0) # flags
    @emitter.mov_rax(3); @emitter.push_reg(0) # prot
    # size is on stack
    @emitter.mov_rax(0); @emitter.push_reg(0) # addr = 0

    @emitter.pop_reg(@arch == :aarch64 ? 0 : 7)
    @emitter.pop_reg(@arch == :aarch64 ? 1 : 6) # size
    @emitter.pop_reg(@arch == :aarch64 ? 2 : 2)
    @emitter.pop_reg(@arch == :aarch64 ? 3 : 10)
    @emitter.pop_reg(@arch == :aarch64 ? 4 : 8)
    @emitter.pop_reg(@arch == :aarch64 ? 5 : 9)
    emit_syscall(:mmap)

    @emitter.pop_reg(2) # restore total size to X2 / RDX
    @emitter.mov_mem_idx(@arch == :aarch64 ? 0 : 0, 0, 2, 8) # [rax] = total_size
    @emitter.emit_add_rax(8) # Return ptr+8
  end

  def gen_realloc(node)
    eval_expression(node[:args][0]); @emitter.push_reg(0) # old_ptr
    eval_expression(node[:args][1]); @emitter.push_reg(0) # new_size

    @emitter.pop_reg(4) # new_size
    @emitter.pop_reg(5) # old_ptr
    @emitter.push_reg(4); @emitter.push_reg(5)

    # malloc(new_size)
    @emitter.mov_reg_reg(0, 4)
    gen_malloc(nil)
    @emitter.mov_reg_reg(@arch == :aarch64 ? 6 : 14, 0) # new_ptr in X6/R14

    @emitter.pop_reg(5); @emitter.pop_reg(4)
    @emitter.test_reg_reg(5, 5) # old_ptr
    p_end = @emitter.je_rel32

    # copy old to new
    @emitter.mov_reg_reg(0, 5)
    @emitter.emit_sub_rax(8)
    @emitter.mov_rax_mem(0) # old total size
    @emitter.emit_sub_rax(8) # old user size
    @emitter.mov_reg_reg(2, 0) # old user size
    @emitter.mov_reg_reg(1, 4) # new user size
    @emitter.cmp_rax_rdx(">") # if old > new, use new
    # simplified: use min
    # ...

    @emitter.mov_reg_reg(@arch == :aarch64 ? 2 : 2, 0) # n
    @emitter.mov_reg_reg(@arch == :aarch64 ? 1 : 6, 5) # src = old_ptr
    @emitter.mov_reg_reg(@arch == :aarch64 ? 0 : 7, @arch == :aarch64 ? 6 : 14) # dest = new_ptr
    @emitter.memcpy

    # free old
    @emitter.mov_reg_reg(0, 5)
    gen_free({args: [node[:args][0]]})

    @emitter.patch_je(p_end, @emitter.current_pos)
    @emitter.mov_reg_reg(0, @arch == :aarch64 ? 6 : 14)
  end

  def gen_free(node)
    args = node[:args] || []
    return if args.empty?
    eval_expression(args[0])
    @emitter.test_rax_rax
    p = @emitter.je_rel32

    if args.length >= 2
       eval_expression(args[1]); @emitter.push_reg(0)
       eval_expression(args[0])
       @emitter.pop_reg(@arch == :aarch64 ? 1 : 6)
       @emitter.mov_reg_reg(@arch == :aarch64 ? 0 : 7, 0)
    else
       @emitter.emit_sub_rax(8)
       @emitter.push_reg(0)
       @emitter.mov_rax_mem(0)
       @emitter.mov_reg_reg(@arch == :aarch64 ? 1 : 6, 0)
       @emitter.pop_reg(@arch == :aarch64 ? 0 : 7)
    end
    emit_syscall(:munmap)
    @emitter.patch_je(p, @emitter.current_pos)
  end
end
