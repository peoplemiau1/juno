# Juno Error System - Beautiful error messages

module JunoColors
  RED = "\e[31m"
  YELLOW = "\e[33m"
  CYAN = "\e[36m"
  GRAY = "\e[90m"
  BOLD = "\e[1m"
  RESET = "\e[0m"
  UNDERLINE = "\e[4m"
end

class JunoError < StandardError
  include JunoColors
  
  attr_reader :error_type, :message, :filename, :line_num, :column, :source
  
  def initialize(error_type, message, filename: "unknown", line_num: nil, column: nil, source: nil)
    @error_type = error_type
    @message = message
    @filename = filename
    @line_num = line_num
    @column = column
    @source = source
    super(message)
  end

  def display
    puts ""
    puts "#{RED}#{BOLD}error[#{@error_type}]#{RESET}: #{BOLD}#{@message}#{RESET}"
    puts "  #{CYAN}-->#{RESET} #{@filename}:#{@line_num || '?'}:#{@column || '?'}"
    
    if @source && @line_num
      display_source_context
    end
    
    puts ""
  end

  private

  def display_source_context
    lines = @source.lines
    
    # Show 2 lines before, the error line, and 1 line after
    start_line = [@line_num - 2, 1].max
    end_line = [@line_num + 1, lines.length].min
    
    puts "   #{GRAY}|#{RESET}"
    
    (start_line..end_line).each do |ln|
      line_content = lines[ln - 1]&.chomp || ""
      line_num_str = ln.to_s.rjust(3)
      
      if ln == @line_num
        # Error line - highlight
        puts " #{RED}#{line_num_str}#{RESET} #{GRAY}|#{RESET} #{line_content}"
        
        # Show caret pointing to error
        if @column
          padding = " " * (@column - 1)
          puts "   #{GRAY}|#{RESET} #{padding}#{RED}^#{RESET}"
        else
          puts "   #{GRAY}|#{RESET} #{RED}^~~~#{RESET}"
        end
      else
        # Context line
        puts " #{GRAY}#{line_num_str} |#{RESET} #{line_content}"
      end
    end
    
    puts "   #{GRAY}|#{RESET}"
  end
end

# Specific error types
class JunoSyntaxError < JunoError
  def initialize(message, **opts)
    super("E0001", message, **opts)
  end
end

class JunoLexerError < JunoError
  def initialize(message, **opts)
    super("E0002", message, **opts)
  end
end

class JunoParseError < JunoError
  def initialize(message, **opts)
    super("E0003", message, **opts)
  end
end

class JunoTypeError < JunoError
  def initialize(message, **opts)
    super("E0004", message, **opts)
  end
end

class JunoUndefinedError < JunoError
  def initialize(message, **opts)
    super("E0005", message, **opts)
  end
end

class JunoCodegenError < JunoError
  def initialize(message, **opts)
    super("E0006", message, **opts)
  end
end

# Helper module for error reporting
module JunoErrorReporter
  include JunoColors
  
  def self.report(error)
    error.display
    exit 1
  end
  
  def self.warn(message, filename: nil, line_num: nil)
    puts ""
    puts "#{YELLOW}#{BOLD}warning#{RESET}: #{message}"
    if filename && line_num
      puts "  #{CYAN}-->#{RESET} #{filename}:#{line_num}"
    end
    puts ""
  end
  
  def self.hint(message)
    puts "#{CYAN}hint#{RESET}: #{message}"
  end
  
  def self.note(message)
    puts "#{GRAY}note#{RESET}: #{message}"
  end
end
