# Simple heap allocator using mmap

module BuiltinHeap
  def gen_malloc(node)
    eval_expression(node[:args][0]) if node && node[:args] && node[:args][0]
    if @arch == :aarch64
      @emitter.mov_reg_reg(1, 0) # size in X1
      @emitter.emit_add_imm(1, 1, 8) # add x1, x1, #8 (total size)
      @emitter.push_reg(1) # save total size
      @emitter.mov_rax(0); @emitter.mov_reg_reg(0, 0) # addr = 0
      @emitter.mov_rax(3); @emitter.mov_reg_reg(2, 0) # prot = PROT_READ|PROT_WRITE
      @emitter.mov_rax(0x22); @emitter.mov_reg_reg(3, 0) # flags = MAP_PRIVATE|MAP_ANONYMOUS
      @emitter.mov_rax(0xffffffffffffffff); @emitter.mov_reg_reg(4, 0) # fd = -1
      @emitter.mov_rax(0); @emitter.mov_reg_reg(5, 0) # offset = 0
      @emitter.mov_rax(222); @emitter.mov_reg_reg(8, 0) # x8 = 222 (mmap)
      @emitter.emit32(0xd4000001) # svc 0

      @emitter.pop_reg(1) # restore total size to X1
      @emitter.emit32(0xf9000001) # str x1, [x0] (store header)
      @emitter.emit_add_imm(0, 0, 8) # add x0, x0, #8 (return ptr+8)
    else
      @emitter.mov_reg_reg(6, 0) # rsi = size
      @emitter.emit([0x48, 0x83, 0xc6, 0x08]) # rsi += 8
      @emitter.push_reg(6) # save total size
      @emitter.mov_rax(0); @emitter.mov_reg_reg(7, 0) # rdi = 0
      @emitter.mov_rax(3); @emitter.mov_reg_reg(2, 0) # rdx = 3
      @emitter.mov_rax(0x22); @emitter.mov_reg_reg(10, 0) # r10 = 0x22
      @emitter.mov_rax(0xffffffffffffffff); @emitter.mov_reg_reg(8, 0) # r8 = -1
      @emitter.mov_rax(0); @emitter.mov_reg_reg(9, 0) # r9 = 0
      @emitter.mov_rax(9); @emitter.emit([0x0f, 0x05]) # mmap

      @emitter.pop_reg(2) # restore total size to rdx
      @emitter.emit([0x48, 0x89, 0x10]) # mov [rax], rdx
      @emitter.emit([0x48, 0x83, 0xc0, 0x08]) # return rax+8
    end
  end

  def gen_realloc(node)
    # ptr in node[:args][0], size in node[:args][1]
    eval_expression(node[:args][0]); @emitter.push_reg(0) # old_ptr
    eval_expression(node[:args][1]); @emitter.push_reg(0) # new_size

    if @arch == :aarch64
       @emitter.pop_reg(14) # x14 = new_size
       @emitter.pop_reg(15) # x15 = old_ptr
       @emitter.push_reg(14); @emitter.push_reg(15) # preserve

       # malloc(new_size)
       @emitter.mov_reg_reg(0, 14)
       gen_malloc(nil)
       # result in x0 (new_ptr)

       @emitter.emit32(0xeb0001ff) # cmp x15, 0
       jz_pos = @emitter.current_pos; @emitter.emit32(0x54000000)

       @emitter.push_reg(0) # save new_ptr
       @emitter.emit_sub_imm(15, 15, 8) # sub x15, x15, #8
       @emitter.emit32(0xf94001e1) # ldr x1, [x15] (old total size)
       @emitter.emit_add_imm(15, 15, 8) # add x15, x15, #8
       @emitter.emit_sub_imm(1, 1, 8) # sub x1, x1, #8 (old user size)
       @emitter.emit32(0xeb0e003f) # cmp x1, x14
       @emitter.emit32(0x9a8e2021) # csel x1, x1, x14, ls (x1 = min)

       @emitter.mov_reg_reg(9, 0) # x9 = new_ptr_cursor
       @emitter.mov_reg_reg(10, 15) # x10 = old_ptr_cursor

       # Copy loop
       l = @emitter.current_pos
       @emitter.emit32(0xb40000a1) # cbz x1, end
       @emitter.emit32(0x38400542) # ldrb w2, [x10], #1
       @emitter.emit32(0x38000522) # strb w2, [x9], #1
       @emitter.emit_sub_imm(1, 1, 1) # sub x1, x1, #1
       @emitter.patch_jmp(@emitter.current_pos, l)

       @emitter.pop_reg(0) # restore new_ptr
       @emitter.patch_je(jz_pos, @emitter.current_pos)
       @emitter.pop_reg(15); @emitter.pop_reg(14)
    else
       @emitter.pop_reg(14); @emitter.pop_reg(15)
       @emitter.push_reg(14); @emitter.push_reg(15)
       @emitter.mov_reg_reg(0, 14); gen_malloc(nil)

       # if (old_ptr == 0) return new_ptr
       @emitter.emit([0x4d, 0x85, 0xff]) # test r15, r15
       p_skip = @emitter.je_rel32

       @emitter.push_reg(0) # save new_ptr
       # r9 = min(old_size, new_size)
       # [r15-8] has old total size
       @emitter.mov_reg_mem_idx(1, 15, -8) # rcx = [r15-8]
       @emitter.emit([0x48, 0x83, 0xe9, 0x08]) # sub rcx, 8 (old user size)
       @emitter.mov_reg_reg(9, 1) # r9 = old user size
       @emitter.emit([0x4d, 0x39, 0xf1]) # cmp r9, r14
       @emitter.cmov("<=", 9, 14) # wait, cmov uses reg codes

       @emitter.mov_reg_reg(7, 0) # rdi = new_ptr
       @emitter.mov_reg_reg(6, 15) # rsi = old_ptr
       @emitter.mov_reg_reg(1, 9) # rcx = min size
       @emitter.memcpy

       @emitter.pop_reg(0) # restore new_ptr
       @emitter.patch_je(p_skip, @emitter.current_pos)
       @emitter.pop_reg(15); @emitter.pop_reg(14)
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
         @emitter.mov_reg_reg(1, 0) # X1 = size
         @emitter.pop_reg(0) # X0 = ptr
         @emitter.mov_rax(215); @emitter.mov_reg_reg(8, 0); @emitter.syscall
       else
         @emitter.emit32(0xeb00001f) # cmp x0, 0
         jz_pos = @emitter.current_pos; @emitter.emit32(0x54000000)
         @emitter.emit_sub_imm(0, 0, 8) # x0 -= 8
         @emitter.emit32(0xf9400001) # x1 = [x0]
         @emitter.mov_rax(215); @emitter.mov_reg_reg(8, 0); @emitter.syscall
         @emitter.patch_je(jz_pos, @emitter.current_pos)
       end
    else
       if args.length >= 2
         @emitter.push_reg(0)
         eval_expression(args[1])
         @emitter.mov_reg_reg(6, 0) # RSI = size
         @emitter.pop_reg(7) # RDI = ptr
         @emitter.mov_rax(11); @emitter.syscall
       else
         @emitter.test_rax_rax
         p_skip = @emitter.je_rel32
         @emitter.emit([0x48, 0x83, 0xe8, 0x08]) # rax -= 8
         @emitter.mov_reg_reg(7, 0) # RDI = header addr
         @emitter.mov_rax_mem(0) # RAX = total size (from [RDI])
         @emitter.mov_reg_reg(6, 0) # RSI = total size
         @emitter.mov_rax(11) # munmap
         @emitter.syscall
         @emitter.patch_je(p_skip, @emitter.current_pos)
       end
    end
  end

  def gen_heap_init(node); @emitter.mov_rax(0); end
end
