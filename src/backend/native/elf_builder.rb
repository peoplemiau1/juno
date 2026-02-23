class ELFBuilder
  def initialize(bytes, arch = :x86_64, code_len = 0, data_len = 0, bss_len = 0, external_symbols: [], got_slots: {}, label_rvas: {})
    @bytes = bytes
    @arch = arch
    @code_len = code_len
    @data_len = data_len
    @bss_len = bss_len
    @external_symbols = external_symbols
    @got_slots = got_slots
    @label_rvas = label_rvas
  end

  def align_val(val, a); (val + a - 1) & ~(a - 1); end

  def build
    has_dyn = @external_symbols.any?
    base = (@arch == :aarch64) ? 0 : 0x400000

    interp_data = ""; dynstr = ""; dynsym = ""; rela_plt = ""; hash = ""; dynamic = ""
    interp_rva = 0; metadata_rel_off = 0; dynamic_rva = 0; dynstr_rva = 0; dyn_len = 0

    if has_dyn
      interp_data = (@arch == :aarch64) ? "/lib/ld-linux-aarch64.so.1\x00" : "/lib64/ld-linux-x86-64.so.2\x00"
      dynstr = "\x00"
      lib_names = @external_symbols.map { |s| s[:lib] }.uniq
      lib_offsets = {}
      lib_names.each { |l| lib_offsets[l] = dynstr.length; dynstr += l + "\x00" }
      sym_offsets = {}
      @external_symbols.each { |s| sym_offsets[s[:name]] = dynstr.length; dynstr += s[:name] + "\x00" }
      dynsym = "\x00" * 24
      @external_symbols.each do |s|
        dynsym += [sym_offsets[s[:name]], 0x12, 0, 0, 0, 0].pack("LCCSQQ")
      end
      rel_type = (@arch == :aarch64) ? 1025 : 7 # JUMP_SLOT for x86
      @external_symbols.each_with_index do |s, i|
        got_rva = @label_rvas[@got_slots[s[:name]]]
        rela_plt += [got_rva, (i + 1) << 32 | rel_type, 0].pack("QQq")
      end
      n_syms = @external_symbols.length + 1
      hash = [1, n_syms, 1].pack("LLL")
      chain = Array.new(n_syms, 0); (1...n_syms-1).each { |i| chain[i] = i + 1 }
      hash += chain.pack("L*")

      interp_rva = base + 0x200

      metadata_rel_off = align_val(@data_len, 16)
      metadata_rva = base + 0x1000 + @code_len + metadata_rel_off

      dynstr_rva = metadata_rva
      dynsym_rva = align_val(dynstr_rva + dynstr.length, 8)
      hash_rva = align_val(dynsym_rva + dynsym.length, 8)
      rela_plt_rva = align_val(hash_rva + hash.length, 8)
      dynamic_rva = align_val(rela_plt_rva + rela_plt.length, 8)

      dyn_tags = []
      lib_names.each { |l| dyn_tags << [1, lib_offsets[l]] }
      dyn_tags += [
        [5, dynstr_rva], [10, dynstr.length],
        [6, dynsym_rva], [11, 24],
        [4, hash_rva],
        [7, rela_plt_rva], [8, rela_plt.length], [9, 24], # RELA
        [0, 0]
      ]
      dynamic = dyn_tags.map{|t| t.pack("Qq")}.join
      dyn_len = dynamic.length
    end

    machine = (@arch == :aarch64) ? 0xb7 : 0x3e
    type = (@arch == :aarch64) ? 3 : 2 # ET_DYN for ARM, ET_EXEC for x86
    header = "\x7fELF".b << [2, 1, 1, 0].pack("C4") << "\x00" * 8
    header << [type, machine].pack("SS") << [1].pack("L")
    header << [base + 0x1000].pack("Q")

    ph_num = 2
    ph_num += 2 if has_dyn
    header << [64].pack("Q") << [0].pack("Q") << [0].pack("L")
    header << [64, 56, ph_num].pack("SSS") << [0, 0, 0].pack("SSS")

    ph = ""
    if has_dyn
      ph += [3, 4, 0x200, interp_rva, interp_rva, interp_data.length, interp_data.length, 1].pack("LLQQQQQQ")
    end

    code_segment_filesz = 0x1000 + @code_len
    ph += [1, 5, 0, base, base, code_segment_filesz, code_segment_filesz, 0x1000].pack("LLQQQQQQ")

    if has_dyn
      ph += [2, 6, 0x1000 + @code_len + metadata_rel_off + (dynamic_rva - dynstr_rva), dynamic_rva, dynamic_rva, dyn_len, dyn_len, 8].pack("LLQQQQQQ")
    end

    data_filesz = @data_len + (has_dyn ? (metadata_rel_off + (dynamic_rva - dynstr_rva) + dyn_len) : 0)
    data_memsz = data_filesz + @bss_len
    ph += [1, 6, 0x1000 + @code_len, base + 0x1000 + @code_len, base + 0x1000 + @code_len, data_filesz, data_memsz, 0x1000].pack("LLQQQQQQ")

    result = (header + ph).ljust(0x200, "\x00")
    result += interp_data.ljust(32, "\x00") if has_dyn
    result = result.ljust(0x1000, "\x00")
    result += @bytes[0...@code_len].pack("C*")
    data_part = @bytes[@code_len..-1].pack("C*")
    if has_dyn
      m2 = dynstr.ljust(align_val(dynstr.length, 8), "\x00")
      m2 += dynsym.ljust(align_val(dynsym.length, 8), "\x00")
      m2 += hash.ljust(align_val(hash.length, 8), "\x00")
      m2 += rela_plt.ljust(align_val(rela_plt.length, 8), "\x00")
      m2 += dynamic
      data_part = data_part.ljust(metadata_rel_off, "\x00")
      data_part += m2
    end
    result += data_part

    # Add dummy section headers for better compatibility
    sh_off = result.length
    sh = "\x00" * 64 # NULL section
    sh += [1, 1, 6, base + 0x1000, 0x1000, @code_len, 0, 0, 16, 0].pack("LLQQQQLLQQ") # .text
    sh += [7, 1, 3, base + 0x1000 + @code_len, 0x1000 + @code_len, data_filesz, 0, 0, 16, 0].pack("LLQQQQLLQQ") # .data

    # Update ELF header with SH info
    result[40..47] = [sh_off].pack("Q")  # e_shoff
    result[58..59] = [64].pack("S")      # e_shentsize
    result[60..61] = [3].pack("S")       # e_shnum

    result + sh
  end
end
