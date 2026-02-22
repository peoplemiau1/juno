module BuiltinStrings
  def gen_concat(node)
    eval_expression(node[:args][0]); @emitter.push_reg(0)
    eval_expression(node[:args][1]); @emitter.mov_reg_reg(2, 0); @emitter.pop_reg(6) # RSI=s1, RDX=s2
    
    if @arch == :aarch64
       @emitter.push_reg(2)
       @emitter.emit_load_address("concat_buffer_idx", @linker)
       @emitter.mov_reg_reg(10, 0); @emitter.mov_rax_mem_idx(10, 0)
       @emitter.mov_reg_reg(9, 0); @emitter.emit_add_imm(0, 0, 1)
       @emitter.mov_mem_reg_idx(10, 0, 0, 8)
       @emitter.mov_reg_reg(0, 9); @emitter.mov_reg_imm(1, 15); @emitter.and_rax_rdx
       @emitter.shl_rax_imm(11); @emitter.mov_reg_reg(9, 0)
       @emitter.emit_load_address("concat_buffer_pool", @linker); @emitter.add_rax_rdx
       @emitter.mov_reg_reg(10, 0); @emitter.mov_reg_reg(11, 0); @emitter.pop_reg(2)
       
       l1 = @emitter.current_pos
       @emitter.emit32(0x384004c3); @emitter.emit32(0x6b1f007f)
       p_end1 = @emitter.je_rel32
       @emitter.emit32(0x38000563)
       @emitter.patch_jmp(@emitter.jmp_rel32, l1)
       @emitter.patch_je(p_end1, @emitter.current_pos)

       l2 = @emitter.current_pos
       @emitter.emit32(0x38400443); @emitter.emit32(0x6b1f007f)
       p_end2 = @emitter.je_rel32
       @emitter.emit32(0x38000563)
       @emitter.patch_jmp(@emitter.jmp_rel32, l2)
       @emitter.patch_je(p_end2, @emitter.current_pos)
       @emitter.mov_reg_imm(3, 0); @emitter.emit32(0x38000163)
       @emitter.mov_reg_reg(0, 10)
    else
       @emitter.push_reg(6) # SAVE s1
       @emitter.push_reg(2) # SAVE s2
       @emitter.emit_load_address("concat_buffer_idx", @linker)
       @emitter.mov_rax(1); @emitter.mov_reg_reg(2, 0)
       @emitter.emit_load_address("concat_buffer_idx", @linker)
       @emitter.emit([0xf0, 0x48, 0x0f, 0xc1, 0x10]) # lock xadd
       @emitter.mov_reg_reg(0, 2); @emitter.emit([0x48, 0x83, 0xe0, 0x0f])
       @emitter.shl_rax_imm(11); @emitter.push_reg(0)
       @emitter.emit_load_address("concat_buffer_pool", @linker)
       @emitter.pop_reg(2); @emitter.add_rax_rdx
       @emitter.mov_reg_reg(7, 0); @emitter.mov_reg_reg(8, 0) # RDI, R8 = buffer
       
       @emitter.pop_reg(2) # RESTORE s2
       @emitter.pop_reg(6) # RESTORE s1
       
       # Loop 1: Copy s1
       l1 = @emitter.current_pos
       @emitter.emit([0x8a, 0x06, 0x84, 0xc0]) # mov al, [rsi]; test al, al
       p_end1 = @emitter.je_rel32
       @emitter.emit([0x88, 0x07, 0x48, 0xff, 0xc7, 0x48, 0xff, 0xc6]) # mov [rdi], al; inc rdi; inc rsi
       @emitter.patch_jmp(@emitter.jmp_rel32, l1)
       @emitter.patch_je(p_end1, @emitter.current_pos)
       
       @emitter.mov_reg_reg(6, 2) # RSI = s2
       
       # Loop 2: Copy s2
       l2 = @emitter.current_pos
       @emitter.emit([0x8a, 0x06, 0x84, 0xc0])
       p_end2 = @emitter.je_rel32
       @emitter.emit([0x88, 0x07, 0x48, 0xff, 0xc7, 0x48, 0xff, 0xc6])
       @emitter.patch_jmp(@emitter.jmp_rel32, l2)
       @emitter.patch_je(p_end2, @emitter.current_pos)
       
       @emitter.emit([0xc6, 0x07, 0x00]) # null terminator
       @emitter.mov_rax_from_reg(8) # return original buffer addr
    end
  end

  def gen_prints(node)
    eval_expression(node[:args][0])
    if @arch == :aarch64
       @emitter.mov_reg_reg(6, 0); @emitter.mov_reg_imm(1, 0)
       l = @emitter.current_pos
       @emitter.emit32(0x386168c2); @emitter.emit32(0x6b1f005f)
       jz = @emitter.je_rel32
       @emitter.emit_add_imm(1, 1, 1)
       @emitter.patch_jmp(@emitter.jmp_rel32, l)
       @emitter.patch_je(jz, @emitter.current_pos)
       @emitter.mov_reg_reg(2, 1); @emitter.mov_reg_reg(1, 6); @emitter.mov_reg_imm(0, 1)
       emit_syscall(:write)
       @emitter.emit_load_address("newline_char", @linker)
       @emitter.mov_reg_reg(1, 0); @emitter.mov_reg_imm(0, 1); @emitter.mov_reg_imm(2, 1)
       emit_syscall(:write)
    else
       @emitter.mov_reg_reg(6, 0); @emitter.mov_reg_imm(1, 0)
       l = @emitter.current_pos
       @emitter.emit([0x80, 0x3c, 0x0e, 0x00]) # cmp byte ptr [rsi+rcx], 0
       p_done = @emitter.je_rel32
       @emitter.emit([0x48, 0xff, 0xc1]) # inc rcx
       @emitter.patch_jmp(@emitter.jmp_rel32, l)
       @emitter.patch_je(p_done, @emitter.current_pos)
       
       @emitter.mov_reg_reg(2, 1); @emitter.mov_reg_reg(6, 6); @emitter.mov_reg_imm(7, 1)
       @emitter.mov_reg_imm(0, 1)
       emit_syscall(:write)
       
       @emitter.emit_load_address("newline_char", @linker)
       @emitter.mov_reg_reg(6, 0); @emitter.mov_reg_imm(7, 1); @emitter.mov_reg_imm(2, 1)
       @emitter.mov_reg_imm(0, 1)
       emit_syscall(:write)
    end
  end
end
