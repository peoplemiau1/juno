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

    # Sections setup for Android compatibility (requires non-zero shstrndx if shnum > 0)
    shstrtab = "\x00.shstrtab\x00".b
    sh_num = 2
    e_shstrndx = 1
    total_code_size = 0x1000 + @code.length
    sh_offset = total_code_size

    header << [64].pack("Q")          # Program Header Start
    header << [sh_offset].pack("Q")   # Section Header Start
    header << [0].pack("L")           # Flags
    header << [64, 56, 1].pack("SSS") # HdrSize, PhEntSize, PhNum
    header << [64, sh_num, e_shstrndx].pack("SSS") # ShEntSize, ShNum, ShStrIdx

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
    padding = "\x00".b * (0x1000 - (64 + 56))

    # Section Table
    # Section 0: NULL
    s0 = "\x00".b * 64
    # Section 1: .shstrtab
    s1 = [1, 3, 0, 0].pack("LLQQ") # name_off=1, type=3(STRTAB), flags=0, addr=0
    s1 << [sh_offset + 128].pack("Q") # offset (immediately after table)
    s1 << [shstrtab.length].pack("Q") # size
    s1 << [0, 0, 1, 0].pack("LLQQ") # link=0, info=0, align=1, entsize=0

    result = header + ph + padding + @code.pack("C*")
    result += s0 + s1 + shstrtab
    result
  end
end
