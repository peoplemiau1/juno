module GeneratorIO
  def output_string(str)
    if @target_os == :windows
      output_string_windows(str)
    else
      output_string_linux(str)
    end
  end

  def output_rax_as_int
    if @target_os == :windows
      output_rax_as_int_windows
    else
      output_rax_as_int_linux
    end
  end

  private

  def output_string_linux(str)
    str_id = "str_#{@data_pool.length}"
    @data_pool << { id: str_id, data: str, type: :string }

    # Linux sys_write(fd: RDI, buf: RSI, count: RDX)
    @code_bytes += [0x48, 0xc7, 0xc0, 1, 0, 0, 0] # mov rax, 1 (sys_write)
    @code_bytes += [0x48, 0xc7, 0xc7, 1, 0, 0, 0] # mov rdi, 1 (stdout)
    
    @data_patches << { pos: @code_bytes.length + 3, id: str_id }
    @code_bytes += [0x48, 0x8d, 0x35, 0, 0, 0, 0] # lea rsi, [rip + str]
    
    @code_bytes += [0x48, 0xc7, 0xc2] + [str.length].pack("l<").bytes # mov rdx, len
    @code_bytes += [0x0f, 0x05] # syscall
  end

  def output_rax_as_int_linux
    # Сохраняем регистры
    @code_bytes += [0x50, 0x53, 0x56, 0x52, 0x51] # push rax, rbx, rsi, rdx, rcx

    # Подготовка буфера (аналогично windows, но вывод через syscall)
    @data_patches << { pos: @code_bytes.length + 3, id: "int_buffer" }
    @code_bytes += [0x48, 0x8d, 0x1d, 0, 0, 0, 0] # lea rbx, [rip + buffer]
    @code_bytes += [0x48, 0x83, 0xc3, 62] # rbx = end of buffer
    @code_bytes += [0xc6, 0x03, 10] # \n
    
    @code_bytes += [0x48, 0x89, 0xde] # rsi = cur (rbx)
    @code_bytes += [0x49, 0xc7, 0xc0, 1, 0, 0, 0] # r8 = len
    @code_bytes += [0x48, 0xb9, 10, 0,0,0,0,0,0,0] # rcx = 10
    
    l_start = @code_bytes.length
    @code_bytes += [0x48, 0x31, 0xd2, 0x48, 0xf7, 0xf1] # xor rdx, rdx; div rcx
    @code_bytes += [0x80, 0xc2, 0x30, 0x48, 0xff, 0xce, 0x88, 0x16, 0x49, 0xff, 0xc0] # add dl, '0'; dec rsi; mov [rsi], dl; inc r8
    @code_bytes += [0x48, 0x85, 0xc0] # test rax, rax
    jump_off = l_start - (@code_bytes.length + 2)
    @code_bytes += [0x75, jump_off & 0xFF]

    # syscall sys_write(1, rsi, r8)
    @code_bytes += [0x48, 0xc7, 0xc0, 1, 0, 0, 0] # mov rax, 1
    @code_bytes += [0x48, 0xc7, 0xc7, 1, 0, 0, 0] # mov rdi, 1
    @code_bytes += [0x4c, 0x89, 0xc2] # mov rdx, r8 (len)
    @code_bytes += [0x0f, 0x05] # syscall

    @code_bytes += [0x59, 0x5a, 0x5e, 0x5b, 0x58] # pop registers
  end

  def output_string_windows(str)
    str_id = "str_#{@data_pool.length}"
    @data_pool << { id: str_id, data: str, type: :string }
    @code_bytes += [0x48, 0x83, 0xec, 0x20] 
    @code_bytes += X64.mov_rcx_imm64(0xFFFFFFFFFFFFFFF5)
    @code_bytes += X64.call_rip_rel32(CompilerBase::IAT[:get_std_handle] - (0x1000 + @code_bytes.length + 6))
    @code_bytes += [0x48, 0x83, 0xc4, 0x20]
    @code_bytes += [0x48, 0x89, 0xc7] # RDI = Handle
    @code_bytes += [0x48, 0x83, 0xec, 0x30] 
    @code_bytes += [0x48, 0x89, 0xf9]
    @data_patches << { pos: @code_bytes.length + 3, id: str_id }
    @code_bytes += [0x48, 0x8d, 0x15, 0, 0, 0, 0]
    @code_bytes += X64.mov_r8_imm64(str.length)
    @code_bytes += [0x4c, 0x8d, 0x4d, 0xd0]
    @code_bytes += [0x48, 0xc7, 0x44, 0x24, 0x20, 0,0,0,0] 
    @code_bytes += X64.call_rip_rel32(CompilerBase::IAT[:write_file] - (0x1000 + @code_bytes.length + 6))
    @code_bytes += [0x48, 0x83, 0xc4, 0x30]
  end

  def output_rax_as_int_windows
    @code_bytes += [0x48, 0x89, 0x45, 0xd8] # spill rax
    @code_bytes += [0x48, 0x83, 0xec, 0x20]
    @code_bytes += X64.mov_rcx_imm64(0xFFFFFFFFFFFFFFF5)
    @code_bytes += X64.call_rip_rel32(CompilerBase::IAT[:get_std_handle] - (0x1000 + @code_bytes.length + 6))
    @code_bytes += [0x48, 0x83, 0xc4, 0x20]
    @code_bytes += [0x48, 0x89, 0xc7] 
    @code_bytes += [0x48, 0x8b, 0x45, 0xd8]
    @code_bytes += [0x48, 0x89, 0x5d, 0xe0]
    @code_bytes += [0x48, 0x89, 0x75, 0xe8]
    @data_patches << { pos: @code_bytes.length + 3, id: "int_buffer" }
    @code_bytes += [0x48, 0x8d, 0x1d, 0, 0, 0, 0]
    @code_bytes += [0x48, 0x83, 0xc3, 62]
    @code_bytes += [0xc6, 0x03, 10]    
    @code_bytes += [0x48, 0x89, 0xde]
    @code_bytes += [0x49, 0xc7, 0xc0, 1, 0, 0, 0]
    @code_bytes += [0x48, 0xb9, 10, 0,0,0,0,0,0,0]
    l_start = @code_bytes.length
    @code_bytes += [0x48, 0x31, 0xd2, 0x48, 0xf7, 0xf1] 
    @code_bytes += [0x80, 0xc2, 0x30, 0x48, 0xff, 0xce, 0x88, 0x16, 0x49, 0xff, 0xc0] 
    @code_bytes += [0x48, 0x85, 0xc0]     
    jump_off = l_start - (@code_bytes.length + 2)
    @code_bytes += [0x75, jump_off & 0xFF]
    @code_bytes += [0x48, 0x83, 0xec, 0x30] 
    @code_bytes += [0x48, 0x89, 0xf9, 0x48, 0x89, 0xf2] 
    @code_bytes += [0x4c, 0x8d, 0x4d, 0xd0]
    @code_bytes += [0x48, 0xc7, 0x44, 0x24, 0x20, 0,0,0,0] 
    @code_bytes += X64.call_rip_rel32(CompilerBase::IAT[:write_file] - (0x1000 + @code_bytes.length + 6))
    @code_bytes += [0x48, 0x83, 0xc4, 0x30] 
    @code_bytes += [0x48, 0x8b, 0x5d, 0xe0, 0x48, 0x8b, 0x75, 0xe8]
  end
end
