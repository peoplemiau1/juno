# Simple heap allocator using mmap
module BuiltinHeap
  def gen_malloc(node)
    return unless @target_os == :linux
    args = node[:args] || []; return @emitter.mov_rax(0) if args.empty?
    eval_expression(args[0]); @emitter.mov_reg_reg(@emitter.class::REG_R11, @emitter.class::REG_RAX)
    # Add 8 for header, align 16
    if @arch == :aarch64
       @emitter.emit32(0x9100216b); @emitter.emit32(0x91003d6b); @emitter.emit32(0x927cec6b)
    else
       @emitter.emit([0x49, 0x83, 0xc3, 0x08, 0x49, 0x83, 0xc3, 0x0f, 0x49, 0x83, 0xe3, 0xf0])
    end
    if @arch == :aarch64
       @emitter.mov_rax(0); @emitter.mov_reg_reg(0, 0)
       @emitter.mov_reg_reg(1, 11)
       @emitter.mov_rax(3); @emitter.mov_reg_reg(2, 0)
       @emitter.mov_rax(0x22); @emitter.mov_reg_reg(3, 0)
       @emitter.mov_rax(0xFFFFFFFFFFFFFFFF); @emitter.mov_reg_reg(4, 0)
       @emitter.mov_rax(0); @emitter.mov_reg_reg(5, 0)
       @emitter.mov_rax(222); @emitter.mov_reg_reg(8, 0); @emitter.emit32(0xd4000001)
    else
       @emitter.emit([0x48, 0x31, 0xff, 0x4c, 0x89, 0xde, 0xba, 0x03, 0,0,0, 0x41, 0xba, 0x22, 0,0,0, 0x49, 0xc7, 0xc0, 0xff, 0xff, 0xff, 0xff, 0x4d, 0x31, 0xc9, 0xb8, 0x09, 0,0,0, 0x0f, 0x05])
    end
    # Store header and return ptr+8
    if @arch == :aarch64
       @emitter.emit32(0xf900000b); @emitter.emit32(0x91002000)
    else
       @emitter.emit([0x4c, 0x89, 0x18, 0x48, 0x83, 0xc0, 0x08])
    end
  end

  def gen_realloc(node)
    # Placeholder for AArch64 realloc, keep x86-64 for now
    return unless @target_os == :linux
    if @arch == :aarch64
       eval_expression(node[:args][0]); return # Stub
    end
    @emitter.push_reg(12); @emitter.push_reg(13); @emitter.push_reg(14); @emitter.push_reg(15)
    eval_expression(node[:args][0]); @emitter.mov_reg_reg(15, 0)
    eval_expression(node[:args][1]); @emitter.mov_reg_reg(14, 0)
    @emitter.mov_reg_reg(3, 14); @emitter.emit([0x48, 0x83, 0xc3, 0x08, 0x48, 0x83, 0xc3, 0x0f, 0x48, 0x83, 0xe3, 0xf0, 0x48, 0x31, 0xff, 0x48, 0x89, 0xde, 0xba, 0x03, 0,0,0, 0x41, 0xba, 0x22, 0,0,0, 0x49, 0xc7, 0xc0, 0xff, 0xff, 0xff, 0xff, 0x4d, 0x31, 0xc9, 0xb8, 0x09, 0,0,0, 0x0f, 0x05, 0x48, 0x89, 0x18, 0x48, 0x83, 0xc0, 0x08])
    @emitter.emit([0x4d, 0x85, 0xff]); jz = @emitter.je_rel32
    @emitter.push_reg(0); @emitter.emit([0x4d, 0x8b, 0x4f, 0xf8, 0x49, 0x83, 0xe9, 0x08, 0x4d, 0x39, 0xf1, 0x4d, 0x0f, 0x47, 0xce, 0x48, 0x89, 0xc7, 0x4c, 0x89, 0xfe, 0x4c, 0x89, 0xc9, 0xf3, 0xa4, 0x58])
    @emitter.patch_je(jz, @emitter.current_pos)
    @emitter.pop_reg(15); @emitter.pop_reg(14); @emitter.pop_reg(13); @emitter.pop_reg(12)
  end

  def gen_heap_init(node); @emitter.mov_rax(0); end

  def gen_free(node)
    return unless @target_os == :linux
    args = node[:args] || []; return if args.empty?
    eval_expression(args[0]); @emitter.test_rax_rax; jz = @emitter.je_rel32
    if args.length >= 2
      @emitter.push_reg(@emitter.class::REG_RAX)
      eval_expression(args[1]); @emitter.mov_reg_reg(@emitter.class::REG_RSI, @emitter.class::REG_RAX)
      @emitter.pop_reg(@emitter.class::REG_RDI)
    else
      if @arch == :aarch64
        @emitter.emit32(0xd1002000); @emitter.mov_reg_reg(4, 0); @emitter.mov_rax_mem(0); @emitter.mov_reg_reg(1, 0); @emitter.mov_reg_reg(0, 4)
      else
        @emitter.emit([0x48, 0x89, 0xc7, 0x48, 0x83, 0xef, 0x08, 0x48, 0x8b, 0x37])
      end
    end
    if @arch == :aarch64
      @emitter.mov_rax(215); @emitter.mov_reg_reg(8, 0); @emitter.emit32(0xd4000001)
    else
      @emitter.emit([0xb8, 0x0b, 0x00, 0x00, 0x00, 0x0f, 0x05])
    end
    @emitter.patch_je(jz, @emitter.current_pos); @emitter.mov_rax(0)
  end
end
