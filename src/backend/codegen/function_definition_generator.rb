module FunctionDefinitionGenerator
  def self.generate(node, c_code, variables)
    c_code << "void #{node[:name]}() {\n"
    node[:body].each do |sub_node|
      # We need a way to generate code for nodes inside the body.
      # Let's use a helper method or just inline some logic.
      # For now, let's keep it simple.
      MainFunctionGenerator.generate_node(sub_node, 0, c_code, variables)
    end
    c_code << "}\n\n"
  end
end
