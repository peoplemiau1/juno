# Utility built-in functions for Juno

module BuiltinUtils
  def gen_exit(node)
    eval_expression(node[:args][0])
    if @arch == :aarch64
      @emitter.push_reg(0) # save exit code
      @emitter.mov_rax(93); @emitter.mov_reg_reg(8, 0) # x8 = 93
      @emitter.pop_reg(0) # restore code to x0
      @emitter.syscall
    else
      @emitter.mov_reg_reg(7, 0) # rdi = code
      @emitter.mov_rax(60); @emitter.syscall
    end
  end

  def gen_sleep(node)
    eval_expression(node[:args][0])
    if @arch == :aarch64
      # nanosleep(timespec: {sec, nsec}, rem)
      @emitter.mov_reg_reg(19, 0) # X19 = ms
      @emitter.emit32(0xd10043ff) # sub sp, sp, #16

      # sec = ms / 1000
      @emitter.mov_rax(1000); @emitter.mov_reg_reg(1, 0) # X1 = 1000
      @emitter.mov_reg_reg(0, 19) # X0 = ms
      @emitter.emit32(0x9ac10802) # sdiv x2, x0, x1 (sec)
      @emitter.emit32(0x9b018043) # msub x3, x2, x1, x0 (ms % 1000)

      # nsec = (ms % 1000) * 1000000
      @emitter.mov_rax(1000000); @emitter.mov_reg_reg(1, 0) # X1 = 1M
      @emitter.emit32(0x9b017c61) # mul x1, x3, x1 (nsec)

      @emitter.emit32(0xa90007e2) # stp x2, x1, [sp] (sec, nsec)
      @emitter.mov_reg_reg(0, 31) # x0 = sp
      @emitter.mov_rax(0); @emitter.mov_reg_reg(1, 0) # x1 = NULL
      @emitter.mov_rax(101); @emitter.mov_reg_reg(8, 0); @emitter.syscall
      @emitter.emit32(0x910043ff) # add sp, sp, #16
    else
      @emitter.emit([0x48, 0x89, 0xc1, 0x48, 0x31, 0xd2, 0x48, 0xb8] + [1000].pack("Q<").bytes)
      @emitter.emit([0x48, 0x89, 0xc3, 0x48, 0x89, 0xc8, 0x48, 0xf7, 0xf3, 0x50])
      @emitter.emit([0x48, 0x69, 0xd2] + [1000000].pack("l<").bytes)
      @emitter.emit([0x52, 0x48, 0x89, 0xe7, 0x48, 0x31, 0xf6, 0x48, 0xc7, 0xc0, 35, 0,0,0, 0x0f, 0x05, 0x48, 0x83, 0xc4, 16])
    end
  end

  def gen_time(node)
    if @arch == :aarch64
      @emitter.mov_rax(0); @emitter.mov_reg_reg(0, 0)
      @emitter.mov_rax(169); @emitter.mov_reg_reg(8, 0); @emitter.syscall
    else
      @emitter.mov_rax(0); @emitter.mov_reg_reg(7, 0); @emitter.mov_rax(201); @emitter.syscall
    end
  end

  def gen_rand(node)
    if @arch == :aarch64
      @emitter.mov_rax(0) # todo
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
      @emitter.mov_rax(0); @emitter.mov_reg_reg(0, 0) # X0 = 0 (stdin)
      @emitter.emit_load_address("input_buffer", @linker)
      @emitter.mov_reg_reg(1, 0) # X1 = buf
      @emitter.mov_rax(1024); @emitter.mov_reg_reg(2, 0) # X2 = 1024
      @emitter.mov_rax(63); @emitter.mov_reg_reg(8, 0); @emitter.syscall
      @emitter.emit_load_address("input_buffer", @linker)
    else
      @emitter.mov_rax(0); @emitter.mov_reg_reg(7, 0)
      @emitter.emit_load_address("input_buffer", @linker)
      @emitter.mov_reg_reg(6, 0)
      @emitter.mov_rax(1024); @emitter.mov_reg_reg(2, 0)
      @emitter.mov_rax(0); @emitter.syscall
      @emitter.emit_load_address("input_buffer", @linker)
    end
  end

  def gen_write(node)
    eval_expression(node[:args][0]); @emitter.push_reg(0)
    eval_expression(node[:args][1]); @emitter.push_reg(0)
    eval_expression(node[:args][2]); @emitter.mov_reg_reg(2, 0)
    if @arch == :aarch64
      @emitter.pop_reg(1); @emitter.pop_reg(0); @emitter.mov_rax(64); @emitter.mov_reg_reg(8, 0); @emitter.syscall
    else
      @emitter.pop_reg(6); @emitter.pop_reg(7); @emitter.mov_rax(1); @emitter.syscall
    end
  end
end
