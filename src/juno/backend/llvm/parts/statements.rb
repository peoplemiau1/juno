module LLVMStatementGenerator
  def gen_statement(node)
    return if node.nil?
    @loop_stack ||= []
    case node[:type]
    when :assignment
      gen_assignment(node)
    when :array_decl
    when :array_assign
      val = eval_expr(node[:value])
      idx = eval_expr(node[:index])
      if @current_arrays && @current_arrays[node[:name]]
        size = @current_arrays[node[:name]]
        tmp_ptr = next_tmp
        @output << "  %#{tmp_ptr} = getelementptr inbounds [#{size} x i64], [#{size} x i64]* %#{node[:name]}, i64 0, i64 #{idx}\n"
        @output << "  store i64 #{val}, i64* %#{tmp_ptr}\n"
      else
        base = next_tmp
        @output << "  %#{base} = load i64, i64* %#{node[:name]}\n"
        offset = next_tmp
        @output << "  %#{offset} = mul i64 #{idx}, 8\n"
        addr = next_tmp
        @output << "  %#{addr} = add i64 %#{base}, %#{offset}\n"
        tmp_ptr = next_tmp
        @output << "  %#{tmp_ptr} = inttoptr i64 %#{addr} to i64*\n"
        @output << "  store i64 #{val}, i64* %#{tmp_ptr}\n"
      end
    when :deref_assign
      val = eval_expr(node[:value])
      ptr = eval_expr(node[:target])
      tmp_ptr = next_tmp
      @output << "  %#{tmp_ptr} = inttoptr i64 #{ptr} to i64*\n"
      @output << "  store i64 #{val}, i64* %#{tmp_ptr}\n"
    when :if_statement
      gen_if(node)
    when :while_statement
      gen_while(node)
    when :for_statement
      gen_for(node)
    when :increment
      gen_increment(node)
    when :break
      if @loop_stack && !@loop_stack.empty?
        @output << "  br label %#{@loop_stack.last[:break_label]}\n"
        dummy = next_label("break_dummy")
        @output << "#{dummy}:\n"
      end
    when :continue
      if @loop_stack && !@loop_stack.empty?
        @output << "  br label %#{@loop_stack.last[:continue_label]}\n"
        dummy = next_label("continue_dummy")
        @output << "#{dummy}:\n"
      end
    when :panic
      @output << "  call void @exit(i32 1)\n"
    when :todo
      @output << "  call void @exit(i32 2)\n"
    when :fn_call, :method_call
      eval_expr(node)
    when :match_expression
      eval_expr(node)
    when :insertC
      gen_llvm_insertC(node)
    when :return
      val = eval_expr(node[:expression] || {type: :literal, value: 0})
      @output << "  ret i64 #{val}\n"
    end
  end

  def gen_assignment(node)
    if node[:name].include?('.')
      parts = node[:name].split('.')
      receiver = parts[0]
      field_name = parts[1]
      struct_name = node[:struct_name] || find_struct_for_field(field_name)
      if struct_name
        ptr = next_tmp
        ptr_sigil = (@globals && @globals.key?(receiver)) ? "@" : "%"
        @output << "  %#{ptr} = load i64, i64* #{ptr_sigil}#{receiver}\n"
        struct_ptr = next_tmp
        @output << "  %#{struct_ptr} = inttoptr i64 %#{ptr} to %struct.#{struct_name}*\n"
        field_idx = @structs[struct_name][:fields].index(field_name)
        gep = next_tmp
        @output << "  %#{gep} = getelementptr inbounds %struct.#{struct_name}, %struct.#{struct_name}* %#{struct_ptr}, i32 0, i32 #{field_idx}\n"
        val = eval_expr(node[:expression])
        @output << "  store i64 #{val}, i64* %#{gep}\n"
      end
    else
      val = eval_expr(node[:expression])
      ptr_sigil = (@globals && @globals.key?(node[:name])) ? "@" : "%"
      @output << "  store i64 #{val}, i64* #{ptr_sigil}#{node[:name]}\n"
    end
  end

  def gen_if(node)
    cond = eval_expr(node[:condition])
    true_label = next_label("if_true")
    false_label = next_label("if_false")
    end_label = next_label("if_end")
    tmp = next_tmp
    @output << "  %#{tmp} = icmp ne i64 #{cond}, 0\n"
    @output << "  br i1 %#{tmp}, label %#{true_label}, label %#{node[:else_body] ? false_label : end_label}\n"
    @output << "#{true_label}:\n"
    node[:body].each { |s| gen_statement(s) }
    @output << "  br label %#{end_label}\n"
    if node[:else_body]
      @output << "#{false_label}:\n"
      node[:else_body].each { |s| gen_statement(s) }
      @output << "  br label %#{end_label}\n"
    end
    @output << "#{end_label}:\n"
  end

  def gen_while(node)
    @loop_stack ||= []
    start_label = next_label("while_start")
    body_label = next_label("while_body")
    end_label = next_label("while_end")
    @loop_stack << { break_label: end_label, continue_label: start_label }
    @output << "  br label %#{start_label}\n"
    @output << "#{start_label}:\n"
    cond = eval_expr(node[:condition])
    tmp = next_tmp
    @output << "  %#{tmp} = icmp ne i64 #{cond}, 0\n"
    @output << "  br i1 %#{tmp}, label %#{body_label}, label %#{end_label}\n"
    @output << "#{body_label}:\n"
    node[:body].each { |s| gen_statement(s) }
    @output << "  br label %#{start_label}\n"
    @output << "#{end_label}:\n"
    @loop_stack.pop
  end

  def gen_for(node)
    @loop_stack ||= []
    if node[:init]
      gen_statement(node[:init])
    end
    start_label = next_label("for_start")
    body_label = next_label("for_body")
    end_label = next_label("for_end")
    update_label = next_label("for_update")
    @loop_stack << { break_label: end_label, continue_label: update_label }
    @output << "  br label %#{start_label}\n"
    @output << "#{start_label}:\n"
    cond = eval_expr(node[:condition])
    tmp = next_tmp
    @output << "  %#{tmp} = icmp ne i64 #{cond}, 0\n"
    @output << "  br i1 %#{tmp}, label %#{body_label}, label %#{end_label}\n"
    @output << "#{body_label}:\n"
    node[:body].each { |s| gen_statement(s) }
    @output << "  br label %#{update_label}\n"
    @output << "#{update_label}:\n"
    if node[:update]
      gen_statement(node[:update])
    end
    @output << "  br label %#{start_label}\n"
    @output << "#{end_label}:\n"
    @loop_stack.pop
  end

  def gen_increment(node)
    val = next_tmp
    ptr_sigil = (@globals && @globals.key?(node[:name])) ? "@" : "%"
    @output << "  %#{val} = load i64, i64* #{ptr_sigil}#{node[:name]}\n"
    res = next_tmp
    if node[:op] == "++"
      @output << "  %#{res} = add i64 %#{val}, 1\n"
    else
      @output << "  %#{res} = sub i64 %#{val}, 1\n"
    end
    @output << "  store i64 %#{res}, i64* #{ptr_sigil}#{node[:name]}\n"
  end

  def collect_locals(nodes, locals, arrays)
    nodes.each do |node|
      next unless node.is_a?(Hash)
      if node[:type] == :assignment && !node[:name].include?('.')
        locals << node[:name]
      elsif node[:type] == :array_decl
        arrays[node[:name]] = node[:size]
      elsif node[:type] == :if_statement
        collect_locals(node[:body] || [], locals, arrays)
        collect_locals(node[:else_body] || [], locals, arrays)
      elsif node[:type] == :while_statement || node[:type] == :for_statement
        collect_locals(node[:body] || [], locals, arrays)
        if node[:type] == :for_statement
          if node[:init] && node[:init][:type] == :assignment
            locals << node[:init][:name]
          end
        end
      elsif node[:type] == :increment
        locals << node[:name]
      elsif node[:type] == :match_expression
        node[:cases].each do |c|
          collect_locals(c[:body] || [], locals, arrays)
          if c[:pattern][:type] == :bind_pattern
            locals << c[:pattern][:name]
          elsif c[:pattern][:type] == :variant_pattern
            (c[:pattern][:fields] || []).each { |f| locals << f }
          end
        end
      end
    end
    arrays.each_key { |k| locals.delete(k) }
  end

  def gen_llvm_match(node)
    val = eval_expr(node[:expression])
    end_label = next_label("match_end")
    result_var = next_tmp
    @output << "  %#{result_var} = alloca i64, align 8\n"
    node[:cases].each_with_index do |c, idx|
      next_case_label = next_label("match_case_#{idx}_next")
      body_label = next_label("match_case_#{idx}_body")
      cond = check_llvm_pattern(val, c[:pattern])
      @output << "  br i1 #{cond}, label %#{body_label}, label %#{next_case_label}\n"
      @output << "#{body_label}:\n"
      bind_llvm_pattern_vars(val, c[:pattern])
      if c[:body].is_a?(Array)
        c[:body].each { |s| gen_statement(s) }
        @output << "  store i64 0, i64* %#{result_var}, align 8\n"
      else
        body_val = eval_expr(c[:body])
        @output << "  store i64 #{body_val}, i64* %#{result_var}, align 8\n"
      end
      @output << "  br label %#{end_label}\n"
      @output << "#{next_case_label}:\n"
    end
    @output << "  br label %#{end_label}\n"
    @output << "#{end_label}:\n"
    res = next_tmp
    @output << "  %#{res} = load i64, i64* %#{result_var}, align 8\n"
    "%#{res}"
  end

  def check_llvm_pattern(val, pattern)
    case pattern[:type]
    when :wildcard_pattern
      "true"
    when :literal_pattern
      lit_val = pattern[:value].is_a?(TrueClass) ? "1" : (pattern[:value].is_a?(FalseClass) ? "0" : pattern[:value].to_s)
      cmp = next_tmp
      @output << "  %#{cmp} = icmp eq i64 #{val}, #{lit_val}\n"
      "%#{cmp}"
    when :bind_pattern
      "true"
    when :variant_pattern
      tmp_p = next_tmp
      @output << "  %#{tmp_p} = inttoptr i64 #{val} to i64*\n"
      tag_val = next_tmp
      @output << "  %#{tag_val} = load i64, i64* %#{tmp_p}, align 8\n"
      enum_info = @enums[pattern[:enum]]
      variant_info = enum_info[:variants][pattern[:variant]]
      cmp = next_tmp
      @output << "  %#{cmp} = icmp eq i64 %#{tag_val}, #{variant_info[:tag]}\n"
      "%#{cmp}"
    else
      "true"
    end
  end

  def bind_llvm_pattern_vars(val, pattern)
    if pattern[:type] == :bind_pattern
      @output << "  store i64 #{val}, i64* %#{pattern[:name]}, align 8\n"
    elsif pattern[:type] == :variant_pattern
      (pattern[:fields] || []).each_with_index do |f_name, i|
        tmp_i8 = next_tmp
        @output << "  %#{tmp_i8} = inttoptr i64 #{val} to i8*\n"
        tmp_gep = next_tmp
        offset = 8 + i * 8
        @output << "  %#{tmp_gep} = getelementptr i8, i8* %#{tmp_i8}, i64 #{offset}\n"
        tmp_cast = next_tmp
        @output << "  %#{tmp_cast} = bitcast i8* %#{tmp_gep} to i64*\n"
        field_val = next_tmp
        @output << "  %#{field_val} = load i64, i64* %#{tmp_cast}, align 8\n"
        @output << "  store i64 %#{field_val}, i64* %#{f_name}, align 8\n"
      end
    end
  end

  def gen_llvm_match(node)
    val = eval_expr(node[:expression])
    end_label = next_label("match_end")
    result_var = next_tmp
    @output << "  %#{result_var} = alloca i64, align 8\n"
    node[:cases].each_with_index do |c, idx|
      next_case_label = next_label("match_case_#{idx}_next")
      body_label = next_label("match_case_#{idx}_body")
      cond = check_llvm_pattern(val, c[:pattern])
      @output << "  br i1 #{cond}, label %#{body_label}, label %#{next_case_label}\n"
      @output << "#{body_label}:\n"
      bind_llvm_pattern_vars(val, c[:pattern])
      if c[:body].is_a?(Array)
        c[:body].each { |s| gen_statement(s) }
        @output << "  store i64 0, i64* %#{result_var}, align 8\n"
      else
        body_val = eval_expr(c[:body])
        @output << "  store i64 #{body_val}, i64* %#{result_var}, align 8\n"
      end
      @output << "  br label %#{end_label}\n"
      @output << "#{next_case_label}:\n"
    end
    @output << "  br label %#{end_label}\n"
    @output << "#{end_label}:\n"
    res = next_tmp
    @output << "  %#{res} = load i64, i64* %#{result_var}, align 8\n"
    "%#{res}"
  end

  def gen_llvm_insertC(node)
    raw_content = node[:content] || ""
    bytes = raw_content.scan(/0x[0-9a-fA-F]+|\d+/).map { |b|
      b.start_with?("0x") ? b.to_i(16) : b.to_i
    }
    return if bytes.empty?
    byte_str = bytes.map { |b| "0x%02X" % b }.join(", ")
    asm_instruction = ".byte #{byte_str}"
    
    first_param = @current_function[:params]&.[](0)
    if first_param
      tmp_load = next_tmp
      @output << "  %#{tmp_load} = load i64, i64* %#{first_param}\n"
      @output << "  call void asm sideeffect \"#{asm_instruction}\", \"{rdi}\"(i64 %#{tmp_load})\n"
    else
      @output << "  call void asm sideeffect \"#{asm_instruction}\", \"\"()\n"
    end
  end
end
