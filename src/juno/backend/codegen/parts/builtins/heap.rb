module BuiltinHeap
  def gen_malloc(node)
    eval_expression(node[:args][0]) if node && node[:args] && node[:args][0]
    if @arch == :aarch64
      @emitter.mov_reg_reg(1, 0)
      @emitter.emit_add_imm(1, 1, 8)
      @emitter.push_reg(1)
      @emitter.mov_rax(0); @emitter.mov_reg_reg(0, 0)
      @emitter.mov_rax(3); @emitter.mov_reg_reg(2, 0)
      @emitter.mov_rax(0x22); @emitter.mov_reg_reg(3, 0)
      @emitter.mov_rax(0xffffffffffffffff); @emitter.mov_reg_reg(4, 0)
      @emitter.mov_rax(0); @emitter.mov_reg_reg(5, 0)
      @emitter.mov_rax(222); @emitter.mov_reg_reg(8, 0)
      @emitter.emit32(0xd4000001)

      @emitter.pop_reg(1)
      @emitter.emit32(0xf9000001)
      @emitter.emit_add_imm(0, 0, 8)
    else
      @emitter.mov_reg_reg(6, 0)
      @emitter.emit([0x48, 0x83, 0xc6, 0x08])
      @emitter.push_reg(6)
      @emitter.mov_rax(0); @emitter.mov_reg_reg(7, 0)
      @emitter.mov_rax(3); @emitter.mov_reg_reg(2, 0)
      @emitter.mov_rax(0x22); @emitter.mov_reg_reg(10, 0)
      @emitter.mov_rax(0xffffffffffffffff); @emitter.mov_reg_reg(8, 0)
      @emitter.mov_rax(0); @emitter.mov_reg_reg(9, 0)
      @emitter.mov_rax(9); @emitter.emit([0x0f, 0x05])

      @emitter.cmp_reg_imm(0, -1)
      p_ok = @emitter.jne_rel32
      @emitter.pop_reg(2)
      @emitter.xor_rax_rax
      p_end = @emitter.jmp_rel32

      @emitter.patch_jne(p_ok, @emitter.current_pos)
      @emitter.pop_reg(2)
      @emitter.emit([0x48, 0x89, 0x10])
      @emitter.emit([0x48, 0x83, 0xc0, 0x08])
      @emitter.patch_jmp(p_end, @emitter.current_pos)
    end
  end

  def gen_realloc(node)
    eval_expression(node[:args][0]); @emitter.push_reg(0)
    eval_expression(node[:args][1]); @emitter.push_reg(0)

    if @arch == :aarch64
       @emitter.pop_reg(14)
       @emitter.pop_reg(15)

       @emitter.mov_reg_reg(0, 14)
       gen_malloc(nil)
       @emitter.push_reg(0)

       @emitter.emit32(0xeb0001ff)
       jz_pos = @emitter.current_pos; @emitter.emit32(0x54000000)

       @emitter.emit_sub_imm(15, 15, 8)
       @emitter.emit32(0xf94001e1)
       @emitter.emit_add_imm(15, 15, 8)
       @emitter.emit_sub_imm(1, 1, 8)
       @emitter.emit32(0xeb0e003f)
       @emitter.emit32(0x9a8e2021)

       @emitter.mov_reg_reg(9, 0)
       @emitter.mov_reg_reg(10, 15)

       l = @emitter.current_pos
       @emitter.emit32(0xb40000a1)
       @emitter.emit32(0x38400542)
       @emitter.emit32(0x38000522)
       @emitter.emit_sub_imm(1, 1, 1)
       @emitter.patch_jmp(@emitter.jmp_rel32, l)

       @emitter.patch_je(jz_pos, @emitter.current_pos)
       @emitter.pop_reg(0)
    else
       @emitter.pop_reg(14)
       @emitter.pop_reg(15)

       @emitter.mov_reg_reg(0, 14)
       gen_malloc(nil)
       @emitter.push_reg(0)

       @emitter.emit([0x4d, 0x85, 0xff])
       p_skip = @emitter.je_rel32

       @emitter.mov_reg_mem_idx(1, 15, -8)
       @emitter.emit([0x48, 0x83, 0xe9, 0x08])
       @emitter.mov_reg_reg(9, 1)
       @emitter.emit([0x4d, 0x39, 0xf1])
       @emitter.cmov(">=", 9, 14)

       @emitter.mov_reg_reg(7, 0)
       @emitter.mov_reg_reg(6, 15)
       @emitter.mov_reg_reg(1, 9)
       @emitter.memcpy

       @emitter.patch_je(p_skip, @emitter.current_pos)
       @emitter.pop_reg(0)
    end
  end

  def gen_free(node)
    args = node[:args] || []
    return if args.empty?

    eval_expression(args[0])
    if @arch == :aarch64
       if args.length >= 2
         @emitter.push_reg(0)
         eval_expression(args[1])
         @emitter.mov_reg_reg(1, 0)
         @emitter.pop_reg(0)
         @emitter.mov_rax(215); @emitter.mov_reg_reg(8, 0); @emitter.syscall
       else
         @emitter.emit32(0xeb00001f)
         jz_pos = @emitter.current_pos; @emitter.emit32(0x54000000)
         @emitter.emit_sub_imm(0, 0, 8)
         @emitter.emit32(0xf9400001)
         @emitter.mov_rax(215); @emitter.mov_reg_reg(8, 0); @emitter.syscall
         @emitter.patch_je(jz_pos, @emitter.current_pos)
       end
    else
       if args.length >= 2
         @emitter.push_reg(0)
         eval_expression(args[1])
         @emitter.mov_reg_reg(6, 0)
         @emitter.pop_reg(7)
         @emitter.mov_rax(11); @emitter.syscall
       else
         @emitter.test_rax_rax
         p_skip = @emitter.je_rel32
         @emitter.emit([0x48, 0x83, 0xe8, 0x08])
         @emitter.mov_reg_reg(7, 0)
         @emitter.mov_rax_mem(0)
         @emitter.mov_reg_reg(6, 0)
         @emitter.mov_rax(11)
         @emitter.syscall
         @emitter.patch_je(p_skip, @emitter.current_pos)
       end
    end
  end

  def gen_heap_init(node); @emitter.mov_rax(0); end
end
