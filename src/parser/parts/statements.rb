module ParserStatements
  def consume_type
    name = consume_ident
    if match?(:langle)
      name += "<"
      consume(:langle)
      until match?(:rangle)
        name += consume_type # Рекурсивно для вложенных типа Box<vec<int>>
        if match_symbol?(',')
          consume_symbol(',')
          name += ","
        end
      end
      consume(:rangle)
      name += ">"
    end
    name
  end

  def parse_statement
    token = peek
    if token.nil?
      error_eof("Expected statement")
    end
    if token[:type] == :keyword
      case token[:value]
      when 'if'     then parse_if
      when 'while'  then parse_while
      when 'for'    then parse_for
      when 'let'    then parse_let
      when 'return' then parse_return
      when 'fn'     then parse_fn_definition
      when 'struct' then parse_struct_definition
      when 'packed' then parse_packed_struct
      when 'union'  then parse_union_definition
      when 'import' then parse_import
      else error_unexpected(token, "Unknown keyword")
      end
    elsif token[:type] == :insertC
      consume(:insertC)
      { type: :insertC, content: token[:content] }
    elsif token[:type] == :star
      parse_deref_assign
    elsif token[:type] == :ident
      if peek_next && peek_next[:type] == :lbracket
        parse_array_assign_or_access
      elsif peek_next && peek_next[:value] == '='
        parse_assignment
      elsif peek_next && (peek_next[:value] == '++' || peek_next[:value] == '--')
        parse_increment
      elsif peek_next && peek_next[:value] == '.'
        expr = parse_expression
        if match_symbol?('=')
           consume_symbol('=')
           val = parse_expression
           { type: :assignment, name: "#{expr[:receiver]}.#{expr[:member]}", expression: val }
        else
           expr
        end
      else
        parse_expression
      end
    else
      token = peek
      error_unexpected(token, "Expected statement")
    end
  end

  def parse_array_assign_or_access
    name = consume_ident
    consume(:lbracket)
    index = parse_expression
    consume(:rbracket)
    if match_symbol?('=')
      consume_symbol('=')
      value = parse_expression
      { type: :array_assign, name: name, index: index, value: value }
    else
      { type: :array_access, name: name, index: index }
    end
  end

  def parse_assignment
    name = consume_ident
    consume_symbol('=')
    { type: :assignment, name: name, expression: (match_symbol?(";") ? {type: :literal, value: 0} : parse_expression) }
  end

  def parse_if
    consume_keyword('if')
    has_paren = match_symbol?('(')
    consume_symbol('(') if has_paren
    cond = parse_expression
    consume_symbol(')') if has_paren
    consume_symbol('{')
    body = []
    until match_symbol?('}')
      body << parse_statement
    end
    consume_symbol('}')
    else_body = nil
    if match_keyword?('else')
      consume_keyword('else')
      consume_symbol('{')
      else_body = []
      until match_symbol?('}')
        else_body << parse_statement
      end
      consume_symbol('}')
    end
    { type: :if_statement, condition: cond, body: body, else_body: else_body }
  end

  def parse_return
    consume_keyword('return')
    { type: :return, expression: (match_symbol?(";") ? {type: :literal, value: 0} : parse_expression) }
  end

  def parse_fn_definition
    consume_keyword('fn')
    name = consume_ident
    if match_symbol?('.')
      consume_symbol('.')
      method = consume_ident
      name = "#{name}.#{method}"
    end
    type_params = []
    if match?(:langle)
      consume(:langle)
      until match?(:rangle)
        type_params << consume_ident
        consume_symbol(',') if match_symbol?(',')
      end
      consume(:rangle)
    end
    consume_symbol('(')
    params = []
    param_types = {}
    until match_symbol?(')')
      param_name = consume_ident
      if match?(:colon)
        consume(:colon)
        param_types[param_name] = consume_type
      end
      params << param_name
      consume_symbol(',') if match_symbol?(',')
    end
    consume_symbol(')')
        return_type = nil
    if match?(:colon)
      consume(:colon)
      return_type = consume_type
    elsif match_symbol?('-') && peek_next && peek_next[:value] == '>'
      consume_symbol('-')
      consume_symbol('>')
      return_type = consume_type
    end

    consume_symbol('{')
    body = []
    until match_symbol?('}')
      body << parse_statement
    end
    consume_symbol('}')
    params.unshift("self") if name.include?('.') && !params.include?("self")
    node = { type: :function_definition, name: name, params: params, body: body }
    node[:type_params] = type_params unless type_params.empty?
    node[:param_types] = param_types unless param_types.empty?
    node[:return_type] = return_type if return_type
    node
  end

  def parse_struct_definition
    consume_keyword('struct')
    name = consume_ident
    type_params = []
    if match?(:langle)
      consume(:langle)
      until match?(:rangle)
        type_params << consume_ident
        consume_symbol(',') if match_symbol?(',')
      end
      consume(:rangle)
    end
    consume_symbol('{')
    fields = []
    field_types = {}
    until match_symbol?('}')
      consume_keyword('let') if match_keyword?('let')
      field_name = consume_ident
      if match?(:colon)
        consume(:colon)
        field_types[field_name] = consume_type
      end
      fields << field_name
    end
    consume_symbol('}')
    { type: :struct_definition, name: name, fields: fields, field_types: field_types, type_params: type_params }
  end

  def parse_packed_struct
    consume_keyword('packed')
    consume_keyword('struct')
    name = consume_ident
    type_params = []
    if match?(:langle)
      consume(:langle)
      until match?(:rangle)
        type_params << consume_ident
        consume_symbol(',') if match_symbol?(',')
      end
      consume(:rangle)
    end
    consume_symbol('{')
    fields = []
    field_types = {}
    until match_symbol?('}')
      field_name = consume_ident
      if match?(:colon)
        consume(:colon)
        field_types[field_name] = consume_type
      end
      fields << field_name
    end
    consume_symbol('}')
    { type: :struct_definition, name: name, fields: fields, field_types: field_types, packed: true, type_params: type_params }
  end

  def parse_union_definition
    consume_keyword('union')
    name = consume_ident
    type_params = []
    if match?(:langle)
      consume(:langle)
      until match?(:rangle)
        type_params << consume_ident
        consume_symbol(',') if match_symbol?(',')
      end
      consume(:rangle)
    end
    consume_symbol('{')
    fields = []
    field_types = {}
    until match_symbol?('}')
      field_name = consume_ident
      if match?(:colon)
        consume(:colon)
        field_types[field_name] = consume_type
      end
      fields << field_name
    end
    consume_symbol('}')
    { type: :union_definition, name: name, fields: fields, field_types: field_types, type_params: type_params }
  end

  def parse_let
    token = consume_keyword('let')
    name = consume_ident
    if match?(:lbracket)
      consume(:lbracket)
      size = consume(:number)[:value]
      consume(:rbracket)
      return { type: :array_decl, name: name, size: size }
    end
    var_type = nil
    if match?(:colon)
      consume(:colon)
      var_type = consume_type
    end
    consume_symbol('=')
    node = { type: :assignment, name: name, expression: (match_symbol?(";") ? {type: :literal, value: 0} : parse_expression) }
    node[:let] = true
    node[:var_type] = var_type if var_type
    with_loc(node, token)
  end

  def parse_increment
    name = consume_ident
    op = consume(:operator)[:value]
    { type: :increment, name: name, op: op }
  end

  def parse_while
    consume_keyword('while')
    has_paren = match_symbol?('(')
    consume_symbol('(') if has_paren
    cond = parse_expression
    consume_symbol(')') if has_paren
    consume_symbol('{')
    body = []
    until match_symbol?('}')
      body << parse_statement
    end
    consume_symbol('}')
    { type: :while_statement, condition: cond, body: body }
  end

  def parse_for
    consume_keyword('for')
    consume_symbol('(')
    init_name = consume_ident
    consume_symbol('=')
    init_expr = parse_expression
    init = { type: :assignment, name: init_name, expression: init_expr }
    consume_symbol(';')
    cond = parse_expression
    consume_symbol(';')
    update_name = consume_ident
    update_op = consume(:operator)[:value]
    update = { type: :increment, name: update_name, op: update_op }
    consume_symbol(')')
    consume_symbol('{')
    body = []
    until match_symbol?('}')
      body << parse_statement
    end
    consume_symbol('}')
    { type: :for_statement, init: init, condition: cond, update: update, body: body }
  end

  def parse_import
    consume_keyword('import')
    if match?(:string)
      path = consume(:string)[:value]
      { type: :import, path: path, system: false }
    else
      # System import like std/net
      path = ""
      while match?(:ident) || match_symbol?('/') || match_symbol?('.')
        if match?(:ident)
          path += consume_ident
        elsif match_symbol?('/')
          path += consume_symbol('/')[:value]
        elsif match_symbol?('.')
          path += consume_symbol('.')[:value]
        end
      end

      if path.empty?
        error_unexpected(peek, "Expected string or system path for import")
      end

      { type: :import, path: path + ".juno", system: true }
    end
  end

  def parse_deref_assign
    consume(:star)
    target = parse_primary
    consume_symbol('=')
    value = parse_expression
    { type: :deref_assign, target: target, value: value }
  end
end
