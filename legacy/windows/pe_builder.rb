class PEBuilder
  def initialize(code_bytes)
    @code = code_bytes
  end

  def build
    image_base = 0x140000000
    code_size_aligned = align(@code.length, 0x200)
    idata_rva = 0x2000
    idata_offset = 0x400 + code_size_aligned
    
    dll_name = "kernel32.dll\x00"
    names = ["GetStdHandle\x00", "WriteFile\x00", "ReadFile\x00", "CreateThread\x00", "Sleep\x00", "ExitProcess\x00"]
    
    # Hint/Name entries must be word-aligned
    name_entries = names.map do |n| 
      entry = [0].pack("S") + n
      entry += "\x00" if entry.length % 2 != 0
      entry
    end
    
    num_imports = names.length
    ilt_rva = idata_rva + 40
    iat_rva = ilt_rva + (num_imports + 1) * 8
    dll_name_rva = iat_rva + (num_imports + 1) * 8
    hint_name_base_rva = dll_name_rva + dll_name.length
    hint_name_base_rva += 1 if hint_name_base_rva % 2 != 0
    
    import_dir = [ilt_rva, 0, 0, dll_name_rva, iat_rva].pack("LLLLL") + "\x00" * 20
    
    thunks = []
    current_hint_rva = hint_name_base_rva
    name_entries.each do |ne|
      thunks << current_hint_rva
      current_hint_rva += ne.length
    end
    
    ilt_data = thunks.map { |t| [t].pack("Q") }.join + [0].pack("Q")
    iat_data = ilt_data.dup
    
    # Assemble idata
    # 1. Directory (20) + Terminator (20) = 40
    # 2. ILT ( (6+1)*8 = 56 )
    # 3. IAT ( (6+1)*8 = 56 )
    # 4. DLL Name
    # 5. Padding
    # 6. Hint/Names
    
    idata_content = import_dir + ilt_data + iat_data + dll_name
    padding_size = hint_name_base_rva - (idata_rva + idata_content.length)
    idata_content += "\x00" * padding_size
    idata_content += name_entries.join
    
    idata_size_aligned = align(idata_content.length, 0x200)

    dos_header = [0x5A4D].pack("S") + "\x00" * 58 + [0x80].pack("L")
    pe_header = "PE\x00\x00" + [0x8664, 2, 0, 0, 0, 0x108, 0x0022].pack("SSLLLSS")
    
    opt_header = [0x020B].pack("S") + "\x02\x00" + [code_size_aligned, idata_size_aligned, 0, 0x1000, 0x1000].pack("LLLLL")
    opt_header += [image_base, 0x1000, 0x200, 6, 0, 0, 0, 6, 0, 0].pack("QLLSSSSSS L")
    opt_header += [align(idata_rva + idata_size_aligned, 0x1000), 0x400, 0, 3, 0].pack("LLLS S")
    opt_header += [0x100000, 0x1000, 0x100000, 0x1000, 0, 16].pack("QQQQLL")
    
    data_dirs = "\x00" * 8 + [idata_rva, idata_content.length].pack("LL") + "\x00" * (14 * 8)
    opt_header += data_dirs

    text_sec = ".text\x00\x00\x00" + [align(@code.length, 0x1000), 0x1000, code_size_aligned, 0x400].pack("LLLL") + "\x00" * 12 + [0xE0000020].pack("L")
    idata_sec = ".idata\x00\x00" + [align(idata_content.length, 0x1000), idata_rva, idata_size_aligned, idata_offset].pack("LLLL") + "\x00" * 12 + [0xC0000040].pack("L")

    header = dos_header + "\x00" * (0x80 - dos_header.length) + pe_header + opt_header + text_sec + idata_sec
    header += "\x00" * (0x400 - header.length)
    
    header + @code.pack("C*").ljust(code_size_aligned, "\x00") + idata_content.ljust(idata_size_aligned, "\x00")
  end

  private
  def align(v, a); (v + a - 1) & ~(a - 1); end
end
