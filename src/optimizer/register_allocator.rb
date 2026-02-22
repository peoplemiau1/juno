class RegisterAllocator
  X86_64_REGS = [:rbx, :r12, :r13, :r14, :r15]
  AARCH64_REGS = [19, 20, 21, 22, 23, 24, 25, 26, 27, 28]

  def initialize(arch = :x86_64)
    @arch = arch
    @allocatable_regs = (arch == :aarch64) ? AARCH64_REGS : X86_64_REGS
  end

  def allocate(nodes, globals = [])
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

    # 2. Assign registers based on availability (Linear Scan with Spilling)
    allocations = {}
    spilled = []
    free_regs = @allocatable_regs.dup
    active = [] # [{var: name, reg: sym, end: idx}]

    nodes.each_with_index do |node, idx|
      # Expire old intervals
      active.sort_by! { |a| a[:end] }
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
        next if globals.include?(v) # NEVER allocate registers for globals
        next if addressed_vars.include?(v) # Skip variables with address taken
        next if allocations.key?(v) || spilled.include?(v)

        if free_regs.empty?
          # Register pressure: spill the interval that ends farthest
          spill_candidate = active.max_by { |a| a[:end] }

          if spill_candidate && spill_candidate[:end] > last_use[v]
            # Spill candidate ends later than current var v.
            # Steal register from candidate.
            reg = spill_candidate[:reg]
            var_to_spill = spill_candidate[:var]

            allocations.delete(var_to_spill)
            spilled << var_to_spill
            active.delete(spill_candidate)

            allocations[v] = reg
            active << { var: v, reg: reg, end: last_use[v] }
          else
            # Current var v ends farthest, spill v
            spilled << v
          end
        else
          # Register available
          reg = free_regs.shift
          allocations[v] = reg
          active << { var: v, reg: reg, end: last_use[v] }
        end
      end
    end

    { allocations: allocations, spilled: spilled }
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
      (node[:elif_branches] || []).each { |elif|
        vars += find_vars(elif[:condition])
        (elif[:body] || []).each { |n| vars += find_vars(n) }
      }
      (node[:else_body] || []).each { |n| vars += find_vars(n) }
    when :while_statement
      vars += find_vars(node[:condition])
      (node[:body] || []).each { |n| vars += find_vars(n) }
    when :match_expression
      vars += find_vars(node[:expression])
      (node[:cases] || []).each { |c|
        if c[:body].is_a?(Array)
          c[:body].each { |s| vars += find_vars(s) }
        else
          vars += find_vars(c[:body])
        end
      }
    when :return
      vars += find_vars(node[:expression])
    when :increment
      vars << node[:name]
    end
    vars.uniq
  end

  def find_defined_vars(node)
    return [] unless node.is_a?(Hash)
    if node[:type] == :assignment && node[:name]
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
