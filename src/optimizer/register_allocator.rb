class RegisterAllocator
  ALLOCATABLE_REGS = [:rbx, :r12, :r13, :r14, :r15]

  def initialize
    @allocations = {}
  end

  def reset
    @allocations = {}
  end

  def allocate(nodes)
    # Very simple Linear Scan allocator
    # 1. Collect all variables and their last use index
    last_use = {}
    variables = []
    addressed_vars = [] # Variables that have their address taken (&x)

    nodes.each_with_index do |node, idx|
      find_vars(node).each do |v|
        last_use[v] = idx
        variables << v unless variables.include?(v)
      end
      addressed_vars += find_addressed_vars(node)
    end
    addressed_vars.uniq!

    # 2. Assign registers based on availability
    allocations = {}
    free_regs = ALLOCATABLE_REGS.dup
    active = [] # [{var: name, reg: sym, end: idx}]

    nodes.each_with_index do |node, idx|
      # Expire old intervals
      active.delete_if do |a|
        if a[:end] < idx
          free_regs.push(a[:reg])
          true
        else
          false
        end
      end

      # Allocate for variables defined here
      vars_defined = find_defined_vars(node)
      vars_defined.each do |v|
        next if allocations.key?(v) || free_regs.empty?
        next if addressed_vars.include?(v) # Skip variables with address taken

        reg = free_regs.shift
        allocations[v] = reg
        active << { var: v, reg: reg, end: last_use[v] }
      end
    end

    { allocations: allocations }
  end

  private

  def find_vars(node)
    return [] unless node.is_a?(Hash)
    vars = []
    case node[:type]
    when :variable then vars << node[:name]
    when :assignment then vars << node[:name] if node[:name]; vars += find_vars(node[:expression])
    when :binary_op then vars += find_vars(node[:left]) + find_vars(node[:right])
    when :fn_call then (node[:args] || []).each { |a| vars += find_vars(a) }
    when :if_statement
      vars += find_vars(node[:condition])
      (node[:body] || []).each { |n| vars += find_vars(n) }
      (node[:else_body] || []).each { |n| vars += find_vars(n) }
    when :while_statement
      vars += find_vars(node[:condition])
      (node[:body] || []).each { |n| vars += find_vars(n) }
    end
    vars.uniq
  end

  def find_defined_vars(node)
    return [] unless node.is_a?(Hash)
    if node[:type] == :assignment && node[:let] && node[:name]
      [node[:name]]
    else
      []
    end
  end

  def find_addressed_vars(node)
    return [] unless node.is_a?(Hash)
    case node[:type]
    when :address_of
      op = node[:operand]
      return [op[:name]] if op[:type] == :variable
      []
    when :binary_op then find_addressed_vars(node[:left]) + find_addressed_vars(node[:right])
    when :fn_call then (node[:args] || []).flat_map { |a| find_addressed_vars(a) }
    when :if_statement
      find_addressed_vars(node[:condition]) +
      (node[:body] || []).flat_map { |n| find_addressed_vars(n) } +
      (node[:else_body] || []).flat_map { |n| find_addressed_vars(n) }
    when :while_statement
      find_addressed_vars(node[:condition]) +
      (node[:body] || []).flat_map { |n| find_addressed_vars(n) }
    when :assignment then find_addressed_vars(node[:expression])
    else []
    end
  end
end
