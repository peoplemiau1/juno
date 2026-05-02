require_relative "../../errors"

class BorrowChecker
  def initialize(ast, source = "", filename = "")
    @ast = ast
    @source = source
    @filename = filename
    @var_states = {} # name => { state: :owned|:moved|:freed, line: int }
    @aliases = {}    # name => set of names
  end

  def check
    # Pass 1: Global analysis of function effects
    @fn_effects = {}
    @ast.each do |node|
      if node[:type] == :function_definition
        @fn_effects[node[:name]] = analyze_fn_effects(node)
      end
    end

    # Pass 2: Main borrow check
    @ast.each { |node| process_node(node) }
  end

  def analyze_fn_effects(fn_node)
    consumed_params = []
    params = (fn_node[:params] || []).map { |p| p.is_a?(Hash) ? p[:name] : p }
    
    # Simple check: does the function call free() on a parameter?
    # Or pass it to another function that consumes it?
    # This is a fixed-point analysis in theory, but we'll do one level for now.
    walker = ->(node) {
      return unless node.is_a?(Hash)
      if node[:type] == :fn_call
        if ["free", "close"].include?(node[:name])
          arg = node[:args][0]
          consumed_params << arg[:name] if arg && arg[:type] == :variable && params.include?(arg[:name])
        end
      end
      node.values.each { |v| v.is_a?(Array) ? v.each { |i| walker.call(i) } : walker.call(v) }
    }
    walker.call(fn_node[:body])
    consumed_params.uniq
  end

  private

  def report_error(message, node)
    error = JunoTypeError.new(
      message,
      filename: @filename,
      line_num: node[:line],
      column: node[:column],
      source: @source
    )
    JunoErrorReporter.report(error)
  end

  def process_node(node)
    return unless node.is_a?(Hash)

    case node[:type]
    when :function_definition
      # Reset state for each function
      @var_states = {}
      @aliases = {}
      (node[:params] || []).each do |p|
        p_name = p.is_a?(Hash) ? p[:name] : p
        @var_states[p_name] = { state: :owned, line: node[:line] }
      end
      (node[:body] || []).each { |stmt| process_node(stmt) }
      
      # Check for leaks at the end of function
      @var_states.each do |name, info|
        if info[:state] == :owned && name != "self"
          # This is a potential leak, but we'll let ResourceAuditor handle the warning for now
          # or we can integrate it here.
        end
      end

    when :assignment
      name = node[:name]
      expr = node[:expression]
      
      # Check the expression first
      check_expression(expr)

      if expr[:type] == :fn_call && ["malloc", "open"].include?(expr[:name])
        @var_states[name] = { state: :owned, line: node[:line] }
      elsif expr[:type] == :variable
        src_name = expr[:name]
        if @var_states.key?(src_name)
          state_info = @var_states[src_name]
          if state_info[:state] == :moved
            report_error("Use of moved value '#{src_name}'", node)
          elsif state_info[:state] == :freed
            report_error("Use of freed value '#{src_name}'", node)
          end
          
          # Move semantics: ownership transfers
          @var_states[name] = { state: :owned, line: node[:line] }
          @var_states[src_name] = { state: :moved, line: node[:line] }
        end
      else
        @var_states[name] = { state: :owned, line: node[:line] } if node[:let]
      end

    when :fn_call
      fn_name = node[:name]
      args = node[:args] || []

      if fn_name == "free" || fn_name == "close"
        arg = args[0]
        if arg && arg[:type] == :variable
          v_name = arg[:name]
          if @var_states.key?(v_name)
            state_info = @var_states[v_name]
            if state_info[:state] == :moved
              report_error("Attempt to free already moved value '#{v_name}'", node)
            elsif state_info[:state] == :freed
              report_error("Double free detected for '#{v_name}'", node)
            end
            @var_states[v_name] = { state: :freed, line: node[:line] }
          end
        end
      else
        # PREDICTIVE RULE: Only move if function is known to consume the argument
        fn_effects = @fn_effects[fn_name] || []
        (node[:args] || []).each_with_index do |arg, idx|
          if arg[:type] == :variable
            v_name = arg[:name]
            if @var_states.key?(v_name) && @var_states[v_name][:state] == :owned
              # Check if this parameter index is consumed
              # If we don't know the function (extern), assume it moves for safety
              is_consumed = if @fn_effects.key?(fn_name)
                              param_name = (@ast.find{|n| n[:name] == fn_name}[:params] || [])[idx]
                              param_name = param_name[:name] if param_name.is_a?(Hash)
                              fn_effects.include?(param_name)
                            elsif ["print", "putc", "write"].include?(fn_name)
                              false
                            else
                              true # Extern or unknown: assume move
                            end
              
              if is_consumed
                @var_states[v_name] = { state: :moved, line: node[:line], moved_to: fn_name }
              end
            end
          end
          check_expression(arg)
        end
      end

    when :if_statement
      # Simple path analysis: we clone the state for branches
      # In a real checker, we'd merge them and find inconsistencies
      process_node(node[:condition])
      (node[:body] || []).each { |n| process_node(n) }
      (node[:else_body] || []).each { |n| process_node(n) }

    when :while_statement, :for_statement
      process_node(node[:condition]) if node[:condition]
      (node[:body] || []).each { |n| process_node(n) }
    end
  end

  def check_expression(expr)
    return unless expr.is_a?(Hash)
    
    if expr[:type] == :variable
      name = expr[:name]
      if @var_states.key?(name)
        info = @var_states[name]
        if info[:state] == :moved
          report_error("Value '#{name}' was moved at line #{info[:line]} and is no longer available", expr)
        elsif info[:state] == :freed
          report_error("Value '#{name}' was freed at line #{info[:line]} and cannot be used", expr)
        end
      end
    end

    expr.values.each do |v|
      if v.is_a?(Hash)
        check_expression(v)
      elsif v.is_a?(Array)
        v.each { |i| check_expression(i) if i.is_a?(Hash) }
      end
    end
  end
end
