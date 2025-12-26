# src/optimizer/optimizer.rb - AST Optimizer for Juno
# Includes: constant folding, dead code elimination, strength reduction
require 'set'

class Optimizer
  def initialize(ast)
    @ast = ast
  end

  def optimize
    @ast.map { |node| optimize_node(node) }
  end

  private

  def optimize_node(node)
    return node unless node.is_a?(Hash)
    
    case node[:type]
    when :function_definition
      node[:body] = node[:body].map { |n| optimize_node(n) }
      node[:body] = remove_dead_code(node[:body])
      node[:body] = propagate_constants(node[:body])
      node
    when :assignment
      node[:expression] = optimize_expr(node[:expression])
      node
    when :if_statement
      node[:condition] = optimize_expr(node[:condition])
      node[:body] = node[:body].map { |n| optimize_node(n) }
      node[:else_body] = node[:else_body]&.map { |n| optimize_node(n) }
      if node[:condition][:type] == :literal
        if node[:condition][:value] != 0
          return { type: :block, body: node[:body] }
        elsif node[:else_body]
          return { type: :block, body: node[:else_body] }
        else
          return { type: :noop }
        end
      end
      node
    when :while_statement
      node[:condition] = optimize_expr(node[:condition])
      node[:body] = node[:body].map { |n| optimize_node(n) }
      if node[:condition][:type] == :literal && node[:condition][:value] == 0
        return { type: :noop }
      end
      node
    when :for_statement
      node[:init] = optimize_node(node[:init])
      node[:condition] = optimize_expr(node[:condition])
      node[:update] = optimize_node(node[:update])
      node[:body] = node[:body].map { |n| optimize_node(n) }
      node
    when :return
      node[:expression] = optimize_expr(node[:expression])
      node
    when :deref_assign
      # Don't optimize dereference assignments
      node
    when :binary_op
      optimize_expr(node)
    else
      node
    end
  end

  def optimize_expr(expr)
    return expr unless expr.is_a?(Hash)
    
    case expr[:type]
    when :binary_op
      left = optimize_expr(expr[:left])
      right = optimize_expr(expr[:right])
      
      if left[:type] == :literal && right[:type] == :literal
        result = fold_const(left[:value], expr[:op], right[:value])
        return { type: :literal, value: result } if result
      end
      
      expr[:left] = left
      expr[:right] = right
      strength_reduce(expr)
    when :fn_call
      expr[:args] = expr[:args].map { |a| optimize_expr(a) }
      expr
    when :address_of, :dereference
      # Don't optimize pointer operations
      expr
    else
      expr
    end
  end

  def fold_const(l, op, r)
    case op
    when "+" then l + r
    when "-" then l - r
    when "*" then l * r
    when "/" then r != 0 ? l / r : nil
    when "==" then l == r ? 1 : 0
    when "!=" then l != r ? 1 : 0
    when "<" then l < r ? 1 : 0
    when ">" then l > r ? 1 : 0
    when "<=" then l <= r ? 1 : 0
    when ">=" then l >= r ? 1 : 0
    end
  end

  def strength_reduce(expr)
    left = expr[:left]
    right = expr[:right]
    op = expr[:op]
    
    case op
    when "*"
      return { type: :literal, value: 0 } if right[:type] == :literal && right[:value] == 0
      return { type: :literal, value: 0 } if left[:type] == :literal && left[:value] == 0
      return left if right[:type] == :literal && right[:value] == 1
      return right if left[:type] == :literal && left[:value] == 1
      if right[:type] == :literal && right[:value] == 2
        return { type: :binary_op, op: "+", left: left, right: left.dup }
      end
      if right[:type] == :literal && power_of_two?(right[:value])
        expr[:shift_opt] = Math.log2(right[:value]).to_i
      end
    when "/"
      return left if right[:type] == :literal && right[:value] == 1
      return { type: :literal, value: 0 } if left[:type] == :literal && left[:value] == 0
      if right[:type] == :literal && power_of_two?(right[:value])
        expr[:shift_opt] = Math.log2(right[:value]).to_i
      end
    when "+"
      return left if right[:type] == :literal && right[:value] == 0
      return right if left[:type] == :literal && left[:value] == 0
    when "-"
      return left if right[:type] == :literal && right[:value] == 0
      if left[:type] == :variable && right[:type] == :variable && left[:name] == right[:name]
        return { type: :literal, value: 0 }
      end
    end
    expr
  end

  def power_of_two?(n)
    n > 0 && (n & (n - 1)) == 0
  end

  def remove_dead_code(body)
    result = []
    body.each do |node|
      next if node[:type] == :noop
      if node[:type] == :block
        result.concat(node[:body])
        next
      end
      result << node
      break if node[:type] == :return
    end
    result
  end

  def propagate_constants(body)
    # First pass: find all variables that have their address taken
    addressed_vars = find_addressed_vars(body)
    
    # If any pointers are used, skip constant propagation (conservative)
    has_pointers = body.any? do |node|
      has_pointer_ops?(node)
    end
    return body if has_pointers
    
    constants = {}
    body.map do |node|
      case node[:type]
      when :assignment
        expr = substitute_constants(node[:expression], constants, addressed_vars)
        node[:expression] = expr
        # Don't propagate if address is taken or if it's a struct member
        if expr[:type] == :literal && !node[:name].include?('.') && !addressed_vars.include?(node[:name])
          constants[node[:name]] = expr[:value]
        else
          constants.delete(node[:name])
        end
        node
      when :increment
        constants.delete(node[:name])
        node
      when :deref_assign
        # Pointer write invalidates all constants (conservative)
        constants.clear
        node
      else
        node
      end
    end
  end

  def has_pointer_ops?(node)
    return false unless node.is_a?(Hash)
    return true if node[:type] == :address_of || node[:type] == :dereference || node[:type] == :deref_assign
    
    node.values.any? do |v|
      if v.is_a?(Hash)
        has_pointer_ops?(v)
      elsif v.is_a?(Array)
        v.any? { |item| has_pointer_ops?(item) }
      else
        false
      end
    end
  end

  # Find all variables that have their address taken (&var)
  def find_addressed_vars(body)
    vars = Set.new
    body.each { |node| collect_addressed_vars(node, vars) }
    vars
  end

  def collect_addressed_vars(node, vars)
    return unless node.is_a?(Hash)
    
    case node[:type]
    when :address_of
      if node[:operand][:type] == :variable
        vars << node[:operand][:name]
      end
    when :assignment
      collect_addressed_vars(node[:expression], vars)
    when :fn_call
      node[:args]&.each { |a| collect_addressed_vars(a, vars) }
    when :if_statement
      collect_addressed_vars(node[:condition], vars)
      node[:body]&.each { |n| collect_addressed_vars(n, vars) }
      node[:else_body]&.each { |n| collect_addressed_vars(n, vars) }
    when :while_statement, :for_statement
      collect_addressed_vars(node[:condition], vars)
      node[:body]&.each { |n| collect_addressed_vars(n, vars) }
    when :return
      collect_addressed_vars(node[:expression], vars)
    when :binary_op
      collect_addressed_vars(node[:left], vars)
      collect_addressed_vars(node[:right], vars)
    end
  end

  def substitute_constants(expr, constants, addressed_vars = Set.new)
    return expr unless expr.is_a?(Hash)
    case expr[:type]
    when :variable
      # Don't substitute if address is taken
      if constants.key?(expr[:name]) && !addressed_vars.include?(expr[:name])
        return { type: :literal, value: constants[expr[:name]] }
      end
      expr
    when :binary_op
      expr[:left] = substitute_constants(expr[:left], constants, addressed_vars)
      expr[:right] = substitute_constants(expr[:right], constants, addressed_vars)
      optimize_expr(expr)
    when :address_of, :dereference
      # Don't optimize pointer expressions
      expr
    else
      expr
    end
  end
end
