class RegisterAllocator
  # Callee-saved registers (stable across calls)
  X86_64_CALLEE_SAVED = [:rbx, :r12, :r13, :r14, :r15]
  # Caller-saved registers that are NOT used as primary scratches by backend.
  # We empty this for x86_64 because builtins clobber them without notice.
  X86_64_CALLER_SAVED = [] 

  AARCH64_CALLEE_SAVED = [19, 20, 21, 22, 23, 24, 25, 26, 27, 28]
  AARCH64_CALLER_SAVED = (0..18).to_a - [0, 1, 2, 3, 4, 5, 6, 7] # Exclude arg/scratch regs

  def initialize(arch = :x86_64)
    @arch = arch
    @caller_saved = (arch == :aarch64) ? AARCH64_CALLER_SAVED : X86_64_CALLER_SAVED
    @callee_saved = (arch == :aarch64) ? AARCH64_CALLEE_SAVED : X86_64_CALLEE_SAVED

    # Priority: Callee-saved first (for longer life), then Caller-saved
    @allocatable_regs = @callee_saved + @caller_saved
  end

  def allocate(nodes, globals = [])
    # Very simple Linear Scan allocator
    # 1. Collect all variables and their last use index
    last_use = {}
    variables = []
    addressed_vars = [] # Variables that have their address taken (&x)

    nodes.each_with_index do |node, idx|
      find_vars(node).each do |v|
        next unless v.is_a?(String)
        last_use[v] = idx
        variables << v unless variables.include?(v)
      end
      addressed_vars += find_addressed_vars(node)
    end
    addressed_vars.uniq!

    # 1.5 Identify variables that cross calls
    crosses_call = []
    variables.each do |v|
      # Check if it's a parameter (defined at start) or look for first assignment
      first_def = nodes.index { |n| find_defined_vars(n).include?(v) } || 0
      last_u = last_use[v]
      if first_def && last_u
        (first_def..last_u).each do |i|
          if contains_call?(nodes[i])
            crosses_call << v
            break
          end
        end
      end
    end

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

      # Call Boundary: Spill all caller-saved registers if node contains a call
      if contains_call?(node)
        active.delete_if do |a|
          if @caller_saved.include?(a[:reg])
            # In a real linear scan, we'd spill to stack and potentially reload.
            # Here we just force it to be spilled for its remaining lifetime if it crosses a call.
            spilled << a[:var]
            allocations.delete(a[:var])
            true
          else
            false
          end
        end
        # Ensure clobbered regs are not in free_regs for this instruction
        # But they can be used after.
      end

      # Allocate for variables defined here
      vars_defined = find_defined_vars(node)
      vars_defined.each do |v|
        next if globals.include?(v) # NEVER allocate registers for globals
        next if addressed_vars.include?(v) # Skip variables with address taken
        next if allocations.key?(v) || spilled.include?(v)

        # For variables crossing calls, only allow callee-saved registers
        available_regs = free_regs
        if crosses_call.include?(v)
          available_regs = free_regs.select { |r| @callee_saved.include?(r) }
        end

        if available_regs.empty?
          # Register pressure: spill the interval that ends farthest
          # Only consider candidates that are in registers suitable for v
          spill_candidate = active.select { |a|
            crosses_call.include?(v) ? @callee_saved.include?(a[:reg]) : true
          }.max_by { |a| a[:end] }

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
          reg = available_regs.shift
          free_regs.delete(reg)
          allocations[v] = reg
          active << { var: v, reg: reg, end: last_use[v] }
        end
      end
    end

    { allocations: allocations, spilled: spilled }
  end

  private

  def contains_call?(node)
    if node.is_a?(Hash)
      return true if node[:type] == :fn_call
      return node.any? { |k, v| v.is_a?(Hash) ? contains_call?(v) : (v.is_a?(Array) ? v.any?{|i| contains_call?(i)} : false) }
    elsif node.respond_to?(:op)
      return node.op == :CALL || node.op == :CALL_IND
    end
    false
  end

  def find_vars(node)
    vars = []
    return vars unless node.is_a?(Hash)

    case node[:type]
    when :variable then vars << node[:name]
    when :assignment
      vars << node[:name] if node[:name]
      vars += find_vars(node[:expression])
    when :binary_op
      vars += find_vars(node[:left]) + find_vars(node[:right])
    when :unary_op
      vars += find_vars(node[:operand])
    when :fn_call
      (node[:args] || []).each { |a| vars += find_vars(a) }
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
    when :for_statement
      vars += find_vars(node[:init]) if node[:init]
      vars += find_vars(node[:condition]) if node[:condition]
      vars += find_vars(node[:update]) if node[:update]
      (node[:body] || []).each { |n| vars += find_vars(n) }
    when :deref_assign
      vars += find_vars(node[:target])
      vars += find_vars(node[:value])
    when :array_assign
      vars << node[:name] if node[:name]
      vars += find_vars(node[:index]) if node[:index]
      vars += find_vars(node[:value]) if node[:value]
    when :array_access
      vars << node[:name] if node[:name]
      vars += find_vars(node[:index]) if node[:index]
    when :member_access
      vars << node[:receiver] if node[:receiver]
    when :address_of
      vars += find_vars(node[:operand])
    when :deref
      vars += find_vars(node[:operand])
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
      vars += find_vars(node[:expression]) if node[:expression]
    when :increment
      vars << node[:name]
    end
    vars.uniq
  end

  def find_defined_vars(node)
    return [] unless node.is_a?(Hash)

    case node[:type]
    when :assignment
      node[:name] ? [node[:name]] : []
    when :increment
      node[:name] ? [node[:name]] : []
    when :for_statement
      node[:init] ? find_defined_vars(node[:init]) : []
    else
      []
    end
  end

  def find_addressed_vars(node)
    return [] unless node.is_a?(Hash)

    case node[:type]
    when :address_of
      op = node[:operand]
      case op[:type]
      when :variable then [op[:name]]
      when :member_access then [op[:receiver]]
      when :array_access then [op[:name]]
      else []
      end
    when :binary_op
      find_addressed_vars(node[:left]) + find_addressed_vars(node[:right])
    when :unary_op
      find_addressed_vars(node[:operand])
    when :fn_call
      (node[:args] || []).flat_map { |a| find_addressed_vars(a) }
    when :if_statement
      find_addressed_vars(node[:condition]) +
      (node[:body] || []).flat_map { |n| find_addressed_vars(n) } +
      (node[:elif_branches] || []).flat_map { |elif|
        (elif[:body] || []).flat_map { |n| find_addressed_vars(n) }
      } +
      (node[:else_body] || []).flat_map { |n| find_addressed_vars(n) }
    when :while_statement
      find_addressed_vars(node[:condition]) +
      (node[:body] || []).flat_map { |n| find_addressed_vars(n) }
    when :for_statement
      find_addressed_vars(node[:init]) +
      find_addressed_vars(node[:condition]) +
      (node[:body] || []).flat_map { |n| find_addressed_vars(n) }
    when :deref_assign
      find_addressed_vars(node[:target]) + find_addressed_vars(node[:value])
    when :assignment
      find_addressed_vars(node[:expression])
    when :return
      node[:expression] ? find_addressed_vars(node[:expression]) : []
    else []
    end
  end
end
