require_relative "../errors"
require "strscan"

class Lexer
  attr_reader :tokens, :source, :errors

  MAX_ERRORS = 100

  KEYWORD_RE = /(struct|union|fn|func|def|if|elif|else|return|while|loop|break|continue|let|for|import_c|import|use|packed|extern|from|match|todo|panic|as|true|false|mut|type|enum|real|float|int|string|bool|ptr)\b/

  def initialize(code, filename = "unknown")
    @code = code
    @source = code
    @filename = filename
    @tokens = []
    @errors = []
    @line = 1
    @column = 1
  end

  def tokenize
    scanner = StringScanner.new(@code)
    until scanner.eos? || @errors.length >= MAX_ERRORS
      current_pos = scanner.pos
      last_newline = current_pos > 0 ? @code.rindex("\n", current_pos - 1) : nil
      @column = last_newline ? (current_pos - last_newline) : (current_pos + 1)

      if scanner.scan(/\n/)
        @line += 1
        @column = 1
      elsif scanner.scan(/[ \t\r]+/)
      elsif scanner.scan(/(\/\/|#).*$/)
      elsif scanner.scan(/insertC\s*(?:clobbers\s*\(\s*([^)]*)\s*\)\s*)?\{/i)
        scan_raw_block(scanner, :insertC, "insertC")
      elsif scanner.scan(/asm\s*(?:clobbers\s*\(\s*([^)]*)\s*\)\s*)?\{/i)
        scan_raw_block(scanner, :asm, "asm")
      elsif m = scanner.scan(KEYWORD_RE)
        kw = m
        kw = "fn" if kw == "func" || kw == "def"
        add_token(:keyword, kw)
      elsif scanner.scan(/"/)
        scan_string(scanner)
      elsif m = scanner.scan(/0x[0-9a-fA-F]+/) then add_token(:number, m[2..-1].to_i(16))
      elsif m = scanner.scan(/0b[01]+/) then add_token(:number, m[2..-1].to_i(2))
      elsif m = scanner.scan(/0o[0-7]+/) then add_token(:number, m[2..-1].to_i(8))
      elsif m = scanner.scan(/\d+\.\d+/) then add_token(:float_literal, m.to_f)
      elsif m = scanner.scan(/\d+/) then add_token(:number, m.to_i)
      elsif m = scanner.scan(/[a-zA-Z_]\w*/) then add_token(:ident, m)
      elsif m = scanner.scan(/==|!=|<=|>=|<<|>>|=>|<>|->|\+\+|\-\-|\|\||&&/)
        add_token(:operator, m)
      elsif scanner.scan(/\|/) then add_token(:bitor, '|')
      elsif scanner.scan(/\^/) then add_token(:bitxor, '^')
      elsif scanner.scan(/~/) then add_token(:bitnot, '~')
      elsif scanner.scan(/</) then add_token(:langle, '<')
      elsif scanner.scan(/>/) then add_token(:rangle, '>')
      elsif scanner.scan(/&/) then add_token(:ampersand, '&')
      elsif scanner.scan(/\*/) then add_token(:star, '*')
      elsif scanner.scan(/\[/) then add_token(:lbracket, '[')
      elsif scanner.scan(/\]/) then add_token(:rbracket, ']')
      elsif m = scanner.scan(/[\(\)\{\}\.\,\+\-\/\%\\=\;\!]/) then add_token(:symbol, m)
      elsif scanner.scan(/:/) then add_token(:colon, ':')
      else
        text = scanner.getch
        record_error("Unexpected character '#{text}'")
      end
    end
    raise JunoMultiParseError.new(@errors) unless @errors.empty?
    @tokens
  end

  private

  def scan_raw_block(scanner, type, value)
    matched_str = scanner.matched
    @line += matched_str.count("\n")
    clobbers_str = scanner[1]
    clobbers = clobbers_str ? clobbers_str.split(',').map(&:strip).reject(&:empty?) : []
    content = ""
    until scanner.check(/\}/) || scanner.eos?
      ch = scanner.getch
      @line += 1 if ch == "\n"
      content << ch
    end
    if scanner.eos?
      record_error("Unterminated #{value} block")
      return
    end
    scanner.getch
    @tokens << {
      type: type,
      value: value,
      line: @line,
      column: @column,
      content: content,
      clobbers: clobbers
    }
  end

  def scan_string(scanner)
    str = ""
    start_line = @line
    start_column = @column
    until scanner.scan(/"/)
      if scanner.eos?
        @errors << JunoLexerError.new(
          "Unterminated string",
          filename: @filename,
          line_num: start_line,
          column: start_column,
          source: @source
        )
        return
      end
      if scanner.scan(/\\/)
        if scanner.eos?
          str << "\\"
        else
          case esc = scanner.getch
          when "n" then str << "\n"
          when "t" then str << "\t"
          when "r" then str << "\r"
          when "0" then str << "\0"
          when "\\" then str << "\\"
          when "\"" then str << "\""
          when "e" then str << "\e"
          when "x"
            hex = scanner.scan(/[0-9a-fA-F]{2}/)
            if hex
              str << [hex.to_i(16)].pack('C')
            else
              record_error("Invalid \\x escape, expected two hex digits")
            end
          else str << "\\" << esc
          end
        end
      else
        ch = scanner.getch
        @line += 1 if ch == "\n"
        str << ch
      end
    end
    @tokens << { type: :string, value: str, line: start_line, column: start_column }
  end

  def record_error(message)
    @errors << JunoLexerError.new(
      message,
      filename: @filename,
      line_num: @line,
      column: @column,
      source: @source
    )
  end

  def add_token(type, value, content = nil)
    token = { type: type, value: value, line: @line, column: @column }
    token[:content] = content if content
    @tokens << token
  end
end


