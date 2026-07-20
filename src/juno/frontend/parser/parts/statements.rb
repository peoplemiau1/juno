require_relative "../../ast"
require_relative "../../preprocessor"

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
      when 'import_c' then parse_import_c
      when 'if'       then parse_if
      when 'while'    then parse_while
      when 'for'      then parse_for
      when 'loop'     then parse_loop
      when 'let'      then parse_let
      when 'return'   then parse_return
      when 'break'    then parse_break
      when 'continue' then parse_continue
      when 'fn'       then parse_fn_definition
      when 'struct'   then parse_struct_definition
      when 'enum'     then parse_enum
      when 'type'     then parse_type_alias
      when 'packed'   then parse_packed_struct
      when 'union'    then parse_union_definition
      when 'import'   then parse_import
      when 'use'      then parse_use
      when 'extern'   then parse_extern_definition
      when 'pub'
        consume_keyword('pub')
        stmt = parse_statement
        stmt.instance_variable_set(:@public, true) if stmt.is_a?(AST::Node)
        stmt
      when 'match'    then parse_match
      when 'panic'    then parse_panic
      when 'todo'     then parse_todo
      else error_unexpected(token, "Unknown keyword")
      end
    elsif token[:type] == :insertC
      t = consume(:insertC)
      with_loc(AST::InsertC.new(t[:content], clobbers: t[:clobbers] || []), t)
    elsif token[:type] == :asm
      t = consume(:asm)
      lines = t[:content].lines.map(&:strip)
      begin
        pp = Preprocessor.new
        bytes, clobbers = pp.send(:assemble_block, lines, t[:clobbers].empty? ? nil : t[:clobbers])
      rescue => e
        raise JunoParseError.new(
          e.message,
          filename: @filename,
          line_num: t[:line],
          column: t[:column],
          source: @source
        )
      end
      content_str = bytes.map { |b| "0x%02X" % b }.join(', ')
      with_loc(AST::InsertC.new(content_str, clobbers: clobbers), t)
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
          name = expr.is_a?(AST::MemberAccess) ? "#{expr.receiver}.#{expr.member}" : extract_name(expr)
          with_loc(AST::Assignment.new(name, val), token)
        else
          expr
        end
      else
        parse_expression
      end
    else
      error_unexpected(peek, "Expected statement")
    end
  end

  def parse_block
    consume_symbol('{')
    body = []
    until match_symbol?('}')
      error_eof("Expected '}'") if peek.nil?
      stmt = parse_statement
      body << stmt if stmt
    end
    consume_symbol('}')
    body
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
    body = parse_block

    elif_branches = []
    while match_keyword?('elif')
      consume_keyword('elif')
      e_has_paren = match_symbol?('(')
      consume_symbol('(') if e_has_paren
      e_cond = parse_expression
      consume_symbol(')') if e_has_paren
      e_body = parse_block
      elif_branches << { condition: e_cond, body: e_body }
    end

    else_body = nil
    if match_keyword?('else')
      consume_keyword('else')
      else_body = parse_block
    end
    with_loc(AST::IfStatement.new(cond, body, elif_branches: elif_branches, else_body: else_body), token)
  end

  def parse_return
    token = consume_keyword('return')
    if match_symbol?(";") || match_symbol?("}") || peek.nil? || !on_same_line?
      expr = AST::Literal.new(0)
    else
      expr = parse_expression
    end
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
    type_params = []
    if match?(:langle)
      consume(:langle)
      until match?(:rangle)
        error_eof("Expected '>'") if peek.nil?
        type_params << consume_ident
        consume_symbol(',') if match_symbol?(',')
      end
      consume(:rangle)
    end
    consume_symbol('(')
    params = []
    param_types = {}
    until match_symbol?(')')
      error_eof("Expected ')'") if peek.nil?
      is_mut = false
      if match_keyword?('mut')
        consume_keyword('mut')
        is_mut = true
      end
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
    elsif match_symbol?('->')
      consume_symbol('->')
      return_type = consume_type
    end

    body = parse_block
    with_loc(AST::FunctionDefinition.new(name, params, body, type_params: type_params, param_types: param_types, return_type: return_type), token)
  end

  def parse_struct_definition
    token = consume_keyword('struct')
    name = consume_ident
    type_params = []
    if match?(:langle)
      consume(:langle)
      until match?(:rangle)
        error_eof("Expected '>'") if peek.nil?
        type_params << consume_ident
        consume_symbol(',') if match_symbol?(',')
      end
      consume(:rangle)
    end
    consume_symbol('{')
    fields = []
    field_types = {}
    until match_symbol?('}')
      error_eof("Expected '}'") if peek.nil?
      consume_keyword('let') if match_keyword?('let')
      if match_keyword?('mut')
        consume_keyword('mut')
      end
      field_name = consume_ident
      if match?(:colon)
        consume(:colon)
        field_types[field_name] = consume_type
      end
      fields << field_name
      consume_symbol(",") if match_symbol?(",")
    end
    consume_symbol('}')
    with_loc(AST::StructDefinition.new(name, fields, field_types: field_types, type_params: type_params), token)
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

  def parse_increment
    name = consume_ident
    op = consume(:operator)[:value]
    AST::Increment.new(name, op)
  end

  def parse_while
    token = consume_keyword('while')
    has_paren = match_symbol?('(')
    consume_symbol('(') if has_paren
    cond = parse_expression
    consume_symbol(')') if has_paren
    body = parse_block
    with_loc(AST::WhileStatement.new(cond, body), token)
  end

  def parse_for
    token = consume_keyword('for')
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
    body = parse_block
    with_loc(AST::ForStatement.new(init, cond, update, body), token)
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
    elsif match_symbol?('->')
      consume_symbol('->')
      return_type = consume_type
    end

    lib_name = "libc.so.6"
    if match_keyword?('from')
      consume_keyword('from')
      lib_name = consume(:string)[:value]
    end

    with_loc(AST::ExternDefinition.new(name, params, param_types: param_types, return_type: return_type, lib: lib_name), token)
  end

  def parse_import
    consume_keyword('import')
    if match?(:string)
      path = consume(:string)[:value]
      AST::Import.new(path, system: false)
    else
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
      AST::Import.new(path, system: true)
    end
  end

  def parse_use
    consume_keyword('use')
    path = ""
    if match?(:string)
      path = consume(:string)[:value]
      AST::Import.new(path, system: false)
    else
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
        error_unexpected(peek, "Expected string or system path for use")
      end
      AST::Import.new(path, system: true)
    end
  end

  def parse_deref_assign
    consume(:star)
    target = parse_primary
    consume_symbol('=')
    value = parse_expression
    AST::DerefAssign.new(target, value)
  end

  def parse_loop
    token = consume_keyword('loop')
    body = parse_block
    with_loc(AST::WhileStatement.new(AST::Literal.new(1), body), token)
  end

  def parse_enum
    token = consume_keyword('enum')
    name = consume_ident
    consume_symbol('{')
    variants = []
    until match_symbol?('}')
      error_eof("Expected '}'") if peek.nil?
      v_name = consume_ident
      params = []
      if match_symbol?('(')
        consume_symbol('(')
        until match_symbol?(')')
          error_eof("Expected ')'") if peek.nil?
          params << consume_type
          consume_symbol(',') if match_symbol?(',')
        end
        consume_symbol(')')
      end
      variants << { name: v_name, params: params }
      consume_symbol(',') if match_symbol?(',')
    end
    consume_symbol('}')
    with_loc(AST::EnumDefinition.new(name, variants), token)
  end

  def parse_type_alias
    token = consume_keyword('type')
    alias_name = consume_ident
    consume_symbol('=')
    target_type = consume_type
    with_loc(AST::TypeAlias.new(alias_name, target_type), token)
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

  def parse_packed_struct
    token = consume_keyword('packed')
    consume_keyword('struct')
    name = consume_ident
    consume_symbol('{')
    fields = []
    field_types = {}
    until match_symbol?('}')
      error_eof("Expected '}'") if peek.nil?
      field_name = consume_ident
      if match?(:colon)
        consume(:colon)
        field_types[field_name] = consume_type
      end
      fields << field_name
      consume_symbol(",") if match_symbol?(",")
    end
    consume_symbol('}')
    with_loc(AST::StructDefinition.new(name, fields, field_types: field_types, packed: true), token)
  end

  def parse_union_definition
    token = consume_keyword('union')
    name = consume_ident
    consume_symbol('{')
    fields = []
    field_types = {}
    until match_symbol?('}')
      error_eof("Expected '}'") if peek.nil?
      field_name = consume_ident
      if match?(:colon)
        consume(:colon)
        field_types[field_name] = consume_type
      end
      fields << field_name
      consume_symbol(",") if match_symbol?(",")
    end
    consume_symbol('}')
    with_loc(AST::UnionDefinition.new(name, fields, field_types: field_types), token)
  end

  def parse_match
    token = consume_keyword('match')
    expr = parse_expression
    consume_symbol('{')
    cases = []
    until match_symbol?('}')
      error_eof("Expected '}'") if peek.nil?
      pattern = parse_pattern
      consume_symbol('=>')
      body = []
      if match_symbol?('{')
        body = parse_block
      else
        stmt = parse_statement
        body << stmt if stmt
      end
      cases << { pattern: pattern, body: body }
    end
    consume_symbol('}')
    with_loc(AST::MatchStatement.new(expr, cases), token)
  end

  def parse_pattern
    if match?(:ident)
      name = consume_ident
      if name == "_"
        return { type: :wildcard_pattern }
      elsif match_symbol?('.')
        consume_symbol('.')
        variant = consume_ident
        fields = []
        if match_symbol?('(')
          consume_symbol('(')
          until match_symbol?(')')
            error_eof("Expected ')'") if peek.nil?
            fields << consume_ident
            consume_symbol(',') if match_symbol?(',')
          end
          consume_symbol(')')
        end
        return { type: :variant_pattern, enum: name, variant: variant, fields: fields }
      else
        return { type: :bind_pattern, name: name }
      end
    elsif match?(:number)
      return { type: :literal_pattern, value: consume(:number)[:value] }
    elsif match?(:string)
      return { type: :literal_pattern, value: consume(:string)[:value] }
    elsif match_keyword?('true')
      consume_keyword('true')
      return { type: :literal_pattern, value: true }
    elsif match_keyword?('false')
      consume_keyword('false')
      return { type: :literal_pattern, value: false }
    else
      error_unexpected(peek, "Expected pattern")
    end
  end

  def parse_break
    token = consume_keyword('break')
    with_loc(AST::BreakStatement.new, token)
  end

  def parse_continue
    token = consume_keyword('continue')
    with_loc(AST::ContinueStatement.new, token)
  end

  def parse_import_c
    token = consume_keyword('import_c')
    header_path = consume(:string)[:value]
    lib_name = "libc.so.6"
    if match_keyword?('from')
      consume_keyword('from')
      lib_name = consume(:string)[:value]
    end
    with_loc(AST::ImportC.new(header_path, lib_name), token)
  end
end


