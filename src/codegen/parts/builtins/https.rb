# HTTPS support via system curl/wget
# Simple wrapper that executes curl and captures output

module BuiltinHTTPS
  def setup_https_data
    return if @https_data_setup
    @https_data_setup = true
    
    @linker.add_data("bin_sh", "/bin/sh\x00")
    @linker.add_data("sh_c", "-c\x00")
    @linker.add_data("https_buf", "\x00" * 8192)
  end

  # curl_get(url) - HTTP GET, returns response in buffer
  # Actually returns pointer to internal buffer with response
  # Usage: let response = curl_get("https://example.com")
  def gen_curl_get(node)
    return unless @target_os == :linux
    setup_https_data
    
    # For simplicity, we'll use popen-style approach:
    # Create pipe, fork, child: exec curl, parent: read pipe
    
    # Save URL
    eval_expression(node[:args][0])
    @emitter.emit([0x49, 0x89, 0xc4])  # mov r12, rax (url)
    
    # pipe(pipefd)
    @emitter.emit([0x48, 0x83, 0xec, 0x10])  # sub rsp, 16
    @emitter.emit([0x48, 0x89, 0xe7])  # mov rdi, rsp
    @emitter.emit([0xb8, 0x16, 0x00, 0x00, 0x00])  # mov eax, 22 (pipe)
    @emitter.emit([0x0f, 0x05])
    
    # Save pipe fds: [rsp] = read_fd, [rsp+4] = write_fd
    
    # fork()
    @emitter.emit([0xb8, 0x39, 0x00, 0x00, 0x00])  # mov eax, 57
    @emitter.emit([0x0f, 0x05])
    
    @emitter.emit([0x48, 0x85, 0xc0])  # test rax, rax
    child_jmp = @emitter.current_pos
    @emitter.emit([0x0f, 0x84, 0x00, 0x00, 0x00, 0x00])  # jz child
    
    # === PARENT ===
    # Close write end
    @emitter.emit([0x8b, 0x7c, 0x24, 0x04])  # mov edi, [rsp+4]
    @emitter.emit([0xb8, 0x03, 0x00, 0x00, 0x00])  # mov eax, 3 (close)
    @emitter.emit([0x0f, 0x05])
    
    # Read from pipe into https_buf
    @emitter.emit([0x8b, 0x3c, 0x24])  # mov edi, [rsp] (read_fd)
    @linker.add_data_patch(@emitter.current_pos + 2, "https_buf")
    @emitter.emit([0x48, 0xbe] + [0] * 8)  # mov rsi, https_buf
    @emitter.emit([0x49, 0x89, 0xf5])  # mov r13, rsi (save buf ptr)
    @emitter.emit([0xba, 0x00, 0x20, 0x00, 0x00])  # mov edx, 8192
    @emitter.emit([0xb8, 0x00, 0x00, 0x00, 0x00])  # mov eax, 0 (read)
    @emitter.emit([0x0f, 0x05])
    @emitter.emit([0x49, 0x89, 0xc6])  # mov r14, rax (bytes read)
    
    # Null terminate
    @emitter.emit([0x4c, 0x89, 0xe8])  # mov rax, r13
    @emitter.emit([0x4c, 0x01, 0xf0])  # add rax, r14
    @emitter.emit([0xc6, 0x00, 0x00])  # mov byte [rax], 0
    
    # Close read end
    @emitter.emit([0x8b, 0x3c, 0x24])  # mov edi, [rsp]
    @emitter.emit([0xb8, 0x03, 0x00, 0x00, 0x00])
    @emitter.emit([0x0f, 0x05])
    
    # Wait for child
    @emitter.emit([0x48, 0xc7, 0xc7, 0xff, 0xff, 0xff, 0xff])  # mov rdi, -1
    @emitter.emit([0x48, 0x8d, 0x74, 0x24, 0x08])  # lea rsi, [rsp+8]
    @emitter.emit([0x31, 0xd2])  # xor edx, edx
    @emitter.emit([0x4d, 0x31, 0xc0])  # xor r8, r8
    @emitter.emit([0xb8, 0x3d, 0x00, 0x00, 0x00])  # wait4
    @emitter.emit([0x0f, 0x05])
    
    # Return buffer pointer
    @emitter.emit([0x4c, 0x89, 0xe8])  # mov rax, r13
    @emitter.emit([0x48, 0x83, 0xc4, 0x10])  # add rsp, 16
    parent_end = @emitter.current_pos
    @emitter.emit([0xe9, 0x00, 0x00, 0x00, 0x00])  # jmp end
    
    # === CHILD ===
    child_addr = @emitter.current_pos
    # Patch jump
    offset = child_addr - child_jmp - 6
    @emitter.bytes[child_jmp + 2, 4] = [offset].pack("l<").bytes
    
    # Close read end
    @emitter.emit([0x8b, 0x3c, 0x24])  # mov edi, [rsp]
    @emitter.emit([0xb8, 0x03, 0x00, 0x00, 0x00])
    @emitter.emit([0x0f, 0x05])
    
    # dup2(write_fd, 1) - redirect stdout to pipe
    @emitter.emit([0x8b, 0x7c, 0x24, 0x04])  # mov edi, [rsp+4]
    @emitter.emit([0xbe, 0x01, 0x00, 0x00, 0x00])  # mov esi, 1
    @emitter.emit([0xb8, 0x21, 0x00, 0x00, 0x00])  # mov eax, 33 (dup2)
    @emitter.emit([0x0f, 0x05])
    
    # Build: /bin/sh -c "curl -s URL"
    # We need to build command string
    # For simplicity: execve /usr/bin/curl with args
    
    @linker.add_data("curl_path", "/usr/bin/curl\x00")
    @linker.add_data("curl_s", "-s\x00")
    @linker.add_data("curl_L", "-L\x00")
    
    # Build argv on stack
    @emitter.emit([0x48, 0x83, 0xec, 0x30])  # sub rsp, 48
    
    @linker.add_data_patch(@emitter.current_pos + 2, "curl_path")
    @emitter.emit([0x48, 0xb8] + [0] * 8)
    @emitter.emit([0x48, 0x89, 0x04, 0x24])  # argv[0] = curl
    
    @linker.add_data_patch(@emitter.current_pos + 2, "curl_s")
    @emitter.emit([0x48, 0xb8] + [0] * 8)
    @emitter.emit([0x48, 0x89, 0x44, 0x24, 0x08])  # argv[1] = -s
    
    @linker.add_data_patch(@emitter.current_pos + 2, "curl_L")
    @emitter.emit([0x48, 0xb8] + [0] * 8)
    @emitter.emit([0x48, 0x89, 0x44, 0x24, 0x10])  # argv[2] = -L
    
    @emitter.emit([0x4c, 0x89, 0x64, 0x24, 0x18])  # argv[3] = r12 (url)
    @emitter.emit([0x48, 0xc7, 0x44, 0x24, 0x20, 0x00, 0x00, 0x00, 0x00])  # argv[4] = NULL
    
    # execve
    @linker.add_data_patch(@emitter.current_pos + 2, "curl_path")
    @emitter.emit([0x48, 0xbf] + [0] * 8)  # rdi = path
    @emitter.emit([0x48, 0x89, 0xe6])  # rsi = argv
    @emitter.emit([0x48, 0x31, 0xd2])  # rdx = NULL
    @emitter.emit([0xb8, 0x3b, 0x00, 0x00, 0x00])  # execve
    @emitter.emit([0x0f, 0x05])
    
    # exit if execve fails
    @emitter.emit([0xb8, 0x3c, 0x00, 0x00, 0x00])
    @emitter.emit([0xbf, 0x01, 0x00, 0x00, 0x00])
    @emitter.emit([0x0f, 0x05])
    
    # Patch parent jmp
    end_addr = @emitter.current_pos
    offset = end_addr - parent_end - 5
    @emitter.bytes[parent_end + 1, 4] = [offset].pack("l<").bytes
  end
end
