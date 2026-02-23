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
        @symbol_table[node[:name]] = { type: :function, return_type: node[:return_type] || "int", params: node[:param_types] || {} }
      when :extern_definition
        @symbol_table[node[:name]] = { type: :function, return_type: node[:return_type] || "int", params: node[:param_types] || {} }
      when :struct_definition
        @structs[node[:name]] = node
      when :union_definition
        @unions[node[:name]] = node
      when :enum_definition
        @structs[node[:name]] = node # Treat enums as structs for pointer checks
      end
    end

    # Pass 2: Analyze bodies
    @ast.each do |node|
      analyze_node(node, {}) if node[:type] == :function_definition
    end
    @ast
  end

  private

  def analyze_node(node, local_vars)
    return "int" if node.nil?
    case node[:type]
    when :function_definition
      # Add params to local vars
      node[:params].each do |p|
        p_name = p.is_a?(Hash) ? p[:name] : p
        type = (node[:param_types] && node[:param_types][p_name]) || "int"
        local_vars[p_name] = { type: type, mut: true } # Params are mutable in Juno by default
      end
      node[:body].each { |stmt| analyze_node(stmt, local_vars) }
      "void"
    when :assignment
      type = analyze_node(node[:expression], local_vars)
      if node[:let]
        local_vars[node[:name]] = { type: node[:var_type] || type, mut: node[:mut] }
      else
        # Reassignment
        var_info = local_vars[node[:name]]
        if var_info && !var_info[:mut]
           error_at(node, "Cannot reassign to non-mutable variable '#{node[:name]}'")
        end
      end
      type
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
    when :variable
      name = node[:name]
      return local_vars[name][:type] if local_vars.key?(name) && local_vars[name].is_a?(Hash)
      if @symbol_table.key?(name)
        sym = @symbol_table[name]
        return "fn_ptr" if sym[:type] == :function
        return sym[:type].to_s
      end
      "int"
    when :fn_call
      sym = @symbol_table[node[:name]]
      if sym
        # Check argument count
        expected = sym[:params].length
        actual = (node[:args] || []).length
        if expected != actual
          error_at(node, "Function '#{node[:name]}' expects #{expected} arguments, but got #{actual}")
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
