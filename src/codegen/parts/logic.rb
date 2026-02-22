# logic.rb - Main logic dispatcher for GeneratorLogic
require_relative "logic/assignments"
require_relative "logic/control_flow"
require_relative "logic/expressions"
require_relative "logic/access"

module GeneratorLogic
  include GeneratorAssignments
  include GeneratorControlFlow
  include GeneratorExpressions
  include GeneratorAccess

  def process_node(node)
    return if node.nil?
    case node[:type]
    when :assignment then process_assignment(node)
    when :deref_assign then process_deref_assign(node)
    when :fn_call then gen_fn_call(node)
    when :variable, :binary_op, :literal, :unary_op, :string_literal, :member_access, :array_access, :dereference, :match_expression, :panic, :todo, :cast, :anonymous_function then eval_expression(node)
    when :return
       eval_expression(node[:expression])
       if @arch == :x86_64 && (@emitter.callee_saved_regs.length + 1) % 2 == 0
         @emitter.emit_add_rsp(8)
       end
       @emitter.pop_callee_saved(@emitter.callee_saved_regs)
       @emitter.emit_epilogue(@ctx.current_fn_stack_size || @stack_size || 256)
    when :if_statement then gen_if(node)
    when :while_statement then gen_while(node)
    when :for_statement then gen_for(node)
    when :increment then gen_increment(node)
    when :insertC then gen_insertC(node)
    when :array_decl then gen_array_decl(node)
    when :array_assign then gen_array_assign(node)
    when :break then gen_break(node)
    when :continue then gen_continue(node)
    else
      raise "Unknown node type in process_node: #{node[:type].inspect}"
    end
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

  def gen_string_literal(node)
    @emitter.emit_load_address(@linker.add_string(node[:value]), @linker)
  end
end
