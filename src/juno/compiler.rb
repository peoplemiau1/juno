require_relative "frontend/lexer"
require_relative "frontend/parser"
require_relative "frontend/preprocessor"
require_relative "middle/importer"
require_relative "middle/monomorphizer"
require_relative "middle/semantic"
require_relative "middle/analyzer/auto_drop"
require_relative "middle/analyzer/safety_checker"
require_relative "backend/llvm/generator"
require_relative "errors"

module Juno
  class Compiler
    attr_reader :asm_log

    def initialize(options = {})
      @options = {
        arch: :x86_64,
        os: :linux,
        output: "build/output",
        audit: true,
        stdlib_path: find_stdlib_path,
        no_std: false
      }.merge(options)
    end

    def compile(input_file)
      code = File.read(input_file)
      unless @options[:no_std]
        if input_file != File.join(@options[:stdlib_path], "std.juno") && !code.include?("import \"std\"")
          code = "import \"std.juno\"\n" + code
        end
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

      auto_drop = AutoDropPass.new(ast)
      ast = auto_drop.run

      if @options[:audit]
        safety_checker = JunoSafetyChecker.new(ast, analyzer.function_signatures, code, input_file)
        safety_checker.check
      end

      generator = LLVMGenerator.new(ast, source: code, filename: input_file, arch: @options[:arch])
      llvm_ir = generator.generate
      @asm_log = [llvm_ir]

      ir_file = @options[:output] + ".ll"
      obj_file = @options[:output] + ".o"
      File.write(ir_file, llvm_ir)

      target_triple = detect_target_triple
      llc_cmd = `which llc-19 llc-18 llc-17 llc`.split("\n").first&.strip
      opt_cmd = `which opt-19 opt-18 opt-17 opt`.split("\n").first&.strip
      
      raw_opt = @options[:opt_level].to_s
      opt_level = (raw_opt == 's' || raw_opt == 'z') ? raw_opt : (raw_opt.to_i || 2)

      target_ir_file = ir_file

      if opt_cmd && opt_level.to_s != "0"
        optimized_ir_file = @options[:output] + ".opt.ll"
        pass_val = (opt_level == 's' || opt_level == 'z') ? opt_level : opt_level
        if system("#{opt_cmd} -passes='default<O#{pass_val}>' -S -o #{optimized_ir_file} #{ir_file}")
          target_ir_file = optimized_ir_file
        elsif system("#{opt_cmd} -O#{opt_level} -S -o #{optimized_ir_file} #{ir_file}")
          target_ir_file = optimized_ir_file
        end
      end

      llc_opt = (opt_level == 's' || opt_level == 'z') ? "-O2" : "-O#{opt_level}"
      unless system("#{llc_cmd} #{llc_opt} -function-sections -data-sections -mtriple=#{target_triple} -relocation-model=pic -filetype=obj -o #{obj_file} #{target_ir_file}")
        raise "LLVM backend (llc) compilation failed"
      end

      runtime_obj = File.expand_path("backend/llvm/runtime_#{@options[:os]}_#{@options[:arch]}.o", __dir__)
      runtime_src = File.expand_path("backend/llvm/runtime.c", __dir__)
      
      unless File.exist?(runtime_obj)
        if @options[:os] == :macos && RUBY_PLATFORM !~ /darwin/i && @options[:darling]
          darling_runtime_obj = "/Volumes/SystemRoot" + runtime_obj
          darling_runtime_src = "/Volumes/SystemRoot" + runtime_src
          system("darling shell clang -fPIC -O2 -c -o #{darling_runtime_obj} #{darling_runtime_src}")
        else
          system("gcc -fPIC -O2 -c -o #{runtime_obj} #{runtime_src}")
        end
      end

      if @options[:target] == :flat || @options[:target].to_s == "flat"
        system("objcopy -O binary #{obj_file} #{@options[:output]}")
      elsif @options[:target] == :obj || @options[:target].to_s == "obj"
        File.binwrite(@options[:output], File.binread(obj_file))
      else
        if @options[:os] == :macos
          if RUBY_PLATFORM !~ /darwin/i && @options[:darling]
            darling_output = "/Volumes/SystemRoot" + File.expand_path(@options[:output])
            darling_obj_file = "/Volumes/SystemRoot" + File.expand_path(obj_file)
            darling_runtime_obj = "/Volumes/SystemRoot" + runtime_obj
            link_cmd = "darling shell clang -o #{darling_output} #{darling_obj_file} #{darling_runtime_obj}"
          else
            link_cmd = "gcc -o #{@options[:output]} #{obj_file} #{runtime_obj}"
          end
        else
          link_cmd = "gcc -no-pie -o #{@options[:output]} #{obj_file} #{runtime_obj}"
        end
        system(link_cmd)
      end

      @options[:output]
    end

    private

    def find_stdlib_path
      real_path = nil
      begin
        real_path = File.expand_path("../../stdlib", File.dirname(File.realdirpath(__FILE__)))
      rescue
        nil
      end

      paths = [
        ENV['JUNO_STDLIB'],
        File.expand_path("../../stdlib", __dir__),
        real_path,
        File.expand_path("~/juno/stdlib"),
        File.expand_path("../stdlib", Dir.pwd),
        "/usr/local/lib/juno/stdlib",
        "/usr/lib/juno/stdlib"
      ].compact

      paths.find { |p| File.directory?(p) && File.exist?(File.join(p, "std.juno")) } || File.expand_path("../../stdlib", __dir__)
    end

    def detect_target_triple
      arch = @options[:arch]
      os = @options[:os]
      return (arch == :x86_64 ? "x86_64-apple-macos" : "arm64-apple-macos") if os == :macos
      
      triples = {
        x86_64: "x86_64-pc-linux-gnu",
        aarch64: "aarch64-unknown-linux-gnu",
        arm: "arm-unknown-linux-gnueabi",
        riscv64: "riscv64-unknown-linux-gnu",
        riscv32: "riscv32-unknown-linux-gnu"
      }
      triples[arch] || "x86_64-pc-linux-gnu"
    end
  end
end
