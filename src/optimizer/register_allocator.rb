class RegisterAllocator
  ALLOCATABLE_REGS = [:rbx, :r12, :r13, :r14, :r15]

  def initialize
    @allocations = {}
  end

  def reset
    @allocations = {}
  end

  def allocate(nodes)
    # Disabled for stability
    { allocations: {} }
  end
end
