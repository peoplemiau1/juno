# print_utils.rb - Integer to string conversion for printing

module PrintUtils
  def gen_print_int_compatibility(node)
    if @arch == :aarch64
       # Save registers
       @emitter.push_reg(0); @emitter.push_reg(1); @emitter.push_reg(2)
       @emitter.push_reg(3); @emitter.push_reg(4)

       @emitter.emit_load_address("int_buffer", @linker)
       @emitter.mov_reg_reg(4, 0) # X4 = buf
       @emitter.emit_add_imm(4, 4, 62) # X4 = buf + 62

       @emitter.mov_reg_imm(1, 10) # X1 = 10
       @emitter.emit32(0x39000081) # strb w1, [x4] (store '\n')

       # Original value was in X0, but we pushed X0, X1, X2, X3, X4. Each 16 bytes.
       # X4 at [sp], X3 at [sp+16], X2 at [sp+32], X1 at [sp+48], X0 at [sp+64]
       @emitter.emit32(0xf94023e0) # ldr x0, [sp, #64]

       l = @emitter.current_pos
       @emitter.emit32(0x9ac10802) # sdiv x2, x0, x1
       @emitter.emit32(0x9b018043) # msub x3, x2, x1, x0 (rem = x0 - x2*10)
       @emitter.emit_add_imm(3, 3, 48) # x3 += '0'
       @emitter.emit_sub_imm(4, 4, 1) # x4 -= 1
       @emitter.emit32(0x39000083) # strb w3, [x4]
       @emitter.mov_reg_reg(0, 2) # x0 = quot
       @emitter.test_rax_rax
       p_loop = @emitter.jne_rel32
       @emitter.patch_jne(p_loop, l)

       # Print
       @emitter.mov_reg_reg(1, 4) # X1 = buffer start
       @emitter.emit_load_address("int_buffer", @linker)
       @emitter.mov_reg_reg(2, 0)
       @emitter.emit_add_imm(2, 2, 63) # X2 = buf + 63
       # sub x2, x2, x1
       @emitter.emit32(0xcb010042)

       @emitter.mov_reg_imm(0, 1) # fd = 1
       @emitter.mov_x8(64) # write
       @emitter.syscall

       @emitter.pop_reg(4); @emitter.pop_reg(3); @emitter.pop_reg(2)
       @emitter.pop_reg(1); @emitter.pop_reg(0)
    else
      # x86 implementation
      @emitter.push_reg(0); @emitter.push_reg(7); @emitter.push_reg(6)
      @emitter.push_reg(2); @emitter.push_reg(1)

      @emitter.emit_load_address("int_buffer", @linker)
      # sub rax, 62; mov byte [rax], 10; rsi = rax
      @emitter.emit([0x48, 0x83, 0xc0, 62, 0xc6, 0x00, 10])
      @emitter.mov_reg_reg(6, 0)
      @emitter.mov_reg_imm(1, 10)
      # load original rax from stack [rsp+32]
      @emitter.emit([0x48, 0x8b, 0x44, 0x24, 32])

      l = @emitter.current_pos
      @emitter.emit([0x48, 0x31, 0xd2, 0x48, 0xf7, 0xf1]) # xor rdx, rdx; div rcx
      @emitter.emit([0x80, 0xc2, 0x30]) # add dl, '0'
      @emitter.emit([0x48, 0xff, 0xce, 0x88, 0x16, 0x48, 0x85, 0xc0]) # dec rsi; mov [rsi], dl; test rax, rax
      p_loop = @emitter.jne_rel32
      @emitter.patch_jne(p_loop, l)

      @emitter.mov_reg_reg(11, 6) # start ptr
      @emitter.emit_load_address("int_buffer", @linker)
      # rax += 63; sub rax, r11; rdx = rax; rsi = r11
      @emitter.emit([0x48, 0x83, 0xc0, 63])
      @emitter.sub_reg_reg(0, 11) # rax = buf+63 - start
      @emitter.mov_reg_reg(2, 0) # RDX = len
      @emitter.mov_reg_reg(6, 11) # RSI = start

      @emitter.mov_reg_imm(7, 1) # RDI = 1
      @emitter.mov_reg_imm(0, 1) # RAX = 1
      @emitter.syscall

      @emitter.pop_reg(1); @emitter.pop_reg(2); @emitter.pop_reg(6)
      @emitter.pop_reg(7); @emitter.pop_reg(0)
    end
  end
end
