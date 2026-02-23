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
    when :match_expression then gen_match(expr)
    when :panic then gen_panic(expr)
    when :todo then gen_todo(expr)
    when :cast then gen_cast(expr)
    when :anonymous_function then gen_anonymous_fn(expr)
    else
      raise "Unknown expression type in eval_expression: #{expr[:type].inspect}"
    end
  end

  def gen_match(node)
    eval_expression(node[:expression])
    @emitter.push_reg(0) # Store matched value on stack
    @ctx.stack_depth += 8

    end_patches = []

    node[:cases].each do |c|
      @emitter.mov_rax_rsp_disp8(0) # Load matched value back
      @emitter.mov_reg_reg(2, 0) # RDX = Matched value

      gen_pattern_check(c[:pattern])
      @emitter.test_rax_rax
      next_case_patch = @emitter.je_rel32

      # Match body
      if c[:body].is_a?(Array)
        c[:body].each { |s| process_node(s) }
      else
        eval_expression(c[:body])
      end

      end_patches << @emitter.jmp_rel32
      @emitter.patch_je(next_case_patch, @emitter.current_pos)
    end

    # Label for jumps from inside cases
    pop_pos = @emitter.current_pos
    @emitter.pop_reg(2) # Pop matched value into RDX to keep RAX (result)
    @ctx.stack_depth -= 8

    end_pos = @emitter.current_pos
    end_patches.each { |p| @emitter.patch_jmp(p, pop_pos) }
  end

  def gen_pattern_check(pattern)
    case pattern[:type]
    when :wildcard_pattern
      @emitter.mov_rax(1)
    when :literal_pattern
      @emitter.mov_reg_imm(1, pattern[:value].is_a?(TrueClass) ? 1 : (pattern[:value].is_a?(FalseClass) ? 0 : pattern[:value]))
      @emitter.cmp_rax_rdx("==")
    when :bind_pattern
      # Bind matched value to variable name
      if @ctx.in_register?(pattern[:name])
        reg = @emitter.class.reg_code(@ctx.get_register(pattern[:name]))
        @emitter.mov_reg_reg(reg, 2) # 2 is RDX which has the value
      else
        off = @ctx.get_variable_offset(pattern[:name])
        @emitter.mov_stack_reg_val(off, 2)
      end
      @emitter.mov_rax(1)
    when :variant_pattern
      enum_info = @ctx.enums[pattern[:enum]]
      variant_info = enum_info[:variants][pattern[:variant]]

      # Check tag (at [RDX])
      @emitter.mov_rax_mem_idx(2, 0) # RAX = [RDX]
      @emitter.mov_reg_imm(6, variant_info[:tag]) # RSI = target tag
      @emitter.cmp_rax_rsi("==")

      # If match, bind fields
      # We need a conditional jump to bind only if tag matches
      skip_bind = @emitter.je_rel32 # Wait, je means match, so we should jne to skip
      # Actually cmp_rax_rsi returns 1 in RAX if equal.
      # Let's use internal emitter methods if available or just test rax
      @emitter.test_rax_rax
      skip_bind = @emitter.je_rel32

      unwrap_pattern(2, pattern[:fields] || [])

      @emitter.mov_rax(1)
      @emitter.patch_je(skip_bind, @emitter.current_pos)
    else
      @emitter.mov_rax(0)
    end
  end

  def unwrap_pattern(ptr_reg, fields)
    fields.each_with_index do |f_name, i|
      # Field i is at [ptr_reg + 8 + i*8]
      @emitter.mov_rax_mem_idx(ptr_reg, 8 + i * 8)
      if @ctx.in_register?(f_name)
        reg = @emitter.class.reg_code(@ctx.get_register(f_name))
        @emitter.mov_reg_reg(reg, 0)
      else
        off = @ctx.get_variable_offset(f_name)
        @emitter.mov_stack_reg_val(off, 0)
      end
    end
  end

  def gen_panic(node)
    @emitter.mov_rax(1) # exit code
    @emitter.emit_sys_exit_rax
  end

  def gen_todo(node)
    @emitter.mov_rax(2) # exit code
    @emitter.emit_sys_exit_rax
  end

  def gen_cast(node)
    eval_expression(node[:expression])
    # Juno currently is mostly 64-bit, but we can add truncation if needed
  end

  def gen_anonymous_fn(node)
    label = "anon_fn_#{@ctx.object_id}_#{@emitter.current_pos}"
    @linker.declare_function(label)

    skip_patch = @emitter.jmp_rel32

    old_ctx = @ctx
    @ctx = CodegenContext.new(@arch)
    old_ctx.globals.each { |k, v| @ctx.register_global(k, v) }
    @ctx.structs = old_ctx.structs
    @ctx.unions = old_ctx.unions
    @ctx.enums = old_ctx.enums

    @linker.register_function(label, @emitter.current_pos)

    anon_node = {
      type: :function_definition,
      name: label,
      params: node[:params] || [],
      param_types: node[:param_types] || {},
      body: node[:body]
    }

    gen_function_internal(anon_node)

    @ctx = old_ctx
    @emitter.patch_jmp(skip_patch, @emitter.current_pos)
    @emitter.emit_load_address(label, @linker)
  end

  def has_fn_call?(node)
    return false unless node.is_a?(Hash)
    return true if node[:type] == :fn_call
    node.any? { |k, v| v.is_a?(Hash) ? has_fn_call?(v) : (v.is_a?(Array) ? v.any?{|i| has_fn_call?(i)} : false) }
  end

  def eval_binary_op(expr)
    if (expr[:op] == "+" || expr[:op] == "<>") && (expr[:left][:type] == :string_literal || expr[:right][:type] == :string_literal)
       return gen_fn_call({ type: :fn_call, name: "concat", args: [expr[:left], expr[:right]] })
    end
    if (expr[:op] == "+" || expr[:op] == "-") && (pointer_node?(expr[:left]) || pointer_node?(expr[:right]))
       return gen_pointer_arith(expr)
    end

    eval_expression(expr[:left])
    # Disable scratch registers if right side contains a function call
    scratch = has_fn_call?(expr[:right]) ? nil : @ctx.acquire_scratch

    if scratch
      @emitter.mov_reg_reg(scratch, 0)
      eval_expression(expr[:right])
      @emitter.mov_reg_reg(2, 0) # RDX = Right
      @emitter.mov_reg_reg(0, scratch) # RAX = Left
      @ctx.release_scratch(scratch)
    else
      @emitter.push_reg(0)
      @ctx.stack_depth += 8
      eval_expression(expr[:right])
      @emitter.mov_reg_reg(2, 0); @emitter.pop_reg(0)
      @ctx.stack_depth -= 8
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
    when "&&" then gen_logical_and(expr)
    when "||" then gen_logical_or(expr)
    end
  end

  def gen_logical_and(node)
    eval_expression(node[:left])
    @emitter.test_rax_rax
    exit_patch = @emitter.je_rel32
    eval_expression(node[:right])
    @emitter.test_rax_rax
    @emitter.mov_rax(0)
    @emitter.emit([0x0f, 0x95, 0xc0]) # setne al
    @emitter.patch_je(exit_patch, @emitter.current_pos)
  end

  def gen_logical_or(node)
    eval_expression(node[:left])
    @emitter.test_rax_rax
    success_patch = @emitter.jne_rel32
    eval_expression(node[:right])
    @emitter.test_rax_rax
    @emitter.mov_rax(0)
    @emitter.emit([0x0f, 0x95, 0xc0]) # setne al
    @emitter.patch_jne(success_patch, @emitter.current_pos)
  end

  def pointer_node?(node)
    return false unless node.is_a?(Hash)
    node[:type] == :address_of || (node[:type] == :variable && @ctx.var_is_ptr[node[:name]])
  end

  def gen_pointer_arith(expr)
    base = pointer_node?(expr[:left]) ? expr[:left] : expr[:right]
    offset = (base == expr[:left]) ? expr[:right] : expr[:left]
    eval_expression(base)
    scratch = has_fn_call?(offset) ? nil : @ctx.acquire_scratch
    if scratch
      @emitter.mov_reg_reg(scratch, 0)
      eval_expression(offset)
      @emitter.shl_rax_imm(3)
      @emitter.mov_reg_reg(2, 0) # RDX = Offset
      @emitter.mov_reg_reg(0, scratch) # RAX = Base
      @ctx.release_scratch(scratch)
    else
      @emitter.push_reg(0)
      @ctx.stack_depth += 8
      eval_expression(offset); @emitter.shl_rax_imm(3)
      @emitter.mov_reg_reg(2, 0); @emitter.pop_reg(0)
      @ctx.stack_depth -= 8
    end
    expr[:op] == "+" ? @emitter.add_rax_rdx : @emitter.sub_rax_rdx
  end
end
