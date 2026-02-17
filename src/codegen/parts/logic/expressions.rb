# expressions.rb - Expression evaluation for GeneratorLogic

module GeneratorExpressions
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
end
