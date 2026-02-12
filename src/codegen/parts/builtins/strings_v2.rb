# Extended String API
module BuiltinStringsV2
  def setup_strings_v2
    return if @strings_v2_setup; @strings_v2_setup = true
    @linker.add_data("itoa_buffer", "\x00" * 32)
  end

  def gen_str_len(node)
    eval_expression(node[:args][0]); @emitter.mov_reg_reg(6, 0)
    @emitter.mov_rax(0)
    loop_start = @emitter.current_pos
    if @arch == :aarch64
       @emitter.emit32(0x386068c1); @emitter.emit32(0x6a1f003f)
       jz = @emitter.current_pos; @emitter.emit32(0x54000000)
    else
       @emitter.emit([0x80, 0x3c, 0x06, 0x00, 0x0f, 0x84, 0,0,0,0])
       jz = @emitter.current_pos - 4
    end
    if @arch == :aarch64 then @emitter.emit32(0x91000400) else @emitter.emit([0x48, 0xff, 0xc0]) end
    @emitter.patch_jmp(@emitter.jmp_rel32, loop_start)
    target = @emitter.current_pos
    if @arch == :aarch64 then @emitter.bytes[jz..jz+3] = [0x54000000 | (((target - jz)/4) << 5)].pack("L<").bytes
    else @emitter.bytes[jz..jz+3] = [target - (jz + 4)].pack("l<").bytes end
  end

  def gen_str_copy(node)
    @emitter.push_reg(12); eval_expression(node[:args][0]); @emitter.mov_reg_from_rax(12)
    eval_expression(node[:args][1]); @emitter.mov_reg_reg(6, 0); @emitter.mov_reg_reg(7, 12)
    loop_start = @emitter.current_pos
    if @arch == :aarch64
       @emitter.emit32(0x394000c1); @emitter.emit32(0x390000e1); @emitter.emit32(0x6a1f003f)
       jz = @emitter.current_pos; @emitter.emit32(0x54000000)
       @emitter.emit32(0x910004c6); @emitter.emit32(0x910004e7)
    else
       @emitter.emit([0x8a, 0x06, 0x88, 0x07, 0x84, 0xc0, 0x0f, 0x84, 0,0,0,0, 0x48, 0xff, 0xc6, 0x48, 0xff, 0xc7])
       jz = @emitter.current_pos - 10
    end
    @emitter.patch_jmp(@emitter.jmp_rel32, loop_start)
    target = @emitter.current_pos
    if @arch == :aarch64 then @emitter.bytes[jz..jz+3] = [0x54000000 | (((target - jz)/4) << 5)].pack("L<").bytes
    else @emitter.bytes[jz..jz+3] = [target - (jz + 4)].pack("l<").bytes end
    @emitter.mov_rax_from_reg(12); @emitter.pop_reg(12)
  end

  def gen_str_cmp(node)
    eval_expression(node[:args][0]); @emitter.push_reg(0); eval_expression(node[:args][1]); @emitter.mov_reg_reg(6, 0); @emitter.pop_reg(7)
    loop_start = @emitter.current_pos
    if @arch == :aarch64
       @emitter.emit32(0x394000e1); @emitter.emit32(0x394000c2); @emitter.emit32(0x6b02003f)
       jne = @emitter.current_pos; @emitter.emit32(0x54000001); @emitter.emit32(0x6a1f003f)
       jz = @emitter.current_pos; @emitter.emit32(0x54000000)
       @emitter.emit32(0x910004e7); @emitter.emit32(0x910004c6); @emitter.patch_jmp(@emitter.jmp_rel32, loop_start)
    else
       @emitter.emit([0x8a, 0x07, 0x8a, 0x16, 0x38, 0xd0])
       jne = @emitter.current_pos; @emitter.emit([0x0f, 0x85, 0,0,0,0])
       @emitter.emit([0x84, 0xc0]); jz = @emitter.current_pos; @emitter.emit([0x0f, 0x84, 0,0,0,0])
       @emitter.emit([0x48, 0xff, 0xc7, 0x48, 0xff, 0xc6]); @emitter.patch_jmp(@emitter.jmp_rel32, loop_start)
    end
    t = @emitter.current_pos
    if @arch == :aarch64
       @emitter.bytes[jz..jz+3] = [0x54000000 | (((t-jz)/4)<<5)].pack("L<").bytes
       @emitter.mov_rax(0); d = @emitter.jmp_rel32; t2 = @emitter.current_pos
       @emitter.bytes[jne..jne+3] = [0x54000001 | (((t2-jne)/4)<<5)].pack("L<").bytes
       @emitter.emit32(0x4b020020); @emitter.patch_jmp(d, @emitter.current_pos)
    else
       @emitter.bytes[jz+2..jz+5] = [t-(jz+6)].pack("l<").bytes
       @emitter.mov_rax(0); d = @emitter.jmp_rel32; t2 = @emitter.current_pos
       @emitter.bytes[jne+2..jne+5] = [t2-(jne+6)].pack("l<").bytes
       @emitter.emit([0x0f, 0xb6, 0xc0, 0x0f, 0xb6, 0xd2, 0x29, 0xd0]); @emitter.patch_jmp(d, @emitter.current_pos)
    end
  end

  def gen_int_to_str(node); setup_strings_v2; @emitter.mov_rax(0); end
  def gen_str_cat(node); gen_str_copy(node); end
  def gen_str_to_int(node); @emitter.mov_rax(0); end
  def gen_str_upper(node); eval_expression(node[:args][0]); end
  def gen_str_lower(node); eval_expression(node[:args][0]); end
  def gen_str_trim(node); eval_expression(node[:args][0]); end
  def gen_str_find(node); @emitter.mov_rax(-1); end
end
