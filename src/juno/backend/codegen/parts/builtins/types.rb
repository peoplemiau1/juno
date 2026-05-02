# Type operations and pointer arithmetic for Juno

module BuiltinTypes
  def gen_ptr_add(node)
    eval_expression(node[:args][0]); @emitter.push_reg(0)
    eval_expression(node[:args][1]); @emitter.shl_rax_imm(3)
    @emitter.mov_reg_reg(2, 0); @emitter.pop_reg(0)
    @emitter.add_rax_rdx
  end

  def gen_byte_add(node)
    eval_expression(node[:args][0]); @emitter.push_reg(0)
    eval_expression(node[:args][1])
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
    if @arch == :aarch64
      @emitter.emit32(0x93401c00) # sxtb x0, w0
    else
      @emitter.emit([0x48, 0x0f, 0xbe, 0xc0]) # movsx rax, al
    end
  end

  def gen_cast_u8(node)
    eval_expression(node[:args][0])
    if @arch == :aarch64
      @emitter.emit32(0x53001c00) # uxtb w0, w0 (and x0, x0, #0xff)
    else
      @emitter.emit([0x48, 0x0f, 0xb6, 0xc0]) # movzx rax, al
    end
  end

  def gen_cast_i16(node); eval_expression(node[:args][0]); end
  def gen_cast_u16(node); eval_expression(node[:args][0]); end
  def gen_cast_i32(node)
    eval_expression(node[:args][0])
    if @arch == :aarch64
      @emitter.emit32(0x93407c00) # sxtw x0, w0
    else
      @emitter.emit([0x48, 0x63, 0xc0]) # movsxd rax, eax
    end
  end

  def gen_cast_u32(node)
    eval_expression(node[:args][0])
    if @arch == :aarch64
      # Already in w0, but to clear upper 32 bits of x0:
      @emitter.emit32(0x2a0003e0) # mov w0, w0
    else
      @emitter.emit([0x89, 0xc0]) # mov eax, eax (clears upper 32 bits)
    end
  end
  def gen_cast_i64(node); eval_expression(node[:args][0]); end
  def gen_cast_u64(node); eval_expression(node[:args][0]); end
end
