require 'fileutils'
require_relative "src/lexer"
require_relative "src/parser"
require_relative "src/importer"
require_relative "src/optimizer/optimizer"
require_relative "src/codegen/native_generator"
require_relative "src/errors"

def compile_flat(input_file)
  code = File.read(input_file)
  begin
    puts "Step 1: Lexing..."
    lexer = Lexer.new(code, input_file)
    tokens = lexer.tokenize

    puts "Step 2: Parsing..."
    parser = Parser.new(tokens, input_file, code)
    ast = parser.parse

    puts "Step 3: Resolving imports..."
    importer = Importer.new(File.dirname(input_file))
    ast = importer.resolve(ast, input_file)

    puts "Step 4: Optimizing..."
    optimizer = Optimizer.new(ast)
    ast = optimizer.optimize

    puts "Step 5: Native Code Generation (Flat Binary)..."
    generator = NativeGenerator.new(ast, :flat)
    FileUtils.mkdir_p("build")
    output_path = File.join("build", "output_flat.bin")
    generator.generate(output_path)

    puts "Success! Flat binary generated: #{output_path}"
  rescue JunoError => e
    e.display
    exit 1
  rescue => e
    puts "\e[31mInternal Compiler Error:\e[0m"
    puts e.message
    puts e.backtrace[0..5].join("\n")
    exit 1
  end
end

if ARGV.empty?
  puts "Usage: ruby main_flat.rb <file.juno>"
else
  compile_flat(ARGV[0])
end
