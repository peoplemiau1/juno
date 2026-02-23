class ResourceAuditor
  def initialize(ast, functions = {}, source = "", filename = "")
    @ast = ast
    @functions = functions # name -> return_type
    @source = source
    @filename = filename
    @errors = []
  end

  def audit
    @ast.each do |node|
      if node[:type] == :function_definition
        audit_function(node)
      end
    end

    if @errors.any?
      @errors.each { |e| JunoErrorReporter.report(e) }
      exit 1
    end
  end

  private

  def audit_function(fn_node)
    @var_to_res = {} # var_name -> resource_id
    @res_status = {} # resource_id -> :born | :consumed
    @res_origin = {} # resource_id -> node
    @next_res_id = 1

    process_statements(fn_node[:body])

    @res_status.each do |res_id, status|
      if status == :born
        node = @res_origin[res_id]
        @errors << JunoResourceError.new(
          "Resource leaked: resource allocated here was never consumed",
          filename: @filename,
          line_num: node[:line],
          column: node[:column] || 0,
          source: @source
        )
      end
    end
  end

  def process_statements(statements)
    statements.each do |node|
      process_node(node, false)
    end
  end

  def process_node(node, consumed_by_parent = false)
    return unless node.is_a?(Hash)
    case node[:type]
    when :variable
      res_id = @var_to_res[node[:name]]
      if res_id && @res_status[res_id] == :consumed
        report_use_after_consume(node[:name], node)
      end

    when :member_access
      res_id = @var_to_res[node[:receiver]]
      if res_id && @res_status[res_id] == :consumed
        report_use_after_consume(node[:receiver], node)
      end

    when :array_access
      res_id = @var_to_res[node[:name]]
      if res_id && @res_status[res_id] == :consumed
        report_use_after_consume(node[:name], node)
      end
      process_node(node[:index])

    when :dereference
      process_node(node[:operand])

    when :array_assign
      res_id = @var_to_res[node[:name]]
      if res_id && @res_status[res_id] == :consumed
        report_use_after_consume(node[:name], node)
      end
      process_node(node[:index])
      process_node(node[:value])

    when :assignment
      # If RHS is a producing call, LHS becomes owner of a NEW resource
      if produces_resource?(node[:expression])
        process_node(node[:expression], true) # it's consumed by the assignment
        if !node[:name].include?('.')
          res_id = @next_res_id
          @next_res_id += 1
          @var_to_res[node[:name]] = res_id
          @res_status[res_id] = :born
          @res_origin[res_id] = node
        end
      elsif node[:expression][:type] == :variable && @var_to_res.key?(node[:expression][:name])
        # Alias/Copy ownership (sharing the same resource ID)
        old_var = node[:expression][:name]
        res_id = @var_to_res[old_var]

        if @res_status[res_id] == :consumed
           report_use_after_consume(old_var, node)
        else
           if !node[:name].include?('.')
              @var_to_res[node[:name]] = res_id
           else
              # Assignment to field counts as consumption/transfer
              @res_status[res_id] = :consumed
           end
        end
      else
        process_node(node[:expression])
      end

    when :fn_call
      # Check if this function consumes its arguments
      should_consume = consumes_resource?(node[:name])

      (node[:args] || []).each do |arg|
        if arg[:type] == :variable && @var_to_res.key?(arg[:name])
          res_id = @var_to_res[arg[:name]]
          if @res_status[res_id] == :consumed
            report_use_after_consume(arg[:name], arg)
          elsif should_consume
            @res_status[res_id] = :consumed
          end
        else
          process_node(arg, should_consume)
        end
      end

      if produces_resource?(node) && !consumed_by_parent
        @errors << JunoResourceError.new(
          "Unassigned resource: result of '#{node[:name]}' is never consumed",
          filename: @filename,
          line_num: node[:line] || 0,
          column: node[:column] || 0,
          source: @source
        )
      end

    when :return
      if node[:expression][:type] == :variable && @var_to_res.key?(node[:expression][:name])
        res_id = @var_to_res[node[:expression][:name]]
        if @res_status[res_id] == :consumed
           report_use_after_consume(node[:expression][:name], node)
        else
           @res_status[res_id] = :consumed
        end
      else
        process_node(node[:expression], true)
      end

    when :if_statement
      process_node(node[:condition], false)

      saved_status = @res_status.dup
      process_statements(node[:body])
      body_status = @res_status

      @res_status = saved_status.dup
      process_statements(node[:else_body]) if node[:else_body]
      else_status = @res_status

      # Merge: for strict audit, if it was consumed in ANY branch,
      # we consider it "potentially consumed" for future uses.
      @res_status = body_status
      else_status.each do |id, status|
        @res_status[id] = :consumed if status == :consumed
      end

    when :while_statement
      process_node(node[:condition], false)
      process_statements(node[:body])

    when :binary_op
      process_node(node[:left], false)
      process_node(node[:right], false)

    when :deref_assign
      process_node(node[:target], false)
      process_node(node[:value], false)
    end
  end

  def report_use_after_consume(name, node)
    @errors << JunoResourceError.new(
      "Use after consumption: variable '#{name}' was already consumed",
      filename: @filename,
      line_num: node[:line] || 0,
      column: node[:column] || 0,
      source: @source
    )
  end

  def produces_resource?(node)
    return false unless node.is_a?(Hash) && node[:type] == :fn_call
    name = node[:name]

    # Builtins that produce resources
    return true if ['malloc', 'os_alloc', 'json_loads', 'alloc_stack'].include?(name)

    # Only specific naming patterns for user functions for now
    return true if name.start_with?('create_') || name.start_with?('new_') || name.start_with?('alloc_')
    return true if ['parse_val', 'parse_str', 'parse_num', 'parse_arr', 'parse_obj'].include?(name)

    false
  end

  def consumes_resource?(fn_name)
    exempt = [
      'byte_at', 'byte_set', 'byte_add', 'ptr_add',
      'prints', 'print', 'printi', 'output_int',
      'memcpy', 'memset', 'str_len', 'str_copy', 'str_cat', 'str_cmp', 'str_equals', 'str_empty',
      'json_get', 'json_at', 'json_len', 'json_has', 'json_get_str', 'json_get_int', 'json_get_bool', 'json_is_null',
      'str_contains', 'vec_get', 'fs_write_text', 'fs_read', 'os_read_file', 'net_accept_client', 'net_recv', 'arena_alloc',
      'init', 'add', 'get', 'set', 'push', 'pop', 'at', 'match_kind', 'tokenize', 'parse_statement',
      'parse_val', 'parse_str', 'parse_num', 'parse_arr', 'parse_obj', 'str_new', 'vec_new', 'arena_new'
    ]
    !exempt.include?(fn_name)
  end
end

class JunoResourceError < JunoError
  def initialize(message, **opts)
    super("E0007", message, **opts)
  end
end
