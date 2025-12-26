# src/main.rb (NASM Edition - Clean)
require 'fileutils'

class AsmTranspiler
  def initialize(file)
    @source = File.read(file).gsub(/\/\/.*$/, "")
    @pos = 0
    @data = ["fmt_s db '%s', 0", "fmt_c db '%c', 0", "fmt_d db '%lld', 10, 0"]
    @text = []
    @labels = 0
  end

  def skip_ws
    @pos += 1 while @source[@pos] && @source[@pos] <= ' '
  end

  def find_closing(text, start)
    depth = 0
    (start...text.length).each do |i|
      depth += 1 if text[i] == '{'
      depth -= 1 if text[i] == '}'
      return i if depth == 0 && text[i] == '}'
    end
    -1
  end

  def scan
    while @pos < @source.length
      skip_ws
      break if @pos >= @source.length
      
      if @source[@pos..-1] =~ /\Alet\s+(\w+)\s*=\s*(-?\d+);/
        @data << "#{$1} dq #{$2}"
        @pos += $&.length
      elsif @source[@pos..-1] =~ /\Afn\s+(\w+)\s*\(\)\s*\{/
        name = $1
        b_s = @pos + @source[@pos..-1].index('{')
        b_f = find_closing(@source, b_s)
        body = @source[b_s+1...b_f]
        @pos = b_f + 1
        
        # Rename main to avoid conflict with the entry point
        asm_name = (name == "main" ? "juno_main" : name)
        @text << "global #{asm_name}" << "#{asm_name}:" << "push rbp" << "mov rbp, rsp" << "sub rsp, 32"
        process_body(body)
        @text << "add rsp, 32" << "pop rbp" << "ret" << ""
      elsif @source[@pos..-1] =~ /\A(\w+)\(\);/
        # Top level calls go into the real main
        func = $1
        asm_func = (func == "main" ? "juno_main" : func)
        unless @main_started
          @text << "global main" << "main:" << "push rbp" << "mov rbp, rsp" << "sub rsp, 32"
          @main_started = true
        end
        @text << "call #{asm_func}"
        @pos += $&.length
      else
        @pos += 1
      end
    end
    if @main_started
       @text << "xor rax, rax" << "add rsp, 32" << "pop rbp" << "ret"
    end
  end

  def process_body(body)
    p = 0
    while p < body.length
      body[p..-1] =~ /\A\s+/; p += ($& ? $&.length : 0)
      break if p >= body.length
      
      if body[p, 9] == "insertASM"
        bs = body.index('{', p)
        bf = find_closing(body, bs)
        @text << body[bs+1...bf].strip
        p = bf + 1
      elsif body[p..-1] =~ /\Awhile\s*\((.*?)\)\s*\{/
        cond = $1
        bs = p + body[p..-1].index('{')
        bf = find_closing(body, bs)
        inner = body[bs+1...bf]
        
        l_start = "L#{@labels}"; l_end = "LE#{@labels}"; @labels += 1
        @text << "#{l_start}:"
        if cond =~ /(\w+)\s*!=\s*(-?\d+)/
          @text << "mov rax, [rel #{$1}]"
          @text << "cmp rax, #{$2}"
          @text << "je #{l_end}"
        end
        process_body(inner)
        @text << "jmp #{l_start}"
        @text << "#{l_end}:"
        p = bf + 1
      elsif body[p..-1] =~ /\A(\w+)\(\);/
        func = $1
        asm_func = (func == "main" ? "juno_main" : func)
        @text << "call #{asm_func}"
        p += $&.length
      else
        p += 1
      end
    end
  end

  def assemble
    out = ["extern printf, fgetc, stdin, putchar, strcmp", "section .data"] + @data + ["section .text"] + @text
    File.write("out.asm", out.join("\n"))
    return unless system("nasm -f win64 out.asm -o out.obj")
    system("gcc out.obj -o compiler.exe")
    puts "Stage 2.0: compiler.exe ready."
  end
end

t = AsmTranspiler.new("compiler.juno")
t.scan
t.assemble