class RegisterAllocator
  ALLOCATABLE_REGS = [] # Disabled for stability

  def initialize
    @allocations = {}
  end

  def reset
    @allocations = {}
  end

  def allocate(nodes)
    # Simple allocator: don't allocate anything for now
    { allocations: {} }
  end
end
