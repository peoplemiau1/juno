module GeneratorLogic
  def process_node(node)
    case node[:type]
    when :assignment then process_assignment(node)
    when :deref_assign then process_deref_assign(node)
    when :fn_call then gen_fn_call(node)
    when :return
       eval_expression(node[:expression])
       used_regs = @ctx.used_callee_saved; padding = (used_regs.length % 2 == 1) ? 8 : 0
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
      st_name = node[:expression][:name]; st_size = @ctx.structs[st_name][:size]
       @ctx.stack_ptr += st_size; d_off = @ctx.stack_ptr
       var_off = @ctx.declare_variable(node[:name]); @ctx.var_types[node[:name]] = st_name; @ctx.var_is_ptr[node[:name]] = true
       @emitter.lea_reg_stack(@emitter.class::REG_RAX, d_off)
       @emitter.mov_stack_reg_val(var_off, @emitter.class::REG_RAX); return
    end
    eval_expression(node[:expression])
    if node[:name].include?('.')
       save_member_rax(node[:name])
    else
       @ctx.var_types[node[:name]] = node[:var_type] if node[:var_type]
       if @ctx.in_register?(node[:name])
         reg = @emitter.class.reg_code(@ctx.get_register(node[:name])); @emitter.mov_reg_from_rax(reg)
       else
         off = @ctx.variables[node[:name]] || @ctx.declare_variable(node[:name])
         @emitter.mov_stack_reg_val(off, @emitter.class::REG_RAX)
       end
    end
  end

  def gen_if(node)
    eval_expression(node[:condition]); patch_pos = @emitter.je_rel32
    node[:body].each { |c| process_node(c) }
    end_patch_pos = node[:else_body] ? @emitter.jmp_rel32 : nil
    @emitter.patch_je(patch_pos, @emitter.current_pos)
    if node[:else_body]
       node[:else_body].each { |c| process_node(c) }
       @emitter.patch_jmp(end_patch_pos, @emitter.current_pos)
    end
  end

  def gen_while(node)
    loop_start = @emitter.current_pos; eval_expression(node[:condition]); patch_pos = @emitter.je_rel32
    node[:body].each { |c| process_node(c) }
    jmp_back_pos = @emitter.jmp_rel32; @emitter.patch_jmp(jmp_back_pos, loop_start); @emitter.patch_je(patch_pos, @emitter.current_pos)
  end

  def gen_increment(node)
    if @ctx.in_register?(node[:name])
      reg = @emitter.class.reg_code(@ctx.get_register(node[:name]))
      if @arch == :aarch64
        @emitter.emit32(node[:op] == "++" ? (0x91000400 | (reg << 5) | reg) : (0xd1000400 | (reg << 5) | reg))
      else
        if node[:op] == "++"
          reg >= 8 ? @emitter.emit([0x41, 0xff, 0xc0 + (reg - 8)]) : @emitter.emit([0x48, 0xff, 0xc0 + reg])
        else
          reg >= 8 ? @emitter.emit([0x41, 0xff, 0xc8 + (reg - 8)]) : @emitter.emit([0x48, 0xff, 0xc8 + reg])
        end
      end
    else
      off = @ctx.get_variable_offset(node[:name]); @emitter.mov_reg_stack_val(@emitter.class::REG_RAX, off)
      if @arch == :aarch64
        @emitter.emit32(node[:op] == "++" ? 0x91000400 : 0xd1000400)
      else
        @emitter.emit(node[:op] == "++" ? [0x48, 0xff, 0xc0] : [0x48, 0xff, 0xc8])
      end
      @emitter.mov_stack_reg_val(off, @emitter.class::REG_RAX)
    end
  end

  def gen_for(node)
    process_node(node[:init]); loop_start = @emitter.current_pos; eval_expression(node[:condition]); patch_pos = @emitter.je_rel32
    node[:body].each { |c| process_node(c) }; process_node(node[:update])
    jmp_back_pos = @emitter.jmp_rel32; @emitter.patch_jmp(jmp_back_pos, loop_start); @emitter.patch_je(patch_pos, @emitter.current_pos)
  end

  def eval_expression(expr)
    case expr[:type]
    when :literal then @emitter.mov_rax(expr[:value])
    when :variable
      if @ctx.in_register?(expr[:name])
        @emitter.mov_rax_from_reg(@emitter.class.reg_code(@ctx.get_register(expr[:name])))
      elsif @ctx.variables.key?(expr[:name])
        @emitter.mov_reg_stack_val(@emitter.class::REG_RAX, @ctx.variables[expr[:name]])
      else
        if @arch == :aarch64
          @emitter.emit32(0x10000000); @linker.add_fn_patch(@emitter.current_pos - 4, expr[:name], :aarch64_adr)
        else
          @emitter.emit([0x48, 0x8d, 0x05]); @linker.add_fn_patch(@emitter.current_pos, expr[:name], :rel32); @emitter.emit([0x00, 0x00, 0x00, 0x00])
        end
      end
    when :binary_op
      if string_concat?(expr) then gen_fn_call({ type: :fn_call, name: "concat", args: [expr[:left], expr[:right]] })
      elsif pointer_arith?(expr) then gen_pointer_arith(expr)
      else
        eval_expression(expr[:left]); @emitter.push_reg(@emitter.class::REG_RAX)
        eval_expression(expr[:right]); @emitter.pop_reg(@emitter.class::REG_RDX)
        if @arch == :aarch64
          @emitter.mov_reg_reg(9, 0); @emitter.mov_reg_reg(0, 2); @emitter.mov_reg_reg(2, 9)
        else
          @emitter.emit([0x48, 0x92])
        end
        case expr[:op]
        when "+" then @emitter.add_rax_rdx
        when "-" then @emitter.sub_rax_rdx
        when "*" then expr[:shift_opt] ? @emitter.shl_rax_imm(expr[:shift_opt]) : @emitter.imul_rax_rdx
        when "/" then expr[:shift_opt] ? @emitter.shr_rax_imm(expr[:shift_opt]) : @emitter.div_rax_by_rdx
        when "%" then @emitter.mod_rax_by_rdx
        when "==", "!=", "<", ">", "<=", ">=" then @emitter.cmp_rax_rdx(expr[:op])
        when "&" then @emitter.and_rax_rdx
        when "|" then @emitter.or_rax_rdx
        when "^" then @emitter.xor_rax_rdx
        when "<<"
          if @arch == :aarch64 then @emitter.emit32(0x9ac22000)
          else @emitter.emit([0x48, 0x89, 0xd1, 0x48, 0xd3, 0xe0])
          end
        when ">>"
          if @arch == :aarch64 then @emitter.emit32(0x9ac22400)
          else @emitter.emit([0x48, 0x89, 0xd1, 0x48, 0xd3, 0xe8])
          end
        end
      end
    when :member_access then load_member_rax("#{expr[:receiver]}.#{expr[:member]}")
    when :fn_call then gen_fn_call(expr)
    when :array_access then gen_array_access(expr)
    when :string_literal then gen_string_literal(expr)
    when :address_of then gen_address_of(expr)
    when :dereference then gen_dereference(expr)
    when :unary_op then gen_unary_op(expr)
    end
  end

  def gen_unary_op(expr)
    eval_expression(expr[:operand])
    case expr[:op]
    when '~' then @emitter.not_rax
    when '!'
      if @arch == :aarch64 then @emitter.emit32(0xf100001f); @emitter.emit32(0x1a9f17e0)
      else @emitter.test_rax_rax; @emitter.emit([0x0f, 0x94, 0xc0, 0x48, 0x0f, 0xb6, 0xc0])
      end
    end
  end

  def load_member_rax(full)
    v, f = full.split('.'); st = @ctx.var_types[v]; f_off = @ctx.structs[st][:fields][f]
    @emitter.mov_rax_from_reg(@emitter.class.reg_code(@ctx.get_register(v))) if @ctx.in_register?(v)
    @emitter.mov_reg_stack_val(@emitter.class::REG_RAX, @ctx.variables[v]) unless @ctx.in_register?(v)
    @emitter.mov_rax_mem(f_off)
  end

  def save_member_rax(full)
     v, f = full.split('.'); st = @ctx.var_types[v]; f_off = @ctx.structs[st][:fields][f]
     @emitter.mov_r11_rax
     @emitter.mov_rax_from_reg(@emitter.class.reg_code(@ctx.get_register(v))) if @ctx.in_register?(v)
     @emitter.mov_reg_stack_val(@emitter.class::REG_RAX, @ctx.variables[v]) unless @ctx.in_register?(v)
     @emitter.mov_mem_r11(f_off)
  end

  def gen_insertC(node)
    node[:content].strip.split(/[\s,]+/).each { |t| @emitter.emit([t.sub(/^0x/i, '').to_i(16)]) unless t.empty? }
  end

  def gen_array_decl(node)
    name = node[:name]; size = node[:size]; arr_info = @ctx.declare_array(name, size); @emitter.mov_rax(0)
    size.times { |i| @emitter.mov_stack_reg_val(arr_info[:base_offset] - (i * 8), @emitter.class::REG_RAX) }
    @emitter.lea_reg_stack(@emitter.class::REG_RAX, arr_info[:base_offset])
    @emitter.mov_stack_reg_val(arr_info[:ptr_offset], @emitter.class::REG_RAX)
  end

  def gen_array_assign(node)
    name = node[:name]; eval_expression(node[:value]); @emitter.mov_r11_rax
    eval_expression(node[:index]); @emitter.shl_rax_imm(3)
    arr_info = @ctx.get_array(name)
    @emitter.push_reg(@emitter.class::REG_RAX)
    if arr_info then @emitter.mov_reg_stack_val(@emitter.class::REG_RAX, arr_info[:ptr_offset])
    else @emitter.mov_reg_stack_val(@emitter.class::REG_RAX, @ctx.get_variable_offset(name))
    end
    @emitter.pop_reg(@emitter.class::REG_RDX); @emitter.add_rax_rdx
    @arch == :aarch64 ? @emitter.emit32(0xf9000009) : @emitter.emit([0x4c, 0x89, 0x18])
  end

  def gen_array_access(node)
    name = node[:name]; eval_expression(node[:index]); @emitter.shl_rax_imm(3); arr_info = @ctx.get_array(name)
    @emitter.push_reg(@emitter.class::REG_RAX)
    if arr_info then @emitter.mov_reg_stack_val(@emitter.class::REG_RAX, arr_info[:ptr_offset])
    else @emitter.mov_reg_stack_val(@emitter.class::REG_RAX, @ctx.get_variable_offset(name))
    end
    @emitter.pop_reg(@emitter.class::REG_RDX); @emitter.add_rax_rdx; @emitter.mov_rax_mem(0)
  end

  def gen_string_literal(node)
    label = @linker.add_string(node[:value])
    if @arch == :aarch64 then @emitter.emit32(0x10000000); @linker.add_data_patch(@emitter.current_pos - 4, label, :aarch64_adr)
    else @emitter.emit([0x48, 0x8d, 0x05]); @linker.add_data_patch(@emitter.current_pos, label, :rel32); @emitter.emit([0x00, 0x00, 0x00, 0x00])
    end
  end

  def gen_address_of(expr)
    operand = expr[:operand]
    if operand[:type] == :variable
       off = @ctx.get_variable_offset(operand[:name]); @emitter.lea_reg_stack(@emitter.class::REG_RAX, off)
    elsif operand[:type] == :array_access
      name = operand[:name]; eval_expression(operand[:index]); @emitter.shl_rax_imm(3)
      @emitter.push_reg(@emitter.class::REG_RAX); arr_info = @ctx.get_array(name)
      if arr_info then @emitter.mov_reg_stack_val(@emitter.class::REG_RAX, arr_info[:ptr_offset])
      else @emitter.mov_reg_stack_val(@emitter.class::REG_RAX, @ctx.get_variable_offset(name))
      end
      @emitter.pop_reg(@emitter.class::REG_RDX); @emitter.add_rax_rdx
    end
  end

  def gen_dereference(expr)
    eval_expression(expr[:operand]); @emitter.mov_rax_mem(0)
  end

  def process_deref_assign(node)
    eval_expression(node[:value]); @emitter.mov_r11_rax; eval_expression(node[:target])
    @arch == :aarch64 ? @emitter.emit32(0xf9000009) : @emitter.emit([0x4c, 0x89, 0x18])
  end

  def string_concat?(expr); expr[:op] == "+" && (string_node?(expr[:left]) || string_node?(expr[:right])); end
  def string_node?(node); node && node[:type] == :string_literal; end
  def pointer_arith?(expr); (expr[:op] == "+" || expr[:op] == "-") && (pointer_node?(expr[:left]) ^ pointer_node?(expr[:right])); end
  def pointer_node?(node); node.is_a?(Hash) && (node[:type] == :address_of || @ctx.var_is_ptr[node[:name]] == true); end

  def gen_pointer_arith(expr)
    base_ptr = pointer_node?(expr[:left]) ? expr[:left] : expr[:right]
    offset_expr = (base_ptr == expr[:left]) ? expr[:right] : expr[:left]
    eval_expression(base_ptr); @emitter.push_reg(@emitter.class::REG_RAX)
    eval_expression(offset_expr); @emitter.shl_rax_imm(3)
    @emitter.mov_reg_reg(@emitter.class::REG_RDX, @emitter.class::REG_RAX); @emitter.pop_reg(@emitter.class::REG_RBX)
    if expr[:op] == "+"
      if @arch == :aarch64 then @emitter.mov_reg_reg(0, 19); @emitter.add_rax_rdx
      else @emitter.emit([0x48, 0x01, 0xd8])
      end
    else
      if @arch == :aarch64 then @emitter.mov_reg_reg(0, 19); @emitter.sub_rax_rdx
      else @emitter.emit([0x48, 0x29, 0xd0])
      end
    end
  end
end
