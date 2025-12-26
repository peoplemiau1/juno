# Network built-in functions for Juno
# Linux x86-64 syscalls for networking

module BuiltinNetwork
  # socket(domain, type, protocol) - create socket
  # domain: AF_INET = 2
  # type: SOCK_STREAM = 1 (TCP), SOCK_DGRAM = 2 (UDP)
  # protocol: 0
  # Returns: file descriptor
  def gen_socket(node)
    return unless @target_os == :linux
    
    # Evaluate domain
    eval_expression(node[:args][0])
    @emitter.emit([0x48, 0x89, 0xc7]) # mov rdi, rax
    
    # Evaluate type
    eval_expression(node[:args][1])
    @emitter.emit([0x48, 0x89, 0xc6]) # mov rsi, rax
    
    # Evaluate protocol
    eval_expression(node[:args][2])
    @emitter.emit([0x48, 0x89, 0xc2]) # mov rdx, rax
    
    # syscall 41 = socket
    @emitter.emit([0xb8, 0x29, 0x00, 0x00, 0x00]) # mov eax, 41
    @emitter.emit([0x0f, 0x05])
  end

  # connect(sockfd, ip, port) - connect to server
  def gen_connect(node)
    return unless @target_os == :linux
    
    # Save sockfd to r12
    eval_expression(node[:args][0])
    @emitter.emit([0x49, 0x89, 0xc4]) # mov r12, rax (sockfd)
    
    # Save IP to r13
    eval_expression(node[:args][1])
    @emitter.emit([0x49, 0x89, 0xc5]) # mov r13, rax (ip)
    
    # Port in rax
    eval_expression(node[:args][2])
    @emitter.emit([0x86, 0xc4]) # xchg al, ah (to network byte order)
    @emitter.emit([0x49, 0x89, 0xc6]) # mov r14, rax (port)
    
    # Build sockaddr_in on stack (16 bytes)
    @emitter.emit([0x48, 0x83, 0xec, 0x10]) # sub rsp, 16
    
    # sin_family = AF_INET (2)
    @emitter.emit([0x66, 0xc7, 0x04, 0x24, 0x02, 0x00]) # mov word [rsp], 2
    
    # sin_port
    @emitter.emit([0x66, 0x44, 0x89, 0x74, 0x24, 0x02]) # mov [rsp+2], r14w
    
    # sin_addr
    @emitter.emit([0x44, 0x89, 0x6c, 0x24, 0x04]) # mov [rsp+4], r13d
    
    # Zero padding
    @emitter.emit([0x48, 0xc7, 0x44, 0x24, 0x08, 0x00, 0x00, 0x00, 0x00]) # mov qword [rsp+8], 0
    
    # rdi = sockfd
    @emitter.emit([0x4c, 0x89, 0xe7]) # mov rdi, r12
    
    # rsi = &sockaddr
    @emitter.emit([0x48, 0x89, 0xe6]) # mov rsi, rsp
    
    # rdx = 16
    @emitter.emit([0xba, 0x10, 0x00, 0x00, 0x00]) # mov edx, 16
    
    # syscall 42 = connect
    @emitter.emit([0xb8, 0x2a, 0x00, 0x00, 0x00]) # mov eax, 42
    @emitter.emit([0x0f, 0x05])
    
    # Clean stack
    @emitter.emit([0x48, 0x83, 0xc4, 0x10]) # add rsp, 16
  end

  # send(sockfd, buf, len) - send data
  def gen_send(node)
    return unless @target_os == :linux
    
    eval_expression(node[:args][0])
    @emitter.emit([0x50]) # push sockfd
    
    eval_expression(node[:args][1])
    @emitter.emit([0x50]) # push buf
    
    eval_expression(node[:args][2])
    @emitter.emit([0x48, 0x89, 0xc2]) # mov rdx, rax (len)
    @emitter.emit([0x5e]) # pop rsi (buf)
    @emitter.emit([0x5f]) # pop rdi (sockfd)
    
    # r10 = flags = 0
    @emitter.emit([0x4d, 0x31, 0xd2]) # xor r10, r10
    
    # syscall 44 = sendto
    @emitter.emit([0xb8, 0x2c, 0x00, 0x00, 0x00]) # mov eax, 44
    @emitter.emit([0x0f, 0x05])
  end

  # recv(sockfd, buf, len) - receive data
  def gen_recv(node)
    return unless @target_os == :linux
    
    eval_expression(node[:args][0])
    @emitter.emit([0x50]) # push sockfd
    
    eval_expression(node[:args][1])
    @emitter.emit([0x50]) # push buf
    
    eval_expression(node[:args][2])
    @emitter.emit([0x48, 0x89, 0xc2]) # mov rdx, rax (len)
    @emitter.emit([0x5e]) # pop rsi (buf)
    @emitter.emit([0x5f]) # pop rdi (sockfd)
    
    # r10 = flags = 0
    @emitter.emit([0x4d, 0x31, 0xd2]) # xor r10, r10
    
    # syscall 45 = recvfrom
    @emitter.emit([0xb8, 0x2d, 0x00, 0x00, 0x00]) # mov eax, 45
    @emitter.emit([0x0f, 0x05])
  end

  # bind(sockfd, ip, port) - bind socket to address
  def gen_bind(node)
    return unless @target_os == :linux
    
    eval_expression(node[:args][0])
    @emitter.emit([0x50]) # push sockfd
    
    eval_expression(node[:args][1])
    @emitter.emit([0x50]) # push ip
    
    eval_expression(node[:args][2])
    @emitter.emit([0x86, 0xc4]) # xchg al, ah
    @emitter.emit([0x48, 0x89, 0xc1]) # mov rcx, rax
    
    @emitter.emit([0x58]) # pop rax (ip)
    @emitter.emit([0x48, 0x89, 0xc2]) # mov rdx, rax
    
    @emitter.emit([0x48, 0x83, 0xec, 0x10]) # sub rsp, 16
    @emitter.emit([0x66, 0xc7, 0x04, 0x24, 0x02, 0x00]) # AF_INET
    @emitter.emit([0x66, 0x89, 0x4c, 0x24, 0x02]) # port
    @emitter.emit([0x89, 0x54, 0x24, 0x04]) # ip
    @emitter.emit([0x48, 0xc7, 0x44, 0x24, 0x08, 0x00, 0x00, 0x00, 0x00])
    
    @emitter.emit([0x5f]) # pop rdi
    @emitter.emit([0x48, 0x89, 0xe6]) # mov rsi, rsp
    @emitter.emit([0xba, 0x10, 0x00, 0x00, 0x00]) # mov edx, 16
    
    # syscall 49 = bind
    @emitter.emit([0xb8, 0x31, 0x00, 0x00, 0x00]) # mov eax, 49
    @emitter.emit([0x0f, 0x05])
    
    @emitter.emit([0x48, 0x83, 0xc4, 0x10]) # add rsp, 16
  end

  # listen(sockfd, backlog) - listen for connections
  def gen_listen(node)
    return unless @target_os == :linux
    
    eval_expression(node[:args][0])
    @emitter.emit([0x48, 0x89, 0xc7]) # mov rdi, rax
    
    eval_expression(node[:args][1])
    @emitter.emit([0x48, 0x89, 0xc6]) # mov rsi, rax
    
    # syscall 50 = listen
    @emitter.emit([0xb8, 0x32, 0x00, 0x00, 0x00]) # mov eax, 50
    @emitter.emit([0x0f, 0x05])
  end

  # accept(sockfd) - accept connection
  def gen_accept(node)
    return unless @target_os == :linux
    
    eval_expression(node[:args][0])
    @emitter.emit([0x48, 0x89, 0xc7]) # mov rdi, rax
    
    # rsi = NULL, rdx = NULL
    @emitter.emit([0x48, 0x31, 0xf6]) # xor rsi, rsi
    @emitter.emit([0x48, 0x31, 0xd2]) # xor rdx, rdx
    
    # syscall 43 = accept
    @emitter.emit([0xb8, 0x2b, 0x00, 0x00, 0x00]) # mov eax, 43
    @emitter.emit([0x0f, 0x05])
  end

  # ip(a, b, c, d) - convert IP to integer in network byte order
  # ip(127, 0, 0, 1) for localhost
  def gen_ip(node)
    # Build IP: a | (b << 8) | (c << 16) | (d << 24)
    eval_expression(node[:args][0])  # a
    @emitter.emit([0x48, 0x89, 0xc3]) # mov rbx, rax
    
    eval_expression(node[:args][1])  # b
    @emitter.emit([0x48, 0xc1, 0xe0, 0x08]) # shl rax, 8
    @emitter.emit([0x48, 0x09, 0xc3]) # or rbx, rax
    
    eval_expression(node[:args][2])  # c
    @emitter.emit([0x48, 0xc1, 0xe0, 0x10]) # shl rax, 16
    @emitter.emit([0x48, 0x09, 0xc3]) # or rbx, rax
    
    eval_expression(node[:args][3])  # d
    @emitter.emit([0x48, 0xc1, 0xe0, 0x18]) # shl rax, 24
    @emitter.emit([0x48, 0x09, 0xd8]) # or rax, rbx
  end
end
