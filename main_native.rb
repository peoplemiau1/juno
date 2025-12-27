require 'fileutils'
require_relative "src/lexer"
require_relative "src/parser"
require_relative "src/importer"
require_relative "src/optimizer/optimizer"
require_relative "src/codegen/native_generator"
require_relative "src/preprocessor"
require_relative "src/errors"

def compile_juno_native(source_path)
  source = File.read(source_path)
  
  begin
    puts "Step 1: Preprocessing..."
    preprocessor = Preprocessor.new
    preprocessor.define("WINDOWS")
    preprocessor.define("__JUNO__")
    preprocessor.define("__x86_64__")
    source = preprocessor.process(source, source_path)

    puts "Step 2: Lexing..."
    lexer = Lexer.new(source, source_path)
    tokens = lexer.tokenize

    puts "Step 3: Parsing..."
    parser = Parser.new(tokens, source_path, source)
    ast = parser.parse

    puts "Step 4: Resolving imports..."
    importer = Importer.new(File.dirname(source_path))
    ast = importer.resolve(ast, source_path)

    puts "Step 5: Optimizing..."
    optimizer = Optimizer.new(ast)
    ast = optimizer.optimize

    puts "Step 6: Native Code Generation..."
    generator = NativeGenerator.new(ast, :windows)
    FileUtils.mkdir_p("build")
    output_exe = File.join("build", "output.exe")
    generator.generate(output_exe)

    # Duplicate to root for easy launching
    FileUtils.cp(output_exe, "output.exe")

    puts "Success! Binary generated: #{output_exe}"
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

if __FILE__ == $0
  source_file = ARGV[0] || "test_struct.juno"
  compile_juno_native(source_file)
end
