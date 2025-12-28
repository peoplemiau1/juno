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
    
    eval_expression(node[:args][0])
    @emitter.emit([0x49, 0x89, 0xc4])  # mov r12, rax (dst)
    
    eval_expression(node[:args][1])
    @emitter.emit([0x48, 0x89, 0xc6])  # mov rsi, rax (src)
    @emitter.emit([0x4c, 0x89, 0xe7])  # mov rdi, r12 (dst)
    
    # Copy loop
    @emitter.emit([0x8a, 0x06])  # mov al, [rsi]
    @emitter.emit([0x88, 0x07])  # mov [rdi], al
    @emitter.emit([0x84, 0xc0])  # test al, al
    @emitter.emit([0x74, 0x06])  # je done
    @emitter.emit([0x48, 0xff, 0xc6])  # inc rsi
    @emitter.emit([0x48, 0xff, 0xc7])  # inc rdi
    @emitter.emit([0xeb, 0xf2])  # jmp loop
    
    @emitter.emit([0x4c, 0x89, 0xe0])  # mov rax, r12 (return dst)
  end

  # str_cat(dst, src) - Concatenate src to end of dst
  def gen_str_cat(node)
    return unless @target_os == :linux
    
    eval_expression(node[:args][0])
    @emitter.emit([0x49, 0x89, 0xc4])  # mov r12, rax (dst)
    
    eval_expression(node[:args][1])
    @emitter.emit([0x49, 0x89, 0xc5])  # mov r13, rax (src)
    
    # Find end of dst
    @emitter.emit([0x4c, 0x89, 0xe7])  # mov rdi, r12
    @emitter.emit([0x80, 0x3f, 0x00])  # cmp byte [rdi], 0
    @emitter.emit([0x74, 0x04])  # je found_end
    @emitter.emit([0x48, 0xff, 0xc7])  # inc rdi
    @emitter.emit([0xeb, 0xf6])  # jmp find_loop
    
    # Copy src to end
    @emitter.emit([0x4c, 0x89, 0xee])  # mov rsi, r13 (src)
    @emitter.emit([0x8a, 0x06])  # mov al, [rsi]
    @emitter.emit([0x88, 0x07])  # mov [rdi], al
    @emitter.emit([0x84, 0xc0])  # test al, al
    @emitter.emit([0x74, 0x06])  # je done
    @emitter.emit([0x48, 0xff, 0xc6])  # inc rsi
    @emitter.emit([0x48, 0xff, 0xc7])  # inc rdi
    @emitter.emit([0xeb, 0xf2])  # jmp copy_loop
    
    @emitter.emit([0x4c, 0x89, 0xe0])  # mov rax, r12 (return dst)
  end

  # str_cmp(s1, s2) - Compare strings, returns 0 if equal
  def gen_str_cmp(node)
    return unless @target_os == :linux
    
    eval_expression(node[:args][0])
    @emitter.emit([0x49, 0x89, 0xc4])  # mov r12, rax (s1)
    
    eval_expression(node[:args][1])
    @emitter.emit([0x48, 0x89, 0xc6])  # mov rsi, rax (s2)
    @emitter.emit([0x4c, 0x89, 0xe7])  # mov rdi, r12 (s1)
    
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

  # str_find(haystack, needle) - Find substring, returns index or -1
  def gen_str_find(node)
    return unless @target_os == :linux
    setup_strings_v2
    
    eval_expression(node[:args][0])
    @emitter.emit([0x49, 0x89, 0xc4])  # mov r12, rax (haystack)
    
    eval_expression(node[:args][1])
    @emitter.emit([0x49, 0x89, 0xc5])  # mov r13, rax (needle)
    
    @emitter.emit([0x4d, 0x31, 0xf6])  # xor r14, r14 (index)
    
    # Outer loop - for each position in haystack
    # Check if needle matches at this position
    @emitter.emit([0x4c, 0x89, 0xe7])  # mov rdi, r12
    @emitter.emit([0x4c, 0x01, 0xf7])  # add rdi, r14
    @emitter.emit([0x80, 0x3f, 0x00])  # cmp byte [rdi], 0
    @emitter.emit([0x74, 0x28])  # je not_found
    
    @emitter.emit([0x4c, 0x89, 0xee])  # mov rsi, r13 (needle)
    @emitter.emit([0x48, 0x89, 0xfa])  # mov rdx, rdi (save haystack pos)
    
    # Inner loop - compare needle
    @emitter.emit([0x8a, 0x06])  # mov al, [rsi]
    @emitter.emit([0x84, 0xc0])  # test al, al
    @emitter.emit([0x74, 0x14])  # je found (needle exhausted)
    @emitter.emit([0x8a, 0x1f])  # mov bl, [rdi]
    @emitter.emit([0x38, 0xc3])  # cmp bl, al
    @emitter.emit([0x75, 0x0a])  # jne next_pos
    @emitter.emit([0x48, 0xff, 0xc7])  # inc rdi
    @emitter.emit([0x48, 0xff, 0xc6])  # inc rsi
    @emitter.emit([0xeb, 0xec])  # jmp inner_loop
    
    # next_pos:
    @emitter.emit([0x49, 0xff, 0xc6])  # inc r14
    @emitter.emit([0xeb, 0xd4])  # jmp outer_loop
    
    # found:
    @emitter.emit([0x4c, 0x89, 0xf0])  # mov rax, r14
    @emitter.emit([0xeb, 0x05])  # jmp done
    
    # not_found:
    @emitter.emit([0x48, 0xc7, 0xc0, 0xff, 0xff, 0xff, 0xff])  # mov rax, -1
    # done
  end

  # str_to_int(s) - Parse string to integer
  def gen_str_to_int(node)
    return unless @target_os == :linux
    
    eval_expression(node[:args][0])
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
    
    eval_expression(node[:args][0])
    # rax = number
    
    @linker.add_data_patch(@emitter.current_pos + 2, "itoa_buffer")
    @emitter.emit([0x48, 0xbf] + [0] * 8)  # mov rdi, itoa_buffer
    @emitter.emit([0x48, 0x83, 0xc7, 0x1e])  # add rdi, 30 (end of buffer)
    @emitter.emit([0xc6, 0x07, 0x00])  # mov byte [rdi], 0 (null term)
    
    @emitter.emit([0x48, 0x89, 0xc0])  # mov rax, rax
    @emitter.emit([0x49, 0x89, 0xfc])  # mov r12, rdi (save end)
    @emitter.emit([0x4d, 0x31, 0xed])  # xor r13, r13 (negative flag)
    
    # Handle negative
    @emitter.emit([0x48, 0x85, 0xc0])  # test rax, rax
    @emitter.emit([0x79, 0x05])  # jns positive
    @emitter.emit([0x48, 0xf7, 0xd8])  # neg rax
    @emitter.emit([0x49, 0xff, 0xc5])  # inc r13 (set negative flag)
    
    # Handle 0
    @emitter.emit([0x48, 0x85, 0xc0])  # test rax, rax
    @emitter.emit([0x75, 0x0a])  # jnz convert
    @emitter.emit([0x48, 0xff, 0xcf])  # dec rdi
    @emitter.emit([0xc6, 0x07, 0x30])  # mov byte [rdi], '0'
    @emitter.emit([0xeb, 0x19])  # jmp done
    
    # Convert loop
    @emitter.emit([0x48, 0xc7, 0xc1, 0x0a, 0x00, 0x00, 0x00])  # mov rcx, 10
    @emitter.emit([0x48, 0x31, 0xd2])  # xor rdx, rdx
    @emitter.emit([0x48, 0xf7, 0xf1])  # div rcx
    @emitter.emit([0x48, 0x83, 0xc2, 0x30])  # add rdx, '0'
    @emitter.emit([0x48, 0xff, 0xcf])  # dec rdi
    @emitter.emit([0x88, 0x17])  # mov [rdi], dl
    @emitter.emit([0x48, 0x85, 0xc0])  # test rax, rax
    @emitter.emit([0x75, 0xeb])  # jnz loop
    
    # Add minus if negative
    @emitter.emit([0x4d, 0x85, 0xed])  # test r13, r13
    @emitter.emit([0x74, 0x05])  # jz done
    @emitter.emit([0x48, 0xff, 0xcf])  # dec rdi
    @emitter.emit([0xc6, 0x07, 0x2d])  # mov byte [rdi], '-'
    
    # done - rdi points to start of string
    @emitter.emit([0x48, 0x89, 0xf8])  # mov rax, rdi
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
