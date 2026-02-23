module InputGenerator
  def self.generate(node, variables, c_code)
    if variables[node[:name]]
      type = variables[node[:name]][:type]
      if type == 'int'
        c_code << "  scanf(\"%d\", &#{node[:name]});\n"
      elsif type == 'char*' || type == 'const char*'
        c_code << "  scanf(\"%s\", #{node[:name]});\n"
      end
    else
      # If unknown, assume int for now or error
       c_code << "  scanf(\"%d\", &#{node[:name]});\n"
    end
  end
end
