# Utility built-in functions for Juno
module BuiltinUtils
  # exit(code)
  def gen_exit(node)
    eval_expression(node[:args][0])
    
    if @target_os == :linux
      @emitter.emit([0x48, 0x89, 0xc7])             # mov rdi, rax
      @emitter.emit([0x48, 0xc7, 0xc0, 60, 0, 0, 0]) # mov rax, 60
      @emitter.emit([0x0f, 0x05])
    else
      # Windows ExitProcess(code)
      @emitter.emit_sub_rsp(32)
      @emitter.mov_reg_reg(CodeEmitter::REG_RCX, CodeEmitter::REG_RAX)
      @linker.add_import_patch(@emitter.current_pos + 2, "ExitProcess")
      @emitter.call_ind_rel32
      @emitter.emit_add_rsp(32)
    end
  end

  # sleep(ms)
  def gen_sleep(node)
    eval_expression(node[:args][0])
    
    if @target_os == :linux
      @emitter.emit([0x48, 0x89, 0xc1]) # mov rcx, rax
      @emitter.emit([0x48, 0x31, 0xd2, 0x48, 0xb8] + [1000].pack("Q<").bytes + [0x48, 0x89, 0xc3, 0x48, 0x89, 0xc8, 0x48, 0xf7, 0xf3, 0x50])
      @emitter.emit([0x48, 0x69, 0xd2] + [1000000].pack("l<").bytes + [0x52, 0x48, 0x89, 0xe7, 0x48, 0x31, 0xf6, 0x48, 0xc7, 0xc0, 35, 0, 0, 0, 0x0f, 0x05, 0x48, 0x83, 0xc4, 16])
    else
      # Windows Sleep(ms)
      @emitter.emit_sub_rsp(32)
      @emitter.mov_reg_reg(CodeEmitter::REG_RCX, CodeEmitter::REG_RAX)
      @linker.add_import_patch(@emitter.current_pos + 2, "Sleep")
      @emitter.call_ind_rel32
      @emitter.emit_add_rsp(32)
    end
  end

  # time() - unix timestamp
  def gen_time(node)
    return unless @target_os == :linux
    
    @emitter.emit([0x48, 0x31, 0xff])
    @emitter.emit([0x48, 0xc7, 0xc0, 201, 0, 0, 0])
    @emitter.emit([0x0f, 0x05])
  end

  # rand()
  def gen_rand(node)
    @emitter.emit([0x48, 0x8d, 0x05])
    @linker.add_data_patch(@emitter.current_pos, "rand_seed")
    @emitter.emit([0x00, 0x00, 0x00, 0x00])
    
    @emitter.emit([0x48, 0x8b, 0x08])
    @emitter.emit([0x48, 0xb8] + [1103515245].pack("Q<").bytes)
    @emitter.emit([0x48, 0x0f, 0xaf, 0xc1])
    @emitter.emit([0x48, 0x05] + [12345].pack("l<").bytes)
    
    @emitter.emit([0x48, 0x8d, 0x0d])
    @linker.add_data_patch(@emitter.current_pos, "rand_seed")
    @emitter.emit([0x00, 0x00, 0x00, 0x00])
    @emitter.emit([0x48, 0x89, 0x01])
    @emitter.emit([0x48, 0xc1, 0xe8, 0x01])
  end

  # srand(seed)
  def gen_srand(node)
    eval_expression(node[:args][0])
    
    @emitter.emit([0x48, 0x8d, 0x0d])
    @linker.add_data_patch(@emitter.current_pos, "rand_seed")
    @emitter.emit([0x00, 0x00, 0x00, 0x00])
    @emitter.emit([0x48, 0x89, 0x01])
  end

  # input() - read from stdin
  def gen_input(node)
    return unless @target_os == :linux
    
    @emitter.emit([0x48, 0x31, 0xff])
    
    @emitter.emit([0x48, 0x8d, 0x35])
    @linker.add_data_patch(@emitter.current_pos, "input_buffer")
    @emitter.emit([0x00, 0x00, 0x00, 0x00])
    
    @emitter.emit([0x48, 0xc7, 0xc2, 0x00, 0x04, 0x00, 0x00])
    @emitter.emit([0x48, 0xc7, 0xc0, 0, 0, 0, 0])
    @emitter.emit([0x0f, 0x05])
    
    @emitter.emit([0x48, 0x8d, 0x35])
    @linker.add_data_patch(@emitter.current_pos, "input_buffer")
    @emitter.emit([0x00, 0x00, 0x00, 0x00])
    @emitter.emit([0x48, 0xff, 0xc8])
    @emitter.emit([0xc6, 0x04, 0x06, 0x00])
    @emitter.emit([0x48, 0x89, 0xf0])
  end

  # write(fd, buf, len)
  def gen_write(node)
    return unless @target_os == :linux
    
    eval_expression(node[:args][0])
    @emitter.emit([0x50])
    
    eval_expression(node[:args][1])
    @emitter.emit([0x50])
    
    eval_expression(node[:args][2])
    @emitter.emit([0x48, 0x89, 0xc2])
    @emitter.emit([0x5e, 0x5f])
    
    @emitter.emit([0x48, 0xc7, 0xc0, 1, 0, 0, 0])
    @emitter.emit([0x0f, 0x05])
  end
end
