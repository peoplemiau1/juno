require_relative "../../errors"

class CFGBlock
  attr_reader :id, :instructions, :preds, :succs
  attr_accessor :in_bindings, :in_values, :out_bindings, :out_values

  def initialize(id)
    @id = id
    @instructions = []
    @preds = []
    @succs = []
    @in_bindings = {}
    @in_values = {}
    @out_bindings = {}
    @out_values = {}
  end

  def add_instruction(inst)
    @instructions << inst
  end

  def link_to(other)
    return if @succs.include?(other)
    @succs << other
    other.preds << self
  end
end

class JunoSafetyChecker
  attr_reader :fn_effects

  SAFE_FUNCTIONS = %w[
    print print_s println print_i print_hex print_newline print_space
    write read output putc puts
    strlen streq str_hash str_find str_contains str_substring
    concat substr ord chr itoa format_print
    ptr_add memset memcpy memmove
    square cube abs_val min_val max_val factorial gcd ipow
  ].freeze

  def initialize(ast, functions = {}, source = "", filename = "")
    @ast = ast
    @functions = functions
    @source = source
    @filename = filename
    @errors = []
    @fn_effects = {}
    @allocators = ['malloc', 'open', 'os_open', 'os_alloc', 'mem_malloc', 'fopen', 'alloc']
    @consumers = ['free', 'close', 'os_close', 'os_free', 'mem_free', 'delete']
    
    @bindings = {}
    @values = {}
    @val_counter = 0
    @block_counter = 0
    @current_fn = nil
    @scope_stack = []
    @node_val_ids = {}
  end

  def check
    @errors = []
    infer_allocators
    analyze_all_fn_effects
    
    @ast.each do |node|
      next unless node[:type] == :function_definition
      process_function_cfg(node)
    end

    unless @errors.empty?
      @errors.each(&:display)
      exit 1
    end
  end

  private

  def next_val_id
    @val_counter += 1
  end

  def next_block_id
    @block_counter += 1
  end

  def create_block
    CFGBlock.new(next_block_id)
  end

  def deep_copy_states(states)
    states.transform_values { |v| v.dup }
  end

  def get_or_create_val_id(node, type, state, pool)
    id = @node_val_ids[node.object_id] ||= next_val_id
    pool[id] ||= {
      type: type,
      state: state,
      line: node[:line],
      column: node[:column],
      node: node
    }
    id
  end

  def build_cfg(statements, entry_block, exit_block)
    current = entry_block
    statements.each do |stmt|
      current = build_stmt_cfg(stmt, current, exit_block)
    end
    current.link_to(exit_block) if current
  end

  def build_block_cfg(statements, current, exit_block)
    return current unless statements.is_a?(Array)
    scope_id = next_val_id
    scope_start = { type: :scope_start, scope_id: scope_id }
    scope_end = { type: :scope_end, scope_id: scope_id }
    
    current.add_instruction(scope_start)
    statements.each do |stmt|
      current = build_stmt_cfg(stmt, current, exit_block)
    end
    current.add_instruction(scope_end) if current
    current
  end

  def build_stmt_cfg(stmt, current, exit_block)
    return current unless stmt.is_a?(Hash)

    case stmt[:type]
    when :if_statement
      then_block = create_block
      else_block = create_block
      merge_block = create_block

      current.add_instruction(stmt[:condition]) if stmt[:condition]
      current.link_to(then_block)
      current.link_to(else_block)

      then_terminal = build_block_cfg(stmt[:body] || [], then_block, merge_block)
      then_terminal.link_to(merge_block) if then_terminal

      else_terminal = build_block_cfg(stmt[:else_body] || [], else_block, merge_block)
      else_terminal.link_to(merge_block) if else_terminal

      merge_block
    when :while_statement
      cond_block = create_block
      body_block = create_block
      post_block = create_block

      current.link_to(cond_block)

      cond_block.add_instruction(stmt[:condition]) if stmt[:condition]
      cond_block.link_to(body_block)
      cond_block.link_to(post_block)

      body_terminal = build_block_cfg(stmt[:body] || [], body_block, cond_block)
      body_terminal.link_to(cond_block) if body_terminal

      post_block
    when :for_statement
      init_block = create_block
      cond_block = create_block
      body_block = create_block
      update_block = create_block
      post_block = create_block

      current.link_to(init_block)
      init_block.add_instruction(stmt[:init]) if stmt[:init]
      init_block.link_to(cond_block)

      cond_block.add_instruction(stmt[:condition]) if stmt[:condition]
      cond_block.link_to(body_block)
      cond_block.link_to(post_block)

      body_terminal = build_block_cfg(stmt[:body] || [], body_block, update_block)
      body_terminal.link_to(update_block) if body_terminal

      update_block.add_instruction(stmt[:update]) if stmt[:update]
      update_block.link_to(cond_block)

      post_block
    else
      current.add_instruction(stmt)
      current
    end
  end

  def resolve_access_path(expr)
    return nil unless expr.is_a?(Hash)
    case expr[:type]
    when :variable
      expr[:name]
    when :field_access
      receiver = resolve_access_path(expr[:receiver])
      field = expr[:field] || expr[:name]
      receiver && field ? "#{receiver}.#{field}" : nil
    when :dereference
      operand = expr[:operand] || expr[:expression]
      path = resolve_access_path(operand)
      path ? "*#{path}" : nil
    when :address_of
      operand = expr[:operand] || expr[:expression]
      path = resolve_access_path(operand)
      path ? "&#{path}" : nil
    else
      nil
    end
  end

  def lookup_val_id(path, bindings, values)
    return nil if path.nil?
    return bindings[path] if bindings.key?(path)

    parts = path.split('.')
    if parts.size > 1
      base_name = parts[0]
      base_id = bindings[base_name]
      if base_id && values[base_id]
        target_path = [base_id, *parts[1..]].join('.')
        return bindings[target_path] if bindings.key?(target_path)
      end
    end
    nil
  end

  def resolve_val_id_in_pool(expr, bindings, values)
    return nil unless expr.is_a?(Hash)
    path = resolve_access_path(expr)
    lookup_val_id(path, bindings, values)
  end

  def propagate_bindings(src_path, dest_path, bindings)
    bindings.each do |path, val_id|
      if path.start_with?("#{src_path}.")
        sub_field = path[(src_path.length + 1)..-1]
        bindings["#{dest_path}.#{sub_field}"] = val_id
      end
    end
  end

  def solve_cfg(entry_block)
    worklist = [entry_block]
    
    while worklist.any?
      block = worklist.shift
      
      merged_bindings, merged_values = join_preds(block)
      block.in_bindings = merged_bindings
      block.in_values = merged_values

      curr_bindings = merged_bindings.dup
      curr_values = deep_copy_states(merged_values)

      block.instructions.each do |inst|
        curr_bindings, curr_values = transfer_instruction(inst, curr_bindings, curr_values, false)
      end

      if out_state_changed?(block, curr_bindings, curr_values)
        block.out_bindings = curr_bindings
        block.out_values = curr_values
        block.succs.each do |succ|
          worklist << succ unless worklist.include?(succ)
        end
      end
    end
  end

  def join_preds(block)
    preds = block.preds.select { |p| p.out_bindings && !p.out_bindings.empty? }
    if preds.empty?
      return [block.in_bindings || {}, deep_copy_states(block.in_values || {})]
    end
    return [preds[0].out_bindings.dup, deep_copy_states(preds[0].out_values)] if preds.size == 1

    merged_bindings = {}
    merged_values = {}

    preds.each do |pred|
      pred.out_values.each do |id, val|
        merged_values[id] ||= val.dup
      end
    end

    all_paths = preds.flat_map { |p| p.out_bindings.keys }.uniq

    all_paths.each do |path|
      pred_ids = preds.map { |p| p.out_bindings[path] }
      
      if pred_ids.uniq.size == 1
        val_id = pred_ids.first
        merged_bindings[path] = val_id

        states = preds.map { |p| p.out_values[val_id] ? p.out_values[val_id][:state] : :moved }
        merged_values[val_id][:state] = states.reduce { |s1, s2| reconcile_states(s1, s2) }
      else
        merged_id = next_val_id
        states = preds.map.with_index do |p, idx|
          id = pred_ids[idx]
          id && p.out_values[id] ? p.out_values[id][:state] : :moved
        end
        merged_state = states.reduce { |s1, s2| reconcile_states(s1, s2) }

        types = preds.map.with_index do |p, idx|
          id = pred_ids[idx]
          id && p.out_values[id] ? p.out_values[id][:type] : :stack
        end
        merged_type = types.include?(:heap) ? :heap : :stack

        merged_values[merged_id] = {
          type: merged_type,
          state: merged_state,
          line: block.instructions.first ? block.instructions.first[:line] : 0,
          node: block.instructions.first
        }
        merged_bindings[path] = merged_id
      end
    end

    [merged_bindings, merged_values]
  end

  def reconcile_states(s1, s2)
    return s1 if s1 == s2
    return :maybe_freed if s1 == :freed || s2 == :freed || s1 == :maybe_freed || s2 == :maybe_freed
    return :maybe_moved if s1 == :moved || s2 == :moved || s1 == :maybe_moved || s2 == :maybe_moved
    if s1 == :returned || s2 == :returned
      return (s1 == :owned || s2 == :owned || s1 == :maybe_owned || s2 == :maybe_owned) ? :maybe_owned : :returned
    end
    :maybe_owned
  end

  def out_state_changed?(block, new_bindings, new_values)
    return true if block.out_bindings.nil? || block.out_bindings != new_bindings
    block.out_values.each do |id, val|
      new_val = new_values[id]
      return true if new_val.nil? || new_val[:state] != val[:state]
    end
    false
  end

  def transfer_instruction(inst, bindings, values, validate = false)
    return [bindings, values] unless inst.is_a?(Hash)

    case inst[:type]
    when :scope_start
      @scope_stack.push({})
    when :scope_end
      exited_scope = @scope_stack.pop
      if exited_scope && validate
        exited_scope.each do |name, old_val_id|
          val_id = bindings[name]
          if val_id && values[val_id]
            val = values[val_id]
            if val[:type] == :heap && val[:state] == :owned
              report_error("Resource leak: heap resource allocated at line #{val[:line]} is never freed or returned", val[:node], true)
              val[:state] = :leaked
            end
          end
          if old_val_id.nil?
            bindings.delete(name)
          else
            bindings[name] = old_val_id
          end
        end
      end
    when :assignment
      name = inst[:name]
      expr = inst[:expression]

      if validate
        check_expression(expr, bindings, values) if expr.is_a?(Hash)
        
        if !inst[:let] && (old_id = lookup_val_id(name, bindings, values)) && values[old_id]
          old_val = values[old_id]
          if old_val[:type] == :heap && old_val[:state] == :owned
            has_other_refs = bindings.any? { |path, id| path != name && id == old_id }
            unless has_other_refs
              report_error("Resource leak: variable '#{name}' is reassigned before freeing its previously allocated resource", inst, true)
              old_val[:state] = :leaked
            end
          end
        end
      end

      if inst[:let]
        if @scope_stack.any? && !@scope_stack.last.key?(name)
          @scope_stack.last[name] = bindings[name]
        end
        var_val_id = get_or_create_val_id(inst, :stack, :owned, values)
        bindings[name] = var_val_id
      end

      rhs_val_id = resolve_val_id_in_pool(expr, bindings, values)

      if validate && rhs_val_id
        check_escape(name, rhs_val_id, bindings, values, inst)
      end

      if expr.is_a?(Hash) && expr[:type] == :address_of
        operand = expr[:operand] || expr[:expression]
        if operand && operand[:type] == :variable
          target_id = lookup_val_id(operand[:name], bindings, values)
          if target_id
            ptr_val_id = get_or_create_val_id(expr, :stack_ptr, :owned, values)
            values[ptr_val_id][:target_id] = target_id
            bindings[name] = ptr_val_id
          end
        end
      elsif expr.is_a?(Hash) && expr[:type] == :fn_call && @allocators.include?(expr[:name])
        heap_val_id = get_or_create_val_id(expr, :heap, :owned, values)
        bindings[name] = heap_val_id
      elsif rhs_val_id
        rhs_val = values[rhs_val_id]
        if rhs_val
          bindings[name] = rhs_val_id
          rhs_path = resolve_access_path(expr)
          propagate_bindings(rhs_path, name, bindings) if rhs_path
        end
      end

    when :deref_assign
      if validate
        check_expression(inst[:target], bindings, values)
        check_expression(inst[:value], bindings, values)
      end

      lhs_path = resolve_access_path(inst[:target])
      rhs_id = resolve_val_id_in_pool(inst[:value], bindings, values)
      
      if validate && lhs_path && rhs_id
        check_escape(lhs_path, rhs_id, bindings, values, inst)
      end

    when :fn_call
      fn_name = inst[:name] || ""
      args = inst[:args] || []
      contract = get_function_contract(fn_name, args.size)

      args.each_with_index do |arg, idx|
        is_destr = (idx == 0 && @consumers.include?(fn_name))
        check_expression(arg, bindings, values, is_destr) if validate

        param_spec = contract[:params][idx] || :borrowed
        if param_spec == :consumed
          target_id = resolve_val_id_in_pool(arg, bindings, values)
          if target_id && values[target_id]
            val = values[target_id]
            if val[:state] == :freed
              report_error("Double free/close detected for value", inst) if validate
            elsif val[:state] == :moved
              report_error("Attempt to free already moved value", inst) if validate
            else
              values[target_id][:state] = :freed
              values[target_id][:freed_line] = inst[:line]
            end
          end
        end
      end

    when :return
      expr = inst[:expression]
      if expr
        check_expression(expr, bindings, values) if validate
        target_id = resolve_val_id_in_pool(expr, bindings, values)
        if target_id && values[target_id]
          val = values[target_id]
          if val[:type] == :stack_ptr && val[:target_id]
            target_val = values[val[:target_id]]
            if target_val && target_val[:type] == :stack
              report_error("Dangling pointer: returning pointer to local stack variable", inst) if validate
            end
          elsif val[:type] == :heap && val[:state] == :owned
            values[target_id][:state] = :returned
          end
        end
      end
    end

    [bindings, values]
  end

  def check_escape(lhs_path, rhs_val_id, bindings, values, node)
    return unless rhs_val_id && values[rhs_val_id]
    rhs_val = values[rhs_val_id]
    
    if rhs_val[:type] == :stack_ptr && rhs_val[:target_id]
      target_val = values[rhs_val[:target_id]]
      if target_val && target_val[:type] == :stack
        lhs_base = lhs_path.split('.').first
        lhs_base_id = lookup_val_id(lhs_base, bindings, values)
        rhs_var_name = bindings.key(rhs_val[:target_id]) || "local variable"
        if lhs_base_id && values[lhs_base_id] && values[lhs_base_id][:type] == :heap
          report_error("Escape error: storing pointer to local stack variable '#{rhs_var_name}' into a heap-allocated resource", node)
        elsif lhs_path.start_with?('*')
          report_error("Escape error: storing pointer to local stack variable into a dereferenced target", node)
        end
      end
    end
  end

  def get_function_contract(fn_name, args_count)
    if fn_name == "malloc" || fn_name == "alloc" || fn_name == "os_alloc" || fn_name == "mem_malloc"
      return { params: [], return: :owned }
    elsif @consumers.include?(fn_name)
      return { params: [:consumed], return: :void }
    end

    if @fn_effects.key?(fn_name)
      param_specs = Array.new(args_count, :borrowed)
      @fn_effects[fn_name].each do |idx|
        param_specs[idx] = :consumed if idx < param_specs.size
      end
      return {
        params: param_specs,
        return: @allocators.include?(fn_name) ? :owned : :borrowed
      }
    end

    {
      params: Array.new(args_count, :borrowed),
      return: @allocators.include?(fn_name) ? :owned : :borrowed
    }
  end

  def process_function_cfg(fn_node)
    @block_counter = 0
    @scope_stack = [{}]
    @current_fn = fn_node[:name]

    entry_block = create_block
    exit_block = create_block

    params = fn_node[:params] || []
    params.each do |param|
      p_name = param.is_a?(Hash) ? param[:name] : param
      param_val_id = get_or_create_val_id(fn_node, :stack, :owned, entry_block.in_values)
      entry_block.in_bindings[p_name] = param_val_id
    end

    build_cfg(fn_node[:body] || [], entry_block, exit_block)

    solve_cfg(entry_block)

    verify_cfg(entry_block)

    unless @current_fn.end_with?('.init')
      exit_block.in_values.each do |id, val|
        next unless val[:type] == :heap
        case val[:state]
        when :owned
          report_error("Resource leak: heap resource allocated at line #{val[:line]} is never freed or returned", val[:node], true)
        when :maybe_owned, :maybe_freed, :maybe_moved
          report_error("Potential resource leak: heap resource allocated at line #{val[:line]} may not be freed or returned on all paths", val[:node], true)
        end
      end
    end
  end

  def verify_cfg(entry_block)
    visited = {}
    queue = [entry_block]
    while queue.any?
      block = queue.shift
      next if visited[block.id]
      visited[block.id] = true

      curr_bindings = block.in_bindings.dup
      curr_values = deep_copy_states(block.in_values)

      block.instructions.each do |inst|
        curr_bindings, curr_values = transfer_instruction(inst, curr_bindings, curr_values, true)
      end

      block.succs.each { |succ| queue << succ unless visited[succ.id] }
    end
  end

  def check_expression(expr, bindings, values, is_destructor_arg = false)
    return unless expr.is_a?(Hash)

    target_id = resolve_val_id_in_pool(expr, bindings, values)
    if target_id && values[target_id]
      val = values[target_id]
      case val[:state]
      when :freed
        unless is_destructor_arg
          report_error("Use-after-free: Value was freed at line #{val[:freed_line]}", expr)
        end
      when :maybe_freed
        report_error("Conditional use-after-free: Value may have been freed at line #{val[:freed_line]}", expr)
      when :moved
        report_error("Use-after-move: Value was moved to #{val[:moved_to]} at line #{val[:moved_line]}", expr)
      when :maybe_moved
        report_error("Conditional use-after-move: Value may have been moved to #{val[:moved_to]} at line #{val[:moved_line]}", expr)
      end
    end

    expr.values.each do |v|
      if v.is_a?(Hash)
        check_expression(v, bindings, values, is_destructor_arg)
      elsif v.is_a?(Array)
        v.each { |i| check_expression(i, bindings, values, is_destructor_arg) if i.is_a?(Hash) }
      end
    end
  end

  def infer_allocators
    changed = true
    while changed
      changed = false
      @ast.each do |node|
        next unless node[:type] == :function_definition
        name = node[:name]
        next if @allocators.include?(name)
        if decides_to_allocate?(node)
          @allocators << name
          changed = true
        end
      end
    end
  end

  def decides_to_allocate?(fn_node)
    allocator_found = false
    walker = ->(node) {
      return unless node.is_a?(Hash)
      if node[:type] == :assignment
        expr = node[:expression]
        if expr.is_a?(Hash) && expr[:type] == :fn_call && @allocators.include?(expr[:name])
          allocator_found = true
        end
      elsif node[:type] == :return
        expr = node[:expression]
        if expr.is_a?(Hash) && expr[:type] == :fn_call && @allocators.include?(expr[:name])
          allocator_found = true
        end
      end
      node.values.each do |v|
        if v.is_a?(Hash)
          walker.call(v)
        elsif v.is_a?(Array)
          v.each { |i| walker.call(i) }
        end
      end
    }
    walker.call(fn_node[:body])
    allocator_found
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
    consumed_indices = []
    params = (fn_node[:params] || []).map { |p| p.is_a?(Hash) ? p[:name] : p }
    walker = ->(node) {
      return unless node.is_a?(Hash)
      if node[:type] == :fn_call
        fn_name = node[:name]
        if @consumers.include?(fn_name)
          arg_name = extract_variable_name(node[:args]&.[](0))
          if arg_name && params.include?(arg_name)
            consumed_indices << params.index(arg_name)
          end
        elsif @fn_effects[fn_name]
          node[:args]&.each_with_index do |arg, idx|
            arg_name = extract_variable_name(arg)
            if arg_name && params.include?(arg_name) && @fn_effects[fn_name].include?(idx)
              consumed_indices << params.index(arg_name)
            end
          end
        end
      end
      node.values.each do |v|
        if v.is_a?(Array)
          v.each { |i| walker.call(i) if i.is_a?(Hash) }
        elsif v.is_a?(Hash)
          walker.call(v)
        end
      end
    }
    walker.call(fn_node[:body])
    consumed_indices.uniq
  end

  def extract_variable_name(expr)
    return nil unless expr.is_a?(Hash)
    case expr[:type]
    when :variable
      expr[:name]
    when :address_of, :dereference
      operand = expr[:operand] || expr[:expression]
      extract_variable_name(operand)
    else
      nil
    end
  end

  def report_error(message, node, is_warning = false)
    line = node ? node[:line] : nil
    col = node ? node[:column] : nil
    node_filename = (node && node[:filename]) || @filename
    node_source = @source
    if node && node[:filename] && node[:filename] != @filename
      begin
        node_source = File.read(node[:filename])
      rescue
      end
    end
    if is_warning
      JunoErrorReporter.warn(message, filename: node_filename, line_num: line || 0)
    else
      @errors << JunoTypeError.new(message, filename: node_filename, line_num: line, column: col, source: node_source)
    end
  end
end
