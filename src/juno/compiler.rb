require_relative "frontend/lexer"
require_relative "frontend/parser"
require_relative "middle/importer"
require_relative "middle/monomorphizer"
require_relative "middle/semantic"
require_relative "optimizer/turbo"
require_relative "middle/analyzer/resource_auditor"
require_relative "backend/codegen/native_generator"
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
      generator = NativeGenerator.new(ast, 
        target_os: @options[:os], 
        arch: @options[:arch], 
        source: code, 
        filename: input_file
      )
      generator.generate(@options[:output])

      @options[:output]
    end
  end
end
