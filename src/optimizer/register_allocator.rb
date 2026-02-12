class RegisterAllocator
  ALLOCATABLE_REGS = []

  def initialize; @allocations = {}; @used_regs = []; end
  def reset; @allocations = {}; @used_regs = []; end

  def allocate(nodes)
    nodes.each do |node|
      find_vars(node).each do |var|
        next if @allocations.key?(var)
        next if @used_regs.length >= ALLOCATABLE_REGS.length
        reg = ALLOCATABLE_REGS[@used_regs.length]
        @allocations[var] = reg
        @used_regs << reg
      end
    end
    { allocations: @allocations, used_regs: @used_regs }
  end

  private

  def find_vars(node)
    vars = []
    case node[:type]
    when :assignment then vars << node[:name] unless node[:name].include?('.')
    when :variable then vars << node[:name]
    end
    node.each do |key, value|
      if value.is_a?(Hash) then vars += find_vars(value)
      elsif value.is_a?(Array) then value.each { |v| vars += find_vars(v) if v.is_a?(Hash) }
      end
    end
    vars.uniq
  end
end
