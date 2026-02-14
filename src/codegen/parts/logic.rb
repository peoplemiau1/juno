module GeneratorLogic
  def process_node(node)
    case node[:type]
    when :assignment then process_assignment(node)
    when :deref_assign then process_deref_assign(node)
    when :fn_call then gen_fn_call(node)
    when :return
       eval_expression(node[:expression])
       used_regs = @ctx.used_callee_saved
       padding = (used_regs.length % 2 == 1) ? 8 : 0
       @emitter.pop_callee_saved(used_regs) unless used_regs.empty?
       @emitter.emit_add_rsp(padding) if padding > 0
       @emitter.emit_epilogue(@stack_size || 256)
    when :if_statement then gen_if(node)
    when :while_statement then gen_while(node)
    when :for_statement then gen_for(node)
    when :increment then gen_increment(node)
    when :insertC then gen_insertC(node)
    when :array_decl then gen_array_decl(node)
    when :array_assign then gen_array_assign(node)
    end
  end

  def process_assignment(node)
    if node[:expression][:type] == :variable && @ctx.structs.key?(node[:expression][:name])
      st_name = node[:expression][:name]
      st_size = @ctx.structs[st_name][:size]
       @ctx.stack_ptr += st_size
       d_off = @ctx.stack_ptr
       var_off = @ctx.declare_variable(node[:name])
       @ctx.var_types[node[:name]] = st_name
       @ctx.var_is_ptr[node[:name]] = true
       @emitter.lea_reg_stack(0, d_off)
       @emitter.mov_stack_reg_val(var_off, 0)
       return
    end

    eval_expression(node[:expression])
    if node[:name].include?('.')
       save_member_rax(node[:name])
    else
       @ctx.var_types[node[:name]] = node[:var_type] if node[:var_type]
       if @ctx.in_register?(node[:name])
         reg = @emitter.class.reg_code(@ctx.get_register(node[:name]))
         @emitter.mov_reg_from_rax(reg)
       else
         off = @ctx.variables[node[:name]] || @ctx.declare_variable(node[:name])
         @emitter.mov_stack_reg_val(off, 0)
       end
    end
  end

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

  def gen_increment(node)
    if @ctx.in_register?(node[:name])
      reg = @emitter.class.reg_code(@ctx.get_register(node[:name]))
      @emitter.mov_rax_from_reg(reg)
    else
      off = @ctx.get_variable_offset(node[:name])
      @emitter.mov_reg_stack_val(0, off)
    end
    @emitter.push_reg(0); @emitter.mov_rax(1); @emitter.mov_reg_reg(2, 0); @emitter.pop_reg(0)
    node[:op] == "++" ? @emitter.add_rax_rdx : @emitter.sub_rax_rdx
    if @ctx.in_register?(node[:name])
      reg = @emitter.class.reg_code(@ctx.get_register(node[:name]))
      @emitter.mov_reg_from_rax(reg)
    else
      off = @ctx.get_variable_offset(node[:name])
      @emitter.mov_stack_reg_val(off, 0)
    end
  end

  def eval_expression(expr)
    case expr[:type]
    when :literal then @emitter.mov_rax(expr[:value])
    when :variable
      if @ctx.in_register?(expr[:name])
        reg = @emitter.class.reg_code(@ctx.get_register(expr[:name]))
        @emitter.mov_rax_from_reg(reg)
      elsif @ctx.variables.key?(expr[:name])
        @emitter.mov_reg_stack_val(0, @ctx.variables[expr[:name]])
      else
        @emitter.emit_load_address(expr[:name], @linker)
      end
    when :binary_op then eval_binary_op(expr)
    when :fn_call then gen_fn_call(expr)
    when :unary_op
      eval_expression(expr[:operand])
      if expr[:op] == "~"
        @emitter.not_rax
      elsif expr[:op] == "!"
        @emitter.test_rax_rax
        @emitter.mov_rax(0)
        if @arch == :aarch64 then @emitter.emit32(0x1a9f07e0) else @emitter.emit([0x0f, 0x94, 0xc0]) end
      end
    when :member_access then load_member_rax("#{expr[:receiver]}.#{expr[:member]}")
    when :array_access then gen_array_access(expr)
    when :string_literal then gen_string_literal(expr)
    when :address_of then gen_address_of(expr)
    when :dereference then gen_dereference(expr)
    end
  end

  def eval_binary_op(expr)
    if expr[:op] == "+" && (expr[:left][:type] == :string_literal || expr[:right][:type] == :string_literal)
       return gen_fn_call({ type: :fn_call, name: "concat", args: [expr[:left], expr[:right]] })
    end
    if (expr[:op] == "+" || expr[:op] == "-") && (pointer_node?(expr[:left]) || pointer_node?(expr[:right]))
       return gen_pointer_arith(expr)
    end
    eval_expression(expr[:left]); @emitter.push_reg(0)
    eval_expression(expr[:right]); @emitter.mov_reg_reg(2, 0); @emitter.pop_reg(0)
    case expr[:op]
    when "+" then @emitter.add_rax_rdx
    when "-" then @emitter.sub_rax_rdx
    when "*" then @emitter.imul_rax_rdx
    when "/" then @emitter.div_rax_by_rdx
    when "%" then @emitter.mod_rax_by_rdx
    when "&" then @emitter.and_rax_rdx
    when "|" then @emitter.or_rax_rdx
    when "^" then @emitter.xor_rax_rdx
    when "<<" then @emitter.shl_rax_cl
    when ">>" then @emitter.shr_rax_cl
    when "==", "!=", "<", ">", "<=", ">=" then @emitter.cmp_rax_rdx(expr[:op])
    end
  end

  def pointer_node?(node)
    return false unless node.is_a?(Hash)
    node[:type] == :address_of || (node[:type] == :variable && @ctx.var_is_ptr[node[:name]])
  end

  def gen_pointer_arith(expr)
    base = pointer_node?(expr[:left]) ? expr[:left] : expr[:right]
    offset = (base == expr[:left]) ? expr[:right] : expr[:left]
    eval_expression(base); @emitter.push_reg(0)
    eval_expression(offset); @emitter.shl_rax_imm(3)
    @emitter.mov_reg_reg(2, 0); @emitter.pop_reg(0)
    expr[:op] == "+" ? @emitter.add_rax_rdx : @emitter.sub_rax_rdx
  end

  def load_member_rax(full)
    v, f = full.split('.')
    st = @ctx.var_types[v]
    return unless st && @ctx.structs[st]
    f_off = @ctx.structs[st][:fields][f]
    if @ctx.in_register?(v)
      @emitter.mov_rax_from_reg(@emitter.class.reg_code(@ctx.get_register(v)))
    else
      @emitter.mov_reg_stack_val(0, @ctx.variables[v])
    end
    @emitter.mov_rax_mem(f_off)
  end

  def save_member_rax(full)
     v, f = full.split('.')
     st = @ctx.var_types[v]
     return unless st && @ctx.structs[st]
     f_off = @ctx.structs[st][:fields][f]
     @emitter.mov_r11_rax
     if @ctx.in_register?(v)
       @emitter.mov_rax_from_reg(@emitter.class.reg_code(@ctx.get_register(v)))
     else
       @emitter.mov_reg_stack_val(0, @ctx.variables[v])
     end
     @emitter.mov_mem_r11(f_off)
  end

  def gen_insertC(node)
    @emitter.emit(node[:content].strip.split(/[\s,]+/).map { |t| t.sub(/^0x/i, '').to_i(16) })
  end

  def gen_array_decl(node)
    arr_info = @ctx.declare_array(node[:name], node[:size])
    @emitter.mov_rax(0)
    node[:size].times { |i| @emitter.mov_stack_reg_val(arr_info[:base_offset] - i*8, 0) }
    @emitter.lea_reg_stack(0, arr_info[:base_offset])
    @emitter.mov_stack_reg_val(arr_info[:ptr_offset], 0)
  end

  def gen_array_assign(node)
    eval_expression(node[:value]); @emitter.mov_r11_rax
    eval_expression(node[:index]); @emitter.shl_rax_imm(3); @emitter.push_reg(0)
    arr_info = @ctx.get_array(node[:name])
    if arr_info then @emitter.mov_reg_stack_val(0, arr_info[:ptr_offset])
    else @emitter.mov_reg_stack_val(0, @ctx.get_variable_offset(node[:name])) end
    @emitter.mov_reg_reg(2, 0); @emitter.pop_reg(0); @emitter.add_rax_rdx; @emitter.mov_mem_r11(0)
  end

  def gen_array_access(node)
    eval_expression(node[:index]); @emitter.shl_rax_imm(3); @emitter.push_reg(0)
    arr_info = @ctx.get_array(node[:name])
    if arr_info then @emitter.mov_reg_stack_val(0, arr_info[:ptr_offset])
    else @emitter.mov_reg_stack_val(0, @ctx.get_variable_offset(node[:name])) end
    @emitter.mov_reg_reg(2, 0); @emitter.pop_reg(0); @emitter.add_rax_rdx; @emitter.mov_rax_mem(0)
  end

  def gen_string_literal(node)
    @emitter.emit_load_address(@linker.add_string(node[:value]), @linker)
  end

  def gen_address_of(expr)
    operand = expr[:operand]
    if operand[:type] == :variable
      @emitter.lea_reg_stack(0, @ctx.get_variable_offset(operand[:name]))
    elsif operand[:type] == :array_access
      eval_expression(operand[:index]); @emitter.shl_rax_imm(3); @emitter.push_reg(0)
      arr_info = @ctx.get_array(operand[:name])
      if arr_info then @emitter.mov_reg_stack_val(0, arr_info[:ptr_offset])
      else @emitter.mov_reg_stack_val(0, @ctx.get_variable_offset(operand[:name])) end
      @emitter.mov_reg_reg(2, 0); @emitter.pop_reg(0); @emitter.add_rax_rdx
    end
  end

  def gen_dereference(expr)
    eval_expression(expr[:operand]); @emitter.mov_rax_mem(0)
  end

  def process_deref_assign(node)
    eval_expression(node[:value]); @emitter.mov_r11_rax; eval_expression(node[:target]); @emitter.mov_mem_r11(0)
  end
end
