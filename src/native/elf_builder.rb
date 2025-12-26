class ELFBuilder
  def initialize(code_bytes)
    @code = code_bytes
  end

  def build
    # ELF64 Header (64 bytes)
    header = "\x7fELF".b
    header << [2, 1, 1, 0].pack("C4") # 64-bit, LE, Vers 1, System V
    header << "\x00".b * 8
    header << [2, 0x3e].pack("SS")    # ET_EXEC, x86-64
    header << [1].pack("L")           # Version
    header << [0x401000].pack("Q")    # ENTRY POINT (aligned to 0x1000)
    header << [64].pack("Q")          # Program Header Start
    header << [0].pack("Q")           # Section Header Start
    header << [0].pack("L")           # Flags
    header << [64, 56, 1].pack("SSS") # HdrSize, PhEntSize, PhNum
    header << [64, 0, 0].pack("SSS")  # ShEntSize, ShNum, ShStrIdx

    # Program Header (56 bytes)
    ph = [1, 7].pack("LL")            # PT_LOAD, PF_R | PF_W | PF_X
    ph << [0].pack("Q")               # Offset
    ph << [0x400000].pack("Q")        # VAddr (Base)
    ph << [0x400000].pack("Q")        # PAddr
    
    # КРИТИЧЕСКИЙ ФИКС: Размер должен включать заголовок (0x1000) и ВЕСЬ код+данные
    total_size = 0x1000 + @code.length
    ph << [total_size].pack("Q")      # FileSz
    ph << [total_size].pack("Q")      # MemSz
    ph << [0x1000].pack("Q")          # Align

    # Padding to 0x1000
    padding = "\x00".b * (0x1000 - (header.length + ph.length))

    begin
      @code.pack("C*")
    rescue TypeError => e
      @code.each_with_index do |b, i|
        unless b.is_a?(Integer)
          puts "Error: Non-integer at index #{i}: #{b.inspect} (Type: #{b.class})"
        end
      end
      raise e
    end
    header + ph + padding + @code.pack("C*")
  end
end
