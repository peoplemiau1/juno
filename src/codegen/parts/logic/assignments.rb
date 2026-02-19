# assignments.rb - Assignment and variable handling for GeneratorLogic

module GeneratorAssignments
  def process_assignment(node)
    if node[:expression][:type] == :variable && @ctx.structs.key?(node[:expression][:name])
       st_name = node[:expression][:name]
       st_size = @ctx.structs[st_name][:size]
       @ctx.stack_ptr += st_size
       d_off = @ctx.stack_ptr
       @ctx.var_types[node[:name]] = st_name
       @ctx.var_is_ptr[node[:name]] = true
       @emitter.lea_reg_stack(0, d_off)
       if @ctx.in_register?(node[:name])
         @emitter.mov_reg_from_rax(@emitter.class.reg_code(@ctx.get_register(node[:name])))
       else
         var_off = @ctx.declare_variable(node[:name])
         @emitter.mov_stack_reg_val(var_off, 0)
       end
       return
    end

    eval_expression(node[:expression])
    name = node[:target] ? node[:target][:value] : node[:name]

    if name.include?('.')
       save_member_rax(name)
    elsif @ctx.globals.key?(name)
       label = @ctx.globals[name]
       @emitter.push_reg(0) # RAX
       @emitter.emit_load_address(label, @linker)
       @emitter.mov_reg_reg(@arch == :aarch64 ? 1 : 2, 0) # RDX or X1
       @emitter.pop_reg(0) # RAX or X0
       if @arch == :aarch64
         @emitter.emit32(0xf9000020) # str x0, [x1]
       else
         @emitter.mov_mem_reg_idx(2, 0, 0) # [RDX], RAX
       end
    else
       if node[:var_type]
         @ctx.var_types[name] = node[:var_type]
         @ctx.var_is_ptr[name] = true if node[:var_type] == "ptr" || @ctx.structs.key?(node[:var_type])
       end
       if @ctx.in_register?(name)
         reg = @emitter.class.reg_code(@ctx.get_register(name))
         @emitter.mov_reg_from_rax(reg)
       else
         off = @ctx.variables[name] || @ctx.declare_variable(name)
         @emitter.mov_stack_reg_val(off, 0)
       end
    end
  end

  def process_deref_assign(node)
    eval_expression(node[:value]); @emitter.push_reg(0)
    eval_expression(node[:target])
    target_reg = (@arch == :aarch64 ? 1 : 7)
    @emitter.mov_reg_reg(target_reg, 0) # RDI or X1 = target
    @emitter.pop_reg(0)        # RAX or X0 = value
    @emitter.mov_mem_reg_idx(target_reg, 0, 0, 8)
  end

  def gen_array_assign(node)
    eval_expression(node[:value]); @emitter.push_reg(0)
    eval_expression(node[:index]); @emitter.shl_rax_imm(3)

    scratch = @ctx.acquire_scratch
    if scratch
       @emitter.mov_reg_reg(scratch, 0) # index in scratch
       arr_info = @ctx.get_array(node[:name])
       if arr_info then @emitter.mov_reg_stack_val(0, arr_info[:ptr_offset])
       else @emitter.mov_reg_stack_val(0, @ctx.get_variable_offset(node[:name])) end
       @emitter.mov_reg_reg(2, 0) # base in RDX
       @emitter.mov_reg_reg(0, scratch) # index in RAX
       @ctx.release_scratch(scratch)
       @emitter.add_rax_rdx
    else
       @emitter.push_reg(0) # index
       arr_info = @ctx.get_array(node[:name])
       if arr_info then @emitter.mov_reg_stack_val(0, arr_info[:ptr_offset])
       else @emitter.mov_reg_stack_val(0, @ctx.get_variable_offset(node[:name])) end
       @emitter.pop_reg(2) # index in RDX
       @emitter.add_rax_rdx
    end

    target_reg = (@arch == :aarch64 ? 1 : 7)
    @emitter.mov_reg_reg(target_reg, 0) # target addr (X1 or RDI)
    @emitter.pop_reg(0) # value (X0 or RAX)
    @emitter.mov_mem_reg_idx(target_reg, 0, 0, 8)
  end
end
