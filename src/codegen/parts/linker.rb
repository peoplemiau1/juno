class Linker
  attr_reader :strings

  def initialize(base_rva, arch = :x86_64)
    @base_rva = base_rva
    @arch = arch
    @fn_patches = []
    @data_patches = []
    @import_patches = []
    @functions = {}
    @imports = {}
    @data_pool = []
    @strings = {}
    @string_counter = 0
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

  def finalize(code_bytes)
    @data_pool.each do |item|
      item[:rva] = @base_rva + code_bytes.length
      code_bytes += item[:data].bytes
    end
    @fn_patches.each { |p| patch_value(code_bytes, p, @functions[p[:name]]) }
    @data_patches.each do |p|
       target = @data_pool.find { |d| d[:id] == p[:id] }&.[](:rva) || @functions[p[:id]]
       patch_value(code_bytes, p, target)
    end
    @import_patches.each { |p| patch_value(code_bytes, p, @imports[p[:name]]) }
    code_bytes
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
