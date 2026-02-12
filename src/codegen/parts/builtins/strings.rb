# String built-in functions for Juno
module BuiltinStrings
  # concat(s1, s2) - concatenate two strings
  def gen_concat(node)
    return unless @target_os == :linux
    
    eval_expression(node[:args][0])
    @emitter.emit([0x50]) # push rax (s1)
    
    eval_expression(node[:args][1])
    @emitter.emit([0x48, 0x89, 0xc3]) # mov rbx, rax (s2)
    @emitter.emit([0x5e]) # pop rsi (s1)
    
    @emitter.emit([0x48, 0x8d, 0x3d])
    @linker.add_data_patch(@emitter.current_pos, "concat_buffer")
    @emitter.emit([0x00, 0x00, 0x00, 0x00])
    
    @emitter.emit([0x49, 0x89, 0xf8]) # mov r8, rdi
    
    # Copy s1
    @emitter.emit([0x8a, 0x06, 0x84, 0xc0, 0x74, 0x0a])
    @emitter.emit([0x88, 0x07, 0x48, 0xff, 0xc7, 0x48, 0xff, 0xc6, 0xeb, 0xf0])
    
    # Copy s2
    @emitter.emit([0x8a, 0x03, 0x84, 0xc0, 0x74, 0x0a])
    @emitter.emit([0x88, 0x07, 0x48, 0xff, 0xc7, 0x48, 0xff, 0xc3, 0xeb, 0xf0])
    
    @emitter.emit([0xc6, 0x07, 0x00]) # null terminate
    @emitter.emit([0x4c, 0x89, 0xc0]) # mov rax, r8
  end

  # substr(s, start, len) - extract substring
  def gen_substr(node)
    return unless @target_os == :linux
    
    eval_expression(node[:args][0])
    @emitter.emit([0x50])
    
    eval_expression(node[:args][1])
    @emitter.emit([0x50])
    
    eval_expression(node[:args][2])
    
    @emitter.emit([0x48, 0x89, 0xc1]) # mov rcx, rax
    @emitter.emit([0x5a, 0x5e])       # pop rdx, pop rsi
    @emitter.emit([0x48, 0x01, 0xd6]) # add rsi, rdx
    
    @emitter.emit([0x48, 0x8d, 0x3d])
    @linker.add_data_patch(@emitter.current_pos, "substr_buffer")
    @emitter.emit([0x00, 0x00, 0x00, 0x00])
    
    @emitter.emit([0x49, 0x89, 0xf8]) # mov r8, rdi
    @emitter.emit([0xf3, 0xa4])       # rep movsb
    @emitter.emit([0xc6, 0x07, 0x00]) # null terminate
    @emitter.emit([0x4c, 0x89, 0xc0]) # mov rax, r8
  end

  # chr(n) - number to character
  def gen_chr(node)
    return unless @target_os == :linux
    
    eval_expression(node[:args][0])
    
    @emitter.emit([0x48, 0x8d, 0x3d])
    @linker.add_data_patch(@emitter.current_pos, "chr_buffer")
    @emitter.emit([0x00, 0x00, 0x00, 0x00])
    
    @emitter.emit([0x88, 0x07])             # mov [rdi], al
    @emitter.emit([0xc6, 0x47, 0x01, 0x00]) # mov byte [rdi+1], 0
    @emitter.emit([0x48, 0x89, 0xf8])       # mov rax, rdi
  end

  # ord(s) - character to number
  def gen_ord(node)
    return unless @target_os == :linux
    
    eval_expression(node[:args][0])
    @emitter.emit([0x48, 0x0f, 0xb6, 0x00]) # movzx rax, byte [rax]
  end

  # prints(s) - print string from pointer
  def gen_prints(node)
    return unless @target_os == :linux
    
    eval_expression(node[:args][0])
    
    @emitter.emit([0x48, 0x89, 0xc6]) # mov rsi, rax
    @emitter.emit([0x48, 0x31, 0xc9]) # xor rcx, rcx
    
    # strlen
    @emitter.emit([0x80, 0x3c, 0x0e, 0x00, 0x74, 0x05, 0x48, 0xff, 0xc1, 0xeb, 0xf5])
    
    @emitter.emit([0x48, 0x89, 0xca]) # mov rdx, rcx
    @emitter.emit([0x48, 0xc7, 0xc0, 1, 0, 0, 0])
    @emitter.emit([0x48, 0xc7, 0xc7, 1, 0, 0, 0])
    @emitter.emit([0x0f, 0x05])
    
    # newline
    @emitter.emit([0x48, 0x8d, 0x35])
    @linker.add_data_patch(@emitter.current_pos, "newline_char")
    @emitter.emit([0x00, 0x00, 0x00, 0x00])
    @emitter.emit([0x48, 0xc7, 0xc2, 1, 0, 0, 0])
    @emitter.emit([0x48, 0xc7, 0xc0, 1, 0, 0, 0])
    @emitter.emit([0x48, 0xc7, 0xc7, 1, 0, 0, 0])
    @emitter.emit([0x0f, 0x05])
  end
end
