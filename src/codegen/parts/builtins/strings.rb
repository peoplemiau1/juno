# String built-in functions for Juno

module BuiltinStrings
  def gen_concat(node)
    eval_expression(node[:args][0]); @emitter.push_reg(0)
    eval_expression(node[:args][1]); @emitter.mov_reg_reg(2, 0); @emitter.pop_reg(6) # X6=s1, X2=s2
    if @arch == :aarch64
       @emitter.push_reg(2) # save s2

       # Rotate: atomic_inc(&idx) & 15
       @emitter.emit_load_address("concat_buffer_idx", @linker)
       # LDADDAL X1, X9, [X0]
       # Since I don't have LSE by default, use a loop or just simple add for now?
       # Let's use simple add for now as I don't want to overcomplicate the emitter.
       @emitter.emit32(0xf9400009) # ldr x9, [x0]
       @emitter.emit_add_imm(11, 9, 1) # add x11, x9, #1
       @emitter.emit32(0xf900000b) # str x11, [x0]
       @emitter.emit32(0x92400d29) # and x9, x9, #15

       # buffer = pool + idx * 2048
       @emitter.emit32(0xd375d129) # lsl x9, x9, #11
       @emitter.push_reg(9)
       @emitter.emit_load_address("concat_buffer_pool", @linker)
       @emitter.pop_reg(9) # x9 = idx * 2048
       @emitter.emit32(0x8b090009) # add x9, x0, x9

       @emitter.mov_reg_reg(10, 9) # X10 = buffer (return value)
       @emitter.pop_reg(2) # X2 = s2

       # Copy s1 (in X6)
       l1 = @emitter.current_pos
       @emitter.emit32(0x384004c3) # ldrb w3, [x6], #1
       @emitter.emit32(0x6b1f007f) # cmp w3, #0
       jz1 = @emitter.current_pos; @emitter.emit32(0x54000000) # b.eq
       @emitter.emit32(0x38000523) # strb w3, [x9], #1
       @emitter.emit32(0x17fffffc) # b loop1 (jump back 4 instructions: ldrb, cmp, b.eq, strb -> no, wait)
       # Wait, i'll use relative jump back
       @emitter.patch_jmp(@emitter.current_pos, l1)
       @emitter.patch_je(jz1, @emitter.current_pos)

       # Copy s2 (in X2)
       l2 = @emitter.current_pos
       @emitter.emit32(0x38400443) # ldrb w3, [x2], #1
       @emitter.emit32(0x6b1f007f) # cmp w3, #0
       jz2 = @emitter.current_pos; @emitter.emit32(0x54000000) # b.eq
       @emitter.emit32(0x38000523) # strb w3, [x9], #1
       @emitter.patch_jmp(@emitter.current_pos, l2)
       @emitter.patch_je(jz2, @emitter.current_pos)

       @emitter.emit32(0x3900013f) # strb wzr, [x9] (null terminator)
       @emitter.mov_reg_reg(0, 10) # return X10
    else
       @emitter.push_reg(2) # save s2

       # Rotate buffer: idx = atomic_inc(&idx) & 15
       @emitter.emit_load_address("concat_buffer_idx", @linker)
       @emitter.mov_rax(1)
       @emitter.mov_reg_reg(2, 0) # rdx = 1
       @emitter.emit_load_address("concat_buffer_idx", @linker) # rax = &idx
       @emitter.emit([0xf0, 0x48, 0x0f, 0xc1, 0x10]) # lock xadd [rax], rdx
       @emitter.mov_reg_reg(0, 2) # rax = old idx
       @emitter.emit([0x48, 0x83, 0xe0, 0x0f]) # and rax, 15

       # buffer = pool + idx * 2048
       @emitter.mov_reg_reg(0, 2)
       @emitter.shl_rax_imm(11) # rax *= 2048
       @emitter.push_reg(0)
       @emitter.emit_load_address("concat_buffer_pool", @linker)
       @emitter.pop_reg(2)
       @emitter.add_rax_rdx

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
    eval_expression(node[:args][2]); @emitter.mov_reg_reg(1, 0) # X1 = len
    @emitter.pop_reg(2); @emitter.pop_reg(6) # X2=start, X6=s
    if @arch == :aarch64
       @emitter.emit32(0x8b0200c6) # add x6, x6, x2 (s = s + start)
       @emitter.emit_load_address("substr_buffer", @linker)
       @emitter.mov_reg_reg(9, 0) # X9 = buffer
       @emitter.mov_reg_reg(10, 0) # X10 = return

       # Copy loop
       l = @emitter.current_pos
       @emitter.emit32(0xb40000a1) # cbz x1, end
       @emitter.emit32(0x384004c2) # ldrb w2, [x6], #1
       @emitter.emit32(0x38000522) # strb w2, [x9], #1
       @emitter.emit_sub_imm(1, 1, 1)
       @emitter.patch_jmp(@emitter.current_pos, l)

       @emitter.emit32(0x3900013f) # strb wzr, [x9]
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
       @emitter.emit32(0x3900043f) # strb wzr, [x1, #1]
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

  def gen_prints(node)
    eval_expression(node[:args][0])
    if @arch == :aarch64
       @emitter.mov_reg_reg(6, 0) # X6 = str
       @emitter.mov_rax(0); @emitter.mov_reg_reg(1, 0) # X1 = counter
       l = @emitter.current_pos
       @emitter.emit32(0x386168c2) # ldrb w2, [x6, x1]
       @emitter.emit32(0x6b1f005f) # cmp w2, #0
       jz = @emitter.current_pos; @emitter.emit32(0x54000000) # b.eq
       @emitter.emit_add_imm(1, 1, 1) # add x1, x1, #1
       @emitter.patch_jmp(@emitter.current_pos, l)
       @emitter.patch_je(jz, @emitter.current_pos)
       @emitter.mov_reg_reg(1, 6) # X1 = buf
       @emitter.mov_reg_reg(2, 0) # X2 = len (from counter)
       @emitter.mov_rax(1); @emitter.mov_reg_reg(0, 0) # X0 = 1
       @emitter.mov_rax(64); @emitter.mov_reg_reg(8, 0); @emitter.syscall
       @emitter.emit_load_address("newline_char", @linker)
       @emitter.mov_reg_reg(1, 0); @emitter.mov_rax(1); @emitter.mov_reg_reg(0, 0)
       @emitter.mov_rax(1); @emitter.mov_reg_reg(2, 0)
       @emitter.mov_rax(64); @emitter.mov_reg_reg(8, 0); @emitter.syscall
    else
       @emitter.mov_reg_reg(6, 0); @emitter.mov_rax(0); @emitter.mov_reg_reg(1, 0)
       l = @emitter.current_pos; @emitter.emit([0x80, 0x3c, 0x0e, 0x00, 0x74, 0x05, 0x48, 0xff, 0xc1, 0xeb, 0xf5])
       @emitter.mov_reg_reg(2, 1); @emitter.mov_rax(1); @emitter.mov_reg_reg(7, 0); @emitter.emit([0x0f, 0x05])
       @emitter.emit_load_address("newline_char", @linker)
       @emitter.mov_reg_reg(6, 0); @emitter.mov_rax(1); @emitter.mov_reg_reg(2, 0); @emitter.mov_reg_reg(7, 0); @emitter.emit([0x0f, 0x05])
    end
  end
end
