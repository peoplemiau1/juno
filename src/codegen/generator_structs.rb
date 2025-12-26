module GeneratorStructs
  def gen_struct_def(node)
    offset = 0; fields = {}
    node[:fields].each { |f| fields[f] = offset; offset += 8 }
    @structs[node[:name].to_s] = { size: offset, fields: fields }
  end

  def save_member_rax(full_name)
    var_name, field = full_name.split('.')
    var_offset = @variables[var_name]
    struct_name = @var_types[var_name]
    return unless struct_name && @structs[struct_name]
    field_offset = @structs[struct_name][:fields][field]
    
    if @var_is_ptr && @var_is_ptr[var_name]
      @code_bytes += [0x49, 0x89, 0xc3] # mov r11, rax
      @code_bytes += [0x48, 0x8b, 0x45] + [(-var_offset) & 0xFF].pack("C").bytes # mov rax, [rbp - off]
      @code_bytes += [0x4c, 0x89, 0x58, field_offset & 0xFF] # mov [rax + foff], r11
    else
      st_size = @structs[struct_name][:size]
      real_off = var_offset - st_size + field_offset
      @code_bytes += [0x48, 0x89, 0x45] + [(-real_off) & 0xFF].pack("C").bytes
    end
  end

  def load_member_rax(full_name)
    var_name, field = full_name.split('.')
    var_offset = @variables[var_name]
    struct_name = @var_types[var_name]
    return unless struct_name && @structs[struct_name]
    field_offset = @structs[struct_name][:fields][field]
    
    if @var_is_ptr && @var_is_ptr[var_name]
      @code_bytes += [0x48, 0x8b, 0x45] + [(-var_offset) & 0xFF].pack("C").bytes # mov rax, [rbp - off]
      @code_bytes += [0x48, 0x8b, 0x40, field_offset & 0xFF] # mov rax, [rax + foff]
    else
      st_size = @structs[struct_name][:size]
      real_off = var_offset - st_size + field_offset
      @code_bytes += [0x48, 0x8b, 0x45] + [(-real_off) & 0xFF].pack("C").bytes
    end
  end
end
