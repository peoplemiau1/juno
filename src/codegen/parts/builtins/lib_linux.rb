# lib_linux.rb - Convenient Linux system wrappers

module BuiltinLibLinux
  
  def setup_lib_linux_buf
    return if @lib_linux_buf_setup
    @lib_linux_buf_setup = true
    @linker.add_data("lib_linux_buf", "\x00" * 1024)
  end

  # Helper: emit LEA with RIP-relative addressing
  def emit_lea_rdi_data(label)
    @linker.add_data_patch(@emitter.current_pos + 3, label)
    @emitter.emit([0x48, 0x8d, 0x3d, 0x00, 0x00, 0x00, 0x00])
  end

  def emit_lea_rsi_data(label)
    @linker.add_data_patch(@emitter.current_pos + 3, label)
    @emitter.emit([0x48, 0x8d, 0x35, 0x00, 0x00, 0x00, 0x00])
  end

  # Generic file reader into lib_linux_buf
  # path_bytes = array of bytes for path string on stack
  def read_file_to_buf(path_bytes)
    setup_lib_linux_buf
    
    # Save registers
    @emitter.emit([0x53])  # push rbx
    @emitter.emit([0x55])  # push rbp
    @emitter.emit([0x41, 0x54])  # push r12
    
    # Put path on stack
    stack_size = ((path_bytes.length + 15) / 16) * 16
    @emitter.emit([0x48, 0x81, 0xec] + [stack_size].pack("V").bytes)  # sub rsp, size
    
    # Copy path to stack
    path_bytes.each_slice(8).with_index do |chunk, i|
      chunk = chunk + [0] * (8 - chunk.length)  # pad
      val = chunk.pack("C*").unpack1("Q<")
      @emitter.emit([0x48, 0xb8] + [val].pack("Q<").bytes)  # mov rax, val
      @emitter.emit([0x48, 0x89, 0x44, 0x24, i * 8])  # mov [rsp+i*8], rax
    end
    
    # Open
    @emitter.emit([0x48, 0x89, 0xe7])  # mov rdi, rsp
    @emitter.emit([0x31, 0xf6])
    @emitter.emit([0xb8, 0x02, 0x00, 0x00, 0x00])
    @emitter.emit([0x0f, 0x05])
    @emitter.emit([0x48, 0x89, 0xc3])  # rbx = fd
    
    # Read
    @emitter.emit([0x48, 0x89, 0xc7])
    emit_lea_rsi_data("lib_linux_buf")
    @emitter.emit([0x48, 0x89, 0xf5])  # rbp = buf
    @emitter.emit([0xba, 0x00, 0x03, 0x00, 0x00])
    @emitter.emit([0xb8, 0x00, 0x00, 0x00, 0x00])
    @emitter.emit([0x0f, 0x05])
    @emitter.emit([0x49, 0x89, 0xc4])  # r12 = len
    
    # Close
    @emitter.emit([0x48, 0x89, 0xdf])
    @emitter.emit([0xb8, 0x03, 0x00, 0x00, 0x00])
    @emitter.emit([0x0f, 0x05])
    
    # Null terminate
    @emitter.emit([0x49, 0x83, 0xfc, 0x01])
    @emitter.emit([0x7c, 0x09])
    @emitter.emit([0x4a, 0x8d, 0x44, 0x25, 0xff])
    @emitter.emit([0xc6, 0x00, 0x00])
    
    # Return buf
    @emitter.emit([0x48, 0x89, 0xe8])
    @emitter.emit([0x48, 0x81, 0xc4] + [stack_size].pack("V").bytes)
    
    # Restore
    @emitter.emit([0x41, 0x5c])
    @emitter.emit([0x5d])
    @emitter.emit([0x5b])
  end

  # hostname()
  def gen_hostname(node)
    return unless @target_os == :linux
    read_file_to_buf("/etc/hostname\0".bytes)
  end

  # kernel_version()
  def gen_kernel_version(node)
    return unless @target_os == :linux
    read_file_to_buf("/proc/sys/kernel/osrelease\0".bytes)
  end

  # loadavg()
  def gen_loadavg(node)
    return unless @target_os == :linux
    read_file_to_buf("/proc/loadavg\0".bytes)
  end

  # uptime() - returns seconds
  def gen_uptime(node)
    return unless @target_os == :linux
    read_file_to_buf("/proc/uptime\0".bytes)
    
    # Parse int from string (rax = buf ptr)
    @emitter.emit([0x48, 0x89, 0xc6])  # mov rsi, rax
    @emitter.emit([0x48, 0x31, 0xc0])  # xor rax, rax (result)
    @emitter.emit([0x31, 0xc9])  # xor ecx, ecx
    # Loop
    parse_loop = @emitter.current_pos
    @emitter.emit([0x0f, 0xb6, 0x0e])  # movzx ecx, byte [rsi]
    @emitter.emit([0x83, 0xf9, 0x30])  # cmp ecx, '0'
    done_jmp1 = @emitter.current_pos
    @emitter.emit([0x72, 0x00])  # jb done
    @emitter.emit([0x83, 0xf9, 0x39])  # cmp ecx, '9'
    done_jmp2 = @emitter.current_pos
    @emitter.emit([0x77, 0x00])  # ja done
    @emitter.emit([0x83, 0xe9, 0x30])  # sub ecx, '0'
    @emitter.emit([0x48, 0x6b, 0xc0, 0x0a])  # imul rax, 10
    @emitter.emit([0x48, 0x01, 0xc8])  # add rax, rcx
    @emitter.emit([0x48, 0xff, 0xc6])  # inc rsi
    loop_back = parse_loop - (@emitter.current_pos + 2)
    @emitter.emit([0xeb, loop_back & 0xff])  # jmp parse_loop
    # done:
    done_pos = @emitter.current_pos
    @emitter.bytes[done_jmp1 + 1] = done_pos - done_jmp1 - 2
    @emitter.bytes[done_jmp2 + 1] = done_pos - done_jmp2 - 2
  end

  # num_cpus()
  def gen_num_cpus(node)
    return unless @target_os == :linux
    read_file_to_buf("/sys/devices/system/cpu/online\0".bytes)
    
    # Parse "0-N", return N+1
    @emitter.emit([0x48, 0x89, 0xc6])  # mov rsi, rax
    # Find '-'
    find_loop = @emitter.current_pos
    @emitter.emit([0x80, 0x3e, 0x2d])  # cmp byte [rsi], '-'
    found_jmp = @emitter.current_pos
    @emitter.emit([0x74, 0x00])  # je found
    @emitter.emit([0x48, 0xff, 0xc6])  # inc rsi
    back = find_loop - (@emitter.current_pos + 2)
    @emitter.emit([0xeb, back & 0xff])
    # found:
    found_pos = @emitter.current_pos
    @emitter.bytes[found_jmp + 1] = found_pos - found_jmp - 2
    @emitter.emit([0x48, 0xff, 0xc6])  # inc rsi (skip '-')
    @emitter.emit([0x48, 0x31, 0xc0])  # xor rax, rax
    @emitter.emit([0x31, 0xc9])  # xor ecx, ecx
    # Parse loop
    parse_loop = @emitter.current_pos
    @emitter.emit([0x0f, 0xb6, 0x0e])
    @emitter.emit([0x83, 0xf9, 0x30])
    done_jmp1 = @emitter.current_pos
    @emitter.emit([0x72, 0x00])
    @emitter.emit([0x83, 0xf9, 0x39])
    done_jmp2 = @emitter.current_pos
    @emitter.emit([0x77, 0x00])
    @emitter.emit([0x83, 0xe9, 0x30])
    @emitter.emit([0x48, 0x6b, 0xc0, 0x0a])
    @emitter.emit([0x48, 0x01, 0xc8])
    @emitter.emit([0x48, 0xff, 0xc6])
    back = parse_loop - (@emitter.current_pos + 2)
    @emitter.emit([0xeb, back & 0xff])
    # done:
    done_pos = @emitter.current_pos
    @emitter.bytes[done_jmp1 + 1] = done_pos - done_jmp1 - 2
    @emitter.bytes[done_jmp2 + 1] = done_pos - done_jmp2 - 2
    @emitter.emit([0x48, 0xff, 0xc0])  # inc rax (0-indexed)
  end

  # exec_cmd(cmd) - Execute command, return output
  def gen_exec_cmd(node)
    return unless @target_os == :linux
    setup_lib_linux_buf
    
    @emitter.emit([0x53])
    @emitter.emit([0x55])
    @emitter.emit([0x41, 0x54])
    @emitter.emit([0x41, 0x55])
    
    eval_expression(node[:args][0])
    @emitter.emit([0x49, 0x89, 0xc4])
    
    # pipe
    @emitter.emit([0x48, 0x83, 0xec, 0x10])
    @emitter.emit([0x48, 0x89, 0xe7])
    @emitter.emit([0xb8, 0x16, 0x00, 0x00, 0x00])
    @emitter.emit([0x0f, 0x05])
    
    # fork
    @emitter.emit([0xb8, 0x39, 0x00, 0x00, 0x00])
    @emitter.emit([0x0f, 0x05])
    @emitter.emit([0x49, 0x89, 0xc5])
    
    @emitter.emit([0x48, 0x85, 0xc0])
    child_jmp = @emitter.current_pos
    @emitter.emit([0x0f, 0x84, 0x00, 0x00, 0x00, 0x00])
    
    # PARENT
    @emitter.emit([0x8b, 0x7c, 0x24, 0x04])
    @emitter.emit([0xb8, 0x03, 0x00, 0x00, 0x00])
    @emitter.emit([0x0f, 0x05])
    
    @emitter.emit([0x8b, 0x3c, 0x24])
    emit_lea_rsi_data("lib_linux_buf")
    @emitter.emit([0x48, 0x89, 0xf5])
    @emitter.emit([0xba, 0xff, 0x03, 0x00, 0x00])
    @emitter.emit([0xb8, 0x00, 0x00, 0x00, 0x00])
    @emitter.emit([0x0f, 0x05])
    @emitter.emit([0x48, 0x89, 0xc3])
    
    @emitter.emit([0xc6, 0x44, 0x1d, 0x00, 0x00])
    
    @emitter.emit([0x8b, 0x3c, 0x24])
    @emitter.emit([0xb8, 0x03, 0x00, 0x00, 0x00])
    @emitter.emit([0x0f, 0x05])
    
    # wait
    @emitter.emit([0x48, 0xc7, 0xc7, 0xff, 0xff, 0xff, 0xff])
    @emitter.emit([0x48, 0x31, 0xf6])
    @emitter.emit([0x31, 0xd2])
    @emitter.emit([0x4d, 0x31, 0xc0])
    @emitter.emit([0xb8, 0x3d, 0x00, 0x00, 0x00])
    @emitter.emit([0x0f, 0x05])
    
    @emitter.emit([0x48, 0x89, 0xe8])
    @emitter.emit([0x48, 0x83, 0xc4, 0x10])
    parent_end = @emitter.current_pos
    @emitter.emit([0xe9, 0x00, 0x00, 0x00, 0x00])
    
    # CHILD
    child_pos = @emitter.current_pos
    @emitter.bytes[child_jmp + 2, 4] = [child_pos - child_jmp - 6].pack("l<").bytes
    
    @emitter.emit([0x8b, 0x3c, 0x24])
    @emitter.emit([0xb8, 0x03, 0x00, 0x00, 0x00])
    @emitter.emit([0x0f, 0x05])
    
    @emitter.emit([0x8b, 0x7c, 0x24, 0x04])
    @emitter.emit([0xbe, 0x01, 0x00, 0x00, 0x00])
    @emitter.emit([0xb8, 0x21, 0x00, 0x00, 0x00])
    @emitter.emit([0x0f, 0x05])
    
    @emitter.emit([0x8b, 0x7c, 0x24, 0x04])
    @emitter.emit([0xbe, 0x02, 0x00, 0x00, 0x00])
    @emitter.emit([0xb8, 0x21, 0x00, 0x00, 0x00])
    @emitter.emit([0x0f, 0x05])
    
    @emitter.emit([0x8b, 0x7c, 0x24, 0x04])
    @emitter.emit([0xb8, 0x03, 0x00, 0x00, 0x00])
    @emitter.emit([0x0f, 0x05])
    
    # execve
    @emitter.emit([0x48, 0x83, 0xec, 0x30])
    @emitter.emit([0x48, 0xb8, 0x2f, 0x62, 0x69, 0x6e, 0x2f, 0x73, 0x68, 0x00])
    @emitter.emit([0x48, 0x89, 0x44, 0x24, 0x20])
    @emitter.emit([0xc7, 0x44, 0x24, 0x28, 0x2d, 0x63, 0x00, 0x00])
    @emitter.emit([0x48, 0x8d, 0x44, 0x24, 0x20])
    @emitter.emit([0x48, 0x89, 0x04, 0x24])
    @emitter.emit([0x48, 0x8d, 0x44, 0x24, 0x28])
    @emitter.emit([0x48, 0x89, 0x44, 0x24, 0x08])
    @emitter.emit([0x4c, 0x89, 0x64, 0x24, 0x10])
    @emitter.emit([0x48, 0xc7, 0x44, 0x24, 0x18, 0x00, 0x00, 0x00, 0x00])
    @emitter.emit([0x48, 0x8d, 0x7c, 0x24, 0x20])
    @emitter.emit([0x48, 0x89, 0xe6])
    @emitter.emit([0x48, 0x31, 0xd2])
    @emitter.emit([0xb8, 0x3b, 0x00, 0x00, 0x00])
    @emitter.emit([0x0f, 0x05])
    
    @emitter.emit([0xbf, 0x01, 0x00, 0x00, 0x00])
    @emitter.emit([0xb8, 0x3c, 0x00, 0x00, 0x00])
    @emitter.emit([0x0f, 0x05])
    
    # END
    end_pos = @emitter.current_pos
    @emitter.bytes[parent_end + 1, 4] = [end_pos - parent_end - 5].pack("l<").bytes
    
    @emitter.emit([0x41, 0x5d])
    @emitter.emit([0x41, 0x5c])
    @emitter.emit([0x5d])
    @emitter.emit([0x5b])
  end

  # Simple functions
  def gen_is_root(node)
    return unless @target_os == :linux
    @emitter.emit([0xb8, 0x66, 0x00, 0x00, 0x00])
    @emitter.emit([0x0f, 0x05])
    @emitter.emit([0x48, 0x85, 0xc0])
    @emitter.emit([0x0f, 0x94, 0xc0])
    @emitter.emit([0x48, 0x0f, 0xb6, 0xc0])
  end

  def gen_pid(node)
    return unless @target_os == :linux
    @emitter.emit([0xb8, 0x27, 0x00, 0x00, 0x00])
    @emitter.emit([0x0f, 0x05])
  end

  def gen_uid(node)
    return unless @target_os == :linux
    @emitter.emit([0xb8, 0x66, 0x00, 0x00, 0x00])
    @emitter.emit([0x0f, 0x05])
  end

  def gen_cwd(node)
    return unless @target_os == :linux
    setup_lib_linux_buf
    
    @emitter.emit([0x53])
    emit_lea_rdi_data("lib_linux_buf")
    @emitter.emit([0x48, 0x89, 0xfb])
    @emitter.emit([0xbe, 0x00, 0x04, 0x00, 0x00])
    @emitter.emit([0xb8, 0x4f, 0x00, 0x00, 0x00])
    @emitter.emit([0x0f, 0x05])
    @emitter.emit([0x48, 0x89, 0xd8])
    @emitter.emit([0x5b])
  end

  def gen_env_get(node)
    return unless @target_os == :linux
    @linker.add_data("empty_env", "\x00")
    @linker.add_data_patch(@emitter.current_pos + 3, "empty_env")
    @emitter.emit([0x48, 0x8d, 0x05, 0x00, 0x00, 0x00, 0x00])
  end
end
