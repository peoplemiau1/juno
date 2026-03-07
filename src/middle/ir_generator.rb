# ir_generator.rb - Translates Juno/Watt AST to Juno IR
require_relative "ir"

class IRGenerator
  def initialize
    @vreg_counter = 0
    @labels_counter = 0
    @ir = []
  end

  def generate(ast)
    @ir = []
    # Identify structs/unions for member access calculations
    @structs = {}
    @variables_to_types = {}
    ast.each do |node|
      if node[:type] == :struct_definition
        @structs[node[:name]] = { name: node[:name], fields: node[:fields] }
      elsif node[:type] == :extern_definition
        # Also track externs? No.
      end
    end

    ast.each { |node| process_top_level(node) }
    @ir
  end

  private

  def emit(op, *args, **metadata)
    @ir << JunoIR::Instruction.new(op, *args, **metadata)
  end

  def next_vreg; "v#{@vreg_counter += 1}"; end
  def next_label(prefix = "L"); "#{prefix}_#{@labels_counter += 1}"; end

  def process_top_level(node)
    case node[:type]
    when :function_definition
      emit(:LABEL, node[:name], type: :function, stack_size: node[:stack_size])

      # Map params to param_i vregs
      (node[:params] || []).each_with_index do |p, i|
        p_name = p.is_a?(Hash) ? p[:name] : p
        emit(:MOVE, p_name, "param_#{i}", inferred_type: (node[:param_types] && node[:param_types][p_name]) || "int")
      end

      # ALLOC/FREE handled by backend prologue/epilogue for now
      node[:body].each { |stmt| process_node(stmt) }
      emit(:RET, "v0") # Implicit return 0 if no ret
    when :extern_definition
      # Externs are handled by linker, but IR can track them
      emit(:EXTERN, node[:name], node[:lib])
    when :struct_definition, :union_definition, :enum_definition
      # Metadata for types
      emit(:TYPE_DEF, node)
    else
      process_node(node)
    end
  end

  def process_node(node)
    return if node.nil?
    case node[:type]
    when :assignment
      if node[:name].include?('.')
        # Member assignment: obj.field = val
        parts = node[:name].split('.')
        receiver = eval_expression({ type: :variable, name: parts[0], inferred_type: "ptr" })
        val = eval_expression(node[:expression])
        # Find offset
        type = @variables_to_types[parts[0]]
        f_off = 0
        if type && @structs[type]
          f_idx = @structs[type][:fields].index(parts[1])
          f_off = f_idx * 8 if f_idx
        end
        emit(:STORE_MEM, receiver, f_off, val, 8, inferred_type: (node[:expression] && node[:expression][:inferred_type]) || "int")
      elsif node[:expression][:type] == :variable && @structs[node[:expression][:name]]
        # Stack allocation for struct: let x = MyStruct
        st_name = node[:expression][:name]
        @variables_to_types[node[:name]] = st_name
        emit(:LEA_STACK, node[:name], "#{node[:name]}__struct_data", inferred_type: "ptr")
      else
        src = eval_expression(node[:expression])
        @variables_to_types[node[:name]] = node[:var_type] || (node[:expression] && node[:expression][:inferred_type])
        if node[:expression] && node[:expression][:type] == :variable && @structs[node[:expression][:name]]
          @variables_to_types[node[:name]] = node[:expression][:name]
        end
        emit(:MOVE, node[:name], src, let: node[:let], mut: node[:mut], inferred_type: node[:inferred_type])
      end
    when :deref_assign
      ptr = eval_expression(node[:pointer])
      val = eval_expression(node[:expression])
      emit(:STORE_MEM, ptr, 0, val, 8, inferred_type: (node[:expression] && node[:expression][:inferred_type]) || "int")
    when :array_assign
      if ENV['DEBUG_IR'] then pp node end
      idx = eval_expression(node[:index])
      val = eval_expression(node[:expression])

      if node[:name].include?('.')
        # Member array access: obj.field[idx]
        parts = node[:name].split('.')
        receiver = eval_expression({ type: :variable, name: parts[0], inferred_type: "ptr" })
        # Find field offset
        type = @variables_to_types[parts[0]]
        f_off = 0
        if type && @structs[type]
          f_idx = @structs[type][:fields].index(parts[1])
          f_off = f_idx * 8 if f_idx
        end
        base = next_vreg
        emit(:LOAD_MEM, base, receiver, f_off, 8, inferred_type: "ptr")
        off = next_vreg
        emit(:ARITH, :MUL, off, idx, 8, inferred_type: "int")
        addr = next_vreg
        emit(:ARITH, :ADD, addr, base, off, inferred_type: "ptr")
        emit(:STORE_MEM, addr, 0, val, 8, inferred_type: (node[:value] && node[:value][:inferred_type]) || "int")
      else
        # Local array
        off = next_vreg
        emit(:ARITH, :MUL, off, idx, 8, inferred_type: "int")
        base = next_vreg
        emit(:LOAD, base, "#{node[:name]}__base", inferred_type: "ptr")
        addr = next_vreg
        emit(:ARITH, :ADD, addr, base, off, inferred_type: "ptr")
        emit(:STORE_MEM, addr, 0, val, 8, inferred_type: (node[:value] && node[:value][:inferred_type]) || "int")
      end
    when :if_statement
      process_if(node)
    when :while_statement
      process_while(node)
    when :for_statement
      process_for(node)
    when :return
      src = eval_expression(node[:expression])
      emit(:RET, src, inferred_type: (node[:expression] && node[:expression][:inferred_type]) || "int")
    when :break
      emit(:JMP, @current_break_label)
    when :continue
      emit(:JMP, @current_continue_label)
    when :fn_call
      eval_expression(node)
    when :array_decl
      # Array local decl
      dst = next_vreg
      # Mark for backend to reserve space
      emit(:TYPE_DEF, node)
      emit(:LEA_STACK, dst, "#{node[:name]}__elem_0", inferred_type: "ptr")
      emit(:MOVE, "#{node[:name]}__base", dst, inferred_type: "ptr")
    when :increment
      # Simplified increment
      val = next_vreg
      emit(:LOAD, val, node[:name], inferred_type: "int")
      res = next_vreg
      emit(:ARITH, node[:op] == "++" ? :ADD : :SUB, res, val, 1, inferred_type: "int")
      emit(:STORE, node[:name], res, inferred_type: "int")
    when :panic
      emit(:PANIC, node[:message])
    when :todo
      emit(:TODO, node[:message])
    end
  end

  def eval_expression(expr)
    return "v0" if expr.nil?
    if expr.is_a?(String) || expr.is_a?(Symbol) # Already a vreg name?
      return expr.to_s
    end
    unless expr.is_a?(Hash)
      return "v0"
    end
    case expr[:type]
    when :literal
      dst = next_vreg
      emit(:SET, dst, expr[:value], inferred_type: expr[:inferred_type])
      dst
    when :variable
      dst = next_vreg
      # expr[:name] could be a Symbol if it's from a special node
      name = expr[:name].is_a?(Symbol) ? expr[:name].to_s : (expr[:name] || "unknown")
      emit(:LOAD, dst, name, inferred_type: expr[:inferred_type])
      dst
    when :binary_op
      left = eval_expression(expr[:left])
      right = eval_expression(expr[:right])
      dst = next_vreg
      op = case expr[:op]
           when "+" then :ADD when "-" then :SUB when "*" then :MUL when "/" then :DIV
           when "%" then :MOD when "&" then :AND when "|" then :OR  when "^" then :XOR
           when "<<" then :SHL when ">>" then :SHR
           when "==", "!=", "<", ">", "<=", ">=" then :CMP
           when "<>" then :CONCAT
           end

      # Handle '+' overload for string concat
      if expr[:op] == "+" && expr[:inferred_type] == "str"
        op = :CONCAT
      end

      # Handle pointer arithmetic scaling
      if (op == :ADD || op == :SUB) && expr[:inferred_type] == "ptr"
        # If one is ptr and another is int, scale int
        lt = expr[:left][:inferred_type]
        rt = expr[:right][:inferred_type]
        if (lt == "ptr" || lt == "str") && rt == "int"
          scaled = next_vreg
          emit(:ARITH, :MUL, scaled, right, 8, inferred_type: "int")
          right = scaled
        elsif (rt == "ptr" || rt == "str") && lt == "int"
          scaled = next_vreg
          emit(:ARITH, :MUL, scaled, left, 8, inferred_type: "int")
          left = scaled
        end
      end

      if op == :CMP
        emit(:CMP, left, right, inferred_type: "bool")
        # For simplicity in expressions, we might still need a way to get result in reg
        # But formalized JIR uses CMP + JCC.
        # For expressions, we'll use ARITH for now if it's not for a jump.
        emit(:ARITH, expr[:op], dst, left, right, inferred_type: expr[:inferred_type])
      else
        emit(:ARITH, op, dst, left, right, inferred_type: expr[:inferred_type])
      end
      dst
    when :fn_call
      name = expr[:name]
      if name.include?('.')
        # Method call: receiver.method
        # Receiver should be evaluated and passed as param_0
        parts = name.split('.')
        receiver = eval_expression({ type: :variable, name: parts[0], inferred_type: "ptr" })
        args = [receiver] + (expr[:args] || []).map { |a| eval_expression(a) }
      else
        args = (expr[:args] || []).map { |a| eval_expression(a) }
      end

      # Specialized dispatch for overloaded print
      if name == "print" || name == "output" || name == "prints"
        arg0 = expr[:args] ? expr[:args][0] : nil
        # Check inferred_type from semantic analysis
        if arg0 && arg0[:inferred_type] == "int"
          name = "output_int"
        else
          name = "prints"
        end
      end
      dst = next_vreg
      # Standardized CALL uses args_count
      # Standardized CALL uses args_count
      args.each_with_index { |arg, i|
        # Check if it was a method call (args[0] is receiver)
        inf_type = if expr[:name].include?('.') && i == 0
                     "ptr"
                   elsif expr[:name].include?('.')
                     (expr[:args] && expr[:args][i-1]) ? expr[:args][i-1][:inferred_type] : "int"
                   else
                     (expr[:args] && expr[:args][i]) ? expr[:args][i][:inferred_type] : "int"
                   end
        emit(:MOVE, "param_#{i}", arg, inferred_type: inf_type)
      }

      # Handle struct method names mapping to struct.method
      if name.include?('.')
        receiver_var, method_name = name.split('.')
        type = @variables_to_types[receiver_var]
        name = "#{type}.#{method_name}" if type && @structs[type]
      end

      emit(:CALL, dst, name, args.length, inferred_type: expr[:inferred_type])
      dst
    when :member_access
      dst = next_vreg
      # Safely extract receiver name
      receiver_name = (expr[:receiver] && expr[:receiver].is_a?(Hash) && expr[:receiver][:type] == :variable) ? expr[:receiver][:name].to_s : nil
      receiver = eval_expression(expr[:receiver])

      return "v0" if receiver.nil?

      # Try to use @variables_to_types for accurate offset
      type = @variables_to_types[receiver_name] if receiver_name
      offset = 0
      if type && @structs[type]
        idx = @structs[type][:fields].index(expr[:member])
        offset = idx * 8 if idx
      else
        # Heuristic: assume 8 bytes per field if struct not found
        @structs.values.each do |s|
          idx = s[:fields].index(expr[:member])
          if idx
            offset = idx * 8
            break
          end
        end
      end
      emit(:LOAD_MEM, dst, receiver, offset, 8, inferred_type: expr[:inferred_type])
      dst
    when :string_literal
      dst = next_vreg
      emit(:LEA_STR, dst, expr[:value])
      dst
    when :match_expression
      process_match(expr)
    when :array_access
      idx = eval_expression(expr[:index])
      off = next_vreg
      emit(:ARITH, :MUL, off, idx, 8, inferred_type: "int")
      base = next_vreg
      emit(:LOAD, base, "#{expr[:name]}__base", inferred_type: "ptr")
      addr = next_vreg
      emit(:ARITH, :ADD, addr, base, off, inferred_type: "ptr")
      dst = next_vreg
      emit(:LOAD_MEM, dst, addr, 0, 8, inferred_type: expr[:inferred_type])
      dst
    when :cast
      src = eval_expression(expr[:expression])
      dst = next_vreg
      emit(:MOVE, dst, src, inferred_type: expr[:inferred_type]) # Cast is a move in JIR for now
      dst
    when :anonymous_function
      dst = next_vreg
      label = next_label("anon")
      # Define the function at the label
      # Note: This is simplified IR representation
      emit(:FUNC_ADDR, dst, label, node: expr)
      dst
    when :address_of
      op = expr[:operand] || expr[:expression]
      dst = next_vreg
      if op[:type] == :variable
        emit(:LEA_STACK, dst, op[:name], inferred_type: "ptr")
      elsif op[:type] == :array_access
        # Array address logic
        idx = eval_expression(op[:index])
        off = next_vreg
        emit(:ARITH, :MUL, off, idx, 8, inferred_type: "int")
        base = next_vreg
        emit(:LOAD, base, "#{op[:name]}__base", inferred_type: "ptr")
        emit(:ARITH, :ADD, dst, base, off, inferred_type: "ptr")
      end
      dst
    when :dereference
      src = eval_expression(expr[:operand] || expr[:expression])
      dst = next_vreg
      emit(:LOAD_MEM, dst, src, 0, 8, inferred_type: expr[:inferred_type])
      dst
    end
  end

  def process_if(node)
    else_l = next_label("if_else")
    end_l = next_label("if_end")

    if node[:condition][:type] == :binary_op && ["==", "!=", "<", ">", "<=", ">="].include?(node[:condition][:op])
       # Optimization: JCC directly
    end

    cond = eval_expression(node[:condition])
    emit(:CMP, cond, 0)
    emit(:JCC, "==", else_l) # JZ

    node[:body].each { |s| process_node(s) }
    emit(:JMP, end_l)

    emit(:LABEL, else_l)
    node[:else_body]&.each { |s| process_node(s) }

    emit(:LABEL, end_l)
  end

  def process_while(node)
    start_l = next_label("while_start")
    end_l = next_label("while_end")

    old_break = @current_break_label
    old_continue = @current_continue_label
    @current_break_label = end_l
    @current_continue_label = start_l

    emit(:LABEL, start_l)
    cond = eval_expression(node[:condition])
    emit(:JZ, cond, end_l)

    node[:body].each { |s| process_node(s) }
    emit(:JMP, start_l)

    emit(:LABEL, end_l)
    @current_break_label = old_break
    @current_continue_label = old_continue
  end

  def process_for(node)
    # init
    process_node(node[:init])

    start_l = next_label("for_start")
    update_l = next_label("for_update")
    end_l = next_label("for_end")

    old_break = @current_break_label
    old_continue = @current_continue_label
    @current_break_label = end_l
    @current_continue_label = update_l

    emit(:LABEL, start_l)
    cond = eval_expression(node[:condition])
    emit(:JZ, cond, end_l)

    node[:body].each { |s| process_node(s) }

    emit(:LABEL, update_l)
    process_node(node[:update])
    emit(:JMP, start_l)

    emit(:LABEL, end_l)
    @current_break_label = old_break
    @current_continue_label = old_continue
  end

  def process_match(node)
    matched = eval_expression(node[:expression])
    end_l = next_label("match_end")
    dst = next_vreg
    match_res = next_vreg

    node[:cases].each do |c|
      next_c = next_label("case")
      process_pattern(matched, c[:pattern], next_c)

      # Case body
      res = if c[:body].is_a?(Array)
              c[:body].each { |s| process_node(s) }
              "v0"
            else
              eval_expression(c[:body])
            end
      emit(:MOV, match_res, res)
      emit(:JMP, end_l)
      emit(:LABEL, next_c)
    end

    emit(:LABEL, end_l)
    emit(:MOV, dst, match_res)
    dst
  end

  def process_pattern(matched, pattern, fail_label)
    case pattern[:type]
    when :wildcard_pattern
      # Always matches, do nothing
    when :literal_pattern
      val_reg = next_vreg
      emit(:SET, val_reg, pattern[:value])
      cmp_reg = next_vreg
      emit(:CMP, cmp_reg, matched, val_reg, cond: "==")
      emit(:JZ, cmp_reg, fail_label)
    when :bind_pattern
      emit(:STORE, pattern[:name], matched)
    when :variant_pattern
      # Check tag
      tag_reg = next_vreg
      emit(:LOAD_MEM, tag_reg, matched, 0, 8)

      target_tag_reg = next_vreg
      # We need tag value from somewhere. Let's assume metadata for now.
      # In a real impl, IRGenerator would know the enum layout.
      emit(:SET, target_tag_reg, {enum: pattern[:enum], variant: pattern[:variant]})

      cmp_reg = next_vreg
      emit(:CMP, cmp_reg, tag_reg, target_tag_reg, cond: "==")
      emit(:JZ, cmp_reg, fail_label)

      # Bind fields
      (pattern[:fields] || []).each_with_index do |f, i|
        field_reg = next_vreg
        emit(:LOAD_MEM, field_reg, matched, 8 + i * 8, 8)
        emit(:STORE, f, field_reg)
      end
    end
  end
end
