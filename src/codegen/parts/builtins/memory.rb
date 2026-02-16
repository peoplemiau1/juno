# Memory built-in functions for Juno

module BuiltinMemory
  def gen_alloc(node)
    return unless @target_os == :linux
    eval_expression(node[:args][0])
    if @arch == :aarch64
      @emitter.mov_reg_reg(1, 0); @emitter.mov_rax(0); @emitter.mov_reg_reg(0, 0)
      @emitter.mov_rax(3); @emitter.mov_reg_reg(2, 0); @emitter.mov_rax(0x22); @emitter.mov_reg_reg(3, 0)
      @emitter.mov_rax(0xFFFFFFFFFFFFFFFF); @emitter.mov_reg_reg(4, 0); @emitter.mov_rax(0); @emitter.mov_reg_reg(5, 0)
      @emitter.mov_rax(222); @emitter.mov_reg_reg(8, 0); @emitter.emit32(0xd4000001)
    else
      @emitter.mov_reg_reg(6, 0); @emitter.mov_rax(0); @emitter.mov_reg_reg(7, 0)
      @emitter.mov_rax(3); @emitter.mov_reg_reg(2, 0); @emitter.mov_rax(0x22); @emitter.mov_reg_reg(10, 0)
      @emitter.mov_rax(0xFFFFFFFFFFFFFFFF); @emitter.mov_reg_reg(8, 0); @emitter.mov_rax(0); @emitter.mov_reg_reg(9, 0)
      @emitter.mov_rax(9); @emitter.emit([0x0f, 0x05])
    end
  end

  def gen_free(node)
    return unless @target_os == :linux
    args = node[:args] || []
    return if args.empty?
    eval_expression(args[0])
    if @arch == :aarch64
       @emitter.mov_rax(0)
    else
       if args.length >= 2
         @emitter.push_reg(0); eval_expression(args[1]); @emitter.mov_reg_reg(6, 0); @emitter.pop_reg(7)
         @emitter.mov_rax(11); @emitter.emit([0x0f, 0x05])
       else
         @emitter.emit([0x48, 0x83, 0xe8, 0x08, 0x48, 0x89, 0xc7, 0x48, 0x8b, 0x37, 0xb8, 11, 0, 0, 0, 0x0f, 0x05])
       end
    end
  end
end
