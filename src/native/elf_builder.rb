class ELFBuilder
  def initialize(bytes, arch = :x86_64, code_len = 0, data_len = 0, bss_len = 0)
    @bytes = bytes
    @arch = arch
    @code_len = code_len
    @data_len = data_len
    @bss_len = bss_len
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

    # Sections setup
    shstrtab = "\x00.shstrtab\x00.text\x00.data\x00.bss\x00".b
    sh_num = 5
    e_shstrndx = 1
    total_file_size = 0x1000 + @bytes.length
    sh_offset = (total_file_size + 15) & ~15

    ph_num = (@data_len > 0 || @bss_len > 0) ? 2 : 1

    header << [64].pack("Q")          # Program Header Start
    header << [sh_offset].pack("Q")   # Section Header Start
    header << [0].pack("L")           # Flags
    header << [64, 56, ph_num].pack("SSS") # HdrSize, PhEntSize, PhNum
    header << [64, sh_num, e_shstrndx].pack("SSS") # ShEntSize, ShNum, ShStrIdx

    base = (@arch == :aarch64) ? 0 : 0x400000

    # PH 1: .text (R E)
    ph1 = [1, 5].pack("LL")            # PT_LOAD, PF_R | PF_X
    ph1 << [0].pack("Q")               # Offset
    ph1 << [base].pack("Q")            # VAddr
    ph1 << [base].pack("Q")            # PAddr
    ph1 << [0x1000 + @code_len].pack("Q") # FileSz
    ph1 << [0x1000 + @code_len].pack("Q") # MemSz
    ph1 << [0x1000].pack("Q")          # Align

    ph = ph1

    # PH 2: .data + .bss (R W)
    if @data_len > 0 || @bss_len > 0
      ph2 = [1, 6].pack("LL")            # PT_LOAD, PF_R | PF_W
      ph2 << [0x1000 + @code_len].pack("Q") # Offset
      ph2 << [base + 0x1000 + @code_len].pack("Q") # VAddr
      ph2 << [base + 0x1000 + @code_len].pack("Q") # PAddr
      ph2 << [@data_len].pack("Q")       # FileSz
      ph2 << [@data_len + @bss_len].pack("Q") # MemSz (includes BSS)
      ph2 << [0x1000].pack("Q")          # Align
      ph += ph2
    end

    # Padding to 0x1000
    padding = "\x00".b * (0x1000 - (64 + 56 * ph_num))

    # Section Table
    # 0: NULL
    s0 = "\x00".b * 64
    # 1: .shstrtab
    s1 = [1, 3, 0, 0].pack("LLQQ")
    s1 << [sh_offset + 64 * sh_num].pack("Q")
    s1 << [shstrtab.length].pack("Q")
    s1 << [0, 0, 1, 0].pack("LLQQ")
    # 2: .text
    s2 = [11, 1, 6, base + 0x1000].pack("LLQQ") # name_off=".text", PROGBITS, ALLOC|EXEC
    s2 << [0x1000].pack("Q")
    s2 << [@code_len].pack("Q")
    s2 << [0, 0, 16, 0].pack("LLQQ")
    # 3: .data
    s3 = [17, 1, 3, base + 0x1000 + @code_len].pack("LLQQ") # name_off=".data", PROGBITS, ALLOC|WRITE
    s3 << [0x1000 + @code_len].pack("Q")
    s3 << [@data_len].pack("Q")
    s3 << [0, 0, 16, 0].pack("LLQQ")
    # 4: .bss
    s4 = [23, 8, 3, base + 0x1000 + @code_len + @data_len].pack("LLQQ") # name_off=".bss", NOBITS, ALLOC|WRITE
    s4 << [0x1000 + @code_len + @data_len].pack("Q")
    s4 << [@bss_len].pack("Q")
    s4 << [0, 0, 16, 0].pack("LLQQ")

    result = header + ph + padding + @bytes.pack("C*")
    # Padding before section table if needed
    result += "\x00".b * (sh_offset - result.length)
    result += s0 + s1 + s2 + s3 + s4 + shstrtab
    result
  end
end
