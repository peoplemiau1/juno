require_relative "errors"
require_relative "parser/parts/expressions"
require_relative "parser/parts/statements"
require_relative "parser/parts/watt"

class Parser
  include ParserExpressions
  include ParserStatements
  include WattParser

  def initialize(tokens, filename = "", source = "")
    @tokens = tokens
    @filename = filename
    @source = source
  end

  def parse
    ast = []
    until @tokens.empty?
      if match_symbol?('}')
        error_unexpected(peek, "Unexpected '}' at top level")
      end
      stmt = parse_statement
      ast << stmt if stmt
    end
    ast
  end

  # --- Helpers ---
  def peek; @tokens[0]; end
  def peek_next; @tokens[1]; end
  
  def consume(type = nil)
    t = @tokens.shift
    if t.nil?
      error_eof("Expected #{type || 'token'}")
    end
    if type && t[:type] != type
      error_unexpected(t, "Expected #{type}")
    end
    t
  end

  def match?(type); peek && peek[:type] == type; end
  def match_symbol?(val); peek && (peek[:type] == :symbol || peek[:type] == :operator) && peek[:value] == val; end
  def match_keyword?(val); peek && peek[:type] == :keyword && peek[:value] == val; end

  def with_loc(node, token)
    return node unless node.is_a?(Hash) && token
    node[:line] = token[:line]
    node[:column] = token[:column]
    node
  end

  def consume_symbol(val = nil)
    t = @tokens.shift
    if t.nil?
      error_eof("Expected '#{val}'")
    elsif t[:type] != :symbol && t[:type] != :operator
      error_unexpected(t, "Expected symbol '#{val}'")
    elsif val && t[:value] != val
      error_unexpected(t, "Expected '#{val}' but got '#{t[:value]}'")
    end
    t
  end

  def consume_keyword(val = nil)
    t = @tokens.shift
    if t.nil?
      error_eof("Expected keyword '#{val}'")
    elsif t[:type] != :keyword
      error_unexpected(t, "Expected keyword '#{val}'")
    elsif val && t[:value] != val
      error_unexpected(t, "Expected '#{val}' but got '#{t[:value]}'")
    end
    t
  end

  def consume_ident
    t = @tokens.shift
    if t.nil?
      error_eof("Expected identifier")
    elsif t[:type] != :ident
      error_unexpected(t, "Expected identifier")
    end
    t[:value]
  end

  private

  def error_unexpected(token, message)
    if token.nil?
      error_eof(message)
    end
    error = JunoParseError.new(
      "#{message}, got #{token[:type]} '#{token[:value]}'",
      filename: @filename,
      line_num: token[:line],
      column: token[:column],
      source: @source
    )
    JunoErrorReporter.report(error)
  end

  def error_eof(message)
    error = JunoParseError.new(
      "#{message}, but reached end of file",
      filename: @filename,
      line_num: @source.lines.length,
      source: @source
    )
    JunoErrorReporter.report(error)
  end
end
