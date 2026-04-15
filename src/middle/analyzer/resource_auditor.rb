class ResourceAuditor
  def initialize(ast, functions = {}, source = "", filename = "")
    @ast = ast
    @functions = functions
    @source = source
    @filename = filename
    @errors = []
  end

  def audit
    @ast.each do |node|
      audit_function(node) if node[:type] == :function_definition
    end
    if @errors.any?
      @errors.each { |e| JunoErrorReporter.report(e) }
      exit 1
    end
  end

  private

  def audit_function(fn_node)
    @var_to_res = {}
    @res_status = {}
    @res_origin = {}
    @next_res_id = 1
    process_statements(fn_node[:body])
    @res_status.each do |res_id, status|
      if status == :born
        node = @res_origin[res_id]
        @errors << JunoResourceError.new(
          "Resource leaked: resource allocated here was never consumed",
          filename: @filename, line_num: node[:line] || 0,
          column: node[:column] || 0, source: @source
        )
      end
    end
  end

  def process_statements(statements)
    statements.each { |node| process_node(node) }
  end

  def process_node(node, consumed_by_parent = false)
    return unless node.is_a?(Hash)
    case node[:type]
    when :variable
      check_use(node[:name], node)
    when :member_access
      check_use(node[:receiver], node)
    when :array_access, :array_assign
      check_use(node[:name], node)
      process_node(node[:index]); process_node(node[:value]) if node[:type] == :array_assign
    when :assignment
      if produces_resource?(node[:expression])
        process_node(node[:expression], true) # consumed by the assign
        if !node[:name].include?('.')
          res_id = (@next_res_id += 1) - 1
          @var_to_res[node[:name]] = res_id
          @res_status[res_id] = :born
          @res_origin[res_id] = node
        else
          # Special: Assignment to a field (self.data) counts as valid consumption
          # of the newly produced resource. It becomes part of the object.
        end
      elsif node[:expression][:type] == :variable && @var_to_res.key?(node[:expression][:name])
        old_var = node[:expression][:name]
        res_id = @var_to_res[old_var]
        if @res_status[res_id] == :consumed
          report_use_after_consume(old_var, node[:expression])
        elsif !sync_resource?(old_var) && !sync_resource?(node[:name])
          @res_status[res_id] = :consumed
        end
        @var_to_res[node[:name]] = res_id
      else
        process_node(node[:expression])
      end
    when :fn_call
      fn_name = node[:name]
      args = node[:args] || []
      should_consume = consumes_resource?(fn_name)
      forced_free = fn_name == 'free' || fn_name.include?('.free')
      
      # Handle receiver in method calls
      if fn_name.include?('.')
        recv = fn_name.split('.').first
        consume_var(recv) if (should_consume && !sync_resource?(recv)) || forced_free
      end

      # Handle thread_create specially
      if fn_name == 'thread_create'
        arg_node = args[1]
        if arg_node && arg_node[:type] == :variable
          consume_var(arg_node[:name]) unless sync_resource?(arg_node[:name])
        end
      else
        args.each do |arg|
          if arg[:type] == :variable
            consume_var(arg[:name]) if (should_consume && !sync_resource?(arg[:name])) || forced_free
          else
            process_node(arg, should_consume)
          end
        end
      end
    when :return
      if node[:expression][:type] == :variable
         consume_var(node[:expression][:name])
      else
         process_node(node[:expression], true)
      end
    when :if_statement
      process_node(node[:condition]); saved = @res_status.dup
      process_statements(node[:body]); b_stat = @res_status
      @res_status = saved.dup; process_statements(node[:else_body]) if node[:else_body]
      e_stat = @res_status; @res_status = b_stat
      e_stat.each { |id, s| @res_status[id] = :consumed if s == :consumed }
    when :while_statement
      process_node(node[:condition]); process_statements(node[:body])
    when :binary_op
      process_node(node[:left]); process_node(node[:right])
    when :deref_assign
      process_node(node[:target]); process_node(node[:value])
    end
  end

  def check_use(name, node)
    res_id = @var_to_res[name]
    report_use_after_consume(name, node) if res_id && @res_status[res_id] == :consumed
  end

  def consume_var(name)
    res_id = @var_to_res[name]
    @res_status[res_id] = :consumed if res_id
  end

  def report_use_after_consume(name, node)
    @errors << JunoResourceError.new("Use after consumption: variable '#{name}' was already consumed",
      filename: @filename, line_num: node[:line] || 0, column: node[:column] || 0, source: @source)
  end

  def sync_resource?(name)
    return false unless name
    n = name.downcase
    n.include?("atomic") || n.include?("mutex") || n.include?("lock") || n.include?("shared") || n.include?("spinlock") || n.include?("completion")
  end

  def produces_resource?(node)
    return false unless node.is_a?(Hash) && node[:type] == :fn_call
    ['malloc', 'os_alloc', 'alloc_stack'].include?(node[:name]) || node[:name].start_with?('create_') || node[:name].start_with?('new_')
  end

  def consumes_resource?(name)
    exempt = ['print', 'print_i', 'println', 'print_s', 'print_hex', 'memcpy', 'memset', 'ptr_add', 'len', 'init', 'add', 'get', 'set', 'push', 'pop', 'sleep', 'os_sleep', 'thread_create']
    !exempt.include?(name) && !name.include?('.get') && !name.include?('.size')
  end
end

class JunoResourceError < JunoError
  def initialize(message, **opts)
    super("E0007", message, **opts)
  end
end
