class Preprocessor
  REG_MAP = { rax: 0, rcx: 1, rdx: 2, rbx: 3, rsp: 4, rbp: 5, rsi: 6, rdi: 7 }

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
    skip_stack = []
    asm_mode = false
    asm_bytes = []
    
    lines.each_with_index do |line, idx|
      stripped = line.strip
      
      if skip_stack.any? { |s| s == true }
        if stripped.start_with?('#endif')
          skip_stack.pop
        elsif stripped.start_with?('#ifdef') || stripped.start_with?('#ifndef')
          skip_stack.push(true)
        elsif stripped.start_with?('#else') && skip_stack.length == 1
          skip_stack[-1] = !skip_stack[-1]
        end
        next
      end
      
      if asm_mode
        if stripped == '#endasm'
          asm_mode = false
          result << "insertC { #{asm_bytes.map { |b| "0x%02X" % b }.join(', ')} }\n"
          asm_bytes = []
        else
          bytes = assemble_line(stripped)
          asm_bytes.concat(bytes) if bytes
        end
        next
      end

      if stripped == '#asm'
        asm_mode = true
        asm_bytes = []
        next
      end
      
      if stripped.start_with?('#')
        process_directive(stripped, result, skip_stack, filename)
      else
        processed_line = replace_macros(line)
        result << processed_line
      end
    end
    
    result.join
  end

  private

  def assemble_line(line)
    line = line.split('//').first.split('#').first.strip
    return [] if line.empty?

    case line
    when /^syscall$/i
      [0x0F, 0x05]
    when /^ret$/i
      [0xC3]
    when /^cli$/i
      [0xFA]
    when /^sti$/i
      [0xFB]
    when /^hlt$/i
      [0xF4]
    when /^nop$/i
      [0x90]
    when /^pause$/i
      [0xF3, 0x90]
    when /^iretq$/i
      [0x48, 0xCF]
    when /^rdmsr$/i
      [0x0F, 0x32]
    when /^wrmsr$/i
      [0x0F, 0x30]
    when /^in\s+al\s*,\s*dx$/i
      [0xEC]
    when /^out\s+dx\s*,\s*al$/i
      [0xEE]
    when /^in\s+ax\s*,\s*dx$/i
      [0x66, 0xED]
    when /^out\s+dx\s*,\s*ax$/i
      [0x66, 0xEF]
    when /^in\s+eax\s*,\s*dx$/i
      [0xED]
    when /^out\s+dx\s*,\s*eax$/i
      [0xEF]
    when /^push\s+(rax|rcx|rdx|rbx|rsp|rbp|rsi|rdi)$/i
      reg = REG_MAP[$1.downcase.to_sym]
      [0x50 + reg]
    when /^pop\s+(rax|rcx|rdx|rbx|rsp|rbp|rsi|rdi)$/i
      reg = REG_MAP[$1.downcase.to_sym]
      [0x58 + reg]
    when /^xor\s+(rax|rcx|rdx|rbx|rsp|rbp|rsi|rdi)\s*,\s*\1$/i
      reg = REG_MAP[$1.downcase.to_sym]
      [0x48, 0x31, 0xC0 + reg * 9]
    when /^mov\s+(rax|rcx|rdx|rbx|rsp|rbp|rsi|rdi)\s*,\s*(\d+)$/i
      reg = REG_MAP[$1.downcase.to_sym]
      val = $2.to_i
      [0x48, 0xC7, 0xC0 + reg] + [val].pack("l<").bytes
    when /^mov\s+(rax|rcx|rdx|rbx|rsp|rbp|rsi|rdi)\s*,\s*(0x[0-9a-fA-F]+)$/i
      reg = REG_MAP[$1.downcase.to_sym]
      val = $2.to_i(16)
      [0x48, 0xC7, 0xC0 + reg] + [val].pack("l<").bytes
    when /^mov\s+(rax|rcx|rdx|rbx|rsp|rbp|rsi|rdi)\s*,\s*(rax|rcx|rdx|rbx|rsp|rbp|rsi|rdi)$/i
      dst = REG_MAP[$1.downcase.to_sym]
      src = REG_MAP[$2.downcase.to_sym]
      [0x48, 0x89, 0xC0 + src * 8 + dst]
    when /^mov\s+cr0\s*,\s*(rax|rcx|rdx|rbx|rsp|rbp|rsi|rdi)$/i
      reg = REG_MAP[$1.downcase.to_sym]
      [0x0F, 0x22, 0xC0 + reg]
    when /^mov\s+cr3\s*,\s*(rax|rcx|rdx|rbx|rsp|rbp|rsi|rdi)$/i
      reg = REG_MAP[$1.downcase.to_sym]
      [0x0F, 0x22, 0xD8 + reg]
    when /^mov\s+cr4\s*,\s*(rax|rcx|rdx|rbx|rsp|rbp|rsi|rdi)$/i
      reg = REG_MAP[$1.downcase.to_sym]
      [0x0F, 0x22, 0xE0 + reg]
    when /^mov\s+(rax|rcx|rdx|rbx|rsp|rbp|rsi|rdi)\s*,\s*cr0$/i
      reg = REG_MAP[$1.downcase.to_sym]
      [0x0F, 0x20, 0xC0 + reg]
    when /^mov\s+(rax|rcx|rdx|rbx|rsp|rbp|rsi|rdi)\s*,\s*cr3$/i
      reg = REG_MAP[$1.downcase.to_sym]
      [0x0F, 0x20, 0xD8 + reg]
    when /^mov\s+(rax|rcx|rdx|rbx|rsp|rbp|rsi|rdi)\s*,\s*cr4$/i
      reg = REG_MAP[$1.downcase.to_sym]
      [0x0F, 0x20, 0xE0 + reg]
    when /^int\s+3$/i
      [0xCC]
    when /^int\s+(\d+|0x[0-9a-fA-F]+)$/i
      val = $1.start_with?("0x") ? $1.to_i(16) : $1.to_i
      [0xCD, val]
    else
      []
    end
  end

  def process_directive(line, result, skip_stack, filename)
    case line
    when /^#define\s+(\w+)\s+(.+)$/
      name = $1
      value = $2.strip
      @defines[name] = true
      @define_values[name] = value
      
    when /^#define\s+(\w+)$/
      @defines[$1] = true
      
    when /^#undef\s+(\w+)$/
      @defines.delete($1)
      @define_values.delete($1)
      
    when /^#ifdef\s+(\w+)$/
      skip_stack.push(!@defines[$1])
      
    when /^#ifndef\s+(\w+)$/
      skip_stack.push(@defines[$1] == true)
      
    when /^#else$/
      if skip_stack.any?
        skip_stack[-1] = !skip_stack[-1]
      end
      
    when /^#endif$/
      skip_stack.pop if skip_stack.any?
      
    when /^#error\s+(.+)$/
      raise "Preprocessor error: #{$1}"
      
    when /^#warning\s+(.+)$/
      puts "\e[33mWarning: #{$1}\e[0m"
      
    when /^#if\s+(.+)$/
      expr = $1.strip
      if expr =~ /defined\s*\(\s*(\w+)\s*\)/
        skip_stack.push(!@defines[$1])
      else
        skip_stack.push(false)
      end
    end
  end

  def replace_macros(line)
    result = line
    @define_values.each do |name, value|
      next if value.nil?
      result = result.gsub(/\b#{Regexp.escape(name)}\b/, value.to_s)
    end
    result
  end
end
