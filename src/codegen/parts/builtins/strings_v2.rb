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
    loop_start = @emitter.current_pos
    @emitter.emit([0x80, 0x3c, 0x07, 0x00])  # cmp byte [rdi+rax], 0
    jz_pos = @emitter.current_pos
    @emitter.emit([0x74, 0x00])
    @emitter.emit([0x48, 0xff, 0xc0])  # inc rax
    jmp_back = @emitter.current_pos
    @emitter.emit([0xeb, (loop_start - (jmp_back + 2)) & 0xFF])

    # Patch JZ
    @emitter.bytes[jz_pos + 1] = (@emitter.current_pos - (jz_pos + 2)) & 0xFF
  end

  # str_copy(dst, src) - Copy string
  def gen_str_copy(node)
    return unless @target_os == :linux
    
    # Save r12 since we use it
    @emitter.push_reg(CodeEmitter::REG_R12)

    eval_expression(node[:args][0])
    @emitter.emit([0x49, 0x89, 0xc4])  # mov r12, rax (dst)
    
    eval_expression(node[:args][1])
    @emitter.emit([0x48, 0x89, 0xc6])  # mov rsi, rax (src)
    @emitter.emit([0x4c, 0x89, 0xe7])  # mov rdi, r12 (dst)
    
    # Copy loop
    loop_start = @emitter.current_pos
    @emitter.emit([0x8a, 0x06])  # mov al, [rsi]
    @emitter.emit([0x88, 0x07])  # mov [rdi], al
    @emitter.emit([0x84, 0xc0])  # test al, al
    jz_pos = @emitter.current_pos
    @emitter.emit([0x74, 0x00])
    @emitter.emit([0x48, 0xff, 0xc6])  # inc rsi
    @emitter.emit([0x48, 0xff, 0xc7])  # inc rdi
    jmp_back = @emitter.current_pos
    @emitter.emit([0xeb, (loop_start - (jmp_back + 2)) & 0xFF])

    # Patch JZ
    @emitter.bytes[jz_pos + 1] = (@emitter.current_pos - (jz_pos + 2)) & 0xFF
    
    @emitter.emit([0x4c, 0x89, 0xe0])  # mov rax, r12 (return dst)
    @emitter.pop_reg(CodeEmitter::REG_R12)
  end

  # str_cat(dst, src) - Concatenate src to end of dst
  def gen_str_cat(node)
    return unless @target_os == :linux
    
    @emitter.push_reg(CodeEmitter::REG_R12)
    @emitter.push_reg(CodeEmitter::REG_R13)

    eval_expression(node[:args][0])
    @emitter.emit([0x49, 0x89, 0xc4])  # mov r12, rax (dst)
    
    eval_expression(node[:args][1])
    @emitter.emit([0x49, 0x89, 0xc5])  # mov r13, rax (src)
    
    # Find end of dst
    @emitter.emit([0x4c, 0x89, 0xe7])  # mov rdi, r12
    loop1 = @emitter.current_pos
    @emitter.emit([0x80, 0x3f, 0x00])  # cmp byte [rdi], 0
    jz1 = @emitter.current_pos
    @emitter.emit([0x74, 0x00])
    @emitter.emit([0x48, 0xff, 0xc7])  # inc rdi
    jb1 = @emitter.current_pos
    @emitter.emit([0xeb, (loop1 - (jb1 + 2)) & 0xFF])

    @emitter.bytes[jz1 + 1] = (@emitter.current_pos - (jz1 + 2)) & 0xFF
    
    # Copy src to end
    @emitter.emit([0x4c, 0x89, 0xee])  # mov rsi, r13 (src)
    loop2 = @emitter.current_pos
    @emitter.emit([0x8a, 0x06])  # mov al, [rsi]
    @emitter.emit([0x88, 0x07])  # mov [rdi], al
    @emitter.emit([0x84, 0xc0])  # test al, al
    jz2 = @emitter.current_pos
    @emitter.emit([0x74, 0x00])
    @emitter.emit([0x48, 0xff, 0xc6])  # inc rsi
    @emitter.emit([0x48, 0xff, 0xc7])  # inc rdi
    jb2 = @emitter.current_pos
    @emitter.emit([0xeb, (loop2 - (jb2 + 2)) & 0xFF])

    @emitter.bytes[jz2 + 1] = (@emitter.current_pos - (jz2 + 2)) & 0xFF
    
    @emitter.emit([0x4c, 0x89, 0xe0])  # mov rax, r12 (return dst)
    @emitter.pop_reg(CodeEmitter::REG_R13)
    @emitter.pop_reg(CodeEmitter::REG_R12)
  end

  # str_cmp(s1, s2) - Compare strings, returns 0 if equal
  def gen_str_cmp(node)
    return unless @target_os == :linux
    
    @emitter.push_reg(CodeEmitter::REG_R12)

    eval_expression(node[:args][0])
    @emitter.emit([0x49, 0x89, 0xc4])  # mov r12, rax (s1)
    
    eval_expression(node[:args][1])
    @emitter.emit([0x48, 0x89, 0xc6])  # mov rsi, rax (s2)
    @emitter.emit([0x4c, 0x89, 0xe7])  # mov rdi, r12 (s1)
    
    # Compare loop
    loop_start = @emitter.current_pos
    @emitter.emit([0x8a, 0x07])  # mov al, [rdi]
    @emitter.emit([0x8a, 0x1e])  # mov bl, [rsi]
    @emitter.emit([0x38, 0xd8])  # cmp al, bl
    jne_pos = @emitter.current_pos
    @emitter.emit([0x75, 0x00])
    @emitter.emit([0x84, 0xc0])  # test al, al
    jz_pos = @emitter.current_pos
    @emitter.emit([0x74, 0x00])
    @emitter.emit([0x48, 0xff, 0xc7])  # inc rdi
    @emitter.emit([0x48, 0xff, 0xc6])  # inc rsi
    jb = @emitter.current_pos
    @emitter.emit([0xeb, (loop_start - (jb + 2)) & 0xFF])
    
    # not_equal:
    jne_target = @emitter.current_pos
    @emitter.bytes[jne_pos + 1] = (jne_target - (jne_pos + 2)) & 0xFF
    @emitter.emit([0x0f, 0xb6, 0xc0])  # movzx eax, al
    @emitter.emit([0x0f, 0xb6, 0xdb])  # movzx ebx, bl
    @emitter.emit([0x29, 0xd8])  # sub eax, ebx
    jmp_done = @emitter.current_pos
    @emitter.emit([0xeb, 0x00])
    
    # equal:
    jz_target = @emitter.current_pos
    @emitter.bytes[jz_pos + 1] = (jz_target - (jz_pos + 2)) & 0xFF
    @emitter.emit([0x31, 0xc0])  # xor eax, eax

    # done
    done_target = @emitter.current_pos
    @emitter.bytes[jmp_done + 1] = (done_target - (jmp_done + 2)) & 0xFF

    @emitter.pop_reg(CodeEmitter::REG_R12)
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
    @emitter.emit([0x0f, 0xb6, 0x08])  # movzx ecx, byte [rax] (first char of needle)
    
    @emitter.emit([0x5e])  # pop rsi (haystack)
    @emitter.emit([0x48, 0x31, 0xff])  # xor rdi, rdi (index)
    
    # loop:
    loop_start = @emitter.current_pos
    @emitter.emit([0x0f, 0xb6, 0x1c, 0x3e])  # movzx ebx, byte [rsi+rdi]
    @emitter.emit([0x85, 0xdb])  # test ebx, ebx
    jz_pos = @emitter.current_pos
    @emitter.emit([0x74, 0x00])
    @emitter.emit([0x39, 0xcb])  # cmp ebx, ecx
    je_pos = @emitter.current_pos
    @emitter.emit([0x74, 0x00])
    @emitter.emit([0x48, 0xff, 0xc7])  # inc rdi
    jb = @emitter.current_pos
    @emitter.emit([0xeb, (loop_start - (jb + 2)) & 0xFF])

    # found:
    found_target = @emitter.current_pos
    @emitter.bytes[je_pos + 1] = (found_target - (je_pos + 2)) & 0xFF
    @emitter.emit([0x48, 0x89, 0xf8])  # mov rax, rdi
    jmp_done = @emitter.current_pos
    @emitter.emit([0xeb, 0x00])

    # end (not found):
    not_found_target = @emitter.current_pos
    @emitter.bytes[jz_pos + 1] = (not_found_target - (jz_pos + 2)) & 0xFF
    @emitter.emit([0x48, 0xc7, 0xc0, 0xff, 0xff, 0xff, 0xff]) # mov rax, -1

    # done
    done_target = @emitter.current_pos
    @emitter.bytes[jmp_done + 1] = (done_target - (jmp_done + 2)) & 0xFF
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
    jne_pos = @emitter.current_pos
    @emitter.emit([0x75, 0x00])
    @emitter.emit([0x48, 0xff, 0xc1])  # inc rcx (set negative)
    @emitter.emit([0x48, 0xff, 0xc6])  # inc rsi
    
    # Parse digits
    parse_target = @emitter.current_pos
    @emitter.bytes[jne_pos + 1] = (parse_target - (jne_pos + 2)) & 0xFF

    loop_start = @emitter.current_pos
    @emitter.emit([0x0f, 0xb6, 0x1e])  # movzx ebx, byte [rsi]
    @emitter.emit([0x80, 0xfb, 0x30])  # cmp bl, '0'
    jb_pos = @emitter.current_pos
    @emitter.emit([0x72, 0x00])
    @emitter.emit([0x80, 0xfb, 0x39])  # cmp bl, '9'
    ja_pos = @emitter.current_pos
    @emitter.emit([0x77, 0x00])
    @emitter.emit([0x80, 0xeb, 0x30])  # sub bl, '0'
    @emitter.emit([0x48, 0x6b, 0xc0, 0x0a])  # imul rax, 10
    @emitter.emit([0x48, 0x01, 0xd8])  # add rax, rbx
    @emitter.emit([0x48, 0xff, 0xc6])  # inc rsi
    jmp_back = @emitter.current_pos
    @emitter.emit([0xeb, (loop_start - (jmp_back + 2)) & 0xFF])
    
    # done - apply sign
    done_target = @emitter.current_pos
    @emitter.bytes[jb_pos + 1] = (done_target - (jb_pos + 2)) & 0xFF
    @emitter.bytes[ja_pos + 1] = (done_target - (ja_pos + 2)) & 0xFF

    @emitter.emit([0x48, 0x85, 0xc9])  # test rcx, rcx
    jz_pos = @emitter.current_pos
    @emitter.emit([0x74, 0x03])
    @emitter.emit([0x48, 0xf7, 0xd8])  # neg rax
    # positive/done
    @emitter.bytes[jz_pos + 1] = (@emitter.current_pos - (jz_pos + 2)) & 0xFF
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
    
    # Get buffer address using lea
    @emitter.emit([0x48, 0x8d, 0x1d])  # lea rbx, [rip+offset]
    @linker.add_data_patch(@emitter.current_pos, "itoa_buffer")
    @emitter.emit([0x00, 0x00, 0x00, 0x00])
    @emitter.emit([0x48, 0x83, 0xc3, 0x1f])  # add rbx, 31
    @emitter.emit([0xc6, 0x03, 0x00])  # mov byte [rbx], 0 (null term)
    
    # Handle zero case
    @emitter.emit([0x48, 0x85, 0xc0])  # test rax, rax
    jnz_pos = @emitter.current_pos
    @emitter.emit([0x75, 0x00])
    @emitter.emit([0x48, 0xff, 0xcb])  # dec rbx
    @emitter.emit([0xc6, 0x03, 0x30])  # mov byte [rbx], '0'
    jmp_done = @emitter.current_pos
    @emitter.emit([0xeb, 0x00])
    
    # not_zero: convert loop
    not_zero_target = @emitter.current_pos
    @emitter.bytes[jnz_pos + 1] = (not_zero_target - (jnz_pos + 2)) & 0xFF

    @emitter.emit([0x49, 0x89, 0xc1]) # mov r9, rax (save n)
    @emitter.emit([0xb9, 0x0a, 0x00, 0x00, 0x00])  # mov ecx, 10

    loop_start = @emitter.current_pos
    @emitter.emit([0x4c, 0x89, 0xc8]) # mov rax, r9
    @emitter.emit([0x48, 0x31, 0xd2])  # xor rdx, rdx
    @emitter.emit([0x48, 0xf7, 0xf1])  # div rcx
    @emitter.emit([0x49, 0x89, 0xc1]) # mov r9, rax (quotient)
    @emitter.emit([0x80, 0xc2, 0x30])  # add dl, '0'
    @emitter.emit([0x48, 0xff, 0xcb])  # dec rbx
    @emitter.emit([0x88, 0x13])  # mov [rbx], dl
    @emitter.emit([0x4d, 0x85, 0xc9])  # test r9, r9
    jmp_back = @emitter.current_pos
    @emitter.emit([0x75, (loop_start - (jmp_back + 2)) & 0xFF])
    
    # done:
    done_target = @emitter.current_pos
    @emitter.bytes[jmp_done + 1] = (done_target - (jmp_done + 2)) & 0xFF
    @emitter.emit([0x48, 0x89, 0xd8])  # mov rax, rbx
  end

  # str_upper(s) - Convert to uppercase in-place
  def gen_str_upper(node)
    return unless @target_os == :linux
    
    @emitter.push_reg(CodeEmitter::REG_R12)

    eval_expression(node[:args][0])
    @emitter.emit([0x48, 0x89, 0xc7])  # mov rdi, rax
    @emitter.emit([0x49, 0x89, 0xfc])  # mov r12, rdi (save start)
    
    loop_start = @emitter.current_pos
    @emitter.emit([0x8a, 0x07])  # mov al, [rdi]
    @emitter.emit([0x84, 0xc0])  # test al, al
    jz_pos = @emitter.current_pos
    @emitter.emit([0x74, 0x00])
    @emitter.emit([0x3c, 0x61])  # cmp al, 'a'
    jb_pos = @emitter.current_pos
    @emitter.emit([0x72, 0x00])
    @emitter.emit([0x3c, 0x7a])  # cmp al, 'z'
    ja_pos = @emitter.current_pos
    @emitter.emit([0x77, 0x00])
    @emitter.emit([0x2c, 0x20])  # sub al, 32
    @emitter.emit([0x88, 0x07])  # mov [rdi], al

    next_pos = @emitter.current_pos
    @emitter.bytes[jb_pos + 1] = (next_pos - (jb_pos + 2)) & 0xFF
    @emitter.bytes[ja_pos + 1] = (next_pos - (ja_pos + 2)) & 0xFF

    @emitter.emit([0x48, 0xff, 0xc7])  # inc rdi
    jmp_back = @emitter.current_pos
    @emitter.emit([0xeb, (loop_start - (jmp_back + 2)) & 0xFF])
    
    done_target = @emitter.current_pos
    @emitter.bytes[jz_pos + 1] = (done_target - (jz_pos + 2)) & 0xFF
    @emitter.emit([0x4c, 0x89, 0xe0])  # mov rax, r12
    @emitter.pop_reg(CodeEmitter::REG_R12)
  end

  # str_lower(s) - Convert to lowercase in-place
  def gen_str_lower(node)
    return unless @target_os == :linux
    
    @emitter.push_reg(CodeEmitter::REG_R12)

    eval_expression(node[:args][0])
    @emitter.emit([0x48, 0x89, 0xc7])  # mov rdi, rax
    @emitter.emit([0x49, 0x89, 0xfc])  # mov r12, rdi
    
    loop_start = @emitter.current_pos
    @emitter.emit([0x8a, 0x07])  # mov al, [rdi]
    @emitter.emit([0x84, 0xc0])  # test al, al
    jz_pos = @emitter.current_pos
    @emitter.emit([0x74, 0x00])
    @emitter.emit([0x3c, 0x41])  # cmp al, 'A'
    jb_pos = @emitter.current_pos
    @emitter.emit([0x72, 0x00])
    @emitter.emit([0x3c, 0x5a])  # cmp al, 'Z'
    ja_pos = @emitter.current_pos
    @emitter.emit([0x77, 0x00])
    @emitter.emit([0x04, 0x20])  # add al, 32
    @emitter.emit([0x88, 0x07])  # mov [rdi], al

    next_pos = @emitter.current_pos
    @emitter.bytes[jb_pos + 1] = (next_pos - (jb_pos + 2)) & 0xFF
    @emitter.bytes[ja_pos + 1] = (next_pos - (ja_pos + 2)) & 0xFF

    @emitter.emit([0x48, 0xff, 0xc7])  # inc rdi
    jmp_back = @emitter.current_pos
    @emitter.emit([0xeb, (loop_start - (jmp_back + 2)) & 0xFF])
    
    done_target = @emitter.current_pos
    @emitter.bytes[jz_pos + 1] = (done_target - (jz_pos + 2)) & 0xFF
    @emitter.emit([0x4c, 0x89, 0xe0])  # mov rax, r12
    @emitter.pop_reg(CodeEmitter::REG_R12)
  end

  # str_trim(s) - Trim leading whitespace (returns new ptr)
  def gen_str_trim(node)
    return unless @target_os == :linux
    
    eval_expression(node[:args][0])
    @emitter.emit([0x48, 0x89, 0xc7])  # mov rdi, rax
    
    # Skip leading whitespace
    loop_start = @emitter.current_pos
    @emitter.emit([0x8a, 0x07])  # mov al, [rdi]
    @emitter.emit([0x3c, 0x20])  # cmp al, ' '
    je_pos = @emitter.current_pos
    @emitter.emit([0x74, 0x06])
    @emitter.emit([0x3c, 0x09])  # cmp al, '\t'
    je_pos2 = @emitter.current_pos
    @emitter.emit([0x74, 0x02])
    jmp_found = @emitter.current_pos
    @emitter.emit([0xeb, 0x00]) # jmp found_start (patch later)

    # skip:
    skip_pos = @emitter.current_pos
    @emitter.emit([0x48, 0xff, 0xc7])  # inc rdi
    jmp_back = @emitter.current_pos
    @emitter.emit([0xeb, (loop_start - (jmp_back + 2)) & 0xFF])

    # found_start:
    found_target = @emitter.current_pos
    @emitter.bytes[jmp_found + 1] = (found_target - (jmp_found + 2)) & 0xFF
    
    # Return pointer to first non-space
    @emitter.emit([0x48, 0x89, 0xf8])  # mov rax, rdi
  end
end
