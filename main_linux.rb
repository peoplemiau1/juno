require 'fileutils'
require_relative "src/lexer"
require_relative "src/parser"
require_relative "src/importer"
require_relative "src/monomorphizer"
require_relative "src/optimizer/optimizer"
require_relative "src/codegen/native_generator"
require_relative "src/preprocessor"
require_relative "src/errors"

$hell_mode = nil
def enable_hell_mode(level = :hell)
  require_relative "src/polymorph/hell_mode"
  $hell_mode = HellMode.new(level)
  puts "HELL MODE ACTIVATED - Level: #{level}"
end

def compile_linux(input_file)
  code = File.read(input_file)
  
  begin
    puts "Step 1: Preprocessing..."
    preprocessor = Preprocessor.new
    preprocessor.define("LINUX")
    preprocessor.define("__JUNO__")
    preprocessor.define("__x86_64__")
    code = preprocessor.process(code, input_file)
    
    puts "Step 2: Lexing..."
    lexer = Lexer.new(code, input_file)
    tokens = lexer.tokenize

    puts "Step 3: Parsing..."
    parser = Parser.new(tokens, input_file, code)
    ast = parser.parse

    puts "Step 4: Resolving imports..."
    importer = Importer.new(File.dirname(input_file))
    ast = importer.resolve(ast, input_file)

    puts "Step 5: Monomorphizing generics..."
    monomorphizer = Monomorphizer.new(ast)
    ast = monomorphizer.monomorphize

    puts "Step 6: Optimizing..."
    optimizer = Optimizer.new(ast)
    ast = optimizer.optimize

    puts "Step 7: Native Code Generation (Linux ELF)..."
    generator = NativeGenerator.new(ast, :linux)
    generator.hell_mode = $hell_mode if $hell_mode
    FileUtils.mkdir_p("build")
    output_path = File.join("build", "output_linux")
    generator.generate(output_path)
    
    puts "Success! Binary generated: #{output_path}"
    $hell_mode.report if $hell_mode
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
  puts "Usage: ruby main_linux.rb <file.juno> [--hell]"
else
  if ARGV.include?("--hell")
    enable_hell_mode(:hell)
    ARGV.delete("--hell")
  end
  compile_linux(ARGV[0])
end
