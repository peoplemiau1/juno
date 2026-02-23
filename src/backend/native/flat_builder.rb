class FlatBuilder
  def initialize(code_bytes)
    @code = code_bytes
  end

  def build
    @code.pack("C*")
  end
end
