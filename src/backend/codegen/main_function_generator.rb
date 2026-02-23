module MainFunctionGenerator
  def self.generate(ast, c_code, variables)
    c_code << "int main() {\n"
    ast.each_with_index do |node, index|
      # Skip global definitions
      next if node[:type] == :function_definition
      next if node[:type] == :variable_declaration
      generate_node(node, index, c_code, variables)
    end
    c_code << "  return 0;\n}\n"
  end

  def self.generate_node(node, index, c_code, variables)
    case node[:type]
    when :variable_declaration
      VariableDeclarationGenerator.generate(node, index, c_code, variables)
    when :assignment
      AssignmentGenerator.generate(node, index, c_code, variables)
    when :increment
      IncrementGenerator.generate(node, variables, c_code)
    when :insertC
      InsertcGenerator.generate(node, c_code)
    when :print
      PrintGenerator.generate(node, index, c_code, variables)
    when :input
      InputGenerator.generate(node, variables, c_code)
    when :if_statement
      IfStatementGenerator.generate(node, c_code, variables)
    when :else_statement
      ElseStatementGenerator.generate(node, c_code, variables)
    when :while_statement
      WhileStatementGenerator.generate(node, c_code, variables)
    when :fn_call
      FnCallGenerator.generate(node, c_code)
    when :raw
      RawGenerator.generate(node, c_code)
    end
  end
end