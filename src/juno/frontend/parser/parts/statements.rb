require_relative "../../ast"

module ParserStatements
  def consume_type
    if match?(:keyword) && ["int", "string", "bool", "real", "ptr"].include?(peek[:value])
      name = consume[:value]
    else
      name = consume_ident
    end
    name
  end

  def parse_statement
    while match_symbol?(";")
      consume_symbol(";")
    end
    token = peek
    return nil if token.nil? || match_symbol?("}")

    if token[:type] == :keyword
      case token[:value]
      when 'if'     then parse_if
      when 'while'  then parse_while
      when 'for'    then parse_for
      when 'let'    then parse_let
      when 'return' then parse_return
      when 'break'  then with_loc(AST::BreakStatement.new, token)
      when 'continue' then with_loc(AST::ContinueStatement.new, token)
      when 'fn'     then parse_fn_definition
      when 'struct' then parse_struct_definition
      when 'extern' then parse_extern_definition
      when 'panic'  then parse_panic
      when 'todo'   then parse_todo
      else error_unexpected(token, "Unknown keyword")
      end
    elsif token[:type] == :insertC
      consume(:insertC)
      with_loc(AST::InsertC.new(token[:content]), token)
    elsif token[:type] == :star
      parse_deref_assign
    elsif token[:type] == :ident
      if peek_next && peek_next[:type] == :lbracket
        parse_array_assign_or_access
      elsif peek_next && peek_next[:value] == '='
        parse_assignment
      elsif peek_next && (peek_next[:value] == '++' || peek_next[:value] == '--')
        parse_increment
      else
        parse_expression
      end
    else
      error_unexpected(peek, "Expected statement")
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
      AST::ArrayAssign.new(name, index, value)
    else
      AST::ArrayAccess.new(name, index)
    end
  end

  def parse_assignment
    name = consume_ident
    consume_symbol('=')
    AST::Assignment.new(name, parse_expression)
  end

  def parse_if
    token = consume_keyword('if')
    has_paren = match_symbol?('(')
    consume_symbol('(') if has_paren
    cond = parse_expression
    consume_symbol(')') if has_paren
    consume_symbol('{')
    body = []
    until match_symbol?('}')
      error_eof("Expected '}'") if peek.nil?
      stmt = parse_statement
      body << stmt if stmt
    end
    consume_symbol('}')

    else_body = nil
    if match_keyword?('else')
      consume_keyword('else')
      consume_symbol('{')
      else_body = []
      until match_symbol?('}')
        error_eof("Expected '}'") if peek.nil?
        stmt = parse_statement
        else_body << stmt if stmt
      end
      consume_symbol('}')
    end
    with_loc(AST::IfStatement.new(cond, body, else_body: else_body), token)
  end

  def parse_return
    token = consume_keyword('return')
    expr = match_symbol?(";") ? AST::Literal.new(0) : parse_expression
    with_loc(AST::ReturnStatement.new(expr), token)
  end

  def parse_fn_definition
    token = consume_keyword('fn')
    name = consume_ident
    if match_symbol?('.')
      consume_symbol('.')
      method = consume_ident
      name = "#{name}.#{method}"
    end
    consume_symbol('(')
    params = []
    param_types = {}
    until match_symbol?(')')
      error_eof("Expected ')'") if peek.nil?
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
    end

    consume_symbol('{')
    body = []
    until match_symbol?('}')
      error_eof("Expected '}'") if peek.nil?
      stmt = parse_statement
      body << stmt if stmt
    end
    consume_symbol('}')
    with_loc(AST::FunctionDefinition.new(name, params, body, param_types: param_types, return_type: return_type), token)
  end

  def parse_struct_definition
    token = consume_keyword('struct')
    name = consume_ident
    consume_symbol('{')
    fields = []
    field_types = {}
    until match_symbol?('}')
      error_eof("Expected '}'") if peek.nil?
      consume_keyword('let') if match_keyword?('let')
      field_name = consume_ident
      if match?(:colon)
        consume(:colon)
        field_types[field_name] = consume_type
      end
      fields << field_name
      consume_symbol(",") if match_symbol?(",")
    end
    consume_symbol('}')
    with_loc(AST::StructDefinition.new(name, fields, field_types: field_types), token)
  end

  def parse_let
    token = consume_keyword('let')
    is_mut = false
    if match_keyword?('mut')
      consume_keyword('mut')
      is_mut = true
    end
    name = consume_ident
    if match?(:lbracket)
      consume(:lbracket)
      size = consume(:number)[:value]
      consume(:rbracket)
      return with_loc(AST::ArrayDecl.new(name, size), token)
    end
    var_type = nil
    if match?(:colon)
      consume(:colon)
      var_type = consume_type
    end
    consume_symbol('=')
    expr = match_symbol?(";") ? AST::Literal.new(0) : parse_expression
    with_loc(AST::Assignment.new(name, expr, let: true, mut: is_mut, var_type: var_type), token)
  end

  def parse_extern_definition
    token = consume_keyword('extern')
    consume_keyword('fn')
    name = consume_ident
    consume_symbol('(')
    params = []
    param_types = {}
    until match_symbol?(')')
      error_eof("Expected ')'") if peek.nil?
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
    end

    lib_name = "libc.so.6"
    if match_keyword?('from')
      consume_keyword('from')
      lib_name = consume(:string)[:value]
    end

    with_loc(AST::ExternDefinition.new(name, params, param_types: param_types, return_type: return_type, lib: lib_name), token)
  end

  def parse_deref_assign
    consume(:star)
    target = parse_primary
    consume_symbol('=')
    value = parse_expression
    AST::ArrayAssign.new(target, AST::Literal.new(0), value)
  end

  def parse_panic
    token = consume_keyword('panic')
    msg = match?(:string) ? consume(:string)[:value] : nil
    with_loc(AST::PanicStatement.new(msg), token)
  end

  def parse_todo
    token = consume_keyword('todo')
    msg = match?(:string) ? consume(:string)[:value] : nil
    with_loc(AST::TodoStatement.new(msg), token)
  end
end
