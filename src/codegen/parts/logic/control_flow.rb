# control_flow.rb - IF, WHILE, FOR statements for GeneratorLogic

module GeneratorControlFlow
  def gen_if(node)
    eval_expression(node[:condition])
    @emitter.test_rax_rax
    patch_pos = @emitter.je_rel32
    node[:body].each { |c| process_node(c) }
    end_patch_pos = nil
    if node[:else_body]
       end_patch_pos = @emitter.jmp_rel32
    end
    @emitter.patch_je(patch_pos, @emitter.current_pos)
    if node[:else_body]
       node[:else_body].each { |c| process_node(c) }
       @emitter.patch_jmp(end_patch_pos, @emitter.current_pos)
    end
  end

  def gen_while(node)
    loop_start = @emitter.current_pos
    eval_expression(node[:condition])
    @emitter.test_rax_rax
    patch_pos = @emitter.je_rel32
    node[:body].each { |c| process_node(c) }
    jmp_back = @emitter.jmp_rel32
    @emitter.patch_jmp(jmp_back, loop_start)
    @emitter.patch_je(patch_pos, @emitter.current_pos)
  end

  def gen_for(node)
    process_node(node[:init])
    loop_start = @emitter.current_pos
    eval_expression(node[:condition])
    @emitter.test_rax_rax
    patch_pos = @emitter.je_rel32
    node[:body].each { |c| process_node(c) }
    process_node(node[:update])
    jmp_back = @emitter.jmp_rel32
    @emitter.patch_jmp(jmp_back, loop_start)
    @emitter.patch_je(patch_pos, @emitter.current_pos)
  end
end
