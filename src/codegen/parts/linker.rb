class Linker
  attr_reader :strings
  
  def initialize(base_rva)
    @base_rva = base_rva
    @fn_patches = []   # { pos: int, name: string }
    @data_patches = [] # { pos: int, id: string }
    @import_patches = [] # { pos: int, name: string }
    @functions = {}    # name -> rva
    @imports = {}      # name -> rva
    @data_pool = []    # { id: string, rva: int, data: bytes }
    @strings = {}      # label -> { content: string, id: string }
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

  # Add string literal to data section with null terminator
  # Returns the label/id for the string
  def add_string(content)
    # Check if string already exists
    existing = @strings.values.find { |s| s[:content] == content }
    return existing[:id] if existing
    
    label = "str_#{@string_counter}"
    @string_counter += 1
    
    # Add null terminator
    data_with_null = content + "\0"
    @strings[label] = { content: content, id: label }
    add_data(label, data_with_null)
    
    label
  end

  def add_fn_patch(pos, name)
    @fn_patches << { pos: pos, name: name }
  end

  def add_data_patch(pos, id)
    @data_patches << { pos: pos, id: id }
  end

  def add_import_patch(pos, name)
    @import_patches << { pos: pos, name: name }
  end

  def finalize(code_bytes)
    # 1. Append data to code
    @data_pool.each do |item|
      item[:rva] = @base_rva + code_bytes.length
      code_bytes += item[:data].bytes
    end

    # 2. Patch functions
    @fn_patches.each do |patch|
      target_addr = @functions[patch[:name]]
      unless target_addr
        puts "Error: Function '#{patch[:name]}' not found!"
        exit 1
      end
      # Offset = Target - (InstrAddr + 4)
      # InstrAddr = Base + PatchPos
      instr_end_rva = @base_rva + patch[:pos] + 4
      offset = target_addr - instr_end_rva
      code_bytes[patch[:pos]..patch[:pos]+3] = [offset].pack("l<").bytes
    end

    # 3. Patch data
    @data_patches.each do |patch|
      item = @data_pool.find { |d| d[:id] == patch[:id] }
      unless item
        puts "Error: Data '#{patch[:id]}' not found!"
        exit 1
      end
      instr_end_rva = @base_rva + patch[:pos] + 4
      offset = item[:rva] - instr_end_rva
      code_bytes[patch[:pos]..patch[:pos]+3] = [offset].pack("l<").bytes
    end

    # 4. Patch imports
    @import_patches.each do |patch|
      target_rva = @imports[patch[:name]]
      unless target_rva
        puts "Error: Import '#{patch[:name]}' not found!"
        exit 1
      end
      # Indirect call: FF 15 disp32
      # Instr is 6 bytes. Opcode (FF 15) is at patch-2.
      # pos points to the 4-byte displacement.
      instr_end_rva = @base_rva + patch[:pos] + 4
      offset = target_rva - instr_end_rva
      code_bytes[patch[:pos]..patch[:pos]+3] = [offset].pack("l<").bytes
    end

    code_bytes
  end
end
