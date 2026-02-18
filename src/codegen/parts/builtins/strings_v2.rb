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
    @emitter.emit([0x80, 0x3c, 0x07, 0x00])  # cmp byte [rdi+rax], 0
    @emitter.emit([0x74, 0x04])  # je done
    @emitter.emit([0x48, 0xff, 0xc0])  # inc rax
    @emitter.emit([0xeb, 0xf5])  # jmp loop
    # done - rax has length
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
    @emitter.emit([0x8a, 0x06])  # mov al, [rsi]
    @emitter.emit([0x88, 0x07])  # mov [rdi], al
    @emitter.emit([0x84, 0xc0])  # test al, al
    @emitter.emit([0x74, 0x06])  # je done
    @emitter.emit([0x48, 0xff, 0xc6])  # inc rsi
    @emitter.emit([0x48, 0xff, 0xc7])  # inc rdi
    @emitter.emit([0xeb, 0xf2])  # jmp loop

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
    @emitter.emit([0x80, 0x3f, 0x00])  # cmp byte [rdi], 0
    @emitter.emit([0x74, 0x04])  # je found_end
    @emitter.emit([0x48, 0xff, 0xc7])  # inc rdi
    @emitter.emit([0xeb, 0xf6])  # jmp find_loop

    # Copy src to end
    @emitter.emit([0x8a, 0x06])  # mov al, [rsi]
    @emitter.emit([0x88, 0x07])  # mov [rdi], al
    @emitter.emit([0x84, 0xc0])  # test al, al
    @emitter.emit([0x74, 0x06])  # je done
    @emitter.emit([0x48, 0xff, 0xc6])  # inc rsi
    @emitter.emit([0x48, 0xff, 0xc7])  # inc rdi
    @emitter.emit([0xeb, 0xf2])  # jmp copy_loop

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
    @emitter.emit([0x8a, 0x07])  # mov al, [rdi]
    @emitter.emit([0x8a, 0x1e])  # mov bl, [rsi]
    @emitter.emit([0x38, 0xd8])  # cmp al, bl
    @emitter.emit([0x75, 0x0c])  # jne not_equal
    @emitter.emit([0x84, 0xc0])  # test al, al
    @emitter.emit([0x74, 0x0c])  # je equal (both 0)
    @emitter.emit([0x48, 0xff, 0xc7])  # inc rdi
    @emitter.emit([0x48, 0xff, 0xc6])  # inc rsi
    @emitter.emit([0xeb, 0xed])  # jmp loop

    # not_equal:
    @emitter.emit([0x0f, 0xb6, 0xc0])  # movzx eax, al
    @emitter.emit([0x0f, 0xb6, 0xdb])  # movzx ebx, bl
    @emitter.emit([0x29, 0xd8])  # sub eax, ebx
    @emitter.emit([0xeb, 0x02])  # jmp done

    # equal:
    @emitter.emit([0x31, 0xc0])  # xor eax, eax
    # done
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
    @emitter.emit([0x0f, 0xb6, 0x1c, 0x3e])  # movzx ebx, byte [rsi+rdi]
    @emitter.emit([0x85, 0xdb])  # test ebx, ebx
    @emitter.emit([0x74, 0x0b])  # je end
    @emitter.emit([0x39, 0xcb])  # cmp ebx, ecx
    @emitter.emit([0x74, 0x05])  # je found
    @emitter.emit([0x48, 0xff, 0xc7])  # inc rdi
    @emitter.emit([0xeb, 0xef])  # jmp loop
    # found:
    @emitter.emit([0x48, 0x89, 0xf8])  # mov rax, rdi
    # end:
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
    @emitter.emit([0x75, 0x05])  # jne parse
    @emitter.emit([0x48, 0xff, 0xc1])  # inc rcx (set negative)
    @emitter.emit([0x48, 0xff, 0xc6])  # inc rsi

    # Parse digits
    @emitter.emit([0x0f, 0xb6, 0x1e])  # movzx ebx, byte [rsi]
    @emitter.emit([0x80, 0xfb, 0x30])  # cmp bl, '0'
    @emitter.emit([0x72, 0x12])  # jb done
    @emitter.emit([0x80, 0xfb, 0x39])  # cmp bl, '9'
    @emitter.emit([0x77, 0x0d])  # ja done
    @emitter.emit([0x80, 0xeb, 0x30])  # sub bl, '0'
    @emitter.emit([0x48, 0x6b, 0xc0, 0x0a])  # imul rax, 10
    @emitter.emit([0x48, 0x01, 0xd8])  # add rax, rbx
    @emitter.emit([0x48, 0xff, 0xc6])  # inc rsi
    @emitter.emit([0xeb, 0xe7])  # jmp parse_loop

    # done - apply sign
    @emitter.emit([0x48, 0x85, 0xc9])  # test rcx, rcx
    @emitter.emit([0x74, 0x03])  # jz positive
    @emitter.emit([0x48, 0xf7, 0xd8])  # neg rax
    # positive/done
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

    # Get buffer address using lea (like concat does)
    @emitter.emit([0x48, 0x8d, 0x1d])  # lea rbx, [rip+offset]
    @linker.add_data_patch(@emitter.current_pos, "itoa_buffer")
    @emitter.emit([0x00, 0x00, 0x00, 0x00])
    @emitter.emit([0x48, 0x83, 0xc3, 0x1f])  # add rbx, 31
    @emitter.emit([0xc6, 0x03, 0x00])  # mov byte [rbx], 0 (null term)
    @emitter.emit([0x49, 0x89, 0xd8])  # mov r8, rbx (save end pos)

    # Handle zero case
    @emitter.emit([0x48, 0x85, 0xc0])  # test rax, rax
    @emitter.emit([0x75, 0x08])  # jnz not_zero
    @emitter.emit([0x48, 0xff, 0xcb])  # dec rbx
    @emitter.emit([0xc6, 0x03, 0x30])  # mov byte [rbx], '0'
    @emitter.emit([0xeb, 0x17])  # jmp done

    # not_zero: convert loop
    @emitter.emit([0xb9, 0x0a, 0x00, 0x00, 0x00])  # mov ecx, 10
    # loop:
    @emitter.emit([0x48, 0x31, 0xd2])  # xor rdx, rdx
    @emitter.emit([0x48, 0xf7, 0xf1])  # div rcx
    @emitter.emit([0x80, 0xc2, 0x30])  # add dl, '0'
    @emitter.emit([0x48, 0xff, 0xcb])  # dec rbx
    @emitter.emit([0x88, 0x13])  # mov [rbx], dl
    @emitter.emit([0x48, 0x85, 0xc0])  # test rax, rax
    @emitter.emit([0x75, 0xee])  # jnz loop

    # done:
    @emitter.emit([0x48, 0x89, 0xd8])  # mov rax, rbx
  end

  # str_upper(s) - Convert to uppercase in-place
  def gen_str_upper(node)
    return unless @target_os == :linux

    eval_expression(node[:args][0])
    @emitter.emit([0x48, 0x89, 0xc7])  # mov rdi, rax
    @emitter.emit([0x49, 0x89, 0xfc])  # mov r12, rdi (save start)

    @emitter.emit([0x8a, 0x07])  # mov al, [rdi]
    @emitter.emit([0x84, 0xc0])  # test al, al
    @emitter.emit([0x74, 0x0f])  # je done
    @emitter.emit([0x3c, 0x61])  # cmp al, 'a'
    @emitter.emit([0x72, 0x07])  # jb next
    @emitter.emit([0x3c, 0x7a])  # cmp al, 'z'
    @emitter.emit([0x77, 0x03])  # ja next
    @emitter.emit([0x2c, 0x20])  # sub al, 32
    @emitter.emit([0x88, 0x07])  # mov [rdi], al
    @emitter.emit([0x48, 0xff, 0xc7])  # inc rdi
    @emitter.emit([0xeb, 0xe9])  # jmp loop

    @emitter.emit([0x4c, 0x89, 0xe0])  # mov rax, r12
  end

  # str_lower(s) - Convert to lowercase in-place
  def gen_str_lower(node)
    return unless @target_os == :linux

    eval_expression(node[:args][0])
    @emitter.emit([0x48, 0x89, 0xc7])  # mov rdi, rax
    @emitter.emit([0x49, 0x89, 0xfc])  # mov r12, rdi

    @emitter.emit([0x8a, 0x07])  # mov al, [rdi]
    @emitter.emit([0x84, 0xc0])  # test al, al
    @emitter.emit([0x74, 0x0f])  # je done
    @emitter.emit([0x3c, 0x41])  # cmp al, 'A'
    @emitter.emit([0x72, 0x07])  # jb next
    @emitter.emit([0x3c, 0x5a])  # cmp al, 'Z'
    @emitter.emit([0x77, 0x03])  # ja next
    @emitter.emit([0x04, 0x20])  # add al, 32
    @emitter.emit([0x88, 0x07])  # mov [rdi], al
    @emitter.emit([0x48, 0xff, 0xc7])  # inc rdi
    @emitter.emit([0xeb, 0xe9])  # jmp loop

    @emitter.emit([0x4c, 0x89, 0xe0])  # mov rax, r12
  end

  # str_trim(s) - Trim whitespace (returns new ptr)
  def gen_str_trim(node)
    return unless @target_os == :linux

    eval_expression(node[:args][0])
    @emitter.emit([0x48, 0x89, 0xc7])  # mov rdi, rax

    # Skip leading whitespace
    @emitter.emit([0x8a, 0x07])  # mov al, [rdi]
    @emitter.emit([0x3c, 0x20])  # cmp al, ' '
    @emitter.emit([0x74, 0x06])  # je skip
    @emitter.emit([0x3c, 0x09])  # cmp al, '\t'
    @emitter.emit([0x74, 0x02])  # je skip
    @emitter.emit([0xeb, 0x04])  # jmp found_start
    @emitter.emit([0x48, 0xff, 0xc7])  # inc rdi
    @emitter.emit([0xeb, 0xef])  # jmp loop

    # Return pointer to first non-space
    @emitter.emit([0x48, 0x89, 0xf8])  # mov rax, rdi
  end
end
