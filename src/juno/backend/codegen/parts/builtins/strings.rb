module BuiltinStrings
  def gen_concat(node)
    eval_expression(node[:args][0]); @emitter.push_reg(0)
    eval_expression(node[:args][1]); @emitter.mov_reg_reg(2, 0); @emitter.pop_reg(6)
    if @arch == :aarch64
       @emitter.push_reg(2)

       @emitter.emit_load_address("concat_buffer_idx", @linker)
       @emitter.mov_reg_reg(10, 0)
       @emitter.mov_rax_mem_idx(10, 0)
       @emitter.mov_reg_reg(9, 0)
       @emitter.emit_add_imm(0, 0, 1)
       @emitter.mov_mem_reg_idx(10, 0, 0, 8)

       @emitter.mov_reg_reg(0, 9)
       @emitter.mov_reg_imm(1, 15); @emitter.and_rax_reg(1)

       @emitter.shl_rax_imm(16)
       @emitter.mov_reg_reg(9, 0)
       @emitter.emit_load_address("concat_buffer_pool", @linker)
       @emitter.add_rax_reg(9)

       @emitter.mov_reg_reg(10, 0)
       @emitter.mov_reg_reg(11, 0)
       @emitter.pop_reg(2)

       l1 = @emitter.current_pos
       @emitter.emit32(0x384004c3)
       @emitter.emit32(0x6b1f007f)
       p_end1 = @emitter.je_rel32
       @emitter.emit32(0x38000563)
       p_loop1 = @emitter.jmp_rel32
       @emitter.patch_jmp(p_loop1, l1)
       @emitter.patch_je(p_end1, @emitter.current_pos)

       l2 = @emitter.current_pos
       @emitter.emit32(0x38400443)
       @emitter.emit32(0x6b1f007f)
       p_end2 = @emitter.je_rel32
       @emitter.emit32(0x38000563)
       p_loop2 = @emitter.jmp_rel32
       @emitter.patch_jmp(p_loop2, l2)
       @emitter.patch_je(p_end2, @emitter.current_pos)

       @emitter.mov_reg_imm(3, 0)
       @emitter.emit32(0x38000163)
       @emitter.mov_reg_reg(0, 10)
    else
       @emitter.push_reg(2)
       @emitter.emit_load_address("concat_buffer_idx", @linker)
       @emitter.mov_reg_imm(2, 1)
       @emitter.emit_load_address("concat_buffer_idx", @linker)
       @emitter.emit([0xf0, 0x48, 0x0f, 0xc1, 0x10])
       @emitter.mov_reg_reg(0, 2)
       @emitter.emit([0x48, 0x83, 0xe0, 0x0f])
       @emitter.shl_rax_imm(16)
       @emitter.push_reg(0)
       @emitter.emit_load_address("concat_buffer_pool", @linker)
       @emitter.pop_reg(2)
       @emitter.add_rax_rdx
       @emitter.mov_reg_reg(7, 0)
       @emitter.mov_reg_reg(8, 0)
       @emitter.pop_reg(2)
       l1 = @emitter.current_pos; @emitter.emit([0x8a, 0x06, 0x84, 0xc0, 0x74, 0x0a, 0x88, 0x07, 0x48, 0xff, 0xc7, 0x48, 0xff, 0xc6, 0xeb, 0xf0])
       @emitter.mov_reg_reg(6, 2)
       l2 = @emitter.current_pos; @emitter.emit([0x8a, 0x06, 0x84, 0xc0, 0x74, 0x0a, 0x88, 0x07, 0x48, 0xff, 0xc7, 0x48, 0xff, 0xc6, 0xeb, 0xf0])
       @emitter.emit([0xc6, 0x07, 0x00, 0x4c, 0x89, 0xc0])
    end
  end

  def gen_substr(node)
    eval_expression(node[:args][0]); @emitter.push_reg(0)
    eval_expression(node[:args][1]); @emitter.push_reg(0)
    eval_expression(node[:args][2]); @emitter.mov_reg_reg(1, 0)
    @emitter.pop_reg(2); @emitter.pop_reg(6)
    if @arch == :aarch64
       @emitter.emit32(0x8b0200c6)
       @emitter.emit_load_address("substr_buffer", @linker)
       @emitter.mov_reg_reg(9, 0)
       @emitter.mov_reg_reg(10, 0)

       l = @emitter.current_pos
       @emitter.test_reg_reg(1, 1)
       p_end = @emitter.je_rel32
       @emitter.emit32(0x384004c2)
       @emitter.emit32(0x38000522)
       @emitter.emit_sub_imm(1, 1, 1)
       p_loop = @emitter.jmp_rel32
       @emitter.patch_jmp(p_loop, l)
       @emitter.patch_je(p_end, @emitter.current_pos)

       @emitter.mov_reg_imm(3, 0); @emitter.emit32(0x38000123)
       @emitter.mov_reg_reg(0, 10)
    else
       @emitter.emit([0x48, 0x01, 0xd6])
       @emitter.emit_load_address("substr_buffer", @linker)
       @emitter.mov_reg_reg(7, 0); @emitter.mov_reg_reg(8, 0)
       @emitter.emit([0xf3, 0xa4, 0xc6, 0x07, 0x00, 0x4c, 0x89, 0xc0])
    end
  end

  def gen_chr(node)
    eval_expression(node[:args][0])
    if @arch == :aarch64
       @emitter.push_reg(0)
       @emitter.emit_load_address("chr_buffer", @linker)
       @emitter.mov_reg_reg(1, 0)
       @emitter.pop_reg(0)
       @emitter.emit32(0x39000020)
       @emitter.mov_reg_imm(3, 0); @emitter.emit32(0x39000423)
       @emitter.mov_reg_reg(0, 1)
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

  def gen_int_to_str(node)
    eval_expression(node[:args][0])
    if @arch == :aarch64
       @emitter.push_reg(0)
       @emitter.emit_load_address("int_buffer", @linker)
       @emitter.mov_reg_reg(4, 0)
       @emitter.emit_add_imm(4, 4, 63)
       @emitter.mov_reg_imm(3, 0); @emitter.emit32(0x39000083)
       @emitter.pop_reg(0)
       @emitter.mov_reg_imm(1, 10)

       l = @emitter.current_pos
       @emitter.emit32(0x9ac10802)
       @emitter.emit32(0x9b018043)
       @emitter.emit_add_imm(3, 3, 48)
       @emitter.emit_sub_imm(4, 4, 1)
       @emitter.emit32(0x39000083)
       @emitter.mov_reg_reg(0, 2)
       @emitter.test_rax_rax
       p_loop = @emitter.jne_rel32
       @emitter.patch_jne(p_loop, l)
       @emitter.mov_reg_reg(0, 4)
    else
       @emitter.push_reg(0)
       @emitter.emit_load_address("int_buffer", @linker)
       @emitter.emit([0x48, 0x83, 0xc0, 63, 0xc6, 0x00, 0x00])
       @emitter.mov_reg_reg(6, 0)
       @emitter.mov_reg_imm(1, 10)
       @emitter.pop_reg(0)

       l = @emitter.current_pos
       @emitter.emit([0x48, 0x31, 0xd2, 0x48, 0xf7, 0xf1])
       @emitter.emit([0x80, 0xc2, 0x30])
       @emitter.emit([0x48, 0xff, 0xce, 0x88, 0x16])
       @emitter.test_rax_rax
       p_loop = @emitter.jne_rel32
       @emitter.patch_jne(p_loop, l)

       @emitter.mov_reg_reg(0, 6)
    end
  end

  def gen_str_to_int(node)
    eval_expression(node[:args][0])
    if @arch == :aarch64
       @emitter.mov_reg_reg(6, 0)
       @emitter.mov_reg_imm(0, 0)
       @emitter.mov_reg_imm(2, 10)
       l = @emitter.current_pos
       @emitter.emit32(0x384004c3)
       @emitter.emit32(0x6b1f007f)
       p_end = @emitter.je_rel32
       @emitter.emit_sub_imm(3, 3, 48)
       @emitter.emit32(0x9b027c00)
       @emitter.emit32(0x8b030000)
       p_loop = @emitter.jmp_rel32
       @emitter.patch_jmp(p_loop, l)
       @emitter.patch_je(p_end, @emitter.current_pos)
    else
       @emitter.mov_reg_reg(6, 0)
       @emitter.mov_reg_imm(0, 0)
       l = @emitter.current_pos
       @emitter.emit([0x48, 0x31, 0xd2, 0x8a, 0x16])
       @emitter.emit([0x80, 0xfa, 0x00])
       p_done = @emitter.je_rel32
       @emitter.emit([0x48, 0x83, 0xea, 0x30])
       @emitter.emit([0x48, 0x6b, 0xc0, 0x0a])
       @emitter.add_rax_rdx
       @emitter.emit([0x48, 0xff, 0xc6])
       p_loop = @emitter.jmp_rel32
       @emitter.patch_jmp(p_loop, l)
       @emitter.patch_je(p_done, @emitter.current_pos)
    end
  end

  def gen_prints(node)
    eval_expression(node[:args][0])
    if @arch == :aarch64
       @emitter.mov_reg_reg(6, 0)
       @emitter.mov_reg_imm(1, 0)
       l = @emitter.current_pos
       @emitter.emit32(0x386168c2)
       @emitter.emit32(0x6b1f005f)
       jz = @emitter.je_rel32
       @emitter.emit_add_imm(1, 1, 1)
       p_loop = @emitter.jmp_rel32
       @emitter.patch_jmp(p_loop, l)
       @emitter.patch_je(jz, @emitter.current_pos)

       @emitter.mov_reg_reg(2, 1)
       @emitter.mov_reg_reg(1, 6)
       @emitter.mov_reg_imm(0, 1)
       @emitter.mov_x8(64)
       @emitter.syscall

       @emitter.emit_load_address("newline_char", @linker)
       @emitter.mov_reg_reg(1, 0)
       @emitter.mov_reg_imm(0, 1)
       @emitter.mov_reg_imm(2, 1)
       @emitter.mov_x8(64)
       @emitter.syscall
    else
       @emitter.mov_reg_reg(6, 0); @emitter.mov_reg_imm(1, 0)
       l = @emitter.current_pos
       @emitter.emit([0x80, 0x3c, 0x0e, 0x00])
       p_done = @emitter.je_rel32
       @emitter.emit([0x48, 0xff, 0xc1])
       p_loop = @emitter.jmp_rel32
       @emitter.patch_jmp(p_loop, l)
       @emitter.patch_je(p_done, @emitter.current_pos)

       @emitter.mov_reg_reg(2, 1)
       @emitter.mov_reg_reg(6, 6)
       @emitter.mov_reg_imm(7, 1)
       @emitter.mov_reg_imm(0, 1)
       @emitter.syscall

       @emitter.emit_load_address("newline_char", @linker)
       @emitter.mov_reg_reg(6, 0)
       @emitter.mov_reg_imm(7, 1)
       @emitter.mov_reg_imm(2, 1)
       @emitter.mov_reg_imm(0, 1)
       @emitter.syscall
    end
  end
end
