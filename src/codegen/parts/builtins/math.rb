# Math built-in functions for Juno
module BuiltinMath
  # abs(n) - absolute value
  def gen_abs(node)
    eval_expression(node[:args][0])
    @emitter.emit([0x48, 0x89, 0xc3])       # mov rbx, rax
    @emitter.emit([0x48, 0xc1, 0xfb, 0x3f]) # sar rbx, 63
    @emitter.emit([0x48, 0x31, 0xd8])       # xor rax, rbx
    @emitter.emit([0x48, 0x29, 0xd8])       # sub rax, rbx
  end

  # min(a, b)
  def gen_min(node)
    eval_expression(node[:args][0])
    @emitter.emit([0x50])
    
    eval_expression(node[:args][1])
    @emitter.emit([0x48, 0x89, 0xc3]) # mov rbx, rax
    @emitter.emit([0x58])             # pop rax
    
    @emitter.emit([0x48, 0x39, 0xc3]) # cmp rbx, rax
    @emitter.emit([0x7d, 0x03])       # jge +3
    @emitter.emit([0x48, 0x89, 0xd8]) # mov rax, rbx
  end

  # max(a, b)
  def gen_max(node)
    eval_expression(node[:args][0])
    @emitter.emit([0x50])
    
    eval_expression(node[:args][1])
    @emitter.emit([0x48, 0x89, 0xc3]) # mov rbx, rax
    @emitter.emit([0x58])             # pop rax
    
    @emitter.emit([0x48, 0x39, 0xc3]) # cmp rbx, rax
    @emitter.emit([0x7e, 0x03])       # jle +3
    @emitter.emit([0x48, 0x89, 0xd8]) # mov rax, rbx
  end

  # pow(base, exp)
  def gen_pow(node)
    eval_expression(node[:args][0])
    @emitter.emit([0x50])
    
    eval_expression(node[:args][1])
    @emitter.emit([0x48, 0x89, 0xc1]) # mov rcx, rax
    @emitter.emit([0x5b])             # pop rbx
    
    @emitter.emit([0x48, 0xc7, 0xc0, 1, 0, 0, 0]) # mov rax, 1
    
    @emitter.emit([0x48, 0x85, 0xc9])       # test rcx, rcx
    @emitter.emit([0x74, 0x09])             # jz +9
    @emitter.emit([0x48, 0x0f, 0xaf, 0xc3]) # imul rax, rbx
    @emitter.emit([0x48, 0xff, 0xc9])       # dec rcx
    @emitter.emit([0xeb, 0xf2])             # jmp -14
  end
end
