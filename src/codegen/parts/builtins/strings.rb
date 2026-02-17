# String built-in functions for Juno

module BuiltinStrings
  def gen_concat(node)
    eval_expression(node[:args][0]); @emitter.push_reg(0)
    eval_expression(node[:args][1]); @emitter.mov_reg_reg(2, 0); @emitter.pop_reg(6) # X6=s1, X2=s2
    if @arch == :aarch64
       @emitter.push_reg(2) # save s2

       # Rotate: idx = atomic_inc(&idx) & 15
       @emitter.emit_load_address("concat_buffer_idx", @linker)
       @emitter.mov_reg_reg(10, 0) # X10 = &idx
       @emitter.mov_rax_mem_idx(10, 0) # X0 = idx
       @emitter.mov_reg_reg(9, 0)      # X9 = old idx
       @emitter.emit_add_imm(0, 0, 1)  # X0 = idx + 1
       @emitter.mov_mem_idx(10, 0, 0, 8) # save new idx

       @emitter.mov_reg_reg(0, 9)
       @emitter.mov_reg_imm(1, 15); @emitter.and_rax_rdx # X0 = idx & 15

       # buffer = pool + idx * 2048
       @emitter.shl_rax_imm(11) # X0 *= 2048
       @emitter.mov_reg_reg(9, 0) # X9 = offset
       @emitter.emit_load_address("concat_buffer_pool", @linker)
       @emitter.add_rax_rdx # X0 = pool + offset

       @emitter.mov_reg_reg(10, 0) # X10 = result buffer
       @emitter.mov_reg_reg(11, 0) # X11 = cursor
       @emitter.pop_reg(2) # X2 = s2

       # Copy s1 (in X6)
       l1 = @emitter.current_pos
       @emitter.emit32(0x384004c3) # ldrb w3, [x6], #1
       @emitter.emit32(0x6b1f007f) # cmp w3, #0
       p_end1 = @emitter.je_rel32
       @emitter.emit32(0x38000563) # strb w3, [x11], #1
       p_loop1 = @emitter.jmp_rel32
       @emitter.patch_jmp(p_loop1, l1)
       @emitter.patch_je(p_end1, @emitter.current_pos)

       # Copy s2 (in X2)
       l2 = @emitter.current_pos
       @emitter.emit32(0x38400443) # ldrb w3, [x2], #1
       @emitter.emit32(0x6b1f007f) # cmp w3, #0
       p_end2 = @emitter.je_rel32
       @emitter.emit32(0x38000563) # strb w3, [x11], #1
       p_loop2 = @emitter.jmp_rel32
       @emitter.patch_jmp(p_loop2, l2)
       @emitter.patch_je(p_end2, @emitter.current_pos)

       @emitter.mov_reg_imm(3, 0)
       @emitter.emit32(0x38000163) # strb w3, [x11] (null terminator)
       @emitter.mov_reg_reg(0, 10) # return buffer
    else
       @emitter.push_reg(2)
       @emitter.emit_load_address("concat_buffer_idx", @linker)
       @emitter.mov_rax(1)
       @emitter.mov_reg_reg(2, 0)
       @emitter.emit_load_address("concat_buffer_idx", @linker)
       @emitter.emit([0xf0, 0x48, 0x0f, 0xc1, 0x10])
       @emitter.mov_reg_reg(0, 2)
       @emitter.emit([0x48, 0x83, 0xe0, 0x0f])
       @emitter.mov_reg_reg(0, 2)
       @emitter.shl_rax_imm(11)
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
    eval_expression(node[:args][2]); @emitter.mov_reg_reg(1, 0) # X1 = len
    @emitter.pop_reg(2); @emitter.pop_reg(6) # X2=start, X6=s
    if @arch == :aarch64
       @emitter.emit32(0x8b0200c6) # add x6, x6, x2 (s = s + start)
       @emitter.emit_load_address("substr_buffer", @linker)
       @emitter.mov_reg_reg(9, 0) # X9 = buffer cursor
       @emitter.mov_reg_reg(10, 0) # X10 = return

       # Copy loop
       l = @emitter.current_pos
       @emitter.test_reg_reg(1, 1)
       p_end = @emitter.je_rel32
       @emitter.emit32(0x384004c2) # ldrb w2, [x6], #1
       @emitter.emit32(0x38000522) # strb w2, [x9], #1
       @emitter.emit_sub_imm(1, 1, 1)
       p_loop = @emitter.jmp_rel32
       @emitter.patch_jmp(p_loop, l)
       @emitter.patch_je(p_end, @emitter.current_pos)

       @emitter.mov_reg_imm(3, 0); @emitter.emit32(0x38000123) # strb wzr, [x9]
       @emitter.mov_reg_reg(0, 10)
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
       @emitter.push_reg(0)
       @emitter.emit_load_address("chr_buffer", @linker)
       @emitter.mov_reg_reg(1, 0)
       @emitter.pop_reg(0)
       @emitter.emit32(0x39000020) # strb w0, [x1]
       @emitter.mov_reg_imm(3, 0); @emitter.emit32(0x39000423) # [x1+1] = 0
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
       @emitter.push_reg(0) # val
       @emitter.emit_load_address("int_buffer", @linker)
       @emitter.mov_reg_reg(4, 0) # X4 = buf
       @emitter.emit_add_imm(4, 4, 63)
       @emitter.mov_reg_imm(3, 0); @emitter.emit32(0x39000083) # [x4] = 0 (terminator)
       @emitter.pop_reg(0) # val
       @emitter.mov_reg_imm(1, 10)

       l = @emitter.current_pos
       @emitter.emit32(0x9ac10802) # sdiv x2, x0, x1
       @emitter.emit32(0x9b018043) # msub x3, x2, x1, x0 (rem)
       @emitter.emit_add_imm(3, 3, 48) # '0'
       @emitter.emit_sub_imm(4, 4, 1)
       @emitter.emit32(0x39000083) # strb w3, [x4]
       @emitter.mov_reg_reg(0, 2)
       @emitter.test_rax_rax
       p_loop = @emitter.jne_rel32
       @emitter.patch_jne(p_loop, l)
       @emitter.mov_reg_reg(0, 4) # return buffer start
    else
       @emitter.push_reg(0)
       @emitter.emit_load_address("int_buffer", @linker)
       @emitter.emit([0x48, 0x83, 0xc0, 63, 0xc6, 0x00, 0x00, 0x48, 0x89, 0xc6, 0x48, 0xc7, 0xc1, 10, 0, 0, 0, 0x48, 0x8b, 0x44, 0x24, 8])
       l = @emitter.current_pos
       @emitter.emit([0x48, 0x31, 0xd2, 0x48, 0xf7, 0xf1, 0x80, 0xc2, 0x30, 0x48, 0xff, 0xce, 0x88, 0x16, 0x48, 0x85, 0xc0, 0x75])
       @emitter.emit([(l - (@emitter.current_pos + 1)) & 0xFF])
       @emitter.mov_reg_reg(0, 6)
       @emitter.emit([0x48, 0x83, 0xc4, 8])
    end
  end

  def gen_str_to_int(node)
    eval_expression(node[:args][0])
    if @arch == :aarch64
       @emitter.mov_reg_reg(6, 0) # s
       @emitter.mov_reg_imm(0, 0) # res
       @emitter.mov_reg_imm(2, 10)
       l = @emitter.current_pos
       @emitter.emit32(0x384004c3) # ldrb w3, [x6], #1
       @emitter.emit32(0x6b1f007f) # cmp w3, #0
       p_end = @emitter.je_rel32
       @emitter.emit_sub_imm(3, 3, 48) # w3 -= '0'
       @emitter.emit32(0x9b027c00) # mul x0, x0, x2
       @emitter.emit32(0x8b030000) # add x0, x0, x3
       p_loop = @emitter.jmp_rel32
       @emitter.patch_jmp(p_loop, l)
       @emitter.patch_je(p_end, @emitter.current_pos)
    else
       @emitter.mov_reg_reg(6, 0); @emitter.mov_rax(0)
       l = @emitter.current_pos
       @emitter.emit([0x48, 0x31, 0xd2, 0x8a, 0x16, 0x80, 0xfa, 0x00, 0x74, 0x0d])
       @emitter.emit([0x48, 0x83, 0xea, 0x30, 0x48, 0x6b, 0xc0, 0x0a, 0x48, 0x01, 0xd0, 0x48, 0xff, 0xc6, 0xeb, 0xec])
    end
  end

  def gen_prints(node)
    eval_expression(node[:args][0])
    if @arch == :aarch64
       @emitter.mov_reg_reg(6, 0) # X6 = str
       @emitter.mov_reg_imm(1, 0) # X1 = counter
       l = @emitter.current_pos
       # ldrb w2, [x6, x1]
       @emitter.emit32(0x386168c2)
       # cmp w2, #0
       @emitter.emit32(0x6b1f005f)
       jz = @emitter.je_rel32
       @emitter.emit_add_imm(1, 1, 1) # add x1, x1, #1
       p_loop = @emitter.jmp_rel32
       @emitter.patch_jmp(p_loop, l)
       @emitter.patch_je(jz, @emitter.current_pos)

       # X1 currently has length
       @emitter.mov_reg_reg(2, 1) # X2 = len
       @emitter.mov_reg_reg(1, 6) # X1 = buf (str)
       @emitter.mov_reg_imm(0, 1) # X0 = stdout
       @emitter.mov_x8(64)        # X8 = write
       @emitter.syscall

       @emitter.emit_load_address("newline_char", @linker)
       @emitter.mov_reg_reg(1, 0) # X1 = buf (newline)
       @emitter.mov_reg_imm(0, 1) # X0 = stdout
       @emitter.mov_reg_imm(2, 1) # X2 = 1
       @emitter.mov_x8(64)
       @emitter.syscall
    else
       @emitter.mov_reg_reg(6, 0); @emitter.mov_rax(0); @emitter.mov_reg_reg(1, 0)
       l = @emitter.current_pos; @emitter.emit([0x80, 0x3c, 0x0e, 0x00, 0x74, 0x05, 0x48, 0xff, 0xc1, 0xeb, 0xf5])
       @emitter.mov_reg_reg(2, 1); @emitter.mov_rax(1); @emitter.mov_reg_reg(7, 0); @emitter.emit([0x0f, 0x05])
       @emitter.emit_load_address("newline_char", @linker)
       @emitter.mov_reg_reg(6, 0); @emitter.mov_rax(1); @emitter.mov_reg_reg(2, 0); @emitter.mov_reg_reg(7, 0); @emitter.emit([0x0f, 0x05])
    end
  end
end
