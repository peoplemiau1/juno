# control_flow.rb - IF, WHILE, FOR with BREAK/CONTINUE support

module GeneratorControlFlow
  def gen_if(node)
    return if node[:type] == :noop
    eval_expression(node[:condition])
    @emitter.test_rax_rax
    exit_patch_pos = @emitter.je_rel32
    node[:body].each { |c| process_node(c) }

    end_patches = []
    if node[:elif_branches]&.any? || node[:else_body]
      end_patches << @emitter.jmp_rel32
    end

    @emitter.patch_je(exit_patch_pos, @emitter.current_pos)

    node[:elif_branches]&.each do |elif|
      eval_expression(elif[:condition])
      @emitter.test_rax_rax
      elif_exit_patch = @emitter.je_rel32
      elif[:body].each { |c| process_node(c) }
      end_patches << @emitter.jmp_rel32
      @emitter.patch_je(elif_exit_patch, @emitter.current_pos)
    end

    if node[:else_body]
       node[:else_body].each { |c| process_node(c) }
    end

    end_pos = @emitter.current_pos
    end_patches.each { |p| @emitter.patch_jmp(p, end_pos) }
  end

  def gen_while(node)
    loop_start = @emitter.current_pos
    
    @loop_stack.push({ breaks: [], continues: [], start_pos: loop_start })

    eval_expression(node[:condition])
    @emitter.test_rax_rax
    exit_patch = @emitter.je_rel32

    node[:body].each { |c| process_node(c) }

    jmp_back = @emitter.jmp_rel32
    @emitter.patch_jmp(jmp_back, loop_start)

    loop_end = @emitter.current_pos
    
    @emitter.patch_je(exit_patch, loop_end)

    @loop_stack.last[:breaks].each do |b_pos|
      @emitter.patch_jmp(b_pos, loop_end)
    end

    @loop_stack.last[:continues].each do |c_pos|
      @emitter.patch_jmp(c_pos, loop_start)
    end

    @loop_stack.pop
  end

  def gen_for(node)
    process_node(node[:init])
    
    loop_start = @emitter.current_pos
    
    @loop_stack.push({ breaks: [], continues: [], type: :for })

    eval_expression(node[:condition])
    @emitter.test_rax_rax
    exit_patch = @emitter.je_rel32

    node[:body].each { |c| process_node(c) }

    update_start = @emitter.current_pos
    process_node(node[:update])
    
    jmp_back = @emitter.jmp_rel32
    @emitter.patch_jmp(jmp_back, loop_start)

    loop_end = @emitter.current_pos
    @emitter.patch_je(exit_patch, loop_end)

    @loop_stack.last[:breaks].each do |b_pos|
      @emitter.patch_jmp(b_pos, loop_end)
    end

    @loop_stack.last[:continues].each do |c_pos|
      @emitter.patch_jmp(c_pos, update_start)
    end

    @loop_stack.pop
  end

  def gen_break(node)
    if @loop_stack.empty?
      raise "Error: 'break' used outside of loop"
    end
    pos = @emitter.jmp_rel32
    @loop_stack.last[:breaks] << pos
  end

  def gen_continue(node)
    if @loop_stack.empty?
      raise "Error: 'continue' used outside of loop"
    end
    pos = @emitter.jmp_rel32
    @loop_stack.last[:continues] << pos
  end
end
