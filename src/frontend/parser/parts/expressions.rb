module ParserExpressions
  def parse_expression
    # Lowest priority: logical OR
    parse_logical_or
  end

  def parse_logical_or
    node = parse_logical_and
    while match?(:operator) && peek[:value] == '||'
      token = consume(:operator)
      right = parse_logical_and
      node = with_loc({ type: :binary_op, op: '||', left: node, right: right }, token)
    end
    node
  end

  def parse_logical_and
    node = parse_bit_or
    while match?(:operator) && peek[:value] == '&&'
      token = consume(:operator)
      right = parse_bit_or
      node = with_loc({ type: :binary_op, op: '&&', left: node, right: right }, token)
    end
    node
  end

  def parse_bit_or
    node = parse_bit_xor
    while match?(:bitor)
      token = consume(:bitor)
      right = parse_bit_xor
      node = with_loc({ type: :binary_op, op: '|', left: node, right: right }, token)
    end
    node
  end

  def parse_bit_xor
    node = parse_bit_and
    while match?(:bitxor)
      token = consume(:bitxor)
      right = parse_bit_and
      node = with_loc({ type: :binary_op, op: '^', left: node, right: right }, token)
    end
    node
  end

  def parse_bit_and
    node = parse_comparison
    while match?(:ampersand) && !is_address_of_context?
      token = consume(:ampersand)
      right = parse_comparison
      node = with_loc({ type: :binary_op, op: '&', left: node, right: right }, token)
    end
    node
  end

  def is_address_of_context?
    # If we're at start of expression or after operator, & is address-of
    false  # In binary context, & is bitwise AND
  end

  def parse_comparison
    node = parse_shift
    while (match?(:operator) && ['==', '!=', '<=', '>='].include?(peek[:value])) ||
          match?(:langle) || match?(:rangle)
      token = peek
      if match?(:langle)
        consume(:langle)
        op = '<'
      elsif match?(:rangle)
        consume(:rangle)
        op = '>'
      else
        op = consume(:operator)[:value]
      end
      right = parse_shift
      node = with_loc({ type: :binary_op, op: op, left: node, right: right }, token)
    end
    node
  end

  def parse_shift
    node = parse_additive
    while match?(:operator) && ['<<', '>>'].include?(peek[:value])
      token = consume(:operator)
      op = token[:value]
      right = parse_additive
      node = with_loc({ type: :binary_op, op: op, left: node, right: right }, token)
    end
    node
  end

  def parse_additive
    node = parse_term
    while match_symbol?('+') || match_symbol?('-') || match_symbol?('<>')
      token = consume_symbol
      op = token[:value]
      right = parse_term
      node = with_loc({ type: :binary_op, op: op, left: node, right: right }, token)
    end
    node
  end

  def parse_term
    node = parse_unary
    while match?(:star) || match_symbol?('/') || match_symbol?('%')
      token = peek
      if match?(:star)
        # Hack to avoid grabbing * in *ptr = expr as multiplication
        is_assign = false
        if peek_next && (peek_next[:type] == :ident || peek_next[:value] == '(')
          # Simple lookahead for '='
          i = 1
          depth = 0
          star_line = peek[:line]
          while i < 10 && (t = @tokens[i])
            break if t[:line] > star_line
            break if t[:value] == '}' || t[:value] == '{' || t[:value] == ';'
            if t[:value] == '(' then depth += 1
            elsif t[:value] == ')' then depth -= 1
            elsif t[:value] == '=' && depth == 0
              is_assign = true
              break
            end
            i += 1
          end
        end
        break if is_assign

        consume(:star)
        op = '*'
      else
        op = consume_symbol[:value]
      end
      right = parse_unary
      node = with_loc({ type: :binary_op, op: op, left: node, right: right }, token)
    end
    node
  end

  def parse_unary
    # Bitwise NOT: ~expr
    if match?(:bitnot)
      consume(:bitnot)
      operand = parse_unary
      return { type: :unary_op, op: '~', operand: operand }
    end
    parse_factor
  end

  def parse_factor
    # Primaries and unary or dots
    left = parse_primary

    while match_keyword?('as')
      consume_keyword('as')
      type = consume_type
      left = { type: :cast, expression: left, target_type: type }
    end

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
      token = peek
      with_loc({ type: :literal, value: consume(:number)[:value] }, token)
    elsif match_keyword?('true')
      token = consume_keyword('true')
      with_loc({ type: :literal, value: true }, token)
    elsif match_keyword?('false')
      token = consume_keyword('false')
      with_loc({ type: :literal, value: false }, token)
    elsif match?(:string)
      token = peek
      with_loc({ type: :string_literal, value: consume(:string)[:value] }, token)
    elsif match?(:ident)
      token = peek
      name = consume_ident
      
      # Check for generic type arguments: name<T, U>
      type_args = []
      if match?(:langle) && peek_next && peek_next[:type] == :ident
        saved_tokens = @tokens.dup
        consume(:langle)
        type_arg = consume_ident
        if match?(:rangle)
          consume(:rangle)
          if match_symbol?('(') || !match?(:langle)
            type_args << type_arg
          else
            @tokens = saved_tokens
          end
        elsif match_symbol?(',')
          type_args << type_arg
          while match_symbol?(',')
            consume_symbol(',')
            type_args << consume_ident
          end
          consume(:rangle)
        else
          @tokens = saved_tokens
        end
      end
      
      if match_symbol?('(')
        with_loc(parse_fn_call_at_ident(name, type_args), token)
      elsif match?(:lbracket)
        # Array access: arr[i]
        consume(:lbracket)
        index = parse_expression
        consume(:rbracket)
        with_loc({ type: :array_access, name: name, index: index }, token)
      else
        node = { type: :variable, name: name }
        node[:type_args] = type_args unless type_args.empty?
        with_loc(node, token)
      end
    elsif match_keyword?('match')
      parse_match
    elsif match_keyword?('panic')
      parse_panic
    elsif match_keyword?('todo')
      parse_todo
    elsif match_keyword?('fn')
      parse_anonymous_fn
    elsif match_symbol?('(')
      consume_symbol('(')
      exp = parse_expression
      consume_symbol(')')
      exp
    else
      token = peek
      if token.nil?
        error_eof("Expected expression")
      end
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

  def parse_fn_call_at_ident(name, type_args = [])
    consume_symbol('(')
    args = []
    until match_symbol?(')')
      args << parse_expression
      consume_symbol(',') if match_symbol?(',')
    end
    consume_symbol(')')
    node = { type: :fn_call, name: name, args: args }
    node[:type_args] = type_args unless type_args.empty?
    node
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
