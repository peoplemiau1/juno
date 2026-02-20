# expressions.rb - Expression evaluation for GeneratorLogic

module GeneratorExpressions
  def eval_expression(expr)
    case expr[:type]
    when :literal then @emitter.mov_rax(expr[:value])
    when :variable
      name = expr[:name]
      if @ctx.in_register?(name)
        reg = @emitter.class.reg_code(@ctx.get_register(name))
        @emitter.mov_rax_from_reg(reg)
      elsif @ctx.variables.key?(name)
        @emitter.mov_reg_stack_val(0, @ctx.variables[name])
      elsif @ctx.globals.key?(name)
        @emitter.emit_load_address(@ctx.globals[name], @linker)
        @emitter.mov_rax_mem(0)
      elsif @linker.strings.key?(name) # It might be a data label from elsewhere
        @emitter.emit_load_address(name, @linker)
      else
        # Try to find if it's a known function or global in linker
        if @linker.functions.key?(name) || @linker.data_pool.any?{|d| d[:id] == name} || @linker.bss_pool.any?{|b| b[:id] == name}
           @emitter.emit_load_address(name, @linker)
        else
           # This is likely an undefined variable
           error_undefined(name, expr)
        end
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
        # On AArch64, CSET X0, EQ (to get 1 if X0 was 0) is CSINC X0, XZR, XZR, NE
        if @arch == :aarch64 then @emitter.emit32(0x1a9f17e0) else @emitter.emit([0x0f, 0x94, 0xc0]) end
      end
    when :member_access then load_member_rax("#{expr[:receiver]}.#{expr[:member]}")
    when :array_access then gen_array_access(expr)
    when :string_literal then gen_string_literal(expr)
    when :address_of then gen_address_of(expr)
    when :dereference then gen_dereference(expr)
    else
      raise "Unknown expression type in eval_expression: #{expr[:type].inspect}"
    end
  end

  def eval_binary_op(expr)
    if expr[:op] == "+" && (expr[:left][:type] == :string_literal || expr[:right][:type] == :string_literal)
       return gen_fn_call({ type: :fn_call, name: "concat", args: [expr[:left], expr[:right]] })
    end
    if (expr[:op] == "+" || expr[:op] == "-") && (pointer_node?(expr[:left]) || pointer_node?(expr[:right]))
       return gen_pointer_arith(expr)
    end

    eval_expression(expr[:left])
    scratch = @ctx.acquire_scratch
    if scratch
      @emitter.mov_reg_reg(scratch, 0)
      eval_expression(expr[:right])
      @emitter.mov_reg_reg(2, 0) # RDX = Right
      @emitter.mov_reg_reg(0, scratch) # RAX = Left
      @ctx.release_scratch(scratch)
    else
      @emitter.push_reg(0)
      eval_expression(expr[:right])
      @emitter.mov_reg_reg(2, 0); @emitter.pop_reg(0)
    end

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
    eval_expression(base)
    scratch = @ctx.acquire_scratch
    if scratch
      @emitter.mov_reg_reg(scratch, 0)
      eval_expression(offset)
      @emitter.shl_rax_imm(3)
      @emitter.mov_reg_reg(2, 0) # RDX = Offset
      @emitter.mov_reg_reg(0, scratch) # RAX = Base
      @ctx.release_scratch(scratch)
    else
      @emitter.push_reg(0)
      eval_expression(offset); @emitter.shl_rax_imm(3)
      @emitter.mov_reg_reg(2, 0); @emitter.pop_reg(0)
    end
    expr[:op] == "+" ? @emitter.add_rax_rdx : @emitter.sub_rax_rdx
  end
end
