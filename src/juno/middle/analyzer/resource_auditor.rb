class ResourceAuditor
  def initialize(ast, functions = {}, source = "", filename = "")
    @ast = ast
    @functions = functions
    @source = source
    @filename = filename
    @errors = []
    @var_to_res = {}
    @res_status = {}
    @res_node = {}
    @next_res_id = 0
  end

  def audit
    @ast.each { |node| process_node(node) }
    
    # Check for leaks
    @res_status.each do |id, status|
      if status == :allocated
        node = @res_node[id]
        JunoErrorReporter.warn("Resource leak detected: Resource allocated but never freed/closed.", filename: @filename, line_num: node[:line] || 0)
      end
    end
  end

  def consumes_resource?(name)
    ['free', 'close', 'os_close', 'delete'].include?(name) || name.include?('.free')
  end

  def allocates_resource?(name)
    ['malloc', 'open', 'os_open', 'fopen'].include?(name)
  end

  def process_node(node)
    return unless node.is_a?(Hash)
    
    case node[:type]
    when :function_definition
      # Reset context for each function
      @var_to_res = {}
      @res_status = {}
      @res_node = {}
      (node[:body] || []).each { |n| process_node(n) }
      
      # Check for leaks at the end of the function
      @res_status.each do |id, status|
        if status == :allocated
          n = @res_node[id]
          JunoErrorReporter.warn("Resource leak in function '#{node[:name]}': Resource never freed.", filename: @filename, line_num: n[:line] || 0)
          @res_status[id] = :leaked # Mark to avoid double warning
        end
      end
    when :assignment
      if node[:expression][:type] == :fn_call && allocates_resource?(node[:expression][:name])
        res_id = @next_res_id += 1
        @var_to_res[node[:name]] = res_id
        @res_status[res_id] = :allocated
        @res_node[res_id] = node
      elsif node[:expression][:type] == :variable && @var_to_res.key?(node[:expression][:name])
        # Track aliasing
        @var_to_res[node[:name]] = @var_to_res[node[:expression][:name]]
      end
    when :fn_call
      fn_name = node[:name]
      if consumes_resource?(fn_name)
        (node[:args] || []).each do |arg|
          if arg[:type] == :variable
            name = arg[:name]
            if @var_to_res.key?(name)
              res_id = @var_to_res[name]
              @res_status[res_id] = :consumed if @res_status[res_id] == :allocated
            end
          end
        end
      end
    when :if_statement
      (node[:body] || []).each { |n| process_node(n) }
      (node[:else_body] || []).each { |n| process_node(n) }
    when :while_statement, :for_statement
      (node[:body] || []).each { |n| process_node(n) }
    end
  end
end
