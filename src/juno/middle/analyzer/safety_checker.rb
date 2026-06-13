require_relative "../../errors"

class JunoSafetyChecker
  def initialize(ast, functions = {}, source = "", filename = "")
    @ast = ast
    @functions = functions
    @source = source
    @filename = filename
    @var_states = {}
    @fn_effects = {}
    @errors = []
  end

  attr_reader :fn_effects

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
    @errors = []
    analyze_all_fn_effects
    @ast.each { |node| process_node(node) }
    
    unless @errors.empty?
      @errors.each(&:display)
      exit 1
    end
  end

  def allocates_resource?(name)
    ['malloc', 'open', 'os_open', 'os_alloc', 'mem_malloc', 'fopen'].include?(name) ||
      name.downcase.start_with?('alloc_', 'create_', 'open_') || name.end_with?('.new')
  end

  def consumes_resource?(name)
    ['free', 'close', 'os_close', 'os_free', 'mem_free', 'delete'].include?(name) ||
      name.downcase.start_with?('free_', 'close_', 'destroy_', 'delete') ||
      name.end_with?('.free', '.close')
  end

  private

  def resolve_local_pointer(expr)
    return nil unless expr.is_a?(Hash)
    
    if expr[:type] == :address_of
      operand = expr[:operand] || expr[:expression]
      if operand && operand[:type] == :variable
        return operand[:name]
      end
    elsif expr[:type] == :variable
      name = expr[:name]
      if @var_states.key?(name) && @var_states[name][:state] == :local_ptr
        return @var_states[name][:target]
      end
    end
    nil
  end

  def analyze_all_fn_effects
    @fn_effects = {}
    changed = true
    while changed
      changed = false
      @ast.each do |node|
        if node[:type] == :function_definition
          old_effects = @fn_effects[node[:name]]
          new_effects = analyze_fn_effects(node)
          if new_effects != old_effects
            @fn_effects[node[:name]] = new_effects
            changed = true
          end
        end
      end
    end
  end

  def analyze_fn_effects(fn_node)
    consumed_params = []
    params = (fn_node[:params] || []).map { |p| p.is_a?(Hash) ? p[:name] : p }
    
    walker = ->(node) {
      if node.is_a?(Array)
        node.each { |i| walker.call(i) }
        return
      end
      return unless node.is_a?(Hash)
      
      if node[:type] == :fn_call
        fn_name = node[:name]
        if consumes_resource?(fn_name) || (@fn_effects[fn_name] && !@fn_effects[fn_name].empty?)
          node[:args]&.each_with_index do |arg, idx|
            if arg[:type] == :variable && params.include?(arg[:name])
              if consumes_resource?(fn_name) && idx == 0
                consumed_params << arg[:name]
              elsif @fn_effects[fn_name]
                consumed_params << arg[:name] if idx == 0 
              end
            end
          end
        end
      end
      node.values.each { |v| v.is_a?(Array) ? v.each { |i| walker.call(i) } : walker.call(v) }
    }
    walker.call(fn_node[:body])
    consumed_params.uniq
  end

  def block_returns?(body)
    return false unless body.is_a?(Array)
    body.each do |stmt|
      next unless stmt.is_a?(Hash)
      return true if stmt[:type] == :return || stmt[:type] == :return_statement
      if stmt[:type] == :if_statement
        if block_returns?(stmt[:body]) && block_returns?(stmt[:else_body])
          return true
        end
      end
    end
    false
  end

  def report_error(message, node, is_warning = false)
    line = node[:line]
    col = node[:column]

    if line.nil? || col.nil?
      sub_node = node[:expression] || node[:value] || node[:target] || node[:operand]
      if sub_node.is_a?(Hash)
        line ||= sub_node[:line]
        col ||= sub_node[:column]
      end
    end

    node_filename = node[:filename] || @filename
    node_source = @source
    if node[:filename] && node[:filename] != @filename
      begin
        node_source = File.read(node[:filename])
      rescue
      end
    end

    if is_warning
      JunoErrorReporter.warn(message, filename: node_filename, line_num: line || 0)
    else
      error = JunoTypeError.new(
        message,
        filename: node_filename,
        line_num: line,
        column: col,
        source: node_source
      )
      @errors << error
    end
  end

  def process_node(node)
    return unless node.is_a?(Hash)

    case node[:type]
    when :function_definition
      @var_states = {}
      @current_fn = node[:name]
      (node[:body] || []).each { |stmt| process_node(stmt) }
      
      unless @current_fn.end_with?('.init')
        @var_states.each do |name, info|
          if info[:state] == :owned
            report_error("Resource leak in function '#{@current_fn}': Resource '#{name}' (allocated at line #{info[:line]}) is never freed or closed", info[:node], true)
          end
        end
      end

    when :assignment
      name = node[:name] || ""
      expr = node[:expression]
      
      check_expression(expr) if expr.is_a?(Hash)

      if local_var = resolve_local_pointer(expr)
        @var_states[name] = { state: :local_ptr, target: local_var, line: node[:line], node: node }
      elsif expr.is_a?(Hash) && expr[:type] == :fn_call && allocates_resource?(expr[:name])
        unless name.include?('.')
          @var_states[name] = { state: :owned, line: node[:line], node: node }
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
          
          if state_info[:state] == :owned
            if name.include?('.')
              @var_states[src_name] = { state: :moved, line: node[:line], node: node }
            else
              @var_states[name] = { state: :owned, line: node[:line], node: node }
              @var_states[src_name] = { state: :moved, line: node[:line], node: node }
            end
          end
        end
      end

    when :deref_assign
      check_expression(node[:target])
      check_expression(node[:value])
      
      if local_var = resolve_local_pointer(node[:value])
        report_error("Escape error: storing pointer to local variable '#{local_var}' into a dereferenced pointer, causing it to escape function '#{@current_fn}' scope", node)
      end

    when :fn_call
      fn_name = node[:name] || ""
      args = node[:args] || []

      if consumes_resource?(fn_name)
        arg = args[0]
        if arg && arg[:type] == :variable
          v_name = arg[:name]
          if @var_states.key?(v_name)
            state_info = @var_states[v_name]
            if state_info[:state] == :moved
              report_error("Attempt to free already moved value '#{v_name}'", node)
            elsif state_info[:state] == :freed
              report_error("Double free/close detected for '#{v_name}'", node)
            end
            @var_states[v_name] = { state: :freed, line: node[:line], node: node }
          end
        end
      else
        args.each_with_index do |arg, idx|
          check_expression(arg)

          if arg[:type] == :variable
            v_name = arg[:name]
            if @var_states.key?(v_name) && @var_states[v_name][:state] == :owned
              if function_consumes_arg?(fn_name, idx)
                @var_states[v_name] = { state: :moved, line: node[:line], node: node }
              end
            end
          end
        end
      end

    when :return
      expr = node[:expression]
      
      if local_var = resolve_local_pointer(expr)
        report_error("Dangling pointer: returning pointer to local variable '#{local_var}' which will be destroyed when function '#{@current_fn}' returns", node)
      elsif expr.is_a?(Hash) && expr[:type] == :variable
        ret_name = expr[:name]
        if @var_states.key?(ret_name) && @var_states[ret_name][:state] == :owned
          @var_states[ret_name] = { state: :returned, line: node[:line], node: node }
        end
      end
      check_expression(expr) if expr.is_a?(Hash)

    when :if_statement
      saved_state = @var_states.dup.transform_values(&:dup)
      
      process_node(node[:condition])
      (node[:body] || []).each { |n| process_node(n) }
      
      then_state = @var_states
      then_returns = block_returns?(node[:body])

      @var_states = saved_state
      (node[:else_body] || []).each { |n| process_node(n) }
      
      else_state = @var_states
      else_returns = block_returns?(node[:else_body])

      if then_returns && else_returns
        @var_states = else_state
      elsif then_returns
        @var_states = else_state
      elsif else_returns
        @var_states = then_state
      else
        then_state.each do |name, info|
          if @var_states.key?(name)
            current = @var_states[name]
            if info[:state] != current[:state]
              if info[:state] == :freed || current[:state] == :freed
                @var_states[name] = { state: :freed, line: node[:line], node: node }
              elsif info[:state] == :moved || current[:state] == :moved
                @var_states[name] = { state: :moved, line: node[:line], node: node }
              end
            end
          else
            @var_states[name] = info
          end
        end
      end

    when :while_statement, :for_statement
      process_node(node[:condition]) if node[:condition]
      (node[:body] || []).each { |n| process_node(n) }
    end
  end

  def function_consumes_arg?(fn_name, arg_idx)
    return false if SAFE_FUNCTIONS.include?(fn_name)
    return false if fn_name.include?('.')
    
    if @fn_effects.key?(fn_name)
      fn_node = @ast.find { |n| n[:type] == :function_definition && n[:name] == fn_name }
      if fn_node
        param_name = (fn_node[:params] || [])[arg_idx]
        param_name = param_name[:name] if param_name.is_a?(Hash)
        return (@fn_effects[fn_name] || []).include?(param_name)
      end
    end
    
    consumes_resource?(fn_name) && arg_idx == 0
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
