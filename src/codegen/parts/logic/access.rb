# access.rb - Array and member access for GeneratorLogic

module GeneratorAccess
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

  def gen_array_access(node)
    eval_expression(node[:index])
    @emitter.shl_rax_imm(3)
    @emitter.push_reg(0)
    arr_info = @ctx.get_array(node[:name])
    if arr_info then @emitter.mov_reg_stack_val(0, arr_info[:ptr_offset])
    else @emitter.mov_reg_stack_val(0, @ctx.get_variable_offset(node[:name])) end
    @emitter.mov_reg_reg(2, 0)
    @emitter.pop_reg(0)
    @emitter.add_rax_rdx
    @emitter.mov_rax_mem(0)
  end

  def gen_address_of(expr)
    operand = expr[:operand]
    if operand[:type] == :variable
      @emitter.lea_reg_stack(0, @ctx.get_variable_offset(operand[:name]))
    elsif operand[:type] == :array_access
      eval_expression(operand[:index])
      @emitter.shl_rax_imm(3)
      @emitter.push_reg(0)
      arr_info = @ctx.get_array(operand[:name])
      if arr_info then @emitter.mov_reg_stack_val(0, arr_info[:ptr_offset])
      else @emitter.mov_reg_stack_val(0, @ctx.get_variable_offset(operand[:name])) end
      @emitter.mov_reg_reg(2, 0)
      @emitter.pop_reg(0)
      @emitter.add_rax_rdx
    end
  end

  def gen_dereference(expr)
    eval_expression(expr[:operand])
    @emitter.mov_rax_mem(0)
  end
end
