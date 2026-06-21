module PrintUtils
  def gen_print_int_compatibility(node)
    if @arch == :aarch64
       @emitter.push_reg(0); @emitter.push_reg(1); @emitter.push_reg(2)
       @emitter.push_reg(3); @emitter.push_reg(4)

       @emitter.emit_load_address("int_buffer", @linker)
       @emitter.mov_reg_reg(4, 0)
       @emitter.emit_add_imm(4, 4, 62)

       @emitter.mov_reg_imm(1, 10)
       @emitter.emit32(0x39000081)

       @emitter.emit32(0xf94023e0)

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

       @emitter.mov_reg_reg(1, 4)
       @emitter.emit_load_address("int_buffer", @linker)
       @emitter.mov_reg_reg(2, 0)
       @emitter.emit_add_imm(2, 2, 63)
       @emitter.sub_rax_reg(1)
       @emitter.mov_reg_reg(2, 0)
       @emitter.mov_reg_imm(0, 1)
       @emitter.mov_x8(64)
       @emitter.syscall

       @emitter.pop_reg(4); @emitter.pop_reg(3); @emitter.pop_reg(2)
       @emitter.pop_reg(1); @emitter.pop_reg(0)
    else
      @emitter.push_reg(0); @emitter.push_reg(7); @emitter.push_reg(6)
      @emitter.push_reg(2); @emitter.push_reg(1); @emitter.push_reg(3)

      @emitter.emit_load_address("int_buffer", @linker)
      @emitter.add_reg_imm(0, 62)
      @emitter.mov_mem8_imm8(0, 10)
      @emitter.mov_reg_reg(6, 0)
      @emitter.mov_reg_imm(1, 10)
      @emitter.mov_rax_rsp_disp8(40)

      @emitter.xor_reg_reg(3, 3)
      @emitter.test_rax_rax
      pos_label = @emitter.jge_rel32
      @emitter.neg_reg(0)
      @emitter.mov_reg_imm(3, 1)
      @emitter.patch_jge(pos_label, @emitter.current_pos)

      l = @emitter.current_pos
      @emitter.xor_reg_reg(2, 2)
      @emitter.idiv_reg(1)
      @emitter.add_reg_imm(2, 48)
      @emitter.dec_reg(6)
      @emitter.mov_mem_reg_reg8(6, 2)
      @emitter.test_rax_rax
      p_loop = @emitter.jne_rel32
      @emitter.patch_jne(p_loop, l)

      @emitter.test_reg_reg(3, 3)
      skip_sign = @emitter.je_rel32
      @emitter.dec_reg(6)
      @emitter.mov_mem8_imm8(6, 45)
      @emitter.patch_je(skip_sign, @emitter.current_pos)

      @emitter.mov_reg_reg(11, 6)
      @emitter.emit_load_address("int_buffer", @linker)
      @emitter.add_reg_imm(0, 63)
      @emitter.sub_reg_reg(0, 11)
      @emitter.mov_reg_reg(2, 0)
      @emitter.mov_reg_reg(6, 11)

      @emitter.mov_reg_imm(7, 1)
      @emitter.mov_reg_imm(0, 1)
      @emitter.syscall

      @emitter.pop_reg(3); @emitter.pop_reg(1); @emitter.pop_reg(2)
      @emitter.pop_reg(6); @emitter.pop_reg(7); @emitter.pop_reg(0)
    end
  end
end
