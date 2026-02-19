# Network built-in functions for Juno
# Linux architecture-neutral syscalls for networking

module BuiltinNetwork
  # socket(domain, type, protocol) - create socket
  def gen_socket(node)
    return unless @target_os == :linux
    eval_expression(node[:args][2]); @emitter.push_reg(0) # protocol
    eval_expression(node[:args][1]); @emitter.push_reg(0) # type
    eval_expression(node[:args][0]) # domain
    @emitter.pop_reg(@arch == :aarch64 ? 1 : 6) # type
    @emitter.pop_reg(@arch == :aarch64 ? 2 : 2) # protocol
    @emitter.mov_reg_reg(@arch == :aarch64 ? 0 : 7, 0) # domain
    emit_syscall(:socket)
  end

  # connect(sockfd, ip, port) - connect to server
  def gen_connect(node)
    return unless @target_os == :linux
    eval_expression(node[:args][2]); @emitter.push_reg(0) # port
    eval_expression(node[:args][1]); @emitter.push_reg(0) # ip
    eval_expression(node[:args][0]); @emitter.push_reg(0) # sockfd

    @emitter.pop_reg(@arch == :aarch64 ? 4 : 12) # sockfd
    @emitter.pop_reg(@arch == :aarch64 ? 5 : 13) # ip
    @emitter.pop_reg(@arch == :aarch64 ? 6 : 14) # port

    # Byte swap port (simplistic)
    @emitter.mov_reg_reg(0, @arch == :aarch64 ? 6 : 14)
    if @arch == :aarch64
       @emitter.emit32(0x92401c01); @emitter.emit32(0xd3481c01); @emitter.emit32(0x92402002)
       @emitter.emit32(0xd3482042); @emitter.emit32(0xaa020020)
    else
       @emitter.emit([0x86, 0xc4]) # xchg al, ah
    end
    @emitter.mov_reg_reg(@arch == :aarch64 ? 6 : 14, 0)

    # Build sockaddr_in on stack (16 bytes)
    @emitter.emit_sub_rsp(16)
    @emitter.mov_reg_imm(0, 2); @emitter.mov_mem_reg_idx(@arch == :aarch64 ? 31 : 4, 0, 0, 2) # family
    @emitter.mov_reg_reg(0, @arch == :aarch64 ? 6 : 14); @emitter.mov_mem_reg_idx(@arch == :aarch64 ? 31 : 4, 2, 0, 2) # port
    @emitter.mov_reg_reg(0, @arch == :aarch64 ? 5 : 13); @emitter.mov_mem_reg_idx(@arch == :aarch64 ? 31 : 4, 4, 0, 4) # ip
    @emitter.mov_reg_imm(0, 0); @emitter.mov_mem_reg_idx(@arch == :aarch64 ? 31 : 4, 8, 0, 8) # zero

    @emitter.mov_reg_reg(@arch == :aarch64 ? 0 : 7, @arch == :aarch64 ? 4 : 12)
    @emitter.mov_reg_sp(@arch == :aarch64 ? 1 : 6)
    @emitter.mov_reg_imm(@arch == :aarch64 ? 2 : 2, 16)
    emit_syscall(:connect)
    @emitter.emit_add_rsp(16)
  end

  # send(sockfd, buf, len) - send data
  def gen_send(node)
    return unless @target_os == :linux
    eval_expression(node[:args][2]); @emitter.push_reg(0) # len
    eval_expression(node[:args][1]); @emitter.push_reg(0) # buf
    eval_expression(node[:args][0]) # sockfd
    @emitter.pop_reg(@arch == :aarch64 ? 1 : 6) # buf
    @emitter.pop_reg(@arch == :aarch64 ? 2 : 2) # len
    @emitter.mov_reg_reg(@arch == :aarch64 ? 0 : 7, 0) # sockfd
    @emitter.mov_reg_imm(@arch == :aarch64 ? 3 : 10, 0) # flags=0
    if @arch == :aarch64
       @emitter.mov_reg_imm(4, 0); @emitter.mov_reg_imm(5, 0)
    end
    emit_syscall(:sendto)
  end

  # recv(sockfd, buf, len) - receive data
  def gen_recv(node)
    return unless @target_os == :linux
    eval_expression(node[:args][2]); @emitter.push_reg(0) # len
    eval_expression(node[:args][1]); @emitter.push_reg(0) # buf
    eval_expression(node[:args][0]) # sockfd
    @emitter.pop_reg(@arch == :aarch64 ? 1 : 6) # buf
    @emitter.pop_reg(@arch == :aarch64 ? 2 : 2) # len
    @emitter.mov_reg_reg(@arch == :aarch64 ? 0 : 7, 0) # sockfd
    @emitter.mov_reg_imm(@arch == :aarch64 ? 3 : 10, 0) # flags=0
    if @arch == :aarch64
       @emitter.mov_reg_imm(4, 0); @emitter.mov_reg_imm(5, 0)
    end
    emit_syscall(:recvfrom)
  end

  # bind(sockfd, ip, port)
  def gen_bind(node)
    return unless @target_os == :linux
    eval_expression(node[:args][2]); @emitter.push_reg(0) # port
    eval_expression(node[:args][1]); @emitter.push_reg(0) # ip
    eval_expression(node[:args][0]); @emitter.push_reg(0) # sockfd
    @emitter.pop_reg(@arch == :aarch64 ? 4 : 12); @emitter.pop_reg(@arch == :aarch64 ? 5 : 13); @emitter.pop_reg(@arch == :aarch64 ? 6 : 14)

    @emitter.mov_reg_reg(0, @arch == :aarch64 ? 6 : 14)
    if @arch == :aarch64
       @emitter.emit32(0x92401c01); @emitter.emit32(0xd3481c01); @emitter.emit32(0x92402002); @emitter.emit32(0xd3482042); @emitter.emit32(0xaa020020)
    else
       @emitter.emit([0x86, 0xc4])
    end
    @emitter.mov_reg_reg(@arch == :aarch64 ? 6 : 14, 0)

    @emitter.emit_sub_rsp(16)
    @emitter.mov_reg_imm(0, 2); @emitter.mov_mem_reg_idx(@arch == :aarch64 ? 31 : 4, 0, 0, 2)
    @emitter.mov_reg_reg(0, @arch == :aarch64 ? 6 : 14); @emitter.mov_mem_reg_idx(@arch == :aarch64 ? 31 : 4, 2, 0, 2)
    @emitter.mov_reg_reg(0, @arch == :aarch64 ? 5 : 13); @emitter.mov_mem_reg_idx(@arch == :aarch64 ? 31 : 4, 4, 0, 4)
    @emitter.mov_reg_imm(0, 0); @emitter.mov_mem_reg_idx(@arch == :aarch64 ? 31 : 4, 8, 0, 8)

    @emitter.mov_reg_reg(@arch == :aarch64 ? 0 : 7, @arch == :aarch64 ? 4 : 12)
    @emitter.mov_reg_sp(@arch == :aarch64 ? 1 : 6)
    @emitter.mov_reg_imm(@arch == :aarch64 ? 2 : 2, 16)
    emit_syscall(:bind)
    @emitter.emit_add_rsp(16)
  end

  def gen_listen(node)
    return unless @target_os == :linux
    eval_expression(node[:args][1]); @emitter.push_reg(0) # backlog
    eval_expression(node[:args][0]) # sockfd
    @emitter.pop_reg(@arch == :aarch64 ? 1 : 6)
    @emitter.mov_reg_reg(@arch == :aarch64 ? 0 : 7, 0)
    emit_syscall(:listen)
  end

  def gen_accept(node)
    return unless @target_os == :linux
    eval_expression(node[:args][0]) # sockfd
    @emitter.mov_reg_reg(@arch == :aarch64 ? 0 : 7, 0)
    @emitter.mov_reg_imm(@arch == :aarch64 ? 1 : 6, 0) # addr=NULL
    @emitter.mov_reg_imm(@arch == :aarch64 ? 2 : 2, 0) # addrlen=NULL
    if @arch == :aarch64
       @emitter.mov_reg_imm(3, 0) # flags=0
       emit_syscall(:accept4)
    else
       emit_syscall(:accept)
    end
  end

  def gen_ip(node)
    eval_expression(node[:args][3]); @emitter.push_reg(0) # d
    eval_expression(node[:args][2]); @emitter.push_reg(0) # c
    eval_expression(node[:args][1]); @emitter.push_reg(0) # b
    eval_expression(node[:args][0]) # a
    @emitter.pop_reg(1); @emitter.pop_reg(2); @emitter.pop_reg(3)
    if @arch == :aarch64
       @emitter.emit32(0xd3481c21); @emitter.emit32(0xaa010000)
       @emitter.emit32(0xd3501c42); @emitter.emit32(0xaa020000)
       @emitter.emit32(0xd3581c63); @emitter.emit32(0xaa030000)
    else
       @emitter.shl_reg_imm(1, 8); @emitter.or_rax_reg(1)
       @emitter.shl_reg_imm(2, 16); @emitter.or_rax_reg(2)
       @emitter.shl_reg_imm(3, 24); @emitter.or_rax_reg(3)
    end
  end
end
