# assignments.rb - Assignment and variable handling for GeneratorLogic

module GeneratorAssignments
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
       if node[:var_type]
         @ctx.var_types[node[:name]] = node[:var_type]
         @ctx.var_is_ptr[node[:name]] = true if node[:var_type] == "ptr" || @ctx.structs.key?(node[:var_type])
       end
       if @ctx.in_register?(node[:name])
         reg = @emitter.class.reg_code(@ctx.get_register(node[:name]))
         @emitter.mov_reg_from_rax(reg)
       else
         off = @ctx.variables[node[:name]] || @ctx.declare_variable(node[:name])
         @emitter.mov_stack_reg_val(off, 0)
       end
    end
  end

  def process_deref_assign(node)
    eval_expression(node[:value])
    @emitter.mov_r11_rax
    eval_expression(node[:target])
    @emitter.mov_mem_r11(0)
  end

  def gen_array_assign(node)
    eval_expression(node[:value])
    @emitter.mov_r11_rax
    eval_expression(node[:index])
    @emitter.shl_rax_imm(3)
    @emitter.push_reg(0)
    arr_info = @ctx.get_array(node[:name])
    if arr_info
      @emitter.mov_reg_stack_val(0, arr_info[:ptr_offset])
    else
      @emitter.mov_reg_stack_val(0, @ctx.get_variable_offset(node[:name]))
    end
    @emitter.mov_reg_reg(2, 0)
    @emitter.pop_reg(0)
    @emitter.add_rax_rdx
    @emitter.mov_mem_r11(0)
  end
end
