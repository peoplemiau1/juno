# Collections - dynamic arrays (vectors)
# vec_new, vec_push, vec_pop, vec_get, vec_set, vec_len

module BuiltinCollections
  def setup_collections
    return if @collections_setup
    @collections_setup = true
    @linker.add_data("vec_storage", "\x00" * 65536)
    @linker.add_data("vec_storage_ptr", [0].pack("Q<"))
  end

  def gen_vec_new(node)
    setup_collections
    args = node[:args] || []
    if args[0] then eval_expression(args[0]) else @emitter.mov_rax(16) end

    @emitter.mov_reg_reg(4, 0) # r12/x4 = capacity
    @emitter.shl_rax_imm(3)
    @emitter.emit_add_rax(16) # total size = capacity*8 + 16
    @emitter.mov_reg_reg(5, 0) # r13/x5 = total size

    @emitter.emit_load_address("vec_storage_ptr", @linker)
    @emitter.mov_reg_reg(@arch == :aarch64 ? 6 : 14, 0) # ptr_addr
    @emitter.mov_rax_mem(0) # rax = current offset
    @emitter.push_reg(0) # save current offset

    @emitter.emit_load_address("vec_storage", @linker)
    @emitter.mov_reg_reg(2, 0)
    @emitter.pop_reg(0)
    @emitter.add_rax_rdx # rax = absolute address of new vector
    @emitter.mov_reg_reg(@arch == :aarch64 ? 7 : 15, 0) # r15/x7 = vec_ptr

    # Update storage ptr
    @emitter.mov_rax_mem_idx(@arch == :aarch64 ? 6 : 14, 0)
    @emitter.mov_reg_reg(2, 5) # total size
    @emitter.add_rax_rdx
    @emitter.mov_mem_idx(@arch == :aarch64 ? 6 : 14, 0, 0, 8)

    # Init vec header
    @emitter.mov_reg_reg(0, 4) # capacity
    @emitter.mov_mem_idx(@arch == :aarch64 ? 7 : 15, 0, 0, 8)
    @emitter.mov_rax(0) # len
    @emitter.mov_mem_idx(@arch == :aarch64 ? 7 : 15, 8, 0, 8)

    @emitter.mov_reg_reg(0, @arch == :aarch64 ? 7 : 15)
  end

  def gen_vec_push(node)
    eval_expression(node[:args][1]); @emitter.push_reg(0) # value
    eval_expression(node[:args][0]); @emitter.push_reg(0) # vec
    @emitter.pop_reg(@arch == :aarch64 ? 4 : 12) # vec
    @emitter.pop_reg(@arch == :aarch64 ? 5 : 13) # value

    @emitter.mov_rax_mem_idx(@arch == :aarch64 ? 4 : 12, 8) # len
    @emitter.mov_reg_reg(2, 0) # len
    @emitter.mov_rax_mem_idx(@arch == :aarch64 ? 4 : 12, 0) # cap
    @emitter.cmp_rax_rdx(">") # if cap > len
    p = @emitter.je_rel32 # simplified: if cap <= len skip

    @emitter.mov_reg_reg(0, 2) # len
    @emitter.shl_rax_imm(3)
    @emitter.emit_add_rax(16)
    @emitter.mov_reg_reg(2, @arch == :aarch64 ? 4 : 12)
    @emitter.add_rax_rdx # rax = slot addr
    @emitter.mov_mem_idx(0, 0, @arch == :aarch64 ? 5 : 13, 8)

    # Increment len
    @emitter.mov_rax_mem_idx(@arch == :aarch64 ? 4 : 12, 8)
    @emitter.emit_add_rax(1)
    @emitter.mov_mem_idx(@arch == :aarch64 ? 4 : 12, 8, 0, 8)

    @emitter.patch_je(p, @emitter.current_pos)
    @emitter.mov_reg_reg(0, @arch == :aarch64 ? 4 : 12)
  end

  def gen_vec_len(node)
    eval_expression(node[:args][0])
    @emitter.mov_rax_mem_idx(0, 8)
  end

  def gen_vec_get(node)
    eval_expression(node[:args][1]); @emitter.push_reg(0) # index
    eval_expression(node[:args][0]); @emitter.pop_reg(1) # vec
    @emitter.mov_reg_reg(2, 1)
    @emitter.shl_rax_imm(3)
    @emitter.emit_add_rax(16)
    @emitter.add_rax_rdx
    @emitter.mov_rax_mem(0)
  end
end
