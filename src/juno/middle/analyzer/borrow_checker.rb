require_relative "../../errors"

class BorrowChecker
  def initialize(ast, source = "", filename = "")
    @ast = ast
    @source = source
    @filename = filename
    @var_states = {} # name => { state: :owned|:moved|:freed, line: int }
    @aliases = {}    # name => set of names
  end

  # Functions that are known to NEVER consume (free/close) their arguments
  SAFE_FUNCTIONS = %w[
    print print_s println print_i print_hex print_newline print_space
    write read output putc puts
    strlen streq str_hash str_find str_contains str_substring
    concat substr ord chr itoa
    format_print
    ptr_add memset memcpy memmove
    square cube abs_val min_val max_val factorial gcd ipow
  ].freeze

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
    
    # Check: does the function call free()/close() on a parameter?
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
      @var_states = {}
      @aliases = {}
      (node[:body] || []).each { |stmt| process_node(stmt) }

    when :assignment
      name = node[:name] || ""
      expr = node[:expression]
      
      # Check the expression first
      check_expression(expr) if expr.is_a?(Hash)

      # Track resources only from actual allocation calls
      if expr.is_a?(Hash) && expr[:type] == :fn_call && ["malloc", "open"].include?(expr[:name])
        # Don't track field assignments (self.data = malloc) — those belong to the struct
        unless name.include?('.')
          @var_states[name] = { state: :owned, line: node[:line] }
        end
      elsif expr.is_a?(Hash) && expr[:type] == :variable
        src_name = expr[:name]
        if @var_states.key?(src_name)
          state_info = @var_states[src_name]
          if state_info[:state] == :moved
            report_error("Use of moved value '#{src_name}'", node)
          elsif state_info[:state] == :freed
            report_error("Use of freed value '#{src_name}'", node)
          end
          
          # Transfer ownership only for tracked resources
          if state_info[:state] == :owned
            @var_states[name] = { state: :owned, line: node[:line] }
            @var_states[src_name] = { state: :moved, line: node[:line] }
          end
        end
      end

    when :fn_call
      fn_name = node[:name] || ""
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
        # Check each argument
        args.each_with_index do |arg, idx|
          if arg[:type] == :variable
            v_name = arg[:name]
            if @var_states.key?(v_name) && @var_states[v_name][:state] == :owned
              # Determine if this function consumes the argument
              is_consumed = function_consumes_arg?(fn_name, idx)
              
              if is_consumed
                @var_states[v_name] = { state: :moved, line: node[:line], moved_to: fn_name }
              end
            end
          end
          check_expression(arg)
        end
      end

    when :if_statement
      # Clone state for branch analysis
      saved_state = @var_states.dup.transform_values(&:dup)
      
      process_node(node[:condition])
      (node[:body] || []).each { |n| process_node(n) }
      
      then_state = @var_states
      @var_states = saved_state
      (node[:else_body] || []).each { |n| process_node(n) }
      
      # Merge: if either branch freed/moved, consider it potentially freed/moved
      # This is conservative but safe
      then_state.each do |name, info|
        if @var_states.key?(name)
          current = @var_states[name]
          # If the then-branch freed it but else didn't, or vice versa, warn
          if info[:state] != current[:state]
            # Take the more restrictive state
            if info[:state] == :freed || current[:state] == :freed
              @var_states[name] = { state: :freed, line: node[:line] }
            elsif info[:state] == :moved || current[:state] == :moved
              @var_states[name] = { state: :moved, line: node[:line] }
            end
          end
        else
          @var_states[name] = info
        end
      end

    when :while_statement, :for_statement
      process_node(node[:condition]) if node[:condition]
      (node[:body] || []).each { |n| process_node(n) }
    end
  end

  # Determine if a function consumes (frees) its argument at the given index
  def function_consumes_arg?(fn_name, arg_idx)
    # Known safe functions never consume
    return false if SAFE_FUNCTIONS.include?(fn_name)
    
    # Method calls on objects (e.g., list.add) — generally don't consume args
    return false if fn_name.include?('.')
    
    # If we analyzed the function and know its effects, use that
    if @fn_effects.key?(fn_name)
      fn_node = @ast.find { |n| n[:type] == :function_definition && n[:name] == fn_name }
      if fn_node
        param_name = (fn_node[:params] || [])[arg_idx]
        param_name = param_name[:name] if param_name.is_a?(Hash)
        return (@fn_effects[fn_name] || []).include?(param_name)
      end
      return false
    end
    
    # Unknown function: assume it does NOT consume (borrow semantics by default)
    # This is the opposite of the old behavior which assumed move.
    # Rationale: most functions just read their arguments.
    false
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
