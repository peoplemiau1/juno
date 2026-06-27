require_relative "frontend/lexer"
require_relative "frontend/parser"
require_relative "middle/importer"
require_relative "middle/monomorphizer"
require_relative "middle/semantic"
require_relative "backend/llvm/generator"
require_relative "frontend/preprocessor"
require_relative "errors"

module Juno
  class Compiler
    attr_reader :asm_log

    def initialize(options = {})
      @options = {
        arch: :x86_64,
        os: :linux,
        output: "build/output",
        stdlib_path: ENV['JUNO_STDLIB'] || File.expand_path("../../stdlib", __dir__)
      }.merge(options)
    end

    def compile(input_file)
      code = File.read(input_file)
      if input_file != File.join(@options[:stdlib_path], "std.juno") && !code.include?("import \"std\"")
        code = "import \"std.juno\"\n" + code
      end

      preprocessor = Preprocessor.new
      preprocessor.define(@options[:os].to_s.upcase)
      preprocessor.define("__JUNO__")
      code = preprocessor.process(code, input_file)

      lexer = Lexer.new(code, input_file)
      tokens = lexer.tokenize
      parser = Parser.new(tokens, input_file, code)
      ast = parser.parse

      importer = Importer.new(File.dirname(input_file), system_path: @options[:stdlib_path])
      ast = importer.resolve(ast, input_file)

      monomorphizer = Monomorphizer.new(ast)
      ast = monomorphizer.monomorphize

      analyzer = SemanticAnalyzer.new(ast, input_file, code)
      ast = analyzer.analyze

      generator = LLVMGenerator.new(ast, source: code, filename: input_file, arch: @options[:arch])
      llvm_ir = generator.generate
      @asm_log = [llvm_ir]

      ir_file = @options[:output] + ".ll"
      obj_file = @options[:output] + ".o"
      File.write(ir_file, llvm_ir)

      target_triple = detect_target_triple
      llc_cmd = `which llc-19 llc-18 llc-17 llc`.split("\n").first&.strip
      
      unless system("#{llc_cmd} -O2 -filetype=obj -mtriple=#{target_triple} -o #{obj_file} #{ir_file}")
        raise "LLVM Compiler (llc) execution failed. Please verify LLVM installation."
      end

      runtime_obj = File.expand_path("backend/llvm/runtime.o", __dir__)
      runtime_src = File.expand_path("backend/llvm/runtime.c", __dir__)
      
      unless File.exist?(runtime_obj)
        system("gcc -fPIC -O2 -c -o #{runtime_obj} #{runtime_src}")
      end

      link_cmd = "gcc -no-pie -o #{@options[:output]} #{obj_file} #{runtime_obj}"
      system(link_cmd)

      @options[:output]
    end

    private

    def detect_target_triple
      arch = @options[:arch]
      os = @options[:os]
      return "x86_64-apple-macos" if os == :macos
      "x86_64-pc-linux-gnu"
    end
  end
end
