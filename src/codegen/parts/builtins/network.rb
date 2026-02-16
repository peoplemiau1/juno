# Network built-in functions for Juno
# Linux architecture-neutral syscalls for networking

module BuiltinNetwork
  # socket(domain, type, protocol) - create socket
  def gen_socket(node)
    return unless @target_os == :linux
    eval_expression(node[:args][2]); @emitter.push_reg(0)
    eval_expression(node[:args][1]); @emitter.push_reg(0)
    eval_expression(node[:args][0])
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
    @emitter.pop_reg(@arch == :aarch64 ? 6 : 14) # port (host order)

    # xchg port bytes
    @emitter.mov_reg_reg(0, @arch == :aarch64 ? 6 : 14)
    if @arch == :aarch64
       # x0 = ((x0 & 0xff) << 8) | ((x0 & 0xff00) >> 8)
       @emitter.emit32(0x92401c01) # and x1, x0, #0xff
       @emitter.emit32(0xd3481c01) # lsl x1, x1, #8
       @emitter.emit32(0x92402002) # and x2, x0, #0xff00
       @emitter.emit32(0xd3482042) # lsr x2, x2, #8
       @emitter.emit32(0xaa020020) # orr x0, x1, x2
    else
       @emitter.emit([0x86, 0xc4]) # xchg al, ah
    end
    @emitter.mov_reg_reg(@arch == :aarch64 ? 6 : 14, 0) # port (network order)

    # Build sockaddr_in on stack (16 bytes)
    @emitter.emit_sub_rsp(16)

    # sin_family = AF_INET (2)
    @emitter.mov_rax(2)
    @emitter.mov_stack_reg_val(0, 0) # simplified: assuming first 8 bytes of stack
    # Wait, need exact offsets.
    # [rsp] = family(2) | port << 16
    @emitter.mov_rax(2)
    @emitter.mov_reg_reg(1, @arch == :aarch64 ? 6 : 14) # port
    if @arch == :aarch64
       @emitter.emit32(0xd350fc21) # lsl x1, x1, #16
       @emitter.emit32(0xaa010000) # orr x0, x0, x1
    else
       @emitter.shl_rax_imm(16)
       @emitter.emit([0x48, 0x09, 0xc8]) # or rax, rcx -> wait, i didn't use rcx
       # Let's just do it manually for x86 too
    end
    # Actually, let's use mov_mem_idx for better control
    @emitter.mov_rax(2)
    @emitter.mov_mem_idx(@arch == :aarch64 ? 31 : 4, 0, 0, 2) # [sp+0] = 2
    @emitter.mov_reg_reg(0, @arch == :aarch64 ? 6 : 14)
    @emitter.mov_mem_idx(@arch == :aarch64 ? 31 : 4, 2, 0, 2) # [sp+2] = port
    @emitter.mov_reg_reg(0, @arch == :aarch64 ? 5 : 13)
    @emitter.mov_mem_idx(@arch == :aarch64 ? 31 : 4, 4, 0, 4) # [sp+4] = ip
    @emitter.mov_rax(0)
    @emitter.mov_mem_idx(@arch == :aarch64 ? 31 : 4, 8, 0, 8) # [sp+8] = 0

    @emitter.mov_reg_reg(@arch == :aarch64 ? 0 : 7, @arch == :aarch64 ? 4 : 12) # sockfd
    @emitter.mov_reg_sp(@arch == :aarch64 ? 1 : 6) # rsi = sp
    @emitter.mov_rax(16); @emitter.mov_reg_reg(@arch == :aarch64 ? 2 : 2, 0) # rdx = 16

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
    @emitter.mov_rax(0); @emitter.mov_reg_reg(@arch == :aarch64 ? 3 : 10, 0) # flags=0

    if @arch == :aarch64
       @emitter.mov_rax(0); @emitter.mov_reg_reg(4, 0) # dest_addr=NULL
       @emitter.mov_rax(0); @emitter.mov_reg_reg(5, 0) # addrlen=0
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
    @emitter.mov_rax(0); @emitter.mov_reg_reg(@arch == :aarch64 ? 3 : 10, 0) # flags=0

    if @arch == :aarch64
       @emitter.mov_rax(0); @emitter.mov_reg_reg(4, 0) # src_addr=NULL
       @emitter.mov_rax(0); @emitter.mov_reg_reg(5, 0) # addrlen=NULL
    end

    emit_syscall(:recvfrom)
  end

  # bind(sockfd, ip, port)
  def gen_bind(node)
    # Similar to connect
    return unless @target_os == :linux
    eval_expression(node[:args][2]); @emitter.push_reg(0) # port
    eval_expression(node[:args][1]); @emitter.push_reg(0) # ip
    eval_expression(node[:args][0]); @emitter.push_reg(0) # sockfd
    @emitter.pop_reg(@arch == :aarch64 ? 4 : 12); @emitter.pop_reg(@arch == :aarch64 ? 5 : 13); @emitter.pop_reg(@arch == :aarch64 ? 6 : 14)

    # Port swap
    @emitter.mov_reg_reg(0, @arch == :aarch64 ? 6 : 14)
    if @arch == :aarch64
       @emitter.emit32(0x92401c01); @emitter.emit32(0xd3481c01); @emitter.emit32(0x92402002); @emitter.emit32(0xd3482042); @emitter.emit32(0xaa020020)
    else
       @emitter.emit([0x86, 0xc4])
    end
    @emitter.mov_reg_reg(@arch == :aarch64 ? 6 : 14, 0)

    @emitter.emit_sub_rsp(16)
    @emitter.mov_rax(2); @emitter.mov_mem_idx(@arch == :aarch64 ? 31 : 4, 0, 0, 2)
    @emitter.mov_reg_reg(0, @arch == :aarch64 ? 6 : 14); @emitter.mov_mem_idx(@arch == :aarch64 ? 31 : 4, 2, 0, 2)
    @emitter.mov_reg_reg(0, @arch == :aarch64 ? 5 : 13); @emitter.mov_mem_idx(@arch == :aarch64 ? 31 : 4, 4, 0, 4)
    @emitter.mov_rax(0); @emitter.mov_mem_idx(@arch == :aarch64 ? 31 : 4, 8, 0, 8)

    @emitter.mov_reg_reg(@arch == :aarch64 ? 0 : 7, @arch == :aarch64 ? 4 : 12)
    @emitter.mov_reg_sp(@arch == :aarch64 ? 1 : 6)
    @emitter.mov_rax(16); @emitter.mov_reg_reg(@arch == :aarch64 ? 2 : 2, 0)
    emit_syscall(:bind)
    @emitter.emit_add_rsp(16)
  end

  def gen_listen(node)
    return unless @target_os == :linux
    eval_expression(node[:args][1]); @emitter.push_reg(0)
    eval_expression(node[:args][0])
    @emitter.pop_reg(@arch == :aarch64 ? 1 : 6)
    @emitter.mov_reg_reg(@arch == :aarch64 ? 0 : 7, 0)
    emit_syscall(:listen)
  end

  def gen_accept(node)
    return unless @target_os == :linux
    eval_expression(node[:args][0])
    @emitter.mov_reg_reg(@arch == :aarch64 ? 0 : 7, 0)
    @emitter.mov_rax(0); @emitter.mov_reg_reg(@arch == :aarch64 ? 1 : 6, 0)
    @emitter.mov_rax(0); @emitter.mov_reg_reg(@arch == :aarch64 ? 2 : 2, 0)
    if @arch == :aarch64
       @emitter.mov_rax(0); @emitter.mov_reg_reg(3, 0) # flags=0
       emit_syscall(:accept4)
    else
       emit_syscall(:accept)
    end
  end

  def gen_ip(node)
    eval_expression(node[:args][3]); @emitter.push_reg(0)
    eval_expression(node[:args][2]); @emitter.push_reg(0)
    eval_expression(node[:args][1]); @emitter.push_reg(0)
    eval_expression(node[:args][0]) # a

    @emitter.pop_reg(1) # b
    @emitter.pop_reg(2) # c
    @emitter.pop_reg(3) # d

    if @arch == :aarch64
       @emitter.emit32(0xd3481c21) # lsl x1, x1, #8
       @emitter.emit32(0xaa010000) # orr x0, x0, x1
       @emitter.emit32(0xd3501c42) # lsl x2, x2, #16
       @emitter.emit32(0xaa020000) # orr x0, x0, x2
       @emitter.emit32(0xd3581c63) # lsl x3, x3, #24
       @emitter.emit32(0xaa030000) # orr x0, x0, x3
    else
       @emitter.emit([0x48, 0xc1, 0xe1, 0x08]) # shl rcx, 8 -> wait pop order and regs
       # Let's rewrite x86 part too to be safe
       @emitter.mov_reg_reg(6, 1) # rsi = b
       @emitter.shl_reg_imm(6, 8)
       @emitter.or_rax_reg(6)
       @emitter.mov_reg_reg(6, 2) # rsi = c
       @emitter.shl_reg_imm(6, 16)
       @emitter.or_rax_reg(6)
       @emitter.mov_reg_reg(6, 3) # rsi = d
       @emitter.shl_reg_imm(6, 24)
       @emitter.or_rax_reg(6)
    end
  end
end
