# src/importer.rb - Module import system for Juno
require_relative "../frontend/lexer"
require_relative "../frontend/parser"
require_relative "../errors"

class Importer
  def initialize(base_path = ".", system_path: nil)
    @base_path = base_path
    @system_path = system_path
    @imported = {}  # path -> ast (cache to avoid circular imports)
    @import_stack = []  # for detecting circular imports
  end

  # Process AST and resolve all imports
  # Returns merged AST with all imported definitions
  def resolve(ast, current_file = nil)
    result = []

    ast.each do |node|
      if node[:type] == :import || node[:type] == :use_statement
        if node[:type] == :use_statement || node[:system]
          begin
            imported_ast = process_import(node[:path], current_file, true)
          rescue JunoImportError
            imported_ast = process_import(node[:path], current_file, false)
          end
        else
          imported_ast = process_import(node[:path], current_file, false)
        end
        result.concat(imported_ast)
      else
        result << node
      end
    end

    result
  end

  private

  def process_import(path, current_file, is_system = false)
    # Resolve path
    if is_system && @system_path
      full_path = File.join(@system_path, path)
    elsif current_file
      base_dir = File.dirname(current_file)
      full_path = File.join(base_dir, path)
    else
      full_path = File.join(@base_path, path)
    end

    # Normalize path
    full_path = File.expand_path(full_path)

    # Support .juno and .wt extensions
    unless File.exist?(full_path)
      if File.exist?(full_path + ".juno")
        full_path += ".juno"
      elsif File.exist?(full_path + ".wt")
        full_path += ".wt"
      end
    end

    # Check for circular imports
    if @import_stack.include?(full_path)
      cycle = @import_stack.drop_while { |p| p != full_path } + [full_path]
      raise JunoImportError.new(
        "Circular import detected: #{cycle.join(' -> ')}",
        filename: current_file || "unknown"
      )
    end

    # Return cached if already imported
    return [] if @imported.key?(full_path)

    # Check file exists
    unless File.exist?(full_path)
      raise JunoImportError.new(
        "Cannot find module '#{path}'",
        filename: current_file || "unknown"
      )
    end

    # Parse imported file
    @import_stack.push(full_path)
    begin
      source = File.read(full_path)
      lexer = Lexer.new(source, full_path)
      tokens = lexer.tokenize
      parser = Parser.new(tokens, full_path, source)
      imported_ast = parser.parse

      # Recursively resolve imports in the imported file
      resolved_ast = resolve(imported_ast, full_path)

      # Cache and return only definitions (structs, functions)
      # Skip main function from imported modules
      definitions = resolved_ast.select do |node|
        case node[:type]
        when :struct_definition, :enum_definition, :type_alias, :extern_definition, :union_definition
          true
        when :function_definition
          node[:name] != "main"  # Don't import main()
        when :assignment
          node[:let] == true     # Import top-level let globals
        else
          false
        end
      end

      @imported[full_path] = definitions
      definitions
    ensure
      @import_stack.pop
    end
  end
end

# Custom error for import issues
class JunoImportError < JunoError
  def initialize(message, filename: "unknown", line_num: nil)
    super("E0002", message, filename: filename, line_num: line_num)
  end
end
