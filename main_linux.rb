require 'fileutils'
require_relative "src/lexer"
require_relative "src/parser"
require_relative "src/importer"
require_relative "src/monomorphizer"
require_relative "src/optimizer/optimizer"
require_relative "src/optimizer/turbo"
require_relative "src/analyzer/resource_auditor"
require_relative "src/codegen/native_generator"
require_relative "src/preprocessor"
require_relative "src/errors"

$hell_mode = nil
def enable_hell_mode(level = :hell)
  require_relative "src/polymorph/hell_mode"
  $hell_mode = HellMode.new(level)
  puts "HELL MODE ACTIVATED - Level: #{level}"
end

def compile_linux(input_file, arch = :x86_64, output_path = "build/output_linux")
  code = File.read(input_file)

  begin
    puts "Step 1: Preprocessing..."
    preprocessor = Preprocessor.new
    preprocessor.define("LINUX")
    preprocessor.define("__JUNO__")
    preprocessor.define("__#{arch}__")
    code = preprocessor.process(code, input_file)

    puts "Step 2: Lexing..."
    lexer = Lexer.new(code, input_file)
    tokens = lexer.tokenize

    puts "Step 3: Parsing..."
    parser = Parser.new(tokens, input_file, code)
    ast = parser.parse

    puts "Step 4: Resolving imports..."
    importer = Importer.new(File.dirname(input_file), system_path: File.join(__dir__, "stdlib"))
    ast = importer.resolve(ast, input_file)

    puts "Step 5: Monomorphizing generics..."
    monomorphizer = Monomorphizer.new(ast)
    ast = monomorphizer.monomorphize

    puts "Step 6: Resource Auditing..."
    func_signatures = {}
    ast.each do |node|
      if node[:type] == :function_definition
        func_signatures[node[:name]] = node[:return_type]
      end
    end
    auditor = ResourceAuditor.new(ast, func_signatures, code, input_file)
    auditor.audit

    puts "Step 6.5: Optimizing (Turbo)..."
    optimizer = TurboOptimizer.new(ast)
    ast = optimizer.optimize

    puts "Step 7: Native Code Generation (Linux ELF, Arch: #{arch})..."
    generator = NativeGenerator.new(ast, target_os: :linux, arch: arch, source: code, filename: input_file)
    generator.hell_mode = $hell_mode if $hell_mode
    FileUtils.mkdir_p("build")
    generator.generate(output_path)

    puts "Success! Binary generated: #{output_path}"
    $hell_mode.report if $hell_mode
  rescue JunoError => e
    e.display
    exit 1
  rescue => e
    ice = JunoInternalError.new(e.message, e, filename: input_file)
    ice.display
    exit 1
  end
end

if ARGV.empty?
  puts "Usage: ruby main_linux.rb <file.juno> [--arch aarch64|x86_64] [--hell]"
else
  arch = :x86_64
  if ARGV.include?("--arch")
    idx = ARGV.index("--arch")
    arch = ARGV[idx + 1].to_sym
    ARGV.delete_at(idx + 1)
    ARGV.delete_at(idx)
  end

  if ARGV.include?("--hell")
    enable_hell_mode(:hell)
    ARGV.delete("--hell")
  end

  output = (arch == :aarch64) ? "build/output_aarch64" : "build/output_linux"
  compile_linux(ARGV[0], arch, output)
end
