class ELFBuilder
  def initialize(code_bytes, arch = :x86_64)
    @code = code_bytes
    @arch = arch
  end

  def build
    # Machine types: x86-64 is 0x3e, AArch64 is 0xb7
    machine = (@arch == :aarch64) ? 0xb7 : 0x3e

    # ELF64 Header (64 bytes)
    header = "\x7fELF".b
    header << [2, 1, 1, 0].pack("C4") # 64-bit, LE, Vers 1, System V
    header << "\x00".b * 8
    # ET_DYN (3) is used for PIE on modern Linux/Android
    type = (@arch == :aarch64) ? 3 : 2
    header << [type, machine].pack("SS") # Type, Machine
    header << [1].pack("L")           # Version
    entry = (@arch == :aarch64) ? 0x1000 : 0x401000
    header << [entry].pack("Q")       # ENTRY POINT
    header << [64].pack("Q")          # Program Header Start
    header << [0].pack("Q")           # Section Header Start
    header << [0].pack("L")           # Flags
    header << [64, 56, 1].pack("SSS") # HdrSize, PhEntSize, PhNum
    header << [64, 0, 0].pack("SSS")  # ShEntSize, ShNum, ShStrIdx

    # Program Header (56 bytes)
    ph = [1, 7].pack("LL")            # PT_LOAD, PF_R | PF_W | PF_X
    ph << [0].pack("Q")               # Offset
    base = (@arch == :aarch64) ? 0 : 0x400000
    ph << [base].pack("Q")            # VAddr (Base)
    ph << [base].pack("Q")            # PAddr

    # Size must include header (0x1000) and ALL code+data
    total_size = 0x1000 + @code.length
    ph << [total_size].pack("Q")      # FileSz
    ph << [total_size].pack("Q")      # MemSz
    ph << [0x1000].pack("Q")          # Align

    # Padding to 0x1000
    padding = "\x00".b * (0x1000 - (header.length + ph.length))

    header + ph + padding + @code.pack("C*")
  end
end
