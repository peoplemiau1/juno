module LLVMExpressionGenerator
  def eval_expr(node)
    return "0" if node.nil?
    case node[:type]
    when :literal
      node[:value].to_s
    when :float_literal
      [node[:value].to_f].pack("E").unpack1("Q<").to_s
    when :string_literal
      id = @strings[node[:value]]
      tmp = next_tmp
      len = node[:value].bytesize + 1
      @output << "  %#{tmp} = getelementptr inbounds [#{len} x i8], [#{len} x i8]* @#{id}, i64 0, i64 0\n"
      tmp_ptr = next_tmp
      @output << "  %#{tmp_ptr} = ptrtoint i8* %#{tmp} to i64\n"
      "%#{tmp_ptr}"
    when :variable
      if @structs && @structs.key?(node[:name])
        size = @structs[node[:name]][:fields].size * 8
        tmp = next_tmp
        @output << "  %#{tmp} = call i64 @malloc(i64 #{size})\n"
        "%#{tmp}"
      elsif @current_arrays && @current_arrays[node[:name]]
        size = @current_arrays[node[:name]]
        gep = next_tmp
        @output << "  %#{gep} = getelementptr inbounds [#{size} x i64], [#{size} x i64]* %#{node[:name]}, i64 0, i64 0\n"
        tmp_ptr = next_tmp
        @output << "  %#{tmp_ptr} = ptrtoint i64* %#{gep} to i64\n"
        "%#{tmp_ptr}"
      elsif @globals && @globals.key?(node[:name])
        tmp = next_tmp
        @output << "  %#{tmp} = load i64, i64* @#{node[:name]}\n"
        "%#{tmp}"
      elsif fn_node = @ast.find { |n| (n[:type] == :function_definition || n[:type] == :extern_definition) && n[:name] == node[:name] }
        params_count = fn_node[:params] ? fn_node[:params].length : 0
        args_types = Array.new(params_count, "i64").join(", ")
        fn_type = "i64 (#{args_types})*"
        
        tmp = next_tmp
        @output << "  %#{tmp} = ptrtoint #{fn_type} @#{node[:name].gsub('.', '_')} to i64\n"
        "%#{tmp}"
      else
        tmp = next_tmp
        @output << "  %#{tmp} = load i64, i64* %#{node[:name]}\n"
        "%#{tmp}"
      end
    when :fn_call, :method_call
      gen_call(node)
    when :binary_op
      gen_binary_op(node)
    when :unary_op
      gen_unary_op(node)
    when :dereference
      val = eval_expr(node[:operand] || node[:expression])
      tmp_ptr = next_tmp
      @output << "  %#{tmp_ptr} = inttoptr i64 #{val} to i64*\n"
      tmp = next_tmp
      @output << "  %#{tmp} = load i64, i64* %#{tmp_ptr}\n"
      "%#{tmp}"
    when :address_of
      operand = node[:operand] || node[:expression]
      case operand[:type]
      when :variable
        tmp = next_tmp
        ptr_sigil = (@globals && @globals.key?(operand[:name])) ? "@" : "%"
        @output << "  %#{tmp} = ptrtoint i64* #{ptr_sigil}#{operand[:name]} to i64\n"
        "%#{tmp}"
      when :array_access
        idx = eval_expr(operand[:index])
        gep = next_tmp
        if @current_arrays && @current_arrays[operand[:name]]
          size = @current_arrays[operand[:name]]
          @output << "  %#{gep} = getelementptr inbounds [#{size} x i64], [#{size} x i64]* %#{operand[:name]}, i64 0, i64 #{idx}\n"
        else
          base = next_tmp
          ptr_sigil = (@globals && @globals.key?(operand[:name])) ? "@" : "%"
          @output << "  %#{base} = load i64, i64* #{ptr_sigil}#{operand[:name]}\n"
          offset = next_tmp
          @output << "  %#{offset} = mul i64 #{idx}, 8\n"
          addr = next_tmp
          @output << "  %#{addr} = add i64 %#{base}, %#{offset}\n"
          @output << "  %#{gep} = inttoptr i64 %#{addr} to i64*\n"
        end
        res = next_tmp
        @output << "  %#{res} = ptrtoint i64* %#{gep} to i64\n"
        "%#{res}"
      when :member_access
        receiver_name = operand[:receiver]
        member = operand[:member]
        struct_name = operand[:struct_name] || find_struct_for_field(member)
        if struct_name
          ptr = next_tmp
          ptr_sigil = (@globals && @globals.key?(receiver_name)) ? "@" : "%"
          @output << "  %#{ptr} = load i64, i64* #{ptr_sigil}#{receiver_name}\n"
          struct_ptr = next_tmp
          @output << "  %#{struct_ptr} = inttoptr i64 %#{ptr} to %struct.#{struct_name}*\n"
          field_idx = @structs[struct_name][:fields].index(member)
          gep = next_tmp
          @output << "  %#{gep} = getelementptr inbounds %struct.#{struct_name}, %struct.#{struct_name}* %#{struct_ptr}, i32 0, i32 #{field_idx}\n"
          res = next_tmp
          @output << "  %#{res} = ptrtoint i64* %#{gep} to i64\n"
          return "%#{res}"
        end
        "0"
      else
        eval_expr(operand)
      end
    when :array_access
      idx = eval_expr(node[:index])
      gep = next_tmp
      if @current_arrays && @current_arrays[node[:name]]
        size = @current_arrays[node[:name]]
        @output << "  %#{gep} = getelementptr inbounds [#{size} x i64], [#{size} x i64]* %#{node[:name]}, i64 0, i64 #{idx}\n"
      else
        base = next_tmp
        ptr_sigil = (@globals && @globals.key?(node[:name])) ? "@" : "%"
        @output << "  %#{base} = load i64, i64* #{ptr_sigil}#{node[:name]}\n"
        offset = next_tmp
        @output << "  %#{offset} = mul i64 #{idx}, 8\n"
        addr = next_tmp
        @output << "  %#{addr} = add i64 %#{base}, %#{offset}\n"
        @output << "  %#{gep} = inttoptr i64 %#{addr} to i64*\n"
      end
      res = next_tmp
      @output << "  %#{res} = load i64, i64* %#{gep}\n"
      "%#{res}"
    when :cast
      eval_expr(node[:expression])
    when :member_access
      gen_member_access(node)
    else
      "0"
    end
  end

  def gen_unary_op(node)
    val = eval_expr(node[:value] || node[:operand])
    case node[:op]
    when "*"
      tmp_ptr = next_tmp
      @output << "  %#{tmp_ptr} = inttoptr i64 #{val} to i64*\n"
      tmp = next_tmp
      @output << "  %#{tmp} = load i64, i64* %#{tmp_ptr}\n"
      "%#{tmp}"
    when "&"
      tmp = next_tmp
      @output << "  %#{tmp} = ptrtoint i64* %#{(node[:value] || node[:operand])[:name]} to i64\n"
      "%#{tmp}"
    else
      val
    end
  end

  def gen_binary_op(node)
    l = eval_expr(node[:left])
    r = eval_expr(node[:right])
    
    l_type = node[:left][:inferred_type] || "int"
    r_type = node[:right][:inferred_type] || "int"
    
    is_string = (l_type == "str" || l_type == "string" || 
                 r_type == "str" || r_type == "string" ||
                 node[:left][:type] == :string_literal || node[:right][:type] == :string_literal)
    
    if node[:op] == "+" && is_string
       tmp = next_tmp
       @output << "  %#{tmp} = call i64 @concat(i64 #{l}, i64 #{r})\n"
       return "%#{tmp}"
    end

    is_float = (l_type == "float" || r_type == "float" ||
                node[:left][:type] == :float_literal || node[:right][:type] == :float_literal)

    tmp = next_tmp
    if is_float
      t_l = next_tmp
      @output << "  %#{t_l} = bitcast i64 #{l} to double\n"
      t_r = next_tmp
      @output << "  %#{t_r} = bitcast i64 #{r} to double\n"
      
      case node[:op]
      when "+"
        t_res = next_tmp
        @output << "  %#{t_res} = fadd double %#{t_l}, %#{t_r}\n"
        @output << "  %#{tmp} = bitcast double %#{t_res} to i64\n"
      when "-"
        t_res = next_tmp
        @output << "  %#{t_res} = fsub double %#{t_l}, %#{t_r}\n"
        @output << "  %#{tmp} = bitcast double %#{t_res} to i64\n"
      when "*"
        t_res = next_tmp
        @output << "  %#{t_res} = fmul double %#{t_l}, %#{t_r}\n"
        @output << "  %#{tmp} = bitcast double %#{t_res} to i64\n"
      when "/"
        t_res = next_tmp
        @output << "  %#{t_res} = fdiv double %#{t_l}, %#{t_r}\n"
        @output << "  %#{tmp} = bitcast double %#{t_res} to i64\n"
      when "<=", ">=", "==", "!=", "<", ">"
        op_map = { "==" => "oeq", "!=" => "one", "<" => "olt", ">" => "ogt", "<=" => "ole", ">=" => "oge" }
        cmp = next_tmp
        @output << "  %#{cmp} = fcmp #{op_map[node[:op]]} double %#{t_l}, %#{t_r}\n"
        @output << "  %#{tmp} = zext i1 %#{cmp} to i64\n"
      end
    else
      case node[:op]
      when "+" then @output << "  %#{tmp} = add i64 #{l}, #{r}\n"
      when "-" then @output << "  %#{tmp} = sub i64 #{l}, #{r}\n"
      when "*" then @output << "  %#{tmp} = mul i64 #{l}, #{r}\n"
      when "/" then @output << "  %#{tmp} = sdiv i64 #{l}, #{r}\n"
      when "%" then @output << "  %#{tmp} = srem i64 #{l}, #{r}\n"
      when "<<" then @output << "  %#{tmp} = shl i64 #{l}, #{r}\n"
      when ">>" then @output << "  %#{tmp} = ashr i64 #{l}, #{r}\n"
      when "&" then @output << "  %#{tmp} = and i64 #{l}, #{r}\n"
      when "|" then @output << "  %#{tmp} = or i64 #{l}, #{r}\n"
      when "^" then @output << "  %#{tmp} = xor i64 #{l}, #{r}\n"
      when "<=", ">=", "==", "!=", "<", ">"
        op_map = { "<=" => "sle", ">=" => "sge", "==" => "eq", "!=" => "ne", "<" => "slt", ">" => "sgt" }
        cmp = next_tmp
        @output << "  %#{cmp} = icmp #{op_map[node[:op]]} i64 #{l}, #{r}\n"
        @output << "  %#{tmp} = zext i1 %#{cmp} to i64\n"
      when "||", "&&"
        l_bool = next_tmp
        r_bool = next_tmp
        res_bool = next_tmp
        @output << "  %#{l_bool} = icmp ne i64 #{l}, 0\n"
        @output << "  %#{r_bool} = icmp ne i64 #{r}, 0\n"
        @output << "  %#{res_bool} = #{node[:op] == '||' ? 'or' : 'and'} i1 %#{l_bool}, %#{r_bool}\n"
        @output << "  %#{tmp} = zext i1 %#{res_bool} to i64\n"
      end
    end
    "%#{tmp}"
  end

  def gen_member_access(node)
    receiver_name = node[:receiver]
    member = node[:member]
    struct_name = node[:struct_name] || find_struct_for_field(member)
    if struct_name
      ptr = next_tmp
      @output << "  %#{ptr} = load i64, i64* %#{receiver_name}\n"
      struct_ptr = next_tmp
      @output << "  %#{struct_ptr} = inttoptr i64 %#{ptr} to %struct.#{struct_name}*\n"
      field_idx = @structs[struct_name][:fields].index(member)
      gep = next_tmp
      @output << "  %#{gep} = getelementptr inbounds %struct.#{struct_name}, %struct.#{struct_name}* %#{struct_ptr}, i32 0, i32 #{field_idx}\n"
      res = next_tmp
      @output << "  %#{res} = load i64, i64* %#{gep}\n"
      return "%#{res}"
    end
    "0"
  end

  def find_struct_for_field(field_name)
    @structs.each { |name, info| return name if info[:fields].include?(field_name) }
    nil
  end
end
