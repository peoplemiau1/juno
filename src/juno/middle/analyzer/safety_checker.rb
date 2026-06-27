require_relative "../../errors"

class CFGBlock
  attr_reader   :id, :instructions, :preds, :succs
  attr_accessor :in_bindings, :in_values, :out_bindings, :out_values

  def initialize(id)
    @id            = id
    @instructions  = []
    @preds         = []
    @succs         = []
    @in_bindings   = {}
    @in_values     = {}
    @out_bindings  = {}
    @out_values    = {}
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

class VariableRenamer
  SCOPED_NODE_TYPES = %i[function_definition if_statement while_statement for_statement].freeze

  def initialize
    @scopes        = [{}]
    @scope_counter = 0
  end

  def rename(nodes)
    nodes.map { |n| rename_node(n) }
  end

  private

  def push_scope
    @scope_counter += 1
    @scopes.push({})
  end

  def pop_scope
    @scopes.pop
  end

  def declare(name)
    @scopes.last[name] = "scoped_#{name}_#{@scope_counter}"
  end

  def resolve(name)
    @scopes.reverse_each { |scope| return scope[name] if scope.key?(name) }
    name
  end

  def rename_node(node)
    return node unless node.is_a?(Hash)
    node = node.dup

    case node[:type]
    when :function_definition then rename_function(node)
    when :assignment          then rename_assignment(node)
    when :variable, :increment
      node[:name] = resolve(node[:name])
      node
    when :array_decl
      declare(node[:name])
      node[:name] = resolve(node[:name])
      node
    when :array_assign, :array_access
      node[:name]  = resolve(node[:name])
      node[:index] = rename_node(node[:index]) if node[:index]
      node[:value] = rename_node(node[:value]) if node[:value]
      node
    when :if_statement     then rename_if(node)
    when :while_statement  then rename_while(node)
    when :for_statement    then rename_for(node)
    else
      rename_children(node)
    end
  end

  def rename_function(node)
    push_scope
    params = node[:params] || []
    params.each { |p| declare(p.is_a?(Hash) ? p[:name] : p) }

    if node[:params]
      node[:params] = params.map do |p|
        if p.is_a?(Hash)
          p = p.dup
          p[:name] = resolve(p[:name])
          p
        else
          resolve(p)
        end
      end
    end

    node[:body] = rename(node[:body]) if node[:body]
    pop_scope
    node
  end

  def rename_assignment(node)
    if node[:let]
      node[:expression] = rename_node(node[:expression]) if node[:expression]
      declare(node[:name])
      node[:name] = resolve(node[:name])
    else
      node[:name]       = resolve(node[:name])
      node[:expression] = rename_node(node[:expression]) if node[:expression]
    end
    node
  end

  def rename_if(node)
    node[:condition] = rename_node(node[:condition]) if node[:condition]

    push_scope
    node[:body] = rename(node[:body]) if node[:body]
    pop_scope

    if node[:else_body]
      push_scope
      node[:else_body] = rename(node[:else_body])
      pop_scope
    end
    node
  end

  def rename_while(node)
    node[:condition] = rename_node(node[:condition]) if node[:condition]
    push_scope
    node[:body] = rename(node[:body]) if node[:body]
    pop_scope
    node
  end

  def rename_for(node)
    push_scope
    node[:init]      = rename_node(node[:init])      if node[:init]
    node[:condition] = rename_node(node[:condition]) if node[:condition]
    node[:update]    = rename_node(node[:update])    if node[:update]
    node[:body]      = rename(node[:body])           if node[:body]
    pop_scope
    node
  end

  def rename_children(node)
    node.each do |k, v|
      case v
      when Hash  then node[k] = rename_node(v)
      when Array then node[k] = v.map { |item| rename_node(item) }
      end
    end
    node
  end
end

