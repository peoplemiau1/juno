# Extended String API
# str_new, str_concat, str_find, str_split, str_to_int, int_to_str

module BuiltinStringsV2
  def setup_strings_v2
    return if @strings_v2_setup
    @strings_v2_setup = true

    # String buffers (4KB each)
    @linker.add_data("str_buf_1", "\x00" * 4096)
    @linker.add_data("str_buf_2", "\x00" * 4096)
    @linker.add_data("str_buf_3", "\x00" * 4096)
    @linker.add_data("itoa_buffer", "\x00" * 32)
    @linker.add_data("str_buf_idx", [0].pack("Q<"))
  end

  # str_len(s) - Get string length (null-terminated)
  def gen_str_len(node)
    return unless @target_os == :linux

    eval_expression(node[:args][0])
    @emitter.emit([0x48, 0x89, 0xc7])  # mov rdi, rax (string ptr)
    @emitter.emit([0x48, 0x31, 0xc0])  # xor rax, rax (counter)

    # Loop
    l_loop = @emitter.current_pos
    @emitter.emit([0x80, 0x3c, 0x07, 0x00])  # cmp byte [rdi+rax], 0
    p_done = @emitter.je_rel32
    @emitter.emit([0x48, 0xff, 0xc0])  # inc rax
    p_loop = @emitter.jmp_rel32
    @emitter.patch_jmp(p_loop, l_loop)
    @emitter.patch_je(p_done, @emitter.current_pos)
  end

  # str_copy(dst, src) - Copy string
  def gen_str_copy(node)
    return unless @target_os == :linux

    eval_expression(node[:args][0]); @emitter.push_reg(0) # dst
    eval_expression(node[:args][1]) # src
    @emitter.mov_reg_reg(6, 0) # RSI = src
    @emitter.pop_reg(7)        # RDI = dst
    @emitter.push_reg(7)       # save original dst for return

    # Copy loop
    l_loop = @emitter.current_pos
    @emitter.emit([0x8a, 0x06])  # mov al, [rsi]
    @emitter.emit([0x88, 0x07])  # mov [rdi], al
    @emitter.emit([0x84, 0xc0])  # test al, al
    p_done = @emitter.je_rel32
    @emitter.emit([0x48, 0xff, 0xc6])  # inc rsi
    @emitter.emit([0x48, 0xff, 0xc7])  # inc rdi
    p_loop = @emitter.jmp_rel32
    @emitter.patch_jmp(p_loop, l_loop)
    @emitter.patch_je(p_done, @emitter.current_pos)

    @emitter.pop_reg(0) # return dst
  end

  # str_cat(dst, src) - Concatenate src to end of dst
  def gen_str_cat(node)
    return unless @target_os == :linux

    eval_expression(node[:args][0]); @emitter.push_reg(0) # dst
    eval_expression(node[:args][1]); @emitter.push_reg(0) # src
    @emitter.pop_reg(6)         # RSI = src
    @emitter.pop_reg(7)         # RDI = dst
    @emitter.push_reg(7)        # save original dst for return

    # Find end of dst
    l_find = @emitter.current_pos
    @emitter.emit([0x80, 0x3f, 0x00])  # cmp byte [rdi], 0
    p_found = @emitter.je_rel32
    @emitter.emit([0x48, 0xff, 0xc7])  # inc rdi
    p_find_loop = @emitter.jmp_rel32
    @emitter.patch_jmp(p_find_loop, l_find)
    @emitter.patch_je(p_found, @emitter.current_pos)

    # Copy src to end
    l_copy = @emitter.current_pos
    @emitter.emit([0x8a, 0x06])  # mov al, [rsi]
    @emitter.emit([0x88, 0x07])  # mov [rdi], al
    @emitter.emit([0x84, 0xc0])  # test al, al
    p_done = @emitter.je_rel32
    @emitter.emit([0x48, 0xff, 0xc6])  # inc rsi
    @emitter.emit([0x48, 0xff, 0xc7])  # inc rdi
    p_copy_loop = @emitter.jmp_rel32
    @emitter.patch_jmp(p_copy_loop, l_copy)
    @emitter.patch_je(p_done, @emitter.current_pos)

    @emitter.pop_reg(0) # return original dst
  end

  # str_cmp(s1, s2) - Compare strings, returns 0 if equal
  def gen_str_cmp(node)
    return unless @target_os == :linux

    eval_expression(node[:args][0]); @emitter.push_reg(0) # s1
    eval_expression(node[:args][1]) # s2
    @emitter.mov_reg_reg(6, 0) # RSI = s2
    @emitter.pop_reg(7)        # RDI = s1

    # Compare loop
    l_loop = @emitter.current_pos
    @emitter.emit([0x8a, 0x07])  # mov al, [rdi]
    @emitter.emit([0x44, 0x8a, 0x16])  # mov r10b, [rsi]
    @emitter.emit([0x44, 0x38, 0xd0])  # cmp al, r10b
    p_ne = @emitter.jne_rel32
    @emitter.emit([0x84, 0xc0])  # test al, al
    p_eq = @emitter.je_rel32
    @emitter.emit([0x48, 0xff, 0xc7])  # inc rdi
    @emitter.emit([0x48, 0xff, 0xc6])  # inc rsi
    p_loop = @emitter.jmp_rel32
    @emitter.patch_jmp(p_loop, l_loop)

    # not_equal:
    @emitter.patch_jne(p_ne, @emitter.current_pos)
    @emitter.emit([0x0f, 0xb6, 0xc0])  # movzx eax, al
    @emitter.emit([0x45, 0x0f, 0xb6, 0xd2])  # movzx r10d, r10b
    @emitter.emit([0x44, 0x29, 0xd0])  # sub eax, r10d
    p_done = @emitter.jmp_rel32

    # equal:
    @emitter.patch_je(p_eq, @emitter.current_pos)
    @emitter.emit([0x31, 0xc0])  # xor eax, eax
    
    @emitter.patch_jmp(p_done, @emitter.current_pos)
  end

  # str_find(haystack, needle) - Find first char of needle in haystack
  def gen_str_find(node)
    return unless @target_os == :linux

    args = node[:args] || []
    if args.length < 2
      @emitter.emit([0x48, 0xc7, 0xc0, 0xff, 0xff, 0xff, 0xff])
      return
    end

    eval_expression(args[0])
    @emitter.emit([0x50])  # push rax (haystack)

    eval_expression(args[1])
    @emitter.emit([0x0f, 0xb6, 0x08])  # movzx ecx, byte [rax]

    @emitter.emit([0x5e])  # pop rsi (haystack)
    @emitter.emit([0x48, 0xc7, 0xc0, 0xff, 0xff, 0xff, 0xff])  # mov rax, -1
    @emitter.emit([0x48, 0x31, 0xff])  # xor rdi, rdi (index)

    # loop:
    l_loop = @emitter.current_pos
    @emitter.emit([0x44, 0x0f, 0xb6, 0x14, 0x3e])  # movzx r10d, byte [rsi+rdi]
    @emitter.emit([0x45, 0x85, 0xd2])  # test r10d, r10d
    p_end = @emitter.je_rel32
    @emitter.emit([0x44, 0x39, 0xca])  # cmp r10d, ecx
    p_found = @emitter.je_rel32
    @emitter.emit([0x48, 0xff, 0xc7])  # inc rdi
    p_loop = @emitter.jmp_rel32
    @emitter.patch_jmp(p_loop, l_loop)

    # found:
    @emitter.patch_je(p_found, @emitter.current_pos)
    @emitter.emit([0x48, 0x89, 0xf8])  # mov rax, rdi
    
    # end:
    @emitter.patch_je(p_end, @emitter.current_pos)
  end

  # str_to_int(s) - Parse string to integer
  def gen_str_to_int(node)
    return unless @target_os == :linux

    args = node[:args] || []
    return @emitter.emit([0x48, 0x31, 0xc0]) if args.empty?

    eval_expression(args[0])
    @emitter.emit([0x48, 0x89, 0xc6])  # mov rsi, rax (string)
    @emitter.emit([0x48, 0x31, 0xc0])  # xor rax, rax (result)
    @emitter.emit([0x48, 0x31, 0xc9])  # xor rcx, rcx (negative flag)

    # Check for minus sign
    @emitter.emit([0x80, 0x3e, 0x2d])  # cmp byte [rsi], '-'
    p_parse = @emitter.jne_rel32
    @emitter.emit([0x48, 0xff, 0xc1])  # inc rcx (set negative)
    @emitter.emit([0x48, 0xff, 0xc6])  # inc rsi

    # Parse digits
    @emitter.patch_jne(p_parse, @emitter.current_pos)
    l_loop = @emitter.current_pos
    @emitter.emit([0x44, 0x0f, 0xb6, 0x16])  # movzx r10d, byte [rsi]
    @emitter.emit([0x41, 0x80, 0xfa, 0x30])  # cmp r10b, '0'
    p_done1 = @emitter.jl_rel32
    @emitter.emit([0x41, 0x80, 0xfa, 0x39])  # cmp r10b, '9'
    p_done2 = @emitter.jg_rel32
    
    @emitter.emit([0x41, 0x80, 0xea, 0x30])  # sub r10b, '0'
    @emitter.emit([0x48, 0x6b, 0xc0, 0x0a])  # imul rax, 10
    @emitter.emit([0x4c, 0x01, 0xd0])  # add rax, r10
    @emitter.emit([0x48, 0xff, 0xc6])  # inc rsi
    p_loop = @emitter.jmp_rel32
    @emitter.patch_jmp(p_loop, l_loop)

    # done - apply sign
    @emitter.patch_jl(p_done1, @emitter.current_pos)
    @emitter.patch_jg(p_done2, @emitter.current_pos)
    @emitter.emit([0x48, 0x85, 0xc9])  # test rcx, rcx
    p_pos = @emitter.je_rel32
    @emitter.emit([0x48, 0xf7, 0xd8])  # neg rax
    @emitter.patch_je(p_pos, @emitter.current_pos)
  end

  # int_to_str(n) - Convert integer to string
  def gen_int_to_str(node)
    return unless @target_os == :linux
    setup_strings_v2

    args = node[:args] || []
    if args.empty?
      @emitter.emit([0x48, 0x31, 0xc0])  # xor rax, rax
      return
    end

    eval_expression(args[0])
    # rax = number to convert

    # Get buffer address
    @emitter.emit([0x4c, 0x8d, 0x15])  # lea r10, [rip+offset]
    @linker.add_data_patch(@emitter.current_pos, "itoa_buffer")
    @emitter.emit([0x00, 0x00, 0x00, 0x00])
    @emitter.emit([0x49, 0x83, 0xc2, 0x1f])  # add r10, 31
    @emitter.emit([0x41, 0xc6, 0x02, 0x00])  # mov byte [r10], 0 (null term)
    @emitter.emit([0x4d, 0x89, 0xd0])  # mov r8, r10 (save end pos)

    # Handle zero case
    @emitter.emit([0x48, 0x85, 0xc0])  # test rax, rax
    p_nz = @emitter.jne_rel32
    @emitter.emit([0x49, 0xff, 0xca])  # dec r10
    @emitter.emit([0x41, 0xc6, 0x02, 0x30])  # mov byte [r10], '0'
    p_done = @emitter.jmp_rel32

    # not_zero: convert loop
    @emitter.patch_jne(p_nz, @emitter.current_pos)
    @emitter.emit([0xb9, 0x0a, 0x00, 0x00, 0x00])  # mov ecx, 10
    l_loop = @emitter.current_pos
    @emitter.emit([0x48, 0x31, 0xd2])  # xor rdx, rdx
    @emitter.emit([0x48, 0xf7, 0xf1])  # div rcx
    @emitter.emit([0x80, 0xc2, 0x30])  # add dl, '0'
    @emitter.emit([0x49, 0xff, 0xca])  # dec r10
    @emitter.emit([0x41, 0x88, 0x12])  # mov [r10], dl
    @emitter.emit([0x48, 0x85, 0xc0])  # test rax, rax
    p_loop = @emitter.jne_rel32
    @emitter.patch_jne(p_loop, l_loop)

    # done:
    @emitter.patch_jmp(p_done, @emitter.current_pos)
    @emitter.emit([0x4c, 0x89, 0xd0])  # mov rax, r10
  end

  # str_upper(s) - Convert to uppercase in-place
  def gen_str_upper(node)
    return unless @target_os == :linux

    eval_expression(node[:args][0])
    @emitter.emit([0x48, 0x89, 0xc7])  # mov rdi, rax
    @emitter.emit([0x49, 0x89, 0xfb])  # mov r11, rdi (save start)

    l_loop = @emitter.current_pos
    @emitter.emit([0x8a, 0x07])  # mov al, [rdi]
    @emitter.emit([0x84, 0xc0])  # test al, al
    p_end = @emitter.je_rel32
    
    @emitter.emit([0x3c, 0x61])  # cmp al, 'a'
    p_next1 = @emitter.jl_rel32
    @emitter.emit([0x3c, 0x7a])  # cmp al, 'z'
    p_next2 = @emitter.jg_rel32
    
    @emitter.emit([0x2c, 0x20])  # sub al, 32
    @emitter.emit([0x88, 0x07])  # mov [rdi], al
    
    @emitter.patch_jl(p_next1, @emitter.current_pos)
    @emitter.patch_jg(p_next2, @emitter.current_pos)
    @emitter.emit([0x48, 0xff, 0xc7])  # inc rdi
    p_loop = @emitter.jmp_rel32
    @emitter.patch_jmp(p_loop, l_loop)
    
    @emitter.patch_je(p_end, @emitter.current_pos)
    @emitter.emit([0x4c, 0x89, 0xd8])  # mov rax, r11
  end

  # str_lower(s) - Convert to lowercase in-place
  def gen_str_lower(node)
    return unless @target_os == :linux

    eval_expression(node[:args][0])
    @emitter.emit([0x48, 0x89, 0xc7])  # mov rdi, rax
    @emitter.emit([0x49, 0x89, 0xfb])  # mov r11, rdi

    l_loop = @emitter.current_pos
    @emitter.emit([0x8a, 0x07])  # mov al, [rdi]
    @emitter.emit([0x84, 0xc0])  # test al, al
    p_end = @emitter.je_rel32
    
    @emitter.emit([0x3c, 0x41])  # cmp al, 'A'
    p_next1 = @emitter.jl_rel32
    @emitter.emit([0x3c, 0x5a])  # cmp al, 'Z'
    p_next2 = @emitter.jg_rel32
    
    @emitter.emit([0x04, 0x20])  # add al, 32
    @emitter.emit([0x88, 0x07])  # mov [rdi], al
    
    @emitter.patch_jl(p_next1, @emitter.current_pos)
    @emitter.patch_jg(p_next2, @emitter.current_pos)
    @emitter.emit([0x48, 0xff, 0xc7])  # inc rdi
    p_loop = @emitter.jmp_rel32
    @emitter.patch_jmp(p_loop, l_loop)
    
    @emitter.patch_je(p_end, @emitter.current_pos)
    @emitter.emit([0x4c, 0x89, 0xd8])  # mov rax, r11
  end

  # str_trim(s) - Trim leading whitespace and trailing newlines
  def gen_str_trim(node)
    return unless @target_os == :linux

    eval_expression(node[:args][0])
    @emitter.test_rax_rax
    p_null = @emitter.je_rel32
    
    @emitter.mov_reg_reg(7, 0) # rdi = rax
    
    l_loop = @emitter.current_pos
    @emitter.emit([0x0f, 0xb6, 0x07])  # movzx eax, byte [rdi]
    @emitter.emit([0x3c, 0x20])        # cmp al, 0x20 (space)
    p_s1 = @emitter.je_rel32
    @emitter.emit([0x3c, 0x09])        # cmp al, 0x09 (tab)
    p_s2 = @emitter.je_rel32
    @emitter.emit([0x3c, 0x0a])        # cmp al, 0x0a (newline)
    p_s3 = @emitter.je_rel32
    
    p_scan = @emitter.jmp_rel32
    
    @emitter.patch_je(p_s1, @emitter.current_pos)
    @emitter.patch_je(p_s2, @emitter.current_pos)
    @emitter.patch_je(p_s3, @emitter.current_pos)
    
    @emitter.emit([0x48, 0xff, 0xc7])  # inc rdi
    p_loop = @emitter.jmp_rel32
    @emitter.patch_jmp(p_loop, l_loop)
    
    @emitter.patch_jmp(p_scan, @emitter.current_pos)
    
    # Trim trailing newlines (scan forward)
    @emitter.mov_reg_reg(6, 7) # rsi = rdi
    l_scan = @emitter.current_pos
    @emitter.emit([0x0f, 0xb6, 0x0e])  # movzx ecx, byte [rsi]
    @emitter.emit([0x84, 0xc9])        # test cl, cl
    p_end_scan = @emitter.je_rel32
    @emitter.emit([0x80, 0xf9, 0x0a])  # cmp cl, '\n'
    p_chomp1 = @emitter.je_rel32
    @emitter.emit([0x80, 0xf9, 0x0d])  # cmp cl, '\r'
    p_chomp2 = @emitter.je_rel32
    
    @emitter.emit([0x48, 0xff, 0xc6])  # inc rsi
    p_next_scan = @emitter.jmp_rel32
    @emitter.patch_jmp(p_next_scan, l_scan)
    
    @emitter.patch_je(p_chomp1, @emitter.current_pos)
    @emitter.patch_je(p_chomp2, @emitter.current_pos)
    @emitter.emit([0xc6, 0x06, 0x00])  # mov byte [rsi], 0
    
    @emitter.patch_je(p_end_scan, @emitter.current_pos)
    
    @emitter.mov_reg_reg(0, 7) # return rdi (trimmed start)
    @emitter.patch_je(p_null, @emitter.current_pos)
  end

  # byte_at(ptr, idx)
  def gen_byte_at(node)
    eval_expression(node[:args][0]); @emitter.push_reg(0)
    eval_expression(node[:args][1])
    @emitter.pop_reg(2) # rdx = ptr
    @emitter.emit([0x0f, 0xb6, 0x04, 0x02]) # movzx rax, byte [rdx + rax]
  end

  # byte_set(ptr, idx, val)
  def gen_byte_set(node)
    eval_expression(node[:args][0]); @emitter.push_reg(0)
    eval_expression(node[:args][1]); @emitter.push_reg(0)
    eval_expression(node[:args][2]) # rax = val
    @emitter.pop_reg(1) # rcx = idx
    @emitter.pop_reg(2) # rdx = ptr
    @emitter.emit([0x88, 0x04, 0x0a]) # mov [rdx + rcx], al
  end
end
