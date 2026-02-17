# Math built-in functions for Juno

module BuiltinMath
  def gen_abs(node)
    eval_expression(node[:args][0])
    @emitter.mov_reg_reg(2, 0) # X2/RDX = val
    if @arch == :aarch64
      # neg x1, x0
      @emitter.emit32(0xcb0003e1)
      # cmp x0, #0
      @emitter.test_rax_rax
      # csel x0, x0, x1, ge
      @emitter.csel(">=", 0, 0, 1)
    else
      @emitter.emit([0x48, 0xc1, 0xfa, 0x3f, 0x48, 0x31, 0xd0, 0x48, 0x29, 0xd0])
    end
  end

  def gen_min(node)
    eval_expression(node[:args][0]); @emitter.push_reg(0)
    eval_expression(node[:args][1]); @emitter.mov_reg_reg(2, 0); @emitter.pop_reg(0)
    # cmp rax, rdx
    if @arch == :aarch64 then @emitter.emit32(0xeb02001f) else @emitter.emit([0x48, 0x39, 0xd0]) end
    if @arch == :aarch64
       @emitter.csel("<", 0, 0, 2)
    else
       @emitter.cmov("<", 0, 2)
    end
  end

  def gen_max(node)
    eval_expression(node[:args][0]); @emitter.push_reg(0)
    eval_expression(node[:args][1]); @emitter.mov_reg_reg(2, 0); @emitter.pop_reg(0)
    if @arch == :aarch64 then @emitter.emit32(0xeb02001f) else @emitter.emit([0x48, 0x39, 0xd0]) end
    if @arch == :aarch64
       @emitter.csel(">", 0, 0, 2)
    else
       @emitter.cmov(">", 0, 2)
    end
  end

  def gen_pow(node)
    eval_expression(node[:args][0]); @emitter.push_reg(0) # base
    eval_expression(node[:args][1]); @emitter.mov_reg_reg(1, 0); @emitter.pop_reg(2) # X1/RCX = exp, X2/RDX = base
    @emitter.mov_rax(1)
    l = @emitter.current_pos
    @emitter.test_reg_reg(1, 1)
    p_end = @emitter.je_rel32
    @emitter.imul_rax_rdx
    if @arch == :aarch64
       @emitter.emit_sub_imm(1, 1, 1)
    else
       @emitter.emit([0x48, 0xff, 0xc9]) # dec rcx
    end
    p_loop = @emitter.jmp_rel32
    @emitter.patch_jmp(p_loop, l)
    @emitter.patch_je(p_end, @emitter.current_pos)
  end
end
