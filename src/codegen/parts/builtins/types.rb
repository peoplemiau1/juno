# Type operations and pointer arithmetic for Juno

module BuiltinTypes
  def gen_ptr_add(node)
    eval_expression(node[:args][0]); @emitter.push_reg(0)
    eval_expression(node[:args][1]); @emitter.shl_rax_imm(3)
    @emitter.mov_reg_reg(2, 0); @emitter.pop_reg(0)
    @emitter.add_rax_rdx
  end

  def gen_ptr_sub(node)
    eval_expression(node[:args][0]); @emitter.push_reg(0)
    eval_expression(node[:args][1]); @emitter.shl_rax_imm(3)
    @emitter.mov_reg_reg(2, 0); @emitter.pop_reg(0)
    @emitter.sub_rax_rdx
  end

  def gen_ptr_diff(node)
    eval_expression(node[:args][0]); @emitter.push_reg(0)
    eval_expression(node[:args][1]); @emitter.mov_reg_reg(2, 0); @emitter.pop_reg(0)
    @emitter.sub_rax_rdx
    @emitter.shr_rax_imm(3)
  end

  def gen_sizeof(node)
    arg = node[:args][0]
    if arg[:type] == :variable
      @emitter.mov_rax(@ctx.type_size(arg[:name]))
    else
      @emitter.mov_rax(8)
    end
  end

  def gen_cast_i8(node)
    eval_expression(node[:args][0])
    @emitter.mov_rax_mem_sized(1, true) rescue @emitter.mov_rax(0) # simplified
  end

  def gen_cast_u8(node)
    eval_expression(node[:args][0])
    @emitter.mov_rax_mem_sized(1, false) rescue @emitter.mov_rax(0)
  end

  def gen_cast_i16(node); eval_expression(node[:args][0]); end
  def gen_cast_u16(node); eval_expression(node[:args][0]); end
  def gen_cast_i32(node); eval_expression(node[:args][0]); end
  def gen_cast_u32(node); eval_expression(node[:args][0]); end
  def gen_cast_i64(node); eval_expression(node[:args][0]); end
  def gen_cast_u64(node); eval_expression(node[:args][0]); end
end
