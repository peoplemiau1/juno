class RegisterAllocator
  ALLOCATABLE_REGS = [:rbx, :r12, :r13, :r14, :r15]

  def initialize
    @allocations = {}
  end

  def reset
    @allocations = {}
  end

  def allocate(nodes)
    # Simple linear scan-like allocation
    allocations = {}
    counts = Hash.new(0)

    # Count variable usages
    nodes.each do |n|
      case n[:type]
      when :assignment
        counts[n[:name]] += 2
      when :variable
        counts[n[:name]] += 1
      end
    end

    # Allocate top used variables to registers
    sorted_vars = counts.sort_by { |_, v| -v }.map(&:first)

    [sorted_vars.length, ALLOCATABLE_REGS.length].min.times do |i|
      allocations[sorted_vars[i]] = ALLOCATABLE_REGS[i]
    end

    { allocations: allocations }
  end
end