class JunoSafetyChecker
  attr_reader :fn_effects

  ALLOCATORS = %w[malloc open os_open os_alloc mem_malloc fopen alloc].freeze
  CONSUMERS  = %w[free close os_close os_free mem_free delete].freeze

  def initialize(ast, _functions = {}, source = "", filename = "")
    @ast      = ast
    @source   = source
    @filename = filename

    @errors        = []
    @fn_effects    = {}
    @allocators    = ALLOCATORS.dup
    @consumers     = CONSUMERS.dup

    @val_counter        = 0
    @block_counter      = 0
    @current_fn         = nil
    @node_val_ids       = {}
    @stable_merge_ids   = {}
    @exit_block         = nil
  end

  def check
    @errors = []

    infer_allocators
    analyze_all_fn_effects

    @ast = VariableRenamer.new.rename(@ast)

    @ast.each do |node|
      process_function_cfg(node) if node[:type] == :function_definition
    end

    flush_errors
  end

  private

  def next_val_id;   @val_counter   += 1; end
  def next_block_id; @block_counter += 1; end
  def create_block;  CFGBlock.new(next_block_id); end

  def deep_copy_states(states)
    states.transform_values(&:dup)
  end

  def get_or_create_val_id(node, type, state, pool)
    id = @node_val_ids[node.object_id] ||= next_val_id
    if pool[id]
      pool[id] = pool[id].merge(state: state, type: type)
    else
      pool[id] = {
        type:   type,
        state:  state,
        line:   node[:line],
        column: node[:column],
        node:   node
      }
    end
    id
  end

  def get_stable_merge_id(block_id, path)
    @stable_merge_ids[[block_id, path]] ||= next_val_id
  end

  def build_cfg(statements, entry_block, exit_block)
    terminal = build_block_cfg(statements, entry_block, exit_block)
    terminal&.link_to(exit_block)
  end

  def build_block_cfg(statements, current, exit_block)
    return current unless statements.is_a?(Array)
    statements.each { |stmt| current = build_stmt_cfg(stmt, current, exit_block) }
    current
  end

  def build_stmt_cfg(stmt, current, exit_block)
    return nil if current.nil?
    return current unless stmt.is_a?(Hash)

    case stmt[:type]
    when :return
      current.add_instruction(stmt)
      current.link_to(@exit_block) if @exit_block
      nil
    when :if_statement    then build_if(stmt, current, exit_block)
    when :while_statement then build_while(stmt, current)
    when :for_statement   then build_for(stmt, current)
    else
      current.add_instruction(stmt)
      current
    end
  end

  def build_if(stmt, current, exit_block)
    then_block  = create_block
    else_block  = create_block
    merge_block = create_block

    current.add_instruction(stmt[:condition]) if stmt[:condition]
    current.link_to(then_block)
    current.link_to(else_block)

    build_block_cfg(stmt[:body]      || [], then_block, merge_block)&.link_to(merge_block)
    build_block_cfg(stmt[:else_body] || [], else_block, merge_block)&.link_to(merge_block)

    merge_block
  end

  def build_while(stmt, current)
    cond_block = create_block
    body_block = create_block
    post_block = create_block

    current.link_to(cond_block)
    cond_block.add_instruction(stmt[:condition]) if stmt[:condition]
    cond_block.link_to(body_block)
    cond_block.link_to(post_block)

    build_block_cfg(stmt[:body] || [], body_block, cond_block)&.link_to(cond_block)

    post_block
  end

  def build_for(stmt, current)
    init_block   = create_block
    cond_block   = create_block
    body_block   = create_block
    update_block = create_block
    post_block   = create_block

    current.link_to(init_block)
    init_block.add_instruction(stmt[:init]) if stmt[:init]
    init_block.link_to(cond_block)

    cond_block.add_instruction(stmt[:condition]) if stmt[:condition]
    cond_block.link_to(body_block)
    cond_block.link_to(post_block)

    build_block_cfg(stmt[:body] || [], body_block, update_block)&.link_to(update_block)

    update_block.add_instruction(stmt[:update]) if stmt[:update]
    update_block.link_to(cond_block)

    post_block
  end

  def resolve_access_path(expr)
    return nil unless expr.is_a?(Hash)

    case expr[:type]
    when :variable
      expr[:name]
    when :field_access
      receiver = resolve_access_path(expr[:receiver])
      field    = expr[:field] || expr[:name]
      receiver && field ? "#{receiver}.#{field}" : nil
    when :dereference
      path = resolve_access_path(expr[:operand] || expr[:expression])
      path ? "*#{path}" : nil
    when :address_of
      path = resolve_access_path(expr[:operand] || expr[:expression])
      path ? "&#{path}" : nil
    end
  end

  def lookup_val_id(path, bindings, values)
    return nil if path.nil?
    return bindings[path] if bindings.key?(path)

    parts = path.split('.')
    return nil if parts.size <= 1

    base_id = bindings[parts[0]]
    return nil unless base_id && values[base_id]

    target_path = [base_id, *parts[1..]].join('.')
    bindings[target_path]
  end

  def resolve_val_id_in_pool(expr, bindings, values)
    return nil unless expr.is_a?(Hash)

    if expr[:type] == :address_of
      operand = expr[:operand] || expr[:expression]
      return nil unless operand && operand[:type] == :variable

      target_id = lookup_val_id(operand[:name], bindings, values)
      return nil unless target_id

      ptr_id = get_or_create_val_id(expr, :stack_ptr, :owned, values)
      values[ptr_id][:target_id] = target_id
      ptr_id
    else
      lookup_val_id(resolve_access_path(expr), bindings, values)
    end
  end

  def propagate_bindings(src_path, dest_path, bindings)
    bindings.each do |path, val_id|
      next unless path.start_with?("#{src_path}.")
      sub_field = path[(src_path.length + 1)..]
      bindings["#{dest_path}.#{sub_field}"] = val_id
    end
  end

  def solve_cfg(entry_block)
    worklist = [entry_block]

    until worklist.empty?
      block = worklist.shift
      merged_bindings, merged_values = join_preds(block)

      block.in_bindings = merged_bindings
      block.in_values   = merged_values

      curr_bindings = merged_bindings.dup
      curr_values   = deep_copy_states(merged_values)

      block.instructions.each do |inst|
        curr_bindings, curr_values = transfer_instruction(inst, curr_bindings, curr_values, false)
      end

      next unless out_state_changed?(block, curr_bindings, curr_values)

      block.out_bindings = curr_bindings
      block.out_values   = curr_values
      block.succs.each { |succ| worklist << succ unless worklist.include?(succ) }
    end
  end

  def join_preds(block)
    preds = block.preds.select { |p| p.out_bindings && !p.out_bindings.empty? }
    return [block.in_bindings || {}, deep_copy_states(block.in_values || {})] if preds.empty?
    return [preds[0].out_bindings.dup, deep_copy_states(preds[0].out_values)] if preds.size == 1

    merged_bindings = {}
    merged_values   = {}

    preds.each do |pred|
      pred.out_values.each { |id, val| merged_values[id] ||= val.dup }
    end

    all_paths = preds.flat_map { |p| p.out_bindings.keys }.uniq

    all_paths.each do |path|
      pred_ids = preds.map { |p| p.out_bindings[path] }

      if pred_ids.uniq.size == 1
        val_id              = pred_ids.first
        merged_bindings[path] = val_id

        states = preds.map { |p| p.out_values[val_id]&.[](:state) || :moved }
        merged_values[val_id][:state] = states.reduce { |a, b| reconcile_states(a, b) }
      else
        merge_diverging_path(block, path, pred_ids, preds, merged_bindings, merged_values)
      end
    end

    [merged_bindings, merged_values]
  end

  def merge_diverging_path(block, path, pred_ids, preds, merged_bindings, merged_values)
    merged_id = get_stable_merge_id(block.id, path)

    states = preds.each_with_index.map do |p, idx|
      id = pred_ids[idx]
      id && p.out_values[id] ? p.out_values[id][:state] : :moved
    end
    merged_state = states.reduce { |a, b| reconcile_states(a, b) }

    types = preds.each_with_index.map do |p, idx|
      id = pred_ids[idx]
      id && p.out_values[id] ? p.out_values[id][:type] : :stack
    end
    merged_type = types.include?(:heap) ? :heap : :stack

    first_inst = block.instructions.first
    merged_values[merged_id] = {
      type:  merged_type,
      state: merged_state,
      line:  first_inst ? first_inst[:line] : 0,
      node:  first_inst
    }
    merged_bindings[path] = merged_id
  end

  def reconcile_states(s1, s2)
    return s1 if s1 == s2
    return s2 if s1 == :moved
    return s1 if s2 == :moved

    if (%i[freed maybe_freed].include?(s1) && %i[returned].include?(s2)) ||
       (%i[freed maybe_freed].include?(s2) && %i[returned].include?(s1))
      return :returned
    end

    return :maybe_freed if [s1, s2].any? { |s| %i[freed maybe_freed].include?(s) }
    return :maybe_moved if [s1, s2].any? { |s| %i[moved maybe_moved].include?(s) }

    if s1 == :returned || s2 == :returned
      any_owned = [s1, s2].any? { |s| %i[owned maybe_owned].include?(s) }
      return any_owned ? :maybe_owned : :returned
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

  def transfer_instruction(inst, bindings, values, validate)
    return [bindings, values] unless inst.is_a?(Hash)

    case inst[:type]
    when :assignment     then transfer_assignment(inst, bindings, values, validate)
    when :deref_assign   then transfer_deref_assign(inst, bindings, values, validate)
    when :fn_call        then transfer_fn_call(inst, bindings, values, validate)
    when :return         then transfer_return(inst, bindings, values, validate)
    end

    [bindings, values]
  end

  def transfer_assignment(inst, bindings, values, validate)
    name = inst[:name]
    expr = inst[:expression]

    if validate
      check_expression(expr, bindings, values) if expr.is_a?(Hash)
      detect_leak_on_reassign(inst, name, bindings, values) unless inst[:let]
    end

    if inst[:let]
      var_id = get_or_create_val_id(inst, :stack, :owned, values)
      bindings[name] = var_id
    end

    rhs_val_id = resolve_val_id_in_pool(expr, bindings, values)
    check_escape(name, rhs_val_id, bindings, values, inst) if validate && rhs_val_id

    bind_rhs_to_lhs(inst, name, expr, rhs_val_id, bindings, values)
  end

  def detect_leak_on_reassign(inst, name, bindings, values)
    old_id  = lookup_val_id(name, bindings, values)
    old_val = old_id && values[old_id]
    return unless old_val && old_val[:type] == :heap && old_val[:state] == :owned

    has_other_refs = bindings.any? { |path, id| path != name && id == old_id }
    return if has_other_refs

    report_error(
      "Resource leak: variable '#{name}' is reassigned before freeing its previously allocated resource",
      inst, true
    )
    old_val[:state] = :leaked
  end

  def bind_rhs_to_lhs(inst, name, expr, rhs_val_id, bindings, values)
    if expr.is_a?(Hash) && expr[:type] == :address_of
      operand = expr[:operand] || expr[:expression]
      return unless operand && operand[:type] == :variable

      target_id = lookup_val_id(operand[:name], bindings, values)
      return unless target_id

      ptr_id = get_or_create_val_id(expr, :stack_ptr, :owned, values)
      values[ptr_id][:target_id] = target_id
      bindings[name] = ptr_id

    elsif expr.is_a?(Hash) && expr[:type] == :fn_call && @allocators.include?(expr[:name])
      bindings[name] = get_or_create_val_id(expr, :heap, :owned, values)

    elsif rhs_val_id && values[rhs_val_id]
      bindings[name] = rhs_val_id
      rhs_path = resolve_access_path(expr)
      propagate_bindings(rhs_path, name, bindings) if rhs_path
    end
  end

  def transfer_deref_assign(inst, bindings, values, validate)
    return unless validate

    check_expression(inst[:target], bindings, values)
    check_expression(inst[:value],  bindings, values)

    lhs_path = resolve_access_path(inst[:target])
    rhs_id   = resolve_val_id_in_pool(inst[:value], bindings, values)
    check_escape(lhs_path, rhs_id, bindings, values, inst) if lhs_path && rhs_id
  end

  def transfer_fn_call(inst, bindings, values, validate)
    fn_name  = inst[:name] || ""
    args     = inst[:args] || []
    contract = get_function_contract(fn_name, args.size)

    args.each_with_index do |arg, idx|
      is_destr = (idx.zero? && @consumers.include?(fn_name))
      check_expression(arg, bindings, values, is_destr) if validate

      next unless (contract[:params][idx] || :borrowed) == :consumed
      consume_argument(arg, inst, bindings, values, validate)
    end
  end

  def consume_argument(arg, inst, bindings, values, validate)
    target_id = resolve_val_id_in_pool(arg, bindings, values)
    val       = target_id && values[target_id]
    return unless val

    case val[:state]
    when :freed
      report_error("Double free/close detected for value", inst) if validate
    when :moved
      report_error("Attempt to free already moved value", inst) if validate
    else
      val[:state]      = :freed
      val[:freed_line] = inst[:line]
    end
  end

  def transfer_return(inst, bindings, values, validate)
    expr = inst[:expression]
    return unless expr

    check_expression(expr, bindings, values) if validate

    target_id = resolve_val_id_in_pool(expr, bindings, values)
    val       = target_id && values[target_id]
    return unless val

    if val[:type] == :stack_ptr && val[:target_id]
      target_val = values[val[:target_id]]
      if validate && target_val && target_val[:type] == :stack
        report_error("Dangling pointer: returning pointer to local stack variable", inst)
      end
    elsif val[:type] == :heap
      val[:state] = :returned
      name = resolve_access_path(expr)
      if name
        orig_name = name.sub(/^scoped_/, '').sub(/_\d+$/, '')
        bindings.each do |path, val_id|
          if (path.start_with?("#{name}.") || path.start_with?("#{orig_name}.")) && values[val_id]
            values[val_id][:state] = :returned
          end
        end
      end
    end
  end

  def check_escape(lhs_path, rhs_val_id, bindings, values, node)
    rhs_val = rhs_val_id && values[rhs_val_id]
    return unless rhs_val && rhs_val[:type] == :stack_ptr && rhs_val[:target_id]

    target_val = values[rhs_val[:target_id]]
    return unless target_val && target_val[:type] == :stack

    lhs_base    = lhs_path.split('.').first.sub(/^\*+/, '')
    lhs_base_id = lookup_val_id(lhs_base, bindings, values)
    rhs_var     = bindings.key(rhs_val[:target_id]) || "local variable"

    if lhs_base_id && values[lhs_base_id] && values[lhs_base_id][:type] == :heap
      report_error(
        "Escape error: storing pointer to local stack variable '#{rhs_var}' into a heap-allocated resource",
        node
      )
    elsif lhs_path.start_with?('*')
      report_error("Escape error: storing pointer to local stack variable into a dereferenced target", node)
    end
  end

  def check_expression(expr, bindings, values, is_destructor_arg = false)
    return unless expr.is_a?(Hash)

    target_id = resolve_val_id_in_pool(expr, bindings, values)
    val       = target_id && values[target_id]
    report_state_violation(expr, val, is_destructor_arg) if val && val[:type] == :heap

    expr.each_value do |v|
      case v
      when Hash  then check_expression(v, bindings, values, is_destructor_arg)
      when Array then v.each { |i| check_expression(i, bindings, values, is_destructor_arg) if i.is_a?(Hash) }
      end
    end
  end

  def report_state_violation(expr, val, is_destructor_arg)
    case val[:state]
    when :freed
      return if is_destructor_arg
      report_error("Use-after-free: Value was freed at line #{val[:freed_line]}", expr)
    when :maybe_freed
      report_error("Conditional use-after-free: Value may have been freed at line #{val[:freed_line]}", expr)
    when :moved
      report_error("Use-after-move: Value was moved to #{val[:moved_to]} at line #{val[:moved_line]}", expr)
    when :maybe_moved
      report_error("Conditional use-after-move: Value may have been moved to #{val[:moved_to]} at line #{val[:moved_line]}", expr)
    end
  end

  def get_function_contract(fn_name, args_count)
    return { params: [],          return: :owned } if allocator_constructor?(fn_name)
    return { params: [:consumed], return: :void  } if @consumers.include?(fn_name)

    if @fn_effects.key?(fn_name)
      param_specs = Array.new(args_count, :borrowed)
      @fn_effects[fn_name].each { |idx| param_specs[idx] = :consumed if idx < args_count }
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

  def allocator_constructor?(fn_name)
    %w[malloc alloc os_alloc mem_malloc].include?(fn_name)
  end

  def process_function_cfg(fn_node)
    @block_counter = 0
    @current_fn    = fn_node[:name]

    entry_block = create_block
    @exit_block = create_block

    init_param_bindings(fn_node, entry_block)
    build_cfg(fn_node[:body] || [], entry_block, @exit_block)
    solve_cfg(entry_block)
    verify_cfg(entry_block)

    report_unfreed_resources(@exit_block) unless @current_fn.end_with?('.init')
  end

  def init_param_bindings(fn_node, entry_block)
    (fn_node[:params] || []).each do |param|
      p_name   = param.is_a?(Hash) ? param[:name] : param
      param_id = get_or_create_val_id(fn_node, :stack, :owned, entry_block.in_values)
      entry_block.in_bindings[p_name] = param_id
    end
  end

  def report_unfreed_resources(exit_block)
    returned_nodes = []
    exit_block.in_values.each do |_, val|
      if val[:type] == :heap && val[:state] == :returned
        returned_nodes << val[:node].object_id if val[:node]
      end
    end

    exit_block.in_values.each do |_, val|
      next unless val[:type] == :heap
      next if val[:node] && returned_nodes.include?(val[:node].object_id)

      case val[:state]
      when :owned
        report_error(
          "Resource leak: heap resource allocated at line #{val[:line]} is never freed or returned",
          val[:node], true
        )
      when :maybe_owned, :maybe_freed, :maybe_moved
        report_error(
          "Potential resource leak: heap resource allocated at line #{val[:line]} may not be freed or returned on all paths",
          val[:node], true
        )
      end
    end
  end

  def verify_cfg(entry_block)
    visited = {}
    queue   = [entry_block]

    until queue.empty?
      block = queue.shift
      next if visited[block.id]
      visited[block.id] = true

      curr_bindings = block.in_bindings.dup
      curr_values   = deep_copy_states(block.in_values)

      block.instructions.each do |inst|
        curr_bindings, curr_values = transfer_instruction(inst, curr_bindings, curr_values, true)
      end

      block.succs.each { |succ| queue << succ unless visited[succ.id] }
    end
  end

  def try_all_decls(nodes)
    decls = []
    nodes.each do |n|
      next unless n.is_a?(Hash)
      if (n[:type] == :assignment && n[:let]) || n[:type] == :array_decl
        decls << n
      elsif n[:type] == :if_statement
        decls += try_all_decls(n[:body])
        (n[:elif_branches] || []).each { |elif| decls += try_all_decls(elif[:body]) }
        decls += try_all_decls(n[:else_body] || [])
      elsif n[:type] == :while_statement
        decls += try_all_decls(n[:body])
      elsif n[:type] == :for_statement
        decls << n[:init] if n[:init] && n[:init][:type] == :assignment
        decls += try_all_decls(n[:body])
      elsif n[:type] == :match_expression
        n[:cases].each do |c|
          decls += try_decls_in_pattern(c[:pattern])
          decls += try_all_decls(c[:body]) if c[:body].is_a?(Array)
        end
      end
    end
    decls
  end

  def try_decls_in_pattern(pattern)
    case pattern[:type]
    when :bind_pattern
      [{ type: :assignment, let: true, name: pattern[:name] }]
    when :variant_pattern
      (pattern[:fields] || []).map { |f| { type: :assignment, let: true, name: f } }
    else
      []
    end
  end

  def infer_allocators
    fixed_point do
      changed = false
      @ast.each do |node|
        next unless node[:type] == :function_definition
        name = node[:name]
        next if @allocators.include?(name)
        next unless decides_to_allocate?(node)

        @allocators << name
        changed = true
      end
      changed
    end
  end

  def decides_to_allocate?(fn_node)
    found = false
    walk_ast(fn_node[:body]) do |node|
      next unless %i[assignment return].include?(node[:type])
      expr = node[:expression]
      found = true if expr.is_a?(Hash) && expr[:type] == :fn_call && @allocators.include?(expr[:name])
    end
    found
  end

  def analyze_all_fn_effects
    @fn_effects = {}
    fixed_point do
      changed = false
      @ast.each do |node|
        next unless node[:type] == :function_definition
        new_effects = analyze_fn_effects(node)
        if new_effects != @fn_effects[node[:name]]
          @fn_effects[node[:name]] = new_effects
          changed = true
        end
      end
      changed
    end
  end

  def analyze_fn_effects(fn_node)
    params   = (fn_node[:params] || []).map { |p| p.is_a?(Hash) ? p[:name] : p }
    consumed = []

    walk_ast(fn_node[:body]) do |node|
      next unless node[:type] == :fn_call
      collect_consumed_args(node, params, consumed)
    end

    consumed.uniq
  end

  def collect_consumed_args(call_node, params, consumed)
    fn_name = call_node[:name]
    args    = call_node[:args] || []

    if @consumers.include?(fn_name)
      idx = params.index(extract_variable_name(args[0]))
      consumed << idx if idx
    elsif @fn_effects[fn_name]
      args.each_with_index do |arg, i|
        next unless @fn_effects[fn_name].include?(i)
        idx = params.index(extract_variable_name(arg))
        consumed << idx if idx
      end
    end
  end

  def extract_variable_name(expr)
    return nil unless expr.is_a?(Hash)
    case expr[:type]
    when :variable
      expr[:name]
    when :address_of, :dereference
      extract_variable_name(expr[:operand] || expr[:expression])
    end
  end

  def walk_ast(node, &block)
    return unless node

    if node.is_a?(Array)
      node.each { |n| walk_ast(n, &block) }
      return
    end

    return unless node.is_a?(Hash)

    yield node
    node.each_value do |v|
      case v
      when Hash, Array then walk_ast(v, &block)
      end
    end
  end

  def fixed_point
    loop { break unless yield }
  end

  def report_error(message, node, is_warning = false)
    line          = node && node[:line]
    col           = node && node[:column]
    node_filename = (node && node[:filename]) || @filename
    node_source   = source_for(node)

    if is_warning
      JunoErrorReporter.warn(message, filename: node_filename, line_num: line || 0)
    else
      @errors << JunoTypeError.new(
        message,
        filename: node_filename,
        line_num: line,
        column:   col,
        source:   node_source
      )
    end
  end

  def source_for(node)
    return @source unless node && node[:filename] && node[:filename] != @filename
    File.read(node[:filename]) rescue @source
  end

  def flush_errors
    return if @errors.empty?
    @errors.each(&:display)
    exit 1
  end
end
