# semantic.rb - Semantic analysis for Juno compiler

class SemanticAnalyzer
  def initialize(ast, filename = "unknown", source = "")
    @ast = ast
    @filename = filename
    @source = source
    @symbol_table = {}
    @structs = {}
    @unions = {}
  end

  def analyze
    # Pass 1: Collect globals and definitions
    @ast.each do |node|
      case node[:type]
      when :function_definition
        p_names = (node[:params] || []).map { |p| p.is_a?(Hash) ? p[:name] : p }
        @symbol_table[node[:name]] = {
          type: :function,
          return_type: node[:return_type] || "int",
          params: p_names,
          param_types: node[:param_types] || {}
        }
        node[:inferred_type] = "void"
      when :extern_definition
        @symbol_table[node[:name]] = {
          type: :function,
          return_type: node[:return_type] || "int",
          params: node[:params] || [],
          param_types: node[:param_types] || {}
        }
        node[:inferred_type] = "void"
      when :struct_definition
        @structs[node[:name]] = node
        node[:inferred_type] = "type"
      when :union_definition
        @unions[node[:name]] = node
        node[:inferred_type] = "type"
      when :enum_definition
        @structs[node[:name]] = node # Treat enums as structs for pointer checks
        node[:inferred_type] = "type"
      when :assignment
        if node[:let]
           @symbol_table[node[:name]] = { type: :global, var_type: node[:var_type] || "int", mut: node[:mut] }
        end
      end
    end

    # Pass 2: Analyze bodies
    @ast.each do |node|
      if node[:type] == :function_definition
        @local_vars_count = 0

        @local_vars_count = scan_decls(node[:body] || [])

        analyze_node(node, {})
        params_count = (node[:params] || []).length
        # Ensure 'self' is accounted for in stack_size if it's a method
        params_count += 1 if node[:name].include?('.') # self

        # Calculate final stack size with alignment
        stack_size = (@local_vars_count + params_count) * 8
        node[:stack_size] = (stack_size + 15) & ~15
      end
    end
    @ast
  end

  private

  def scan_decls(body)
    count = 0
    body.each do |s|
      next unless s.is_a?(Hash)
      if s[:type] == :array_decl
        count += s[:size] + 1 # elements + base
      elsif s[:type] == :assignment && s[:let]
        count += 1
      elsif s[:type] == :if_statement
        count += scan_decls(s[:body])
        count += scan_decls(s[:else_body]) if s[:else_body]
      elsif s[:type] == :while_statement || s[:type] == :for_statement
        count += scan_decls(s[:body] || [])
      end
    end
    count
  end

  def analyze_node(node, local_vars)
    return "int" if node.nil?
    node[:inferred_type] = case node[:type]
    when :function_definition
      # Add params to local vars
      params = (node[:params] || []).dup
      if node[:name].include?('.')
        params.unshift("self")
      end

      params.each do |p|
        p_name = p.is_a?(Hash) ? p[:name] : p
        type = (node[:param_types] && node[:param_types][p_name]) || (p_name == "self" ? node[:name].split('.')[0] : "int")
        local_vars[p_name] = { type: type, mut: true } # Params are mutable in Juno by default
      end
      node[:body].each { |stmt| analyze_node(stmt, local_vars) }
      "void"
    when :assignment
      type = analyze_node(node[:expression], local_vars)
      if node[:let]
        local_vars[node[:name]] = { type: node[:var_type] || type, mut: node[:mut] }
        @local_vars_count += 1
      elsif node[:name].include?('.')
        # Method call or member access in assignment, ignore count
      else
        # Reassignment
        var_info = local_vars[node[:name]] || @symbol_table[node[:name]]
        if var_info && !var_info[:mut]
           error_at(node, "Cannot reassign to non-mutable variable '#{node[:name]}'")
        end
      end
      type
    when :increment
      var_info = local_vars[node[:name]] || @symbol_table[node[:name]]
      if var_info && !var_info[:mut]
        error_at(node, "Cannot increment/decrement non-mutable variable '#{node[:name]}'")
      end
      "int"
    when :binary_op
      left_type = analyze_node(node[:left], local_vars)
      right_type = analyze_node(node[:right], local_vars)

      if node[:op] == "*" || node[:op] == "/" || node[:op] == "%"
        if left_type == "bool" || right_type == "bool"
          error_at(node, "Arithmetic operation '#{node[:op]}' is not allowed on boolean values")
        end

        # Check for function pointers or pointers
        if is_pointer_type?(left_type) || is_pointer_type?(right_type)
          error_at(node, "Arithmetic operation '#{node[:op]}' is not allowed on pointer or function types")
        end
      end

      # For now, most binary ops return int or bool
      if ["==", "!=", "<", ">", "<=", ">="].include?(node[:op])
        "bool"
      elsif ["+", "-"].include?(node[:op]) && (left_type == "ptr" || right_type == "ptr" || left_type == "str" || right_type == "str")
        if node[:op] == "+" && (left_type == "str" || left_type == "ptr" && node[:left][:type] == :string_literal) && (right_type == "str" || right_type == "ptr" && node[:right][:type] == :string_literal)
          "str"
        else
          "ptr"
        end
      elsif node[:op] == "<>"
        "str"
      else
        "int"
      end
    when :literal
      if node[:value].is_a?(TrueClass) || node[:value].is_a?(FalseClass)
        "bool"
      elsif node[:value].is_a?(Integer)
        "int"
      else
        "ptr" # String literals
      end
    when :string_literal
      "ptr"
    when :variable
      name = node[:name]
      if local_vars.key?(name) && local_vars[name].is_a?(Hash)
        local_vars[name][:type]
      elsif @symbol_table.key?(name)
        sym = @symbol_table[name]
        sym[:type] == :function ? "fn_ptr" : sym[:type].to_s
      else
        "int"
      end
    when :fn_call
      (node[:args] || []).each { |a| analyze_node(a, local_vars) }

      name = node[:name]
      sym = @symbol_table[name]

      # Handle methods
      if name.include?('.') && !sym
        receiver, method = name.split('.')
        receiver_type = nil
        if local_vars.key?(receiver)
           receiver_type = local_vars[receiver][:type]
        end

        if receiver_type && @symbol_table.key?("#{receiver_type}.#{method}")
           sym = @symbol_table["#{receiver_type}.#{method}"]
        else
           # Fallback to heuristic if type unknown
           @symbol_table.each do |k, v|
              if k.end_with?(".#{method}")
                 sym = v
                 break
              end
           end
        end
      end

      if sym && sym[:type] == :function
        # Check argument count
        expected = sym[:params].length
        actual = (node[:args] || []).length
        # actual += 1 if name.include?('.') # Account for implicit self
        if expected != actual
          # error_at(node, "Function '#{name}' expects #{expected} arguments, but got #{actual}")
        end
        sym[:return_type]
      else
        # Allow unknown for now (could be built-in not in symbol table)
        "int"
      end
    when :if_statement
      analyze_node(node[:condition], local_vars)
      node[:body].each { |s| analyze_node(s, local_vars) }
      node[:else_body]&.each { |s| analyze_node(s, local_vars) }
      "void"
    when :while_statement
      analyze_node(node[:condition], local_vars)
      node[:body].each { |s| analyze_node(s, local_vars) }
      "void"
    when :for_statement
      if node[:init] && node[:init][:type] == :assignment
        local_vars[node[:init][:name]] = { type: "int", mut: true }
      end
      analyze_node(node[:condition], local_vars)
      analyze_node(node[:update], local_vars)
      node[:body].each { |s| analyze_node(s, local_vars) }
      "void"
    when :return
      analyze_node(node[:expression], local_vars)
      "void"
    when :address_of
      analyze_node(node[:expression] || node[:operand], local_vars)
      "ptr"
    when :dereference
      analyze_node(node[:expression] || node[:operand], local_vars)
      "int" # Simplified
    when :cast
      analyze_node(node[:expression], local_vars)
      node[:target_type] || "int"
    when :array_access
      analyze_node(node[:index], local_vars)
      "int" # Simplified
    else
      "int"
    end
  end

  def is_pointer_type?(type)
    type == "ptr" || type == "fn_ptr" || @structs.key?(type)
  end

  def error_at(node, message)
    error = JunoTypeError.new(
      message,
      filename: @filename,
      line_num: node[:line],
      column: node[:column],
      source: @source
    )
    JunoErrorReporter.report(error)
  end
end
