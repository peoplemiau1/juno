class Linker
  attr_reader :strings, :functions, :data_pool, :bss_pool

  def initialize(base_rva, arch = :x86_64)
    @base_rva = base_rva
    @arch = arch
    @fn_patches = []
    @data_patches = []
    @import_patches = []
    @functions = {}
    @imports = {}
    @data_pool = []
    @bss_pool = []
    @strings = {}
    @string_counter = 0
  end

  def declare_function(name)
    @functions[name] ||= nil
  end

  def register_function(name, offset_in_code)
    @functions[name] = @base_rva + offset_in_code
  end

  def register_import(name, rva)
    @imports[name] = rva
  end

  def add_data(id, data)
    @data_pool << { id: id, data: data }
  end

  def add_bss(id, size)
    @bss_pool << { id: id, size: size }
  end

  def add_string(content)
    existing = @strings.values.find { |s| s[:content] == content }
    return existing[:id] if existing
    label = "str_#{@string_counter}"
    @string_counter += 1
    data_with_null = content + "\0"
    @strings[label] = { content: content, id: label }
    add_data(label, data_with_null)
    label
  end

  def add_fn_patch(pos, name, type = :rel32)
    @fn_patches << { pos: pos, name: name, type: type }
  end

  def add_data_patch(pos, id, type = :rel32)
    @data_patches << { pos: pos, id: id, type: type }
  end

  def add_import_patch(pos, name, type = :rel32)
    @import_patches << { pos: pos, name: name, type: type }
  end

  def apply_mapping(mapping)
    return if mapping.empty?

    @fn_patches.each { |p| p[:pos] = mapping[p[:pos]] || p[:pos] }
    @data_patches.each { |p| p[:pos] = mapping[p[:pos]] || p[:pos] }
    @import_patches.each { |p| p[:pos] = mapping[p[:pos]] || p[:pos] }

    @functions.each do |name, rva|
      offset = rva - @base_rva
      if mapping[offset]
        @functions[name] = @base_rva + mapping[offset]
      end
    end
  end

  def finalize(code_bytes)
    data_bytes = []
    data_offset = code_bytes.length
    # Align data section to 4096 bytes (page boundary) for proper ELF segment permissions
    padding = (4096 - (data_offset % 4096)) % 4096
    code_bytes += [0] * padding
    data_offset += padding

    @data_pool.each do |item|
      item[:rva] = @base_rva + data_offset + data_bytes.length
      data_bytes += item[:data].bytes
    end

    bss_len = 0
    @bss_pool.each do |item|
      item[:rva] = @base_rva + data_offset + data_bytes.length + bss_len
      bss_len += item[:size]
    end

    full_binary = code_bytes + data_bytes

    @fn_patches.each { |p| patch_value(full_binary, p, @functions[p[:name]]) }
    @data_patches.each do |p|
       target = @data_pool.find { |d| d[:id] == p[:id] }&.[](:rva) ||
                @bss_pool.find { |b| b[:id] == p[:id] }&.[](:rva) ||
                @functions[p[:id]]
       patch_value(full_binary, p, target)
    end
    @import_patches.each { |p| patch_value(full_binary, p, @imports[p[:name]]) }

    { code: code_bytes, data: data_bytes, bss_len: bss_len, combined: full_binary }
  end

  def patch_value(code, patch, target_rva)
    unless target_rva
      $stderr.puts "Error: Target not found for patch at #{patch[:pos]} (type: #{patch[:type]}, id: #{patch[:id] || patch[:name]})"
      exit 1
    end
    pos = patch[:pos]
    instr_rva = @base_rva + pos
    case patch[:type]
    when :rel32
      offset = target_rva - (instr_rva + 4)
      code[pos..pos+3] = [offset].pack("l<").bytes
    when :aarch64_bl
      offset = (target_rva - instr_rva) / 4
      instr = [code[pos..pos+3].pack("C*").unpack1("L<")].first
      instr = (instr & 0xFC000000) | (offset & 0x03FFFFFF)
      code[pos..pos+3] = [instr].pack("L<").bytes
    when :aarch64_adr
      offset = target_rva - instr_rva
      instr = [code[pos..pos+3].pack("C*").unpack1("L<")].first
      immlo = offset & 0x3
      immhi = ((offset >> 2) & 0x7FFFF)
      instr = (instr & 0x9F00001F) | (immlo << 29) | (immhi << 5)
      code[pos..pos+3] = [instr].pack("L<").bytes
    when :aarch64_movz
      imm = target_rva & 0xFFFF
      instr = [code[pos..pos+3].pack("C*").unpack1("L<")].first
      instr = (instr & 0xFFE0001F) | (imm << 5)
      code[pos..pos+3] = [instr].pack("L<").bytes
    end
  end
end
