require_relative "frontend/lexer"
require_relative "frontend/parser"
require_relative "middle/importer"
require_relative "middle/monomorphizer"
require_relative "middle/semantic"
require_relative "optimizer/turbo"
require_relative "middle/analyzer/resource_auditor"
require_relative "backend/codegen/native_generator"
require_relative "backend/llvm/generator"
require_relative "frontend/preprocessor"
require_relative "middle/analyzer/borrow_checker"
require_relative "errors"

module Juno
  class Compiler
    def initialize(options = {})
      @options = {
        arch: :x86_64,
        os: :linux,
        output: "build/output",
        audit: true,
        stdlib_path: ENV['JUNO_STDLIB'] || File.expand_path("../stdlib", __dir__)
      }.merge(options)
    end

    def compile(input_file)
      code = File.read(input_file)

      # 0. Auto-import std if available
      # We use a special syntax or just search for std.juno in stdlib
      if input_file != File.join(@options[:stdlib_path], "std.juno") && !code.include?("import \"std\"")
        code = "import \"std.juno\"\n" + code
      end

      # 1. Preprocessing
      preprocessor = Preprocessor.new
      preprocessor.define(@options[:os].to_s.upcase)
      preprocessor.define("__JUNO__")
      code = preprocessor.process(code, input_file)

      # 2. Frontend
      lexer = Lexer.new(code, input_file)
      tokens = lexer.tokenize
      parser = Parser.new(tokens, input_file, code)
      ast = parser.parse

      # 3. Middle-end
      importer = Importer.new(File.dirname(input_file), system_path: @options[:stdlib_path])
      ast = importer.resolve(ast, input_file)
      
      monomorphizer = Monomorphizer.new(ast)
      ast = monomorphizer.monomorphize

      analyzer = SemanticAnalyzer.new(ast, input_file, code)
      ast = analyzer.analyze

      borrow_checker = BorrowChecker.new(ast, code, input_file)
      borrow_checker.check

      optimizer = TurboOptimizer.new(ast)
      ast = optimizer.optimize

      # Resource auditing using signatures from SemanticAnalyzer
      auditor = ResourceAuditor.new(ast, analyzer.function_signatures, code, input_file)
      auditor.audit

      # 4. Backend
      if @options[:native]
        generator = NativeGenerator.new(ast, 
          target_os: @options[:os], 
          arch: @options[:arch], 
          source: code, 
          filename: input_file
        )
        generator.generate(@options[:output])
      else
        generator = LLVMGenerator.new(ast, 
          source: code, 
          filename: input_file
        )
        llvm_ir = generator.generate
        ir_file = @options[:output] + ".ll"
        obj_file = @options[:output] + ".o"
        File.write(ir_file, llvm_ir)
        
        # Mapping architectures to target triples
        triples = {
          x86_64: "x86_64-pc-linux-gnu",
          aarch64: "aarch64-unknown-linux-gnu",
          arm: "arm-unknown-linux-gnueabi",
          riscv64: "riscv64-unknown-linux-gnu",
          riscv32: "riscv32-unknown-linux-gnu"
        }
        target_triple = triples[@options[:arch]] || "x86_64-pc-linux-gnu"

        # 1. Find llc tool
        llc_cmd = `which llc-19 llc-18 llc-17 llc`.split("\n").first&.strip
        raise "llc tool not found. Please install llvm." unless llc_cmd
        
        # 2. Compile IR to object file
        opt_flag = "-O#{@options[:opt_level] || 2}"
        unless system("#{llc_cmd} #{opt_flag} -mtriple=#{target_triple} -relocation-model=pic -filetype=obj -o #{obj_file} #{ir_file}")
          raise "llc failed to compile IR. Check #{ir_file} for errors."
        end
        
        if @options[:target] == :flat
          # For flat binary, we use llvm-objcopy which is better for cross-arch
          objcopy_cmd = "llvm-objcopy-19" # Match llc version
          unless system("#{objcopy_cmd} -O binary #{obj_file} #{@options[:output]}")
             # Fallback to standard objcopy
             unless system("objcopy -O binary #{obj_file} #{@options[:output]}")
               raise "Failed to generate flat binary using objcopy."
             end
          end
          return @options[:output]
        end

        # 3. Compile runtime if not already done
        runtime_src = File.expand_path("backend/llvm/runtime.c", __dir__)
        runtime_obj = File.expand_path("backend/llvm/runtime.o", __dir__)
        unless File.exist?(runtime_obj)
          unless system("gcc -fPIC -c -o #{runtime_obj} #{runtime_src}")
            raise "Failed to compile C runtime: #{runtime_src}"
          end
        end
        
        # 4. Link everything using gcc
        unless system("gcc -no-pie -o #{@options[:output]} #{obj_file} #{runtime_obj}")
          raise "Linking failed."
        end
      end

      @options[:output]
    end
  end
end
