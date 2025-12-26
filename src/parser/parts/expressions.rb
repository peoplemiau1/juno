module ParserExpressions
  def parse_expression
    # Priority 3: Comparison (lowest)
    node = parse_additive
    while match?(:operator)
      op = consume(:operator)[:value]
      right = parse_additive
      node = { type: :binary_op, op: op, left: node, right: right }
    end
    node
  end

  def parse_additive
    # Priority 2: Addition/Subtraction
    node = parse_term
    while match_symbol?('+') || match_symbol?('-')
      op = consume_symbol[:value]
      right = parse_term
      node = { type: :binary_op, op: op, left: node, right: right }
    end
    node
  end

  def parse_term
    # Priority 1: Multiplication/Division
    node = parse_factor
    while match?(:star) || match_symbol?('/')
      if match?(:star)
        # Check if this is actually a dereference assignment (*ptr = ...)
        # by looking ahead: if next is ident followed by '=', stop here
        if peek_next && peek_next[:type] == :ident
          next_next = @tokens[2]
          if next_next && next_next[:type] == :symbol && next_next[:value] == '='
            break  # This is *ptr = value, not multiplication
          end
        end
        consume(:star)
        op = '*'
      else
        op = consume_symbol[:value]
      end
      right = parse_factor
      node = { type: :binary_op, op: op, left: node, right: right }
    end
    node
  end

  def parse_factor
    # Primaries and unary or dots
    left = parse_primary
    while match_symbol?('.')
      consume_symbol('.')
      member = consume_ident
      if match_symbol?('(')
        left = parse_method_call(left, member)
      else
        receiver_name = left[:name] || left[:receiver]
        left = { type: :member_access, receiver: receiver_name, member: member }
      end
    end
    left
  end

  def parse_primary
    # Address-of: &x
    if match?(:ampersand)
      consume(:ampersand)
      operand = parse_primary
      return { type: :address_of, operand: operand }
    end
    
    # Dereference: *ptr
    if match?(:star)
      consume(:star)
      operand = parse_primary
      return { type: :dereference, operand: operand }
    end
    
    # Unary minus: -expr
    if match_symbol?('-')
      consume_symbol('-')
      operand = parse_primary
      return { type: :binary_op, op: "-", left: { type: :literal, value: 0 }, right: operand }
    end
    
    if match?(:number)
      { type: :literal, value: consume(:number)[:value] }
    elsif match?(:string)
      { type: :string_literal, value: consume(:string)[:value] }
    elsif match?(:ident)
      name = consume_ident
      if match_symbol?('(')
        parse_fn_call_at_ident(name)
      elsif match?(:lbracket)
        # Array access: arr[i]
        consume(:lbracket)
        index = parse_expression
        consume(:rbracket)
        { type: :array_access, name: name, index: index }
      else
        { type: :variable, name: name }
      end
    elsif match_symbol?('(')
      consume_symbol('(')
      exp = parse_expression
      consume_symbol(')')
      exp
    else
      token = peek
      error = JunoParseError.new(
        "Unexpected token '#{token[:value]}' in expression",
        filename: @filename,
        line_num: token[:line],
        column: token[:column],
        source: @source
      )
      JunoErrorReporter.report(error)
    end
  end

  def parse_fn_call_at_ident(name)
    consume_symbol('(')
    args = []
    until match_symbol?(')')
      args << parse_expression
      consume_symbol(',') if match_symbol?(',')
    end
    consume_symbol(')')
    { type: :fn_call, name: name, args: args }
  end

  def parse_method_call(receiver_node, method_name)
    consume_symbol('(')
    args = []
    until match_symbol?(')')
      args << parse_expression
      consume_symbol(',') if match_symbol?(',')
    end
    consume_symbol(')')
    receiver_name = receiver_node[:name] || receiver_node[:receiver]
    { type: :fn_call, name: "#{receiver_name}.#{method_name}", args: args }
  end
end
