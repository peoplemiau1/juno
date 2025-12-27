# Type operations and pointer arithmetic for Juno

module BuiltinTypes
  # ptr_add(ptr, offset) - add offset to pointer (scaled by element size)
  # For now, assumes 8-byte elements
  def gen_ptr_add(node)
    eval_expression(node[:args][0])  # ptr
    @emitter.emit([0x50])  # push rax
    eval_expression(node[:args][1])  # offset
    @emitter.emit([0x48, 0xc1, 0xe0, 0x03])  # shl rax, 3 (multiply by 8)
    @emitter.emit([0x5a])  # pop rdx
    @emitter.add_rax_rdx  # Oops, wrong order
    # Actually: rdx + rax, but add_rax_rdx does rax + rdx -> rax
    # We need: ptr + offset*8
    # After pop rdx: rdx = ptr, rax = offset*8
    # add_rax_rdx: rax = rax + rdx = offset*8 + ptr
    # That's correct!
  end

  # ptr_sub(ptr, offset) - subtract offset from pointer
  def gen_ptr_sub(node)
    eval_expression(node[:args][0])  # ptr
    @emitter.emit([0x50])  # push rax
    eval_expression(node[:args][1])  # offset
    @emitter.emit([0x48, 0xc1, 0xe0, 0x03])  # shl rax, 3
    @emitter.emit([0x48, 0x89, 0xc2])  # mov rdx, rax (offset*8)
    @emitter.emit([0x58])  # pop rax (ptr)
    @emitter.sub_rax_rdx  # rax = ptr - offset*8
  end

  # ptr_diff(ptr1, ptr2) - difference between pointers (in elements)
  def gen_ptr_diff(node)
    eval_expression(node[:args][0])  # ptr1
    @emitter.emit([0x50])  # push
    eval_expression(node[:args][1])  # ptr2
    @emitter.emit([0x48, 0x89, 0xc2])  # mov rdx, rax
    @emitter.emit([0x58])  # pop rax
    @emitter.sub_rax_rdx  # rax = ptr1 - ptr2
    @emitter.emit([0x48, 0xc1, 0xf8, 0x03])  # sar rax, 3 (divide by 8)
  end

  # sizeof(type) - return size of type
  def gen_sizeof(node)
    arg = node[:args][0]
    if arg[:type] == :variable
      type_name = arg[:name]
      size = @ctx.type_size(type_name)
      @emitter.mov_rax(size)
    else
      @emitter.mov_rax(8)  # default
    end
  end

  # Type casts - truncate/extend to specific size
  
  def gen_cast_i8(node)
    eval_expression(node[:args][0])
    @emitter.emit([0x48, 0x0f, 0xbe, 0xc0])  # movsx rax, al (sign extend)
  end

  def gen_cast_u8(node)
    eval_expression(node[:args][0])
    @emitter.emit([0x48, 0x0f, 0xb6, 0xc0])  # movzx rax, al (zero extend)
  end

  def gen_cast_i16(node)
    eval_expression(node[:args][0])
    @emitter.emit([0x48, 0x0f, 0xbf, 0xc0])  # movsx rax, ax
  end

  def gen_cast_u16(node)
    eval_expression(node[:args][0])
    @emitter.emit([0x48, 0x0f, 0xb7, 0xc0])  # movzx rax, ax
  end

  def gen_cast_i32(node)
    eval_expression(node[:args][0])
    @emitter.emit([0x48, 0x63, 0xc0])  # movsxd rax, eax
  end

  def gen_cast_u32(node)
    eval_expression(node[:args][0])
    @emitter.emit([0x89, 0xc0])  # mov eax, eax (zero extends)
  end

  def gen_cast_i64(node)
    eval_expression(node[:args][0])
    # Already 64-bit, nothing to do
  end

  def gen_cast_u64(node)
    eval_expression(node[:args][0])
    # Already 64-bit, nothing to do
  end
end
