require_relative "../errors"
require_relative "parser/parts/expressions"
require_relative "parser/parts/statements"
require "thread"
require "etc"

class Parser
  include ParserExpressions
  include ParserStatements

  def self.parse_many(entries)
    return [] if entries.empty?

    pool_size = [Etc.nprocessors, entries.size].min
    pool_size = 1 if pool_size < 1

    results = Array.new(entries.size)
    errors = Array.new(entries.size)
    queue = Queue.new
    entries.each_with_index { |e, i| queue << [e, i] }

    workers = Array.new(pool_size) do
      Thread.new do
        loop do
          job = begin
            queue.pop(true)
          rescue ThreadError
            nil
          end
          break unless job

          entry, idx = job
          tokens, filename, source = entry
          begin
            results[idx] = new(tokens, filename || "", source || "").parse
          rescue Exception => e
            errors[idx] = e
          end
        end
      end
    end

    workers.each(&:join)

    first_error = errors.compact.first
    raise first_error if first_error

    results
  end

  def initialize(tokens, filename = "", source = "")
    @tokens = tokens
    @filename = filename
    @source = source
    @last_token = nil
  end

  def parse_async(&block)
    Thread.new do
      result = parse
      block.call(result) if block
      result
    end
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
    @last_token = t
    t
  end

  def on_same_line?
    return false unless peek && @last_token
    peek[:line] == @last_token[:line]
  end

  def match?(type)
    return false unless peek
    return (peek[:type] == type) || (type == :ident && peek[:type] == :keyword && (peek[:value] == "ptr" || peek[:value] == "float"))
  end
  def match_symbol?(val); peek && ([:symbol, :operator, :star, :ampersand, :langle, :rangle, :bitor, :bitxor].include?(peek[:type])) && peek[:value] == val; end
  def match_keyword?(val); peek && peek[:type] == :keyword && peek[:value] == val; end

  def with_loc(node, token)
    return node unless node && token
    if node.is_a?(Hash)
      node[:line] = token[:line]
      node[:column] = token[:column]
      node[:filename] = @filename
    elsif node.is_a?(AST::Node)
      node.line = token[:line]
      node.column = token[:column]
      node.filename = @filename
    end
    node
  end

  def consume_symbol(val = nil)
    t = @tokens.shift
    if t.nil?
      error_eof("Expected '#{val}'")
    elsif ![:symbol, :operator, :star, :ampersand, :langle, :rangle, :bitor, :bitxor].include?(t[:type])
      error_unexpected(t, "Expected symbol or operator '#{val}'")
    elsif val && t[:value] != val
      error_unexpected(t, "Expected '#{val}' but got '#{t[:value]}'")
    end
    @last_token = t
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
    @last_token = t
    t
  end

  def consume_ident
    t = @tokens.shift
    if t.nil?
      error_eof("Expected identifier")
    elsif t[:type] == :keyword && (t[:value] == "ptr" || t[:value] == "float")
      @last_token = t
      return t[:value]
    elsif t[:type] != :ident
      error_unexpected(t, "Expected identifier")
    end
    @last_token = t
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
