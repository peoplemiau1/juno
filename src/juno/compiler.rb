require_relative "frontend/lexer"
require_relative "frontend/parser"
require_relative "middle/importer"
require_relative "middle/monomorphizer"
require_relative "middle/semantic"
require_relative "middle/analyzer/resource_auditor"
require_relative "backend/codegen/native_generator"
require_relative "backend/llvm/generator"
require_relative "frontend/preprocessor"
require_relative "middle/analyzer/borrow_checker"
require_relative "optimizer/turbo"
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

      borrow_checker = BorrowChecker.new(ast, code, input_file)
      borrow_checker.check

      auditor = ResourceAuditor.new(ast, analyzer.function_signatures, code, input_file, borrow_checker.fn_effects)
      auditor.audit

      opt_level = @options[:opt_level] || 2

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
        @asm_log = [llvm_ir]
        ir_file = @options[:output] + ".ll"
        obj_file = @options[:output] + ".o"
        File.write(ir_file, llvm_ir)
        
        if @options[:os] == :macos
          triples = {
            x86_64: "x86_64-apple-macos",
            aarch64: "arm64-apple-macos",
            arm: "arm64-apple-macos"
          }
        else
          triples = {
            x86_64: "x86_64-pc-linux-gnu",
            aarch64: "aarch64-unknown-linux-gnu",
            arm: "arm-unknown-linux-gnueabi",
            riscv64: "riscv64-unknown-linux-gnu",
            riscv32: "riscv32-unknown-linux-gnu"
          }
        end
        target_triple = triples[@options[:arch]] || (@options[:os] == :macos ? "x86_64-apple-macos" : "x86_64-pc-linux-gnu")

        llc_cmd = `which llc-19 llc-18 llc-17 llc`.split("\n").first&.strip
        raise "llc tool not found. Please install llvm." unless llc_cmd

        opt_cmd = `which opt-19 opt-18 opt-17 opt`.split("\n").first&.strip
        
        opt_flag = "-O#{opt_level}"

        target_ir_file = ir_file
        if opt_cmd && opt_level > 0
          optimized_ir_file = @options[:output] + ".opt.ll"
          opt_pass_flag = "-passes='default<O#{opt_level}>'"
          
          if system("#{opt_cmd} #{opt_pass_flag} -S -o #{optimized_ir_file} #{ir_file}")
            target_ir_file = optimized_ir_file
          else
            if system("#{opt_cmd} #{opt_flag} -S -o #{optimized_ir_file} #{ir_file}")
              target_ir_file = optimized_ir_file
            end
          end
        end

        unless system("#{llc_cmd} #{opt_flag} -mtriple=#{target_triple} -relocation-model=pic -filetype=obj -o #{obj_file} #{target_ir_file}")
          raise "llc failed to compile IR. Check #{target_ir_file} for errors."
        end
        
        if @options[:target] == :obj
          return obj_file
        elsif @options[:target] == :flat
          objcopy_cmd = "llvm-objcopy-19"
          unless system("#{objcopy_cmd} -O binary #{obj_file} #{@options[:output]}")
             unless system("objcopy -O binary #{obj_file} #{@options[:output]}")
               raise "Failed to generate flat binary using objcopy."
             end
          end
          return @options[:output]
        end

        runtime_src = File.expand_path("backend/llvm/runtime.c", __dir__)
        runtime_obj = File.expand_path("backend/llvm/runtime.o", __dir__)
        unless File.exist?(runtime_obj)
          unless system("gcc -fPIC -c -o #{runtime_obj} #{runtime_src}")
            raise "Failed to compile C runtime: #{runtime_src}"
          end
        end
        
        link_cmd = if @options[:os] == :macos
                         "gcc -o #{@options[:output]} #{obj_file} #{runtime_obj} /bedrock/strata/arch/lib/libraylib.so -Wl,-rpath,/bedrock/strata/arch/lib"
                       else
                         "gcc -no-pie -o #{@options[:output]} #{obj_file} #{runtime_obj} /bedrock/strata/arch/lib/libraylib.so -Wl,-rpath,/bedrock/strata/arch/lib"
                       end

        unless system(link_cmd)
          raise "Linking failed."
        end
      end

      @options[:output]
    end
  end
end
