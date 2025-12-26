module ElseStatementGenerator
  def self.generate(node, c_code, variables)
    c_code << "  else {\n"
    node[:body].each do |sub_node|
      MainFunctionGenerator.generate_node(sub_node, 0, c_code, variables)
    end
    c_code << "  }\n"
  end
end
