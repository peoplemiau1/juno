# File API - high-level file operations
# file_open, file_close, file_read, file_write, file_read_all

module BuiltinFileAPI
  def setup_file_api
    return if @file_api_setup
    @file_api_setup = true
    
    @linker.add_data("file_read_buf", "\x00" * 65536)  # 64KB buffer
  end

  # file_open(path, mode) - Open file
  # mode: 0 = read, 1 = write, 2 = append
  # Returns fd or -1 on error
  def gen_file_open(node)
    return unless @target_os == :linux
    
    eval_expression(node[:args][0])
    @emitter.emit([0x49, 0x89, 0xc4])  # mov r12, rax (path)
    
    eval_expression(node[:args][1])
    @emitter.emit([0x49, 0x89, 0xc5])  # mov r13, rax (mode)
    
    # Convert mode to flags
    # 0 (read) -> O_RDONLY (0)
    # 1 (write) -> O_WRONLY|O_CREAT|O_TRUNC (0x241)
    # 2 (append) -> O_WRONLY|O_CREAT|O_APPEND (0x441)
    
    @emitter.emit([0x4d, 0x85, 0xed])  # test r13, r13
    @emitter.emit([0x75, 0x07])  # jnz not_read
    @emitter.emit([0xbe, 0x00, 0x00, 0x00, 0x00])  # mov esi, 0 (O_RDONLY)
    @emitter.emit([0xeb, 0x14])  # jmp do_open
    
    # not_read
    @emitter.emit([0x49, 0x83, 0xfd, 0x01])  # cmp r13, 1
    @emitter.emit([0x75, 0x07])  # jnz not_write
    @emitter.emit([0xbe, 0x41, 0x02, 0x00, 0x00])  # mov esi, 0x241 (write+create+trunc)
    @emitter.emit([0xeb, 0x05])  # jmp do_open
    
    # append
    @emitter.emit([0xbe, 0x41, 0x04, 0x00, 0x00])  # mov esi, 0x441 (write+create+append)
    
    # do_open: syscall open(path, flags, mode)
    @emitter.emit([0x4c, 0x89, 0xe7])  # mov rdi, r12 (path)
    @emitter.emit([0xba, 0xb6, 0x01, 0x00, 0x00])  # mov edx, 0o666
    @emitter.emit([0xb8, 0x02, 0x00, 0x00, 0x00])  # mov eax, 2 (open)
    @emitter.emit([0x0f, 0x05])  # syscall
  end

  # file_close(fd) - Close file
  def gen_file_close(node)
    return unless @target_os == :linux
    
    eval_expression(node[:args][0])
    @emitter.emit([0x48, 0x89, 0xc7])  # mov rdi, rax (fd)
    @emitter.emit([0xb8, 0x03, 0x00, 0x00, 0x00])  # mov eax, 3 (close)
    @emitter.emit([0x0f, 0x05])  # syscall
  end

  # file_read(fd, buf, size) - Read from file
  def gen_file_read(node)
    return unless @target_os == :linux
    
    eval_expression(node[:args][0])
    @emitter.emit([0x49, 0x89, 0xc4])  # mov r12, rax (fd)
    
    eval_expression(node[:args][1])
    @emitter.emit([0x49, 0x89, 0xc5])  # mov r13, rax (buf)
    
    eval_expression(node[:args][2])
    @emitter.emit([0x48, 0x89, 0xc2])  # mov rdx, rax (size)
    
    @emitter.emit([0x4c, 0x89, 0xe7])  # mov rdi, r12 (fd)
    @emitter.emit([0x4c, 0x89, 0xee])  # mov rsi, r13 (buf)
    @emitter.emit([0xb8, 0x00, 0x00, 0x00, 0x00])  # mov eax, 0 (read)
    @emitter.emit([0x0f, 0x05])  # syscall
  end

  # file_write(fd, buf, size) - Write to file
  def gen_file_write(node)
    return unless @target_os == :linux
    
    eval_expression(node[:args][0])
    @emitter.emit([0x49, 0x89, 0xc4])  # mov r12, rax (fd)
    
    eval_expression(node[:args][1])
    @emitter.emit([0x49, 0x89, 0xc5])  # mov r13, rax (buf)
    
    eval_expression(node[:args][2])
    @emitter.emit([0x48, 0x89, 0xc2])  # mov rdx, rax (size)
    
    @emitter.emit([0x4c, 0x89, 0xe7])  # mov rdi, r12 (fd)
    @emitter.emit([0x4c, 0x89, 0xee])  # mov rsi, r13 (buf)
    @emitter.emit([0xb8, 0x01, 0x00, 0x00, 0x00])  # mov eax, 1 (write)
    @emitter.emit([0x0f, 0x05])  # syscall
  end

  # file_writeln(fd, str) - Write string + newline
  def gen_file_writeln(node)
    return unless @target_os == :linux
    
    eval_expression(node[:args][0])
    @emitter.emit([0x49, 0x89, 0xc4])  # mov r12, rax (fd)
    
    eval_expression(node[:args][1])
    @emitter.emit([0x49, 0x89, 0xc5])  # mov r13, rax (str)
    
    # Get string length
    @emitter.emit([0x4c, 0x89, 0xef])  # mov rdi, r13
    @emitter.emit([0x48, 0x31, 0xc0])  # xor rax, rax
    @emitter.emit([0x80, 0x3c, 0x07, 0x00])  # cmp byte [rdi+rax], 0
    @emitter.emit([0x74, 0x04])  # je len_done
    @emitter.emit([0x48, 0xff, 0xc0])  # inc rax
    @emitter.emit([0xeb, 0xf5])  # jmp loop
    
    @emitter.emit([0x48, 0x89, 0xc2])  # mov rdx, rax (len)
    @emitter.emit([0x4c, 0x89, 0xe7])  # mov rdi, r12 (fd)
    @emitter.emit([0x4c, 0x89, 0xee])  # mov rsi, r13 (buf)
    @emitter.emit([0xb8, 0x01, 0x00, 0x00, 0x00])  # mov eax, 1
    @emitter.emit([0x0f, 0x05])  # syscall
    
    # Write newline
    @linker.add_data("newline_char", "\n")
    @emitter.emit([0x4c, 0x89, 0xe7])  # mov rdi, r12 (fd)
    @linker.add_data_patch(@emitter.current_pos + 2, "newline_char")
    @emitter.emit([0x48, 0xbe] + [0] * 8)  # mov rsi, newline_char
    @emitter.emit([0xba, 0x01, 0x00, 0x00, 0x00])  # mov edx, 1
    @emitter.emit([0xb8, 0x01, 0x00, 0x00, 0x00])  # mov eax, 1
    @emitter.emit([0x0f, 0x05])  # syscall
  end

  # file_read_all(path) - Read entire file into buffer
  # Returns pointer to buffer (null-terminated)
  def gen_file_read_all(node)
    return unless @target_os == :linux
    setup_file_api
    
    eval_expression(node[:args][0])
    @emitter.emit([0x49, 0x89, 0xc4])  # mov r12, rax (path)
    
    # Open file
    @emitter.emit([0x4c, 0x89, 0xe7])  # mov rdi, r12
    @emitter.emit([0xbe, 0x00, 0x00, 0x00, 0x00])  # mov esi, O_RDONLY
    @emitter.emit([0xba, 0x00, 0x00, 0x00, 0x00])  # mov edx, 0
    @emitter.emit([0xb8, 0x02, 0x00, 0x00, 0x00])  # mov eax, 2
    @emitter.emit([0x0f, 0x05])  # syscall
    
    @emitter.emit([0x49, 0x89, 0xc5])  # mov r13, rax (fd)
    
    # Check for error
    @emitter.emit([0x48, 0x85, 0xc0])  # test rax, rax
    @emitter.emit([0x79, 0x05])  # jns ok
    @emitter.emit([0x48, 0x31, 0xc0])  # xor rax, rax (return 0)
    @emitter.emit([0xeb, 0x30])  # jmp end
    
    # Read into buffer
    @emitter.emit([0x4c, 0x89, 0xef])  # mov rdi, r13 (fd)
    @linker.add_data_patch(@emitter.current_pos + 2, "file_read_buf")
    @emitter.emit([0x48, 0xbe] + [0] * 8)  # mov rsi, buffer
    @emitter.emit([0x49, 0x89, 0xf6])  # mov r14, rsi (save buf)
    @emitter.emit([0xba, 0xff, 0xff, 0x00, 0x00])  # mov edx, 65535
    @emitter.emit([0xb8, 0x00, 0x00, 0x00, 0x00])  # mov eax, 0 (read)
    @emitter.emit([0x0f, 0x05])  # syscall
    
    @emitter.emit([0x49, 0x89, 0xc7])  # mov r15, rax (bytes read)
    
    # Null terminate
    @emitter.emit([0x4c, 0x89, 0xf7])  # mov rdi, r14 (buf)
    @emitter.emit([0x4c, 0x01, 0xff])  # add rdi, r15
    @emitter.emit([0xc6, 0x07, 0x00])  # mov byte [rdi], 0
    
    # Close file
    @emitter.emit([0x4c, 0x89, 0xef])  # mov rdi, r13
    @emitter.emit([0xb8, 0x03, 0x00, 0x00, 0x00])  # mov eax, 3
    @emitter.emit([0x0f, 0x05])  # syscall
    
    # Return buffer pointer
    @emitter.emit([0x4c, 0x89, 0xf0])  # mov rax, r14
    # end
  end

  # file_exists(path) - Check if file exists
  # Returns 1 if exists, 0 if not
  def gen_file_exists(node)
    return unless @target_os == :linux
    
    eval_expression(node[:args][0])
    @emitter.emit([0x48, 0x89, 0xc7])  # mov rdi, rax (path)
    
    # access(path, F_OK) - syscall 21
    @emitter.emit([0xbe, 0x00, 0x00, 0x00, 0x00])  # mov esi, 0 (F_OK)
    @emitter.emit([0xb8, 0x15, 0x00, 0x00, 0x00])  # mov eax, 21 (access)
    @emitter.emit([0x0f, 0x05])  # syscall
    
    # Convert -1 to 0, 0 to 1
    @emitter.emit([0x48, 0x85, 0xc0])  # test rax, rax
    @emitter.emit([0x0f, 0x94, 0xc0])  # sete al
    @emitter.emit([0x48, 0x0f, 0xb6, 0xc0])  # movzx rax, al
  end

  # file_size(path) - Get file size
  def gen_file_size(node)
    return unless @target_os == :linux
    
    eval_expression(node[:args][0])
    @emitter.emit([0x48, 0x89, 0xc7])  # mov rdi, rax (path)
    
    # stat(path, statbuf) - need to allocate stat buffer on stack
    @emitter.emit([0x48, 0x83, 0xec, 0x90])  # sub rsp, 144 (sizeof struct stat)
    @emitter.emit([0x48, 0x89, 0xe6])  # mov rsi, rsp (statbuf)
    @emitter.emit([0xb8, 0x04, 0x00, 0x00, 0x00])  # mov eax, 4 (stat)
    @emitter.emit([0x0f, 0x05])  # syscall
    
    # Check error
    @emitter.emit([0x48, 0x85, 0xc0])  # test rax, rax
    @emitter.emit([0x79, 0x07])  # jns ok
    @emitter.emit([0x48, 0x31, 0xc0])  # xor rax, rax
    @emitter.emit([0x48, 0x83, 0xc4, 0x90])  # add rsp, 144
    @emitter.emit([0xeb, 0x06])  # jmp end
    
    # Get st_size (offset 48 in struct stat)
    @emitter.emit([0x48, 0x8b, 0x44, 0x24, 0x30])  # mov rax, [rsp+48]
    @emitter.emit([0x48, 0x83, 0xc4, 0x90])  # add rsp, 144
    # end
  end
end
