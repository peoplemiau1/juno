# Simple heap allocator using mmap

module BuiltinHeap
  def gen_malloc(node)
    eval_expression(node[:args][0]) if node && node[:args] && node[:args][0]
    if @arch == :aarch64
      @emitter.mov_reg_reg(1, 0); @emitter.emit32(0x91002021) # rsi = len + 8
      @emitter.mov_rax(0); @emitter.mov_reg_reg(0, 0)
      @emitter.mov_rax(3); @emitter.mov_reg_reg(2, 0)
      @emitter.mov_rax(0x22); @emitter.mov_reg_reg(3, 0)
      @emitter.mov_rax(0xFFFFFFFFFFFFFFFF); @emitter.mov_reg_reg(4, 0)
      @emitter.mov_rax(0); @emitter.mov_reg_reg(5, 0)
      @emitter.mov_rax(222); @emitter.mov_reg_reg(8, 0); @emitter.emit32(0xd4000001)
      @emitter.emit32(0xf9000001); @emitter.emit32(0x91002000)
    else
      @emitter.mov_reg_reg(6, 0); @emitter.emit([0x48, 0x83, 0xc6, 0x08]) # rsi = len + 8
      @emitter.push_reg(6); @emitter.mov_rax(0); @emitter.mov_reg_reg(7, 0)
      @emitter.mov_rax(3); @emitter.mov_reg_reg(2, 0); @emitter.mov_rax(0x22); @emitter.mov_reg_reg(10, 0)
      @emitter.mov_rax(0xFFFFFFFFFFFFFFFF); @emitter.mov_reg_reg(8, 0); @emitter.mov_rax(0); @emitter.mov_reg_reg(9, 0)
      @emitter.mov_rax(9); @emitter.emit([0x0f, 0x05])
      @emitter.pop_reg(2); @emitter.emit([0x48, 0x89, 0x10, 0x48, 0x83, 0xc0, 0x08])
    end
  end

  def gen_realloc(node)
    eval_expression(node[:args][0]); @emitter.push_reg(0)
    eval_expression(node[:args][1]); @emitter.push_reg(0)
    if @arch == :aarch64
       @emitter.pop_reg(14) # x14=new
       @emitter.pop_reg(15) # x15=old
       @emitter.push_reg(14); @emitter.push_reg(15); @emitter.mov_reg_reg(0, 14); gen_malloc(nil)
       @emitter.emit32(0xeb0001ff) # cmp x15, 0
       jz_pos = @emitter.current_pos; @emitter.emit32(0x54000000)
       @emitter.push_reg(0); @emitter.emit32(0xf94ff9e1) # ldr x1, [x15, #-8]
       @emitter.emit32(0xd1002021) # sub x1, x1, #8
       @emitter.emit32(0xeb0e003f) # cmp x1, x14
       @emitter.emit32(0x9a8e2021) # csel x1, x1, x14, ls
       @emitter.mov_reg_reg(19, 0) # x19 = new_ptr
       # Simple copy loop
       l = @emitter.current_pos
       @emitter.emit32(0xb40000a1) # cbz x1, end
       @emitter.emit32(0x384005e2) # ldrb w2, [x15], #1
       @emitter.emit32(0x38000662) # strb w2, [x19], #1
       @emitter.emit32(0xd1000421) # sub x1, x1, #1
       @emitter.emit32(0x17fffffc) # b loop
       @emitter.pop_reg(0)
       @emitter.patch_je(jz_pos, @emitter.current_pos)
       @emitter.pop_reg(15); @emitter.pop_reg(14)
    else
       @emitter.pop_reg(14); @emitter.pop_reg(15)
       @emitter.push_reg(14); @emitter.push_reg(15)
       @emitter.mov_reg_reg(6, 14); @emitter.emit([0x48, 0x83, 0xc6, 0x08])
       @emitter.mov_rax(0); @emitter.mov_reg_reg(7, 0); @emitter.mov_rax(3); @emitter.mov_reg_reg(2, 0)
       @emitter.mov_rax(0x22); @emitter.mov_reg_reg(10, 0); @emitter.mov_rax(0xFFFFFFFFFFFFFFFF); @emitter.mov_reg_reg(8, 0)
       @emitter.mov_rax(0); @emitter.mov_reg_reg(9, 0); @emitter.mov_rax(9); @emitter.emit([0x0f, 0x05])
       @emitter.emit([0x48, 0x89, 0x30, 0x48, 0x83, 0xc0, 0x08])
       @emitter.emit([0x4d, 0x85, 0xff, 0x74, 0x1c])
       @emitter.push_reg(0); @emitter.emit([0x4d, 0x8b, 0x4f, 0xf8, 0x49, 0x83, 0xe9, 0x08, 0x4d, 0x39, 0xf1, 0x4d, 0x0f, 0x47, 0xce])
       @emitter.mov_reg_reg(7, 0); @emitter.mov_reg_reg(6, 15); @emitter.mov_reg_reg(1, 9); @emitter.emit([0xf3, 0xa4])
       @emitter.pop_reg(0); @emitter.pop_reg(15); @emitter.pop_reg(14)
    end
  end

  def gen_free(node)
    eval_expression(node[:args][0])
    if @arch == :aarch64
       @emitter.emit32(0xeb00001f) # cmp x0, 0
       jz_pos = @emitter.current_pos; @emitter.emit32(0x54000000)
       @emitter.emit32(0xd1002000) # x0 -= 8
       @emitter.mov_reg_reg(0, 0); @emitter.emit32(0xf9400001) # x1 = [x0]
       @emitter.mov_rax(215); @emitter.mov_reg_reg(8, 0); @emitter.emit32(0xd4000001)
       @emitter.patch_je(jz_pos, @emitter.current_pos)
    else
       @emitter.emit([0x48, 0x85, 0xc0, 0x74, 0x11, 0x48, 0x83, 0xe8, 0x08, 0x48, 0x89, 0xc7, 0x48, 0x8b, 0x37, 0xb8, 11, 0,0,0, 0x0f, 0x05])
    end
  end

  def gen_heap_init(node); @emitter.mov_rax(0); end
end
