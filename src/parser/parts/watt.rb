# watt.rb - Watt specific parsing logic

module WattParser
  def parse_use
    consume_keyword('use')
    path = ""
    while match?(:ident) || match_symbol?('/')
      if match?(:ident)
        path += consume_ident
      else
        path += consume_symbol('/')[:value]
      end
    end

    kind = nil
    if match_keyword?('as')
      consume_keyword('as')
      kind = { type: :as_name, name: consume_ident }
    elsif match_keyword?('for')
      consume_keyword('for')
      names = []
      until match_symbol?("\n") || peek.nil? || match?(:keyword)
        names << consume_ident
        break unless match_symbol?(',')
        consume_symbol(',')
      end
      kind = { type: :for_names, names: names }
    end

    { type: :use_statement, path: path, kind: kind }
  end

  def parse_enum
    consume_keyword('enum')
    name = consume_ident
    consume_symbol('{')
    variants = []
    until match_symbol?('}')
      v_name = consume_ident
      params = []
      if match_symbol?('(')
        consume_symbol('(')
        until match_symbol?(')')
          p_name = consume_ident
          consume(:colon)
          p_type = consume_type
          params << { name: p_name, type: p_type }
          consume_symbol(',') if match_symbol?(',')
        end
        consume_symbol(')')
      end
      variants << { name: v_name, params: params }
      consume_symbol(',') if match_symbol?(',')
    end
    consume_symbol('}')
    { type: :enum_definition, name: name, variants: variants }
  end

  def parse_match
    consume_keyword('match')
    expr = parse_expression
    consume_symbol('{')
    cases = []
    until match_symbol?('}')
      pattern = parse_pattern
      if match_symbol?('->')
        consume_symbol('->')
      else
        consume_symbol('-')
        consume_symbol('>')
      end
      body = if match_symbol?('{')
               parse_block
             else
               parse_expression
             end
      cases << { pattern: pattern, body: body }
      consume_symbol(',') if match_symbol?(',')
    end
    consume_symbol('}')
    { type: :match_expression, expression: expr, cases: cases }
  end

  def parse_pattern
    if match_keyword?('_')
      consume_keyword('_')
      { type: :wildcard_pattern }
    elsif match?(:number)
      { type: :literal_pattern, value: consume(:number)[:value] }
    elsif match?(:string)
      { type: :literal_pattern, value: consume(:string)[:value] }
    elsif match_keyword?('true')
      consume_keyword('true')
      { type: :literal_pattern, value: true }
    elsif match_keyword?('false')
      consume_keyword('false')
      { type: :literal_pattern, value: false }
    elsif match?(:ident)
      name = consume_ident
      if match_symbol?('.')
        consume_symbol('.')
        variant = consume_ident
        fields = []
        if match_symbol?('(')
          consume_symbol('(')
          until match_symbol?(')')
            fields << consume_ident
            consume_symbol(',') if match_symbol?(',')
          end
          consume_symbol(')')
        end
        { type: :variant_pattern, enum: name, variant: variant, fields: fields }
      else
        { type: :bind_pattern, name: name }
      end
    else
      error_unexpected(peek, "Expected pattern")
    end
  end

  def parse_block
    consume_symbol('{')
    body = []
    until match_symbol?('}')
      stmt = parse_statement
      body << stmt if stmt
    end
    consume_symbol('}')
    body
  end

  def parse_loop
    token = consume_keyword('loop')
    body = parse_block
    with_loc({ type: :while_statement, condition: { type: :literal, value: true }, body: body }, token)
  end

  def parse_type_alias
    consume_keyword('type')
    name = consume_ident
    consume_symbol('=')
    target = consume_type
    { type: :type_alias, name: name, target: target }
  end

  def parse_panic
    token = consume_keyword('panic')
    message = nil
    if match_keyword?('as')
      consume_keyword('as')
      message = consume(:string)[:value]
    end
    with_loc({ type: :panic, message: message }, token)
  end

  def parse_todo
    token = consume_keyword('todo')
    message = nil
    if match_keyword?('as')
      consume_keyword('as')
      message = consume(:string)[:value]
    end
    with_loc({ type: :todo, message: message }, token)
  end

  def parse_anonymous_fn
    token = consume_keyword('fn')
    consume_symbol('(')
    params = []
    param_types = {}
    until match_symbol?(')')
      p_name = consume_ident
      if match?(:colon)
        consume(:colon)
        param_types[p_name] = consume_type
      end
      params << p_name
      consume_symbol(',') if match_symbol?(',')
    end
    consume_symbol(')')

    return_type = nil
    if match?(:colon)
      consume(:colon)
      return_type = consume_type
    end

    body = nil
    if match_symbol?('{')
      body = parse_block
    elsif match_symbol?('=')
      consume_symbol('=')
      body = [ { type: :return, expression: parse_expression } ]
    else
      error_unexpected(peek, "Expected '{' or '=' after anonymous function signature")
    end

    with_loc({ type: :anonymous_function, params: params, param_types: param_types, return_type: return_type, body: body }, token)
  end
end
