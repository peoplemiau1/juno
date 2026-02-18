require_relative "errors"

class Lexer
  attr_reader :tokens, :source

  def initialize(code, filename = "unknown")
    @code = code
    @source = code
    @filename = filename
    @tokens = []
    @line = 1
    @column = 1
  end

  def tokenize
    cursor = 0
    while cursor < @code.length
      chunk = @code[cursor..-1]
      
      case chunk
      when /\A\n/
        @line += 1
        @column = 1
        cursor += 1
      when /\A[ \t\r]+/
        cursor += $&.length
        @column += $&.length
      when /\A(\/\/|#).*$/
        cursor += $&.length
        @column += $&.length
      when /\A(struct|union|fn|func|def|if|else|return|while|let|for|import|packed)\b/
        # Normalize func/def -> fn
        kw = $1
        kw = "fn" if kw == "func" || kw == "def"
        add_token(:keyword, kw)
        cursor += $&.length
        @column += $&.length
      when /\AinsertC\s*\{/
        start = cursor + $&.length
        brace_count = 1
        pos = start
        while pos < @code.length && brace_count > 0
          brace_count += 1 if @code[pos] == '{'
          brace_count -= 1 if @code[pos] == '}'
          pos += 1 if brace_count > 0
        end
        content = @code[start...pos]
        add_token(:insertC, nil, content)
        cursor = pos + 1
        @column = 1
      when /\A"/
        # Parse string with escape sequences
        cursor += 1  # skip opening quote
        @column += 1
        str_start = cursor
        raw_str = ""
        
        while cursor < @code.length && @code[cursor] != '"'
          if @code[cursor] == '\\'
            # Escape sequence
            raw_str += @code[cursor, 2]
            cursor += 2
            @column += 2
          else
            raw_str += @code[cursor]
            cursor += 1
            @column += 1
          end
        end
        
        if cursor >= @code.length
          error = JunoLexerError.new(
            "Unterminated string",
            filename: @filename,
            line_num: @line,
            column: @column,
            source: @source
          )
          JunoErrorReporter.report(error)
        end
        
        cursor += 1  # skip closing quote
        @column += 1
        
        processed = process_escapes(raw_str)
        add_token(:string, processed)
      when /\A0x[0-9a-fA-F]+/
        add_token(:number, $&.to_i(16))
        cursor += $&.length
        @column += $&.length
      when /\A0b[01]+/
        add_token(:number, $&.to_i(2))
        cursor += $&.length
        @column += $&.length
      when /\A0o[0-7]+/
        add_token(:number, $&.to_i(8))
        cursor += $&.length
        @column += $&.length
      when /\A\d+/
        add_token(:number, $&.to_i)
        cursor += $&.length
        @column += $&.length
      when /\A[a-zA-Z_]\w*/
        add_token(:ident, $&)
        cursor += $&.length
        @column += $&.length
      when /\A(==|!=|<=|>=|<<|>>|\+\+|\-\-)/
        add_token(:operator, $&)
        cursor += $&.length
        @column += $&.length
      when /\A(\|\|)/
        add_token(:operator, '||')
        cursor += 2
        @column += 2
      when /\A(&&)/
        add_token(:operator, '&&')
        cursor += 2
        @column += 2
      when /\A\|/
        add_token(:bitor, '|')
        cursor += 1
        @column += 1
      when /\A\^/
        add_token(:bitxor, '^')
        cursor += 1
        @column += 1
      when /\A~/
        add_token(:bitnot, '~')
        cursor += 1
        @column += 1
      when /\A</
        add_token(:langle, '<')
        cursor += 1
        @column += 1
      when /\A>/
        add_token(:rangle, '>')
        cursor += 1
        @column += 1
      when /\A&/
        add_token(:ampersand, '&')
        cursor += 1
        @column += 1
      when /\A\*/
        # Check context - could be multiply or dereference
        add_token(:star, '*')
        cursor += 1
        @column += 1
      when /\A\[/
        add_token(:lbracket, '[')
        cursor += 1
        @column += 1
      when /\A\]/
        add_token(:rbracket, ']')
        cursor += 1
        @column += 1
      when /\A(\(|\)|\{|\}|\.|\,|\+|\-|\/|%|=|;)/
        add_token(:symbol, $&)
        cursor += $&.length
        @column += $&.length
      when /\A:/
        add_token(:colon, ':')
        cursor += 1
        @column += 1
      else
        error = JunoLexerError.new(
          "Unexpected character '#{@code[cursor]}'",
          filename: @filename,
          line_num: @line,
          column: @column,
          source: @source
        )
        JunoErrorReporter.report(error)
      end
    end
    @tokens
  end

  private

  def add_token(type, value, content = nil)
    token = { type: type, value: value, line: @line, column: @column }
    token[:content] = content if content
    @tokens << token
  end

  # Process escape sequences in strings
  def process_escapes(str)
    str.gsub(/\\x([0-9a-fA-F]{2})/) { [$1.to_i(16)].pack('C') }
       .gsub(/\\n/, "\n")
       .gsub(/\\t/, "\t")
       .gsub(/\\r/, "\r")
       .gsub(/\\0/, "\0")
       .gsub(/\\\\/, "\\")
       .gsub(/\\"/, '"')
       .gsub(/\\e/, "\e")  # ESC character
  end
end
