# Memory built-in functions for Juno
module BuiltinMemory
  def gen_alloc(node)
    return unless @target_os == :linux
    eval_expression(node[:args][0]); @emitter.mov_reg_reg(@emitter.class::REG_RSI, @emitter.class::REG_RAX)
    if @arch == :aarch64
      @emitter.mov_rax(0); @emitter.mov_reg_reg(0, 0); @emitter.mov_rax(3); @emitter.mov_reg_reg(2, 0)
      @emitter.mov_rax(0x22); @emitter.mov_reg_reg(3, 0); @emitter.mov_rax(0xFFFFFFFFFFFFFFFF); @emitter.mov_reg_reg(4, 0)
      @emitter.mov_rax(0); @emitter.mov_reg_reg(5, 0); @emitter.mov_rax(222); @emitter.mov_reg_reg(8, 0); @emitter.emit32(0xd4000001)
    else
      @emitter.emit([0x48, 0x31, 0xff, 0xba, 0x03, 0x00, 0x00, 0x00, 0x41, 0xba, 0x22, 0x00, 0x00, 0x00, 0x49, 0x83, 0xc8, 0xff, 0x4d, 0x31, 0xc9, 0xb8, 0x09, 0x00, 0x00, 0x00, 0x0f, 0x05])
    end
  end

  def gen_ptr_add(node)
    eval_expression(node[:args][0]); @emitter.push_reg(@emitter.class::REG_RAX)
    eval_expression(node[:args][1]); @emitter.mov_reg_reg(@emitter.class::REG_RDX, @emitter.class::REG_RAX)
    @emitter.pop_reg(@emitter.class::REG_RAX); @emitter.add_rax_rdx
  end

  def gen_ptr_sub(node)
    eval_expression(node[:args][0]); @emitter.push_reg(@emitter.class::REG_RAX)
    eval_expression(node[:args][1]); @emitter.mov_reg_reg(@emitter.class::REG_RDX, @emitter.class::REG_RAX)
    @emitter.pop_reg(@emitter.class::REG_RAX); @emitter.sub_rax_rdx
  end

  def gen_ptr_diff(node)
    eval_expression(node[:args][0]); @emitter.push_reg(@emitter.class::REG_RAX)
    eval_expression(node[:args][1]); @emitter.mov_reg_reg(@emitter.class::REG_RDX, @emitter.class::REG_RAX)
    @emitter.pop_reg(@emitter.class::REG_RAX); @emitter.sub_rax_rdx; @emitter.shr_rax_imm(3)
  end
end
