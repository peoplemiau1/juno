# Juno Preprocessor
# Handles #define, #ifdef, #ifndef, #endif, #include

class Preprocessor
  def initialize
    @defines = {}
    @define_values = {}
  end

  def define(name, value = nil)
    @defines[name] = true
    @define_values[name] = value
  end

  def defined?(name)
    @defines[name] == true
  end

  def get_value(name)
    @define_values[name]
  end

  def process(code, filename = "")
    lines = code.lines
    result = []
    skip_stack = []  # Stack of booleans for nested #ifdef
    
    lines.each_with_index do |line, idx|
      stripped = line.strip
      
      # Check if we're in a skipped section
      if skip_stack.any? { |s| s == true }
        if stripped.start_with?('#endif')
          skip_stack.pop
        elsif stripped.start_with?('#ifdef') || stripped.start_with?('#ifndef')
          skip_stack.push(true)  # Nested, still skip
        elsif stripped.start_with?('#else') && skip_stack.length == 1
          skip_stack[-1] = !skip_stack[-1]
        end
        next
      end
      
      if stripped.start_with?('#')
        process_directive(stripped, result, skip_stack, filename)
      else
        # Replace defined macros in the line
        processed_line = replace_macros(line)
        result << processed_line
      end
    end
    
    result.join
  end

  private

  def process_directive(line, result, skip_stack, filename)
    case line
    when /^#define\s+(\w+)\s+(.+)$/
      # #define NAME VALUE
      name = $1
      value = $2.strip
      @defines[name] = true
      @define_values[name] = value
      
    when /^#define\s+(\w+)$/
      # #define NAME
      @defines[$1] = true
      
    when /^#undef\s+(\w+)$/
      # #undef NAME
      @defines.delete($1)
      @define_values.delete($1)
      
    when /^#ifdef\s+(\w+)$/
      # #ifdef NAME
      skip_stack.push(!@defines[$1])
      
    when /^#ifndef\s+(\w+)$/
      # #ifndef NAME
      skip_stack.push(@defines[$1] == true)
      
    when /^#else$/
      # #else
      if skip_stack.any?
        skip_stack[-1] = !skip_stack[-1]
      end
      
    when /^#endif$/
      # #endif
      skip_stack.pop if skip_stack.any?
      
    when /^#error\s+(.+)$/
      # #error MESSAGE
      raise "Preprocessor error: #{$1}"
      
    when /^#warning\s+(.+)$/
      # #warning MESSAGE
      puts "\e[33mWarning: #{$1}\e[0m"
      
    when /^#if\s+(.+)$/
      # #if EXPRESSION (simple: just check if defined)
      expr = $1.strip
      if expr =~ /defined\s*\(\s*(\w+)\s*\)/
        skip_stack.push(!@defines[$1])
      else
        skip_stack.push(false)  # Default: include
      end
    end
  end

  def replace_macros(line)
    result = line
    @define_values.each do |name, value|
      next if value.nil?
      # Replace whole word only
      result = result.gsub(/\b#{Regexp.escape(name)}\b/, value.to_s)
    end
    result
  end
end
