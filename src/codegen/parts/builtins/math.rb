# Math built-in functions for Juno

module BuiltinMath
  def gen_abs(node)
    eval_expression(node[:args][0])
    if @arch == :aarch64
      @emitter.emit32(0x93407c01); @emitter.emit32(0xca010000); @emitter.emit32(0xcb010000)
    else
      @emitter.mov_reg_reg(2, 0); @emitter.emit([0x48, 0xc1, 0xfa, 0x3f, 0x48, 0x31, 0xd0, 0x48, 0x29, 0xd0])
    end
  end

  def gen_min(node)
    eval_expression(node[:args][0]); @emitter.push_reg(0)
    eval_expression(node[:args][1]); @emitter.mov_reg_reg(2, 0); @emitter.pop_reg(0)
    if @arch == :aarch64
      @emitter.emit32(0xeb02001f); @emitter.emit32(0x9a82a000)
    else
      @emitter.emit([0x48, 0x39, 0xd0, 0x48, 0x0f, 0x4f, 0xc2])
    end
  end

  def gen_max(node)
    eval_expression(node[:args][0]); @emitter.push_reg(0)
    eval_expression(node[:args][1]); @emitter.mov_reg_reg(2, 0); @emitter.pop_reg(0)
    if @arch == :aarch64
      @emitter.emit32(0xeb02001f); @emitter.emit32(0x9a82b000)
    else
      @emitter.emit([0x48, 0x39, 0xd0, 0x48, 0x0f, 0x4c, 0xc2])
    end
  end

  def gen_pow(node)
    eval_expression(node[:args][0]); @emitter.push_reg(0)
    eval_expression(node[:args][1]); @emitter.mov_reg_reg(1, 0); @emitter.pop_reg(2)
    @emitter.mov_rax(1)
    if @arch == :aarch64
       @emitter.emit32(0xeb00003f); @emitter.emit32(0x54000060) # cmp x1, 0; b.eq +12
       @emitter.emit32(0x9b027c00); @emitter.emit32(0xd1000421); @emitter.emit32(0x17fffffd)
    else
       @emitter.emit([0x48, 0x85, 0xc9, 0x74, 0x09, 0x48, 0x0f, 0xaf, 0xc2, 0x48, 0xff, 0xc9, 0xeb, 0xf2])
    end
  end
end
