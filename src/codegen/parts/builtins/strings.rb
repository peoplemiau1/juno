# String built-in functions for Juno

module BuiltinStrings
  def gen_concat(node)
    eval_expression(node[:args][0]); @emitter.push_reg(0)
    eval_expression(node[:args][1]); @emitter.mov_reg_reg(2, 0); @emitter.pop_reg(6) # rsi=s1, rdx=s2
    if @arch == :aarch64
       @emitter.mov_rax(0)
    else
       @emitter.push_reg(2) # save s2
       @emitter.emit_load_address("concat_buffer", @linker)
       @emitter.mov_reg_reg(7, 0) # rdi = buffer
       @emitter.mov_reg_reg(8, 0) # r8 = buffer (for return)
       @emitter.pop_reg(2) # rdx = s2

       # Copy s1
       l1 = @emitter.current_pos; @emitter.emit([0x8a, 0x06, 0x84, 0xc0, 0x74, 0x0a, 0x88, 0x07, 0x48, 0xff, 0xc7, 0x48, 0xff, 0xc6, 0xeb, 0xf0])
       # Copy s2
       @emitter.mov_reg_reg(6, 2)
       l2 = @emitter.current_pos; @emitter.emit([0x8a, 0x06, 0x84, 0xc0, 0x74, 0x0a, 0x88, 0x07, 0x48, 0xff, 0xc7, 0x48, 0xff, 0xc6, 0xeb, 0xf0])
       @emitter.emit([0xc6, 0x07, 0x00, 0x4c, 0x89, 0xc0]) # null terminate and return r8
    end
  end

  def gen_substr(node)
    eval_expression(node[:args][0]); @emitter.push_reg(0)
    eval_expression(node[:args][1]); @emitter.push_reg(0)
    eval_expression(node[:args][2]); @emitter.mov_reg_reg(1, 0) # rcx = len
    @emitter.pop_reg(2); @emitter.pop_reg(6) # rdx=start, rsi=s
    if @arch == :aarch64
       @emitter.mov_rax(0)
    else
       @emitter.emit([0x48, 0x01, 0xd6]) # rsi = s + start
       @emitter.emit_load_address("substr_buffer", @linker)
       @emitter.mov_reg_reg(7, 0); @emitter.mov_reg_reg(8, 0)
       @emitter.emit([0xf3, 0xa4, 0xc6, 0x07, 0x00, 0x4c, 0x89, 0xc0])
    end
  end

  def gen_chr(node)
    eval_expression(node[:args][0])
    if @arch == :aarch64
       @emitter.mov_rax(0)
    else
       @emitter.push_reg(0)
       @emitter.emit_load_address("chr_buffer", @linker)
       @emitter.mov_reg_reg(7, 0)
       @emitter.pop_reg(0)
       @emitter.emit([0x88, 0x07, 0xc6, 0x47, 0x01, 0x00, 0x48, 0x89, 0xf8])
    end
  end

  def gen_ord(node)
    eval_expression(node[:args][0])
    @emitter.mov_rax_mem_sized(1, false)
  end

  def gen_prints(node)
    eval_expression(node[:args][0])
    if @arch == :aarch64
       @emitter.mov_rax(0)
    else
       @emitter.mov_reg_reg(6, 0); @emitter.mov_rax(0); @emitter.mov_reg_reg(1, 0)
       l = @emitter.current_pos; @emitter.emit([0x80, 0x3c, 0x0e, 0x00, 0x74, 0x05, 0x48, 0xff, 0xc1, 0xeb, 0xf5])
       @emitter.mov_reg_reg(2, 1); @emitter.mov_rax(1); @emitter.mov_reg_reg(7, 0); @emitter.emit([0x0f, 0x05])
       @emitter.emit_load_address("newline_char", @linker)
       @emitter.mov_reg_reg(6, 0); @emitter.mov_rax(1); @emitter.mov_reg_reg(2, 0); @emitter.mov_reg_reg(7, 0); @emitter.emit([0x0f, 0x05])
    end
  end
end
