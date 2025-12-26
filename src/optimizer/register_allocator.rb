# src/optimizer/register_allocator.rb - Register allocation for Juno
# Tracks variable liveness and assigns registers to reduce stack operations

class RegisterAllocator
  # Available general-purpose registers for allocation (excluding RAX, RSP, RBP)
  ALLOCATABLE_REGS = [:rbx, :r12, :r13, :r14, :r15]
  
  def initialize
    @var_to_reg = {}      # variable name -> register
    @reg_to_var = {}      # register -> variable name
    @free_regs = ALLOCATABLE_REGS.dup
    @spilled = {}         # variables that couldn't get a register
    @live_ranges = {}     # variable -> [first_use, last_use]
  end

  # Analyze function body and compute live ranges
  def analyze(body)
    @live_ranges = {}
    body.each_with_index do |node, idx|
      collect_vars(node, idx)
    end
    @live_ranges
  end

  # Allocate registers for a function
  def allocate(body)
    analyze(body)
    
    # Sort variables by live range length (shorter ranges first - easier to allocate)
    sorted_vars = @live_ranges.keys.sort_by do |var|
      range = @live_ranges[var]
      range[:last] - range[:first]
    end
    
    sorted_vars.each do |var|
      next if var.include?('.')  # Skip struct members
      
      if @free_regs.any?
        reg = @free_regs.shift
        @var_to_reg[var] = reg
        @reg_to_var[reg] = var
      else
        @spilled[var] = true
      end
    end
    
    {
      allocations: @var_to_reg.dup,
      spilled: @spilled.keys,
      live_ranges: @live_ranges.dup
    }
  end

  # Get register for variable (or nil if spilled to stack)
  def get_register(var)
    @var_to_reg[var]
  end

  # Check if variable is in register
  def in_register?(var)
    @var_to_reg.key?(var)
  end

  # Release register when variable goes out of scope
  def release(var)
    if reg = @var_to_reg.delete(var)
      @reg_to_var.delete(reg)
      @free_regs << reg
    end
  end

  # Reset allocator state
  def reset
    @var_to_reg.clear
    @reg_to_var.clear
    @free_regs = ALLOCATABLE_REGS.dup
    @spilled.clear
    @live_ranges.clear
  end

  private

  def collect_vars(node, idx)
    return unless node.is_a?(Hash)
    
    case node[:type]
    when :assignment
      update_range(node[:name], idx)
      collect_vars(node[:expression], idx)
    when :variable
      update_range(node[:name], idx)
    when :binary_op
      collect_vars(node[:left], idx)
      collect_vars(node[:right], idx)
    when :fn_call
      node[:args]&.each { |a| collect_vars(a, idx) }
    when :if_statement
      collect_vars(node[:condition], idx)
      node[:body]&.each_with_index { |n, i| collect_vars(n, idx + i) }
      node[:else_body]&.each_with_index { |n, i| collect_vars(n, idx + i) }
    when :while_statement, :for_statement
      collect_vars(node[:condition], idx)
      node[:body]&.each_with_index { |n, i| collect_vars(n, idx + i) }
    when :return
      collect_vars(node[:expression], idx)
    when :increment
      update_range(node[:name], idx)
    when :array_access
      update_range(node[:name], idx)
      collect_vars(node[:index], idx)
    when :array_assign
      update_range(node[:name], idx)
      collect_vars(node[:index], idx)
      collect_vars(node[:value], idx)
    when :member_access
      update_range(node[:receiver], idx)
    end
  end

  def update_range(var, idx)
    return if var.nil? || var.include?('.')
    
    if @live_ranges[var]
      @live_ranges[var][:last] = idx
    else
      @live_ranges[var] = { first: idx, last: idx }
    end
  end
end
