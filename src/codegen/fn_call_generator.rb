module FnCallGenerator
  def self.generate(node, c_code)
    c_code << "  #{node[:name]}();\n"
  end
end
