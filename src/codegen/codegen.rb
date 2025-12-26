require_relative "header_generator"
require_relative "string_constant_generator"
require_relative "main_function_generator"
require_relative "variable_declaration_generator"
require_relative "assignment_generator"
require_relative "increment_generator"
require_relative "print_generator"
require_relative "insertc_generator"
require_relative "input_generator"
require_relative "function_definition_generator"
require_relative "if_statement_generator"
require_relative "else_statement_generator"
require_relative "while_statement_generator"
require_relative "fn_call_generator"
require_relative "raw_generator"
require_relative "compiler"

class CodeGenerator
  def initialize(ast, path)
    @ast = ast
    @path = path
    @string_counter = 0
    @c_code = ""
    @string_constants = []
    @variables = {}
  end

  def generate
    genHeader
    genStringConst
    genGlobals
    compileRun(@ast)
    return @c_code
  end

  private

  def genHeader
    HeaderGenerator.generate(@c_code)
  end

  def genStringConst
    StringConstantGenerator.generate(@ast, @c_code, @string_constants, @string_counter, @variables)
  end

  def genGlobals
    @ast.each_with_index do |node, index|
      if node[:type] == :function_definition
        FunctionDefinitionGenerator.generate(node, @c_code, @variables)
      elsif node[:type] == :variable_declaration
        # Глобальные переменные (без отступа в начале строки)
        VariableDeclarationGenerator.generate_global(node, index, @c_code, @variables)
      end
    end
  end

  def genMainFn
    MainFunctionGenerator.generate(@ast, @c_code, @variables)
  end

  def compileRun
    Compiler.compileRun(@path, @c_code)
  end
end