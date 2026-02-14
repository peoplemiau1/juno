# Utility built-in functions for Juno

module BuiltinUtils
  def gen_exit(node)
    eval_expression(node[:args][0])
    if @arch == :aarch64
      @emitter.mov_reg_reg(0, 0); @emitter.mov_rax(93); @emitter.mov_reg_reg(8, 0); @emitter.emit32(0xd4000001)
    else
      @emitter.mov_reg_reg(7, 0); @emitter.mov_rax(60); @emitter.emit([0x0f, 0x05])
    end
  end

  def gen_sleep(node)
    eval_expression(node[:args][0])
    if @arch == :aarch64
      @emitter.mov_rax(0) # stub
    else
      @emitter.emit([0x48, 0x89, 0xc1, 0x48, 0x31, 0xd2, 0x48, 0xb8] + [1000].pack("Q<").bytes)
      @emitter.emit([0x48, 0x89, 0xc3, 0x48, 0x89, 0xc8, 0x48, 0xf7, 0xf3, 0x50])
      @emitter.emit([0x48, 0x69, 0xd2] + [1000000].pack("l<").bytes)
      @emitter.emit([0x52, 0x48, 0x89, 0xe7, 0x48, 0x31, 0xf6, 0x48, 0xc7, 0xc0, 35, 0,0,0, 0x0f, 0x05, 0x48, 0x83, 0xc4, 16])
    end
  end

  def gen_time(node)
    if @arch == :aarch64
      @emitter.mov_rax(169); @emitter.mov_rax(0); @emitter.mov_reg_reg(0, 0); @emitter.emit32(0xd4000001)
    else
      @emitter.mov_rax(0); @emitter.mov_reg_reg(7, 0); @emitter.mov_rax(201); @emitter.emit([0x0f, 0x05])
    end
  end

  def gen_rand(node)
    if @arch == :aarch64
      @emitter.mov_rax(0)
    else
      @emitter.emit_load_address("rand_seed", @linker)
      @emitter.emit([0x48, 0x8b, 0x08, 0x48, 0xb8] + [1103515245].pack("Q<").bytes)
      @emitter.emit([0x48, 0x0f, 0xaf, 0xc1, 0x48, 0x05] + [12345].pack("l<").bytes)
      @emitter.push_reg(0); @emitter.emit_load_address("rand_seed", @linker)
      @emitter.pop_reg(2); @emitter.emit([0x48, 0x89, 0x10, 0x48, 0xc1, 0xe8, 0x01])
    end
  end

  def gen_srand(node)
    eval_expression(node[:args][0])
    if @arch == :aarch64
      @emitter.mov_rax(0)
    else
      @emitter.push_reg(0); @emitter.emit_load_address("rand_seed", @linker)
      @emitter.pop_reg(2); @emitter.emit([0x48, 0x89, 0x10])
    end
  end

  def gen_input(node)
    if @arch == :aarch64
      @emitter.mov_rax(0)
    else
      @emitter.mov_rax(0); @emitter.mov_reg_reg(7, 0)
      @emitter.emit_load_address("input_buffer", @linker)
      @emitter.mov_reg_reg(6, 0)
      @emitter.mov_rax(1024); @emitter.mov_reg_reg(2, 0)
      @emitter.mov_rax(0); @emitter.emit([0x0f, 0x05])
      @emitter.emit_load_address("input_buffer", @linker)
    end
  end

  def gen_write(node)
    eval_expression(node[:args][0]); @emitter.push_reg(0)
    eval_expression(node[:args][1]); @emitter.push_reg(0)
    eval_expression(node[:args][2]); @emitter.mov_reg_reg(2, 0)
    @emitter.pop_reg(6); @emitter.pop_reg(7)
    if @arch == :aarch64
      @emitter.mov_rax(64); @emitter.mov_reg_reg(8, 0); @emitter.emit32(0xd4000001)
    else
      @emitter.mov_rax(1); @emitter.emit([0x0f, 0x05])
    end
  end
end
