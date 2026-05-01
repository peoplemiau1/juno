module ParserExpressions
  def parse_expression
    parse_logical_or
  end

  def parse_logical_or
    node = parse_logical_and
    while (t = match_operator?('||')) && on_same_line?
      consume_symbol
      right = parse_logical_and
      node = with_loc({ type: :binary_op, op: '||', left: node, right: right }, t)
    end
    node
  end

  def parse_logical_and
    node = parse_bitwise_or
    while (t = match_operator?('&&')) && on_same_line?
      consume_symbol
      right = parse_bitwise_or
      node = with_loc({ type: :binary_op, op: '&&', left: node, right: right }, t)
    end
    node
  end

  def parse_bitwise_or
    node = parse_bitwise_xor
    while (t = peek) && on_same_line? && t[:type] == :bitor
      consume(:bitor)
      right = parse_bitwise_xor
      node = with_loc({ type: :binary_op, op: '|', left: node, right: right }, t)
    end
    node
  end

  def parse_bitwise_xor
    node = parse_bitwise_and
    while (t = peek) && on_same_line? && t[:type] == :bitxor
      consume(:bitxor)
      right = parse_bitwise_and
      node = with_loc({ type: :binary_op, op: '^', left: node, right: right }, t)
    end
    node
  end

  def parse_bitwise_and
    node = parse_equality
    while (t = match_operator?('&')) && on_same_line?
      consume(:ampersand)
      right = parse_equality
      node = with_loc({ type: :binary_op, op: '&', left: node, right: right }, t)
    end
    node
  end

  def parse_equality
    node = parse_comparison
    while (t = peek) && on_same_line? && is_op?(t) && ['==', '!='].include?(t[:value])
      op = consume_symbol[:value]
      right = parse_comparison
      node = with_loc({ type: :binary_op, op: op, left: node, right: right }, t)
    end
    node
  end

  def parse_comparison
    node = parse_shift
    while (t = peek) && on_same_line? && (is_op?(t) || t[:type] == :langle || t[:type] == :rangle) && 
          ['<', '>', '<=', '>='].include?(t[:value])
      op = consume_symbol[:value]
      right = parse_shift
      node = with_loc({ type: :binary_op, op: op, left: node, right: right }, t)
    end
    node
  end

  def parse_shift
    node = parse_additive
    while (t = peek) && on_same_line? && is_op?(t) && ['<<', '>>'].include?(t[:value])
      op = consume_symbol[:value]
      right = parse_additive
      node = with_loc({ type: :binary_op, op: op, left: node, right: right }, t)
    end
    node
  end

  def parse_additive
    node = parse_term
    while (t = peek) && on_same_line? && is_op?(t) && ['+', '-'].include?(t[:value])
      op = consume_symbol[:value]
      right = parse_term
      node = with_loc({ type: :binary_op, op: op, left: node, right: right }, t)
    end
    node
  end

  def parse_term
    node = parse_unary
    while (t = peek) && on_same_line? && (is_op?(t) || t[:type] == :star) && ['*', '/', '%'].include?(t[:value])
      op = consume_symbol[:value]
      right = parse_unary
      node = with_loc({ type: :binary_op, op: op, left: node, right: right }, t)
    end
    node
  end

  def parse_unary
    t = peek
    if match?(:ampersand)
      consume(:ampersand)
      return with_loc({ type: :address_of, operand: parse_unary }, t)
    elsif match?(:star)
      consume(:star)
      return with_loc({ type: :dereference, operand: parse_unary }, t)
    elsif match_operator?('!')
      consume_symbol
      return with_loc({ type: :unary_op, op: '!', operand: parse_unary }, t)
    elsif match?(:bitnot)
      consume(:bitnot)
      return with_loc({ type: :unary_op, op: '~', operand: parse_unary }, t)
    elsif match_operator?('-')
      consume_symbol
      return with_loc({ type: :binary_op, op: '*', left: with_loc({type: :literal, value: -1}, t), right: parse_unary }, t)
    end
    parse_factor
  end

  def parse_factor
    left = parse_primary
    while (t = peek) && on_same_line? && (t[:type] == :symbol || t[:type] == :operator || t[:type] == :lbracket)
      if match_symbol?('.')
        consume_symbol('.')
        member = consume_ident
        if match_symbol?('(')
          args = []
          consume_symbol('(')
          until match_symbol?(')')
            args << parse_expression
            consume_symbol(',') if match_symbol?(',')
          end
          consume_symbol(')')
          left = with_loc({ type: :fn_call, name: "#{extract_name(left)}.#{member}", args: args }, t)
        else
          left = with_loc({ type: :member_access, receiver: extract_name(left), member: member }, t)
        end
      elsif match?(:lbracket)
        consume(:lbracket)
        index = parse_expression
        consume(:rbracket)
        left = with_loc({ type: :array_access, name: extract_name(left), index: index }, t)
      else
        break
      end
    end
    left
  end

  def extract_name(node)
    return "unknown" unless node
    case node[:type]
    when :variable then node[:name] || "unknown_var"
    when :member_access then "#{node[:receiver] || 'unknown'}.#{node[:member] || 'unknown'}"
    when :fn_call then node[:name] || "unknown_call"
    when :address_of then "(&#{extract_name(node[:operand])})"
    when :dereference then "(*#{extract_name(node[:operand])})"
    when :array_access then node[:name] # Just return base name for array access
    else 
      "unknown_#{node[:type]}"
    end
  end

  def parse_primary
    t = peek
    if match?(:number)
      return with_loc({ type: :literal, value: consume(:number)[:value] }, t)
    end
    if match?(:float_literal)
      return with_loc({ type: :float_literal, value: consume(:float_literal)[:value] }, t)
    end
    if match?(:string)
      return with_loc({ type: :string_literal, value: consume(:string)[:value] }, t)
    end
    
    if match?(:ident) || (match?(:keyword) && ["malloc", "free", "realloc", "realloc_header", "sleep", "os_sleep", "thread_create", "spin_lock", "spin_unlock"].include?(peek[:value]))
      name = (match?(:ident) ? consume_ident : consume[:value])
      
      if match_symbol?('(')
         args = []
         consume_symbol('(')
         until match_symbol?(')')
           if peek.nil? then error_eof("Expected ')'") end
           args << parse_expression
           consume_symbol(',') if match_symbol?(',')
         end
         consume_symbol(')')
         return with_loc({ type: :fn_call, name: name, args: args }, t)
      end
      return with_loc({ type: :variable, name: name }, t)
    end
    
    if match_symbol?('(')
      consume_symbol('(')
      exp = parse_expression
      consume_symbol(')')
      return exp
    end
    
    error_unexpected(t, t ? "Expected expression" : "Unexpected end of input")
  end

  def is_op?(t)
    t && [:operator, :symbol, :bitor, :bitxor, :ampersand, :star, :langle, :rangle].include?(t[:type])
  end
  
  def match_operator?(op)
    t = peek
    t && is_op?(t) && t[:value] == op ? t : nil
  end
end
