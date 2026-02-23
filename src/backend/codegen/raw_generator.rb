module RawGenerator
  def self.generate(node, c_code)
    # Максимально простой вывод без магии с точками с запятой.
    # Это предотвратит разрывы в C-коде.
    c_code << "  #{node[:content].strip}\n"
  end
end
