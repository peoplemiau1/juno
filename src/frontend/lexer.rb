require_relative "../errors"

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

  require 'strscan'

  def tokenize
    scanner = StringScanner.new(@code)
    until scanner.eos?
      @column = (scanner.pos - (@code.rindex("\n", scanner.pos - 1) || -1))
      
      if scanner.scan(/\n/)
        @line += 1
        @column = 1
      elsif scanner.scan(/[ \t\r]+/)
      elsif scanner.scan(/(\/\/|#).*$/)
      elsif m = scanner.scan(/(struct|union|fn|func|def|if|elif|else|return|while|loop|break|continue|let|for|import|use|packed|extern|from|match|todo|panic|as|true|false|mut|type|enum|real|int|string|bool|ptr)\b/)
        kw = m; kw = "fn" if kw == "func" || kw == "def"
        add_token(:keyword, kw)
      elsif scanner.scan(/"/)
        str = ""
        until scanner.scan(/"/)
          if scanner.eos?
             JunoErrorReporter.report(JunoLexerError.new("Unterminated string", filename: @filename, line_num: @line, column: @column, source: @source))
             break
          end
          if scanner.scan(/\\/)
            if scanner.eos? then str << "\\"
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
                str << [hex.to_i(16)].pack('C') if hex
              else str << "\\" << esc
              end
            end
          else str << scanner.getch end
        end
        add_token(:string, process_escapes(str))
      elsif m = scanner.scan(/0x[0-9a-fA-F]+/) then add_token(:number, m[2..-1].to_i(16))
      elsif m = scanner.scan(/0b[01]+/) then add_token(:number, m[2..-1].to_i(2))
      elsif m = scanner.scan(/0o[0-7]+/) then add_token(:number, m[2..-1].to_i(8))
      elsif m = scanner.scan(/\d+/) then add_token(:number, m.to_i)
      elsif m = scanner.scan(/[a-zA-Z_]\w*/) then add_token(:ident, m)
      elsif m = scanner.scan(/==|!=|<=|>=|<<|>>|<>|->|\+\+|\-\-|\|\||&&/)
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
        JunoErrorReporter.report(JunoLexerError.new("Unexpected character '#{text}'", filename: @filename, line_num: @line, column: @column, source: @source))
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
