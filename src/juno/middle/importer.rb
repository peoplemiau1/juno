require_relative "../frontend/lexer"
require_relative "../frontend/parser"
require_relative "../errors"

class Importer
  def initialize(base_path = ".", system_path: nil)
    @base_path = base_path
    @system_path = system_path
    @imported = {}
    @import_stack = []
  end

  def resolve(ast, current_file = nil)
    result = []

    ast.each do |node|
      if node[:type] == :import || node[:type] == :use_statement
        begin
          imported_ast = process_import(node[:path], current_file, node[:system] || node[:type] == :use_statement)
        rescue JunoImportError => e
          if !node[:system] && node[:type] != :use_statement
            begin
              imported_ast = process_import(node[:path], current_file, true)
            rescue JunoImportError
              raise e
            end
          else
            raise e
          end
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
    if is_system && @system_path
      check_path = (path == "std/std") ? "std" : path
      full_path = File.join(@system_path, check_path)
    elsif current_file
      base_dir = File.dirname(current_file)
      full_path = File.join(base_dir, path)
    else
      full_path = File.join(@base_path, path)
    end

    full_path = File.expand_path(full_path)

    unless File.file?(full_path)
      if File.exist?(full_path + ".juno")
        full_path += ".juno"
      elsif File.exist?(full_path + ".wt")
        full_path += ".wt"
      end
    end

    if @import_stack.include?(full_path)
      cycle = @import_stack.drop_while { |p| p != full_path } + [full_path]
      raise JunoImportError.new(
        "Circular import detected: #{cycle.join(' -> ')}",
        filename: current_file || "unknown"
      )
    end

    return [] if @imported.key?(full_path)

    unless File.exist?(full_path)
      raise JunoImportError.new(
        "Cannot find module '#{path}'",
        filename: current_file || "unknown"
      )
    end

    @import_stack.push(full_path)
    begin
      source = File.read(full_path)
      lexer = Lexer.new(source, full_path)
      tokens = lexer.tokenize
      parser = Parser.new(tokens, full_path, source)
      imported_ast = parser.parse

      resolved_ast = resolve(imported_ast, full_path)

      definitions = resolved_ast.select do |node|
        case node[:type]
        when :struct_definition, :enum_definition, :type_alias, :extern_definition, :union_definition
          true
        when :function_definition
          node[:name] != "main"
        when :assignment
          node[:let] == true
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

class JunoImportError < JunoError
  def initialize(message, filename: "unknown", line_num: nil)
    super("E0002", message, filename: filename, line_num: line_num)
  end
end
