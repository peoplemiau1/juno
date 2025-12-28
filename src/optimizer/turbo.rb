# Turbo Optimizer - Aggressive optimizations for maximum performance
# Goal: Beat Rust in speed

require 'set'

class TurboOptimizer
  INLINE_THRESHOLD = 10  # Max nodes for inline
  UNROLL_THRESHOLD = 8   # Max iterations to unroll
  
  def initialize(ast)
    @ast = ast
    @functions = {}
    @call_count = Hash.new(0)
    @inline_candidates = Set.new
  end

  def optimize
    # Phase 1: Analyze
    analyze_functions
    find_inline_candidates
    
    # Phase 2: High-level optimizations
    @ast = @ast.map { |node| optimize_node(node) }
    
    # Phase 3: Inline small functions
    @ast = inline_functions(@ast)
    
    # Phase 4: Loop optimizations
    @ast = @ast.map { |node| optimize_loops(node) }
    
    # Phase 5: Final cleanup
    @ast = @ast.map { |node| final_pass(node) }
    
    @ast
  end

  private

  # === PHASE 1: Analysis ===
  
  def analyze_functions
    @ast.each do |node|
      if node[:type] == :function_definition
        @functions[node[:name]] = {
          node: node,
          size: count_nodes(node[:body]),
          calls: [],
          is_recursive: false,
          is_leaf: true,
          has_loops: has_loops?(node[:body]),
          params: node[:params] || []
        }
      end
    end
    
    # Find call relationships
    @ast.each do |node|
      if node[:type] == :function_definition
        find_calls(node[:body], node[:name])
      end
    end
    
    # Mark recursive functions
    @functions.each do |name, info|
      info[:is_recursive] = info[:calls].include?(name)
    end
  end

  def find_inline_candidates
    @functions.each do |name, info|
      next if name == "main"
      next if info[:is_recursive]
      next if info[:size] > INLINE_THRESHOLD
      next if info[:has_loops]
      @inline_candidates << name
    end
  end

  def count_nodes(body)
    return 0 unless body.is_a?(Array)
    body.sum { |n| 1 + count_children(n) }
  end

  def count_children(node)
    return 0 unless node.is_a?(Hash)
    node.values.sum do |v|
      case v
      when Hash then 1 + count_children(v)
      when Array then v.sum { |x| x.is_a?(Hash) ? 1 + count_children(x) : 0 }
      else 0
      end
    end
  end

  def has_loops?(body)
    return false unless body.is_a?(Array)
    body.any? do |node|
      next false unless node.is_a?(Hash)
      [:while_statement, :for_statement].include?(node[:type]) ||
        node.values.any? { |v| v.is_a?(Array) && has_loops?(v) }
    end
  end

  def find_calls(body, current_fn)
    return unless body.is_a?(Array)
    body.each do |node|
      find_calls_in_node(node, current_fn)
    end
  end

  def find_calls_in_node(node, current_fn)
    return unless node.is_a?(Hash)
    
    if node[:type] == :fn_call && @functions.key?(node[:name])
      @functions[current_fn][:calls] << node[:name]
      @functions[current_fn][:is_leaf] = false
      @call_count[node[:name]] += 1
    end
    
    node.values.each do |v|
      case v
      when Hash then find_calls_in_node(v, current_fn)
      when Array then v.each { |x| find_calls_in_node(x, current_fn) if x.is_a?(Hash) }
      end
    end
  end

  # === PHASE 2: Basic Optimizations ===

  def optimize_node(node)
    return node unless node.is_a?(Hash)
    
    case node[:type]
    when :function_definition
      node[:body] = node[:body].map { |n| optimize_node(n) }
      node[:body] = remove_dead_code(node[:body])
      node[:body] = propagate_constants(node[:body])
      node[:body] = eliminate_common_subexpressions(node[:body])
      node
    when :assignment
      node[:expression] = optimize_expr(node[:expression])
      node
    when :if_statement
      optimize_if(node)
    when :while_statement, :for_statement
      optimize_loop_node(node)
    when :return
      node[:expression] = optimize_expr(node[:expression])
      node
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
      
      # Constant folding
      if left[:type] == :literal && right[:type] == :literal
        result = fold_const(left[:value], expr[:op], right[:value])
        return { type: :literal, value: result } if result
      end
      
      expr[:left] = left
      expr[:right] = right
      
      # Algebraic simplifications
      expr = algebraic_simplify(expr)
      
      # Strength reduction
      expr = strength_reduce(expr)
      
      expr
    when :fn_call
      expr[:args] = expr[:args]&.map { |a| optimize_expr(a) }
      expr
    when :unary_op
      expr[:operand] = optimize_expr(expr[:operand])
      if expr[:operand][:type] == :literal
        case expr[:op]
        when "-" then return { type: :literal, value: -expr[:operand][:value] }
        when "!" then return { type: :literal, value: expr[:operand][:value] == 0 ? 1 : 0 }
        end
      end
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
    when "%" then r != 0 ? l % r : nil
    when "<<" then l << r
    when ">>" then l >> r
    when "&" then l & r
    when "|" then l | r
    when "^" then l ^ r
    when "==" then l == r ? 1 : 0
    when "!=" then l != r ? 1 : 0
    when "<" then l < r ? 1 : 0
    when ">" then l > r ? 1 : 0
    when "<=" then l <= r ? 1 : 0
    when ">=" then l >= r ? 1 : 0
    when "&&" then (l != 0 && r != 0) ? 1 : 0
    when "||" then (l != 0 || r != 0) ? 1 : 0
    end
  end

  def algebraic_simplify(expr)
    left = expr[:left]
    right = expr[:right]
    op = expr[:op]
    
    # x - x = 0
    if op == "-" && exprs_equal?(left, right)
      return { type: :literal, value: 0 }
    end
    
    # x / x = 1 (when x != 0)
    if op == "/" && exprs_equal?(left, right) && left[:type] != :literal
      return { type: :literal, value: 1 }
    end
    
    # x & x = x, x | x = x
    if (op == "&" || op == "|") && exprs_equal?(left, right)
      return left
    end
    
    # x ^ x = 0
    if op == "^" && exprs_equal?(left, right)
      return { type: :literal, value: 0 }
    end
    
    # a + b - b = a
    if op == "-" && left[:type] == :binary_op && left[:op] == "+"
      if exprs_equal?(left[:right], right)
        return left[:left]
      end
    end
    
    expr
  end

  def exprs_equal?(a, b)
    return false unless a.is_a?(Hash) && b.is_a?(Hash)
    return false unless a[:type] == b[:type]
    
    case a[:type]
    when :variable then a[:name] == b[:name]
    when :literal then a[:value] == b[:value]
    when :binary_op
      a[:op] == b[:op] && exprs_equal?(a[:left], b[:left]) && exprs_equal?(a[:right], b[:right])
    else false
    end
  end

  def strength_reduce(expr)
    left = expr[:left]
    right = expr[:right]
    op = expr[:op]
    
    case op
    when "*"
      # x * 0 = 0
      return { type: :literal, value: 0 } if literal_value(right) == 0 || literal_value(left) == 0
      # x * 1 = x
      return left if literal_value(right) == 1
      return right if literal_value(left) == 1
      # x * 2 = x << 1
      if (n = literal_value(right)) && power_of_two?(n)
        return { type: :binary_op, op: "<<", left: left, right: { type: :literal, value: log2(n) } }
      end
      if (n = literal_value(left)) && power_of_two?(n)
        return { type: :binary_op, op: "<<", left: right, right: { type: :literal, value: log2(n) } }
      end
    when "/"
      return left if literal_value(right) == 1
      return { type: :literal, value: 0 } if literal_value(left) == 0
      # x / 2^n = x >> n
      if (n = literal_value(right)) && power_of_two?(n)
        return { type: :binary_op, op: ">>", left: left, right: { type: :literal, value: log2(n) } }
      end
    when "%"
      # x % 2^n = x & (2^n - 1)
      if (n = literal_value(right)) && power_of_two?(n)
        return { type: :binary_op, op: "&", left: left, right: { type: :literal, value: n - 1 } }
      end
    when "+"
      return left if literal_value(right) == 0
      return right if literal_value(left) == 0
    when "-"
      return left if literal_value(right) == 0
    when "<<"
      return left if literal_value(right) == 0
    when ">>"
      return left if literal_value(right) == 0
    end
    
    expr
  end

  def literal_value(expr)
    expr[:type] == :literal ? expr[:value] : nil
  end

  def power_of_two?(n)
    n.is_a?(Integer) && n > 0 && (n & (n - 1)) == 0
  end

  def log2(n)
    Math.log2(n).to_i
  end

  # === PHASE 3: Function Inlining ===

  def inline_functions(ast)
    ast.map do |node|
      if node[:type] == :function_definition
        node[:body] = inline_in_body(node[:body])
      end
      node
    end
  end

  def inline_in_body(body)
    return body unless body.is_a?(Array)
    
    result = []
    body.each do |node|
      inlined = try_inline(node)
      if inlined.is_a?(Array)
        result.concat(inlined)
      else
        result << inlined
      end
    end
    result
  end

  def try_inline(node)
    return node unless node.is_a?(Hash)
    
    case node[:type]
    when :assignment
      if node[:expression][:type] == :fn_call && @inline_candidates.include?(node[:expression][:name])
        return inline_call(node[:expression], node[:name])
      end
      node[:expression] = try_inline_expr(node[:expression])
      node
    when :fn_call
      if @inline_candidates.include?(node[:name])
        return inline_call(node, nil)
      end
      node
    when :if_statement
      node[:body] = inline_in_body(node[:body])
      node[:else_body] = inline_in_body(node[:else_body]) if node[:else_body]
      node
    when :while_statement, :for_statement
      node[:body] = inline_in_body(node[:body])
      node
    else
      node
    end
  end

  def try_inline_expr(expr)
    return expr unless expr.is_a?(Hash)
    
    if expr[:type] == :fn_call && @inline_candidates.include?(expr[:name])
      # Can't inline in expression context easily, skip
      return expr
    end
    
    expr
  end

  def inline_call(call, result_var)
    fn_info = @functions[call[:name]]
    return call unless fn_info
    
    fn = fn_info[:node]
    params = fn[:params] || []
    args = call[:args] || []
    
    # Create variable substitution map
    subst = {}
    params.each_with_index do |param, i|
      param_name = param.is_a?(Hash) ? param[:name] : param
      subst[param_name] = args[i] if args[i]
    end
    
    # Clone and substitute body
    inlined = []
    fn[:body].each do |stmt|
      cloned = deep_clone(stmt)
      substituted = substitute_vars(cloned, subst)
      
      if substituted[:type] == :return && result_var
        inlined << { type: :assignment, name: result_var, expression: substituted[:expression] }
      elsif substituted[:type] != :return
        inlined << substituted
      end
    end
    
    inlined.empty? ? { type: :noop } : inlined
  end

  def deep_clone(node)
    case node
    when Hash then node.transform_values { |v| deep_clone(v) }
    when Array then node.map { |x| deep_clone(x) }
    else node
    end
  end

  def substitute_vars(node, subst)
    return node unless node.is_a?(Hash)
    
    if node[:type] == :variable && subst.key?(node[:name])
      return deep_clone(subst[node[:name]])
    end
    
    node.transform_values { |v|
      case v
      when Hash then substitute_vars(v, subst)
      when Array then v.map { |x| x.is_a?(Hash) ? substitute_vars(x, subst) : x }
      else v
      end
    }
  end

  # === PHASE 4: Loop Optimizations ===

  def optimize_loops(node)
    return node unless node.is_a?(Hash)
    
    case node[:type]
    when :function_definition
      node[:body] = node[:body].map { |n| optimize_loops(n) }
      node
    when :for_statement
      unrolled = try_unroll_for(node)
      return unrolled if unrolled
      
      # Loop-invariant code motion
      node = hoist_invariants(node)
      node
    when :while_statement
      node = hoist_invariants(node)
      node
    when :if_statement
      node[:body] = node[:body].map { |n| optimize_loops(n) }
      node[:else_body] = node[:else_body]&.map { |n| optimize_loops(n) }
      node
    else
      node
    end
  end

  def try_unroll_for(node)
    init = node[:init]
    cond = node[:condition]
    update = node[:update]
    body = node[:body]
    
    # Check if it's a simple counted loop
    return nil unless init[:type] == :assignment
    return nil unless init[:expression][:type] == :literal
    
    loop_var = init[:name]
    start_val = init[:expression][:value]
    
    # Check condition: i < N or i <= N
    return nil unless cond[:type] == :binary_op
    return nil unless cond[:left][:type] == :variable && cond[:left][:name] == loop_var
    return nil unless cond[:right][:type] == :literal
    
    end_val = cond[:right][:value]
    end_val += 1 if cond[:op] == "<="
    
    iterations = end_val - start_val
    return nil if iterations <= 0 || iterations > UNROLL_THRESHOLD
    
    # Check update: i++ or i = i + 1
    return nil unless update[:type] == :increment || 
                      (update[:type] == :assignment && update[:name] == loop_var)
    
    # Unroll!
    unrolled = []
    (start_val...end_val).each do |i|
      body.each do |stmt|
        cloned = deep_clone(stmt)
        substituted = substitute_loop_var(cloned, loop_var, i)
        unrolled << substituted
      end
    end
    
    { type: :block, body: unrolled }
  end

  def substitute_loop_var(node, var_name, value)
    return node unless node.is_a?(Hash)
    
    if node[:type] == :variable && node[:name] == var_name
      return { type: :literal, value: value }
    end
    
    node.transform_values { |v|
      case v
      when Hash then substitute_loop_var(v, var_name, value)
      when Array then v.map { |x| x.is_a?(Hash) ? substitute_loop_var(x, var_name, value) : x }
      else v
      end
    }
  end

  def hoist_invariants(node)
    # Find variables written in loop
    written = find_written_vars(node[:body])
    
    hoisted = []
    new_body = []
    
    node[:body].each do |stmt|
      if can_hoist?(stmt, written)
        hoisted << stmt
      else
        new_body << stmt
      end
    end
    
    return node if hoisted.empty?
    
    node[:body] = new_body
    { type: :block, body: hoisted + [node] }
  end

  def find_written_vars(body)
    vars = Set.new
    body.each do |node|
      collect_written_vars(node, vars)
    end
    vars
  end

  def collect_written_vars(node, vars)
    return unless node.is_a?(Hash)
    
    case node[:type]
    when :assignment then vars << node[:name]
    when :increment then vars << node[:name]
    end
    
    node.values.each do |v|
      case v
      when Hash then collect_written_vars(v, vars)
      when Array then v.each { |x| collect_written_vars(x, vars) }
      end
    end
  end

  def can_hoist?(stmt, written_vars)
    return false unless stmt[:type] == :assignment
    
    # Don't hoist if result is modified in loop
    return false if written_vars.include?(stmt[:name])
    
    # Don't hoist if expression uses modified variables
    !uses_any_var?(stmt[:expression], written_vars)
  end

  def uses_any_var?(expr, vars)
    return false unless expr.is_a?(Hash)
    
    if expr[:type] == :variable
      return vars.include?(expr[:name])
    end
    
    expr.values.any? do |v|
      case v
      when Hash then uses_any_var?(v, vars)
      when Array then v.any? { |x| uses_any_var?(x, vars) }
      else false
      end
    end
  end

  # === PHASE 5: Final Pass ===

  def final_pass(node)
    return node unless node.is_a?(Hash)
    
    case node[:type]
    when :function_definition
      node[:body] = remove_dead_code(node[:body])
      node[:body] = node[:body].map { |n| final_pass(n) }
      node
    when :block
      node[:body] = remove_dead_code(node[:body])
      node[:body] = node[:body].map { |n| final_pass(n) }
      # Flatten single-statement blocks
      return node[:body].first if node[:body].length == 1
      node
    when :if_statement
      node[:body] = node[:body].map { |n| final_pass(n) }
      node[:else_body] = node[:else_body]&.map { |n| final_pass(n) }
      node
    else
      node
    end
  end

  def optimize_if(node)
    node[:condition] = optimize_expr(node[:condition])
    node[:body] = node[:body].map { |n| optimize_node(n) }
    node[:else_body] = node[:else_body]&.map { |n| optimize_node(n) }
    
    # Constant condition
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
  end

  def optimize_loop_node(node)
    node[:condition] = optimize_expr(node[:condition])
    node[:body] = node[:body].map { |n| optimize_node(n) }
    
    if node[:type] == :for_statement
      node[:init] = optimize_node(node[:init])
      node[:update] = optimize_node(node[:update])
    end
    
    # Dead loop
    if node[:condition][:type] == :literal && node[:condition][:value] == 0
      return { type: :noop }
    end
    
    node
  end

  def remove_dead_code(body)
    result = []
    body.each do |node|
      next if node[:type] == :noop
      if node[:type] == :block
        result.concat(node[:body] || [])
        next
      end
      result << node
      break if node[:type] == :return
    end
    result
  end

  def propagate_constants(body)
    constants = {}
    modified = Set.new
    
    # First pass: find all modified variables
    body.each do |node|
      collect_written_vars(node, modified)
    end
    
    body.map do |node|
      case node[:type]
      when :assignment
        expr = substitute_constants_expr(node[:expression], constants)
        expr = optimize_expr(expr)
        node[:expression] = expr
        
        if expr[:type] == :literal && !modified.include?(node[:name])
          constants[node[:name]] = expr[:value]
        else
          constants.delete(node[:name])
        end
        node
      when :increment
        constants.delete(node[:name])
        node
      else
        node
      end
    end
  end

  def substitute_constants_expr(expr, constants)
    return expr unless expr.is_a?(Hash)
    
    case expr[:type]
    when :variable
      if constants.key?(expr[:name])
        return { type: :literal, value: constants[expr[:name]] }
      end
      expr
    when :binary_op
      expr[:left] = substitute_constants_expr(expr[:left], constants)
      expr[:right] = substitute_constants_expr(expr[:right], constants)
      expr
    when :fn_call
      expr[:args] = expr[:args]&.map { |a| substitute_constants_expr(a, constants) }
      expr
    else
      expr
    end
  end

  def eliminate_common_subexpressions(body)
    expr_cache = {}
    temp_counter = 0
    
    body.flat_map do |node|
      if node[:type] == :assignment
        expr = node[:expression]
        expr_key = expr_to_key(expr)
        
        if expr_key && expr_cache.key?(expr_key) && !has_side_effects?(expr)
          # Reuse cached value
          node[:expression] = { type: :variable, name: expr_cache[expr_key] }
          [node]
        elsif expr_key && complex_expr?(expr) && !has_side_effects?(expr)
          # Cache this expression
          expr_cache[expr_key] = node[:name]
          [node]
        else
          [node]
        end
      else
        [node]
      end
    end
  end

  def expr_to_key(expr)
    return nil unless expr.is_a?(Hash)
    
    case expr[:type]
    when :literal then "L#{expr[:value]}"
    when :variable then "V#{expr[:name]}"
    when :binary_op
      l = expr_to_key(expr[:left])
      r = expr_to_key(expr[:right])
      return nil unless l && r
      "B#{expr[:op]}(#{l},#{r})"
    else nil
    end
  end

  def complex_expr?(expr)
    return false unless expr.is_a?(Hash)
    return true if expr[:type] == :binary_op
    return true if expr[:type] == :fn_call
    false
  end

  def has_side_effects?(expr)
    return false unless expr.is_a?(Hash)
    return true if expr[:type] == :fn_call
    
    expr.values.any? do |v|
      case v
      when Hash then has_side_effects?(v)
      when Array then v.any? { |x| has_side_effects?(x) }
      else false
      end
    end
  end
end
