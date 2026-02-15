module ParserStatements
  def parse_statement
    token = peek
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
      else raise "Unknown keyword: #{token[:value]}"
      end
    elsif token[:type] == :insertC
      consume(:insertC)
      { type: :insertC, content: token[:content] }
    elsif token[:type] == :star
      # Dereference assignment: *ptr = value
      parse_deref_assign
    elsif token[:type] == :ident
      # Check for array assignment: arr[i] = value
      if peek_next && peek_next[:type] == :lbracket
        parse_array_assign_or_access
      # Assignment OR plain expression (call)
      elsif peek_next && peek_next[:value] == '='
        parse_assignment
      elsif peek_next && (peek_next[:value] == '++' || peek_next[:value] == '--')
        parse_increment
      elsif peek_next && peek_next[:value] == '.'
        # Could be e.init() OR e.id = ...
        # Let's parse as expression and check if next is '='
        expr = parse_expression
        if match_symbol?('=')
           consume_symbol('=')
           val = parse_expression
           # Flatten e.id assigned
           { type: :assignment, name: "#{expr[:receiver]}.#{expr[:member]}", expression: val }
        else
           expr
        end
      else
        parse_expression
      end
    else
      @tokens.shift # Safety
      { type: :unknown }
    end
  end

  def parse_array_assign_or_access
    name = consume_ident
    consume(:lbracket)
    index = parse_expression
    consume(:rbracket)
    
    if match_symbol?('=')
      # Array assignment: arr[i] = value
      consume_symbol('=')
      value = parse_expression
      { type: :array_assign, name: name, index: index, value: value }
    else
      # Array access as expression (e.g., in a function call)
      { type: :array_access, name: name, index: index }
    end
  end

  def parse_assignment
    name = consume_ident
    consume_symbol('=')
    { type: :assignment, name: name, expression: parse_expression }
  end

  def parse_if
    consume_keyword('if')
    # Parentheses optional: if (x) or if x
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
    { type: :return, expression: parse_expression }
  end

  def parse_fn_definition
    consume_keyword('fn')
    name = consume_ident
    if match_symbol?('.')
      consume_symbol('.')
      method = consume_ident
      name = "#{name}.#{method}"
    end
    
    # Generic type parameters: fn identity<T>(x) { ... }
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
      # Check for type annotation: fn add(a: int, b: int)
      if match?(:colon)
        consume(:colon)
        param_types[param_name] = consume_ident
      end
      params << param_name
      consume_symbol(',') if match_symbol?(',')
    end
    consume_symbol(')')
    
    # Check for return type: fn add(a, b): int
    return_type = nil
    if match?(:colon)
      consume(:colon)
      return_type = consume_ident
    end
    
    consume_symbol('{')
    body = []
    until match_symbol?('}')
      body << parse_statement
    end
    consume_symbol('}')
    
    # Auto-inject self for methods
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
    
    # Generic type parameters: struct Box<T> { ... }
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
      if match_keyword?('let')
        consume_keyword('let')
      end
      field_name = consume_ident
      if match?(:colon)
        consume(:colon)
        field_types[field_name] = consume_ident
      end
      fields << field_name
    end
    consume_symbol('}')
    node = { type: :struct_definition, name: name, fields: fields }
    node[:type_params] = type_params unless type_params.empty?
    node[:field_types] = field_types unless field_types.empty?
    node
  end

  def parse_packed_struct
    consume_keyword('packed')
    consume_keyword('struct')
    name = consume_ident
    consume_symbol('{')
    fields = []
    field_types = {}
    until match_symbol?('}')
      field_name = consume_ident
      if match?(:colon)
        consume(:colon)
        field_types[field_name] = consume_ident
      end
      fields << field_name
    end
    consume_symbol('}')
    { type: :struct_definition, name: name, fields: fields, field_types: field_types, packed: true }
  end

  def parse_union_definition
    consume_keyword('union')
    name = consume_ident
    consume_symbol('{')
    fields = []
    field_types = {}
    until match_symbol?('}')
      field_name = consume_ident
      if match?(:colon)
        consume(:colon)
        field_types[field_name] = consume_ident
      end
      fields << field_name
    end
    consume_symbol('}')
    { type: :union_definition, name: name, fields: fields, field_types: field_types }
  end

  def parse_let
    consume_keyword('let')
    name = consume_ident
    
    # Check for array declaration: let arr[N]
    if match?(:lbracket)
      consume(:lbracket)
      size_token = peek
      raise "Array size must be a constant integer" unless size_token[:type] == :number
      size = consume(:number)[:value]
      raise "Array size must be positive" if size <= 0
      consume(:rbracket)
      return { type: :array_decl, name: name, size: size }
    end
    
    # Check for type annotation: let x: int = 5
    var_type = nil
    if match?(:colon)
      consume(:colon)
      var_type = consume_ident  # int, ptr, str, or struct name
    end
    
    consume_symbol('=')
    node = { type: :assignment, name: name, expression: parse_expression }
    node[:var_type] = var_type if var_type
    node
  end

  def parse_increment
    name = consume_ident
    op = consume(:operator)[:value]
    { type: :increment, name: name, op: op }
  end

  def parse_while
    consume_keyword('while')
    # Parentheses optional
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

  # for (i = 0; i < 10; i++) { ... }
  def parse_for
    consume_keyword('for')
    consume_symbol('(')
    
    # Init
    init_name = consume_ident
    consume_symbol('=')
    init_expr = parse_expression
    init = { type: :assignment, name: init_name, expression: init_expr }
    
    consume_symbol(';')
    
    # Condition
    cond = parse_expression
    
    consume_symbol(';')
    
    # Update (i++ or i--)
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

  # import "module.juno"
  def parse_import
    consume_keyword('import')
    unless match?(:string)
      token = peek
      error = JunoParseError.new(
        "Expected string path after 'import'",
        filename: @filename,
        line_num: token ? token[:line] : 0,
        column: token ? token[:column] : 0,
        source: @source
      )
      JunoErrorReporter.report(error)
    end
    path = consume(:string)[:value]
    { type: :import, path: path }
  end

  # *ptr = value
  def parse_deref_assign
    consume(:star)
    # Parse just the variable/expression for the pointer, not full expression
    target = parse_primary
    consume_symbol('=')
    value = parse_expression
    { type: :deref_assign, target: target, value: value }
  end
end
