# control_flow.rb - IF, WHILE, FOR with BREAK/CONTINUE support

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
    
    # Пушим контекст цикла в стек
    @loop_stack.push({ breaks: [], continues: [], start_pos: loop_start })

    eval_expression(node[:condition])
    @emitter.test_rax_rax
    exit_patch = @emitter.je_rel32 # Прыжок на выход, если условие ложно

    node[:body].each { |c| process_node(c) }

    # Прыжок назад в начало
    jmp_back = @emitter.jmp_rel32
    @emitter.patch_jmp(jmp_back, loop_start)

    loop_end = @emitter.current_pos
    
    # Патчим стандартный выход
    @emitter.patch_je(exit_patch, loop_end)

    # Патчим все break (прыгают в конец)
    @loop_stack.last[:breaks].each do |b_pos|
      @emitter.patch_jmp(b_pos, loop_end)
    end

    # Патчим все continue (прыгают в начало)
    @loop_stack.last[:continues].each do |c_pos|
      @emitter.patch_jmp(c_pos, loop_start)
    end

    @loop_stack.pop
  end

  def gen_for(node)
    process_node(node[:init])
    
    loop_start = @emitter.current_pos
    
    # Для for continue прыгает на update (инкремент), а не на условие!
    # Но update генерируется в конце. Пока запишем start_pos как loop_start,
    # а потом перебьем на update_start.
    @loop_stack.push({ breaks: [], continues: [], type: :for })

    eval_expression(node[:condition])
    @emitter.test_rax_rax
    exit_patch = @emitter.je_rel32

    node[:body].each { |c| process_node(c) }

    # Место, куда прыгает continue
    update_start = @emitter.current_pos
    process_node(node[:update])
    
    jmp_back = @emitter.jmp_rel32
    @emitter.patch_jmp(jmp_back, loop_start)

    loop_end = @emitter.current_pos
    @emitter.patch_je(exit_patch, loop_end)

    # Патчим break
    @loop_stack.last[:breaks].each do |b_pos|
      @emitter.patch_jmp(b_pos, loop_end)
    end

    # Патчим continue (на update!)
    @loop_stack.last[:continues].each do |c_pos|
      @emitter.patch_jmp(c_pos, update_start)
    end

    @loop_stack.pop
  end

  def gen_break(node)
    if @loop_stack.empty?
      raise "Error: 'break' used outside of loop"
    end
    # Генерируем прыжок-заглушку и запоминаем его позицию
    pos = @emitter.jmp_rel32
    @loop_stack.last[:breaks] << pos
  end

  def gen_continue(node)
    if @loop_stack.empty?
      raise "Error: 'continue' used outside of loop"
    end
    # Генерируем прыжок-заглушку
    pos = @emitter.jmp_rel32
    @loop_stack.last[:continues] << pos
  end
end
