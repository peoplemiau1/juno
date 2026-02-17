# base_gen.rb - Common code generation helpers for Juno

module BaseGenerator
  def gen_entry_point
    @emitter.emit_prologue(@stack_size)
    @linker.add_fn_patch(@emitter.current_pos + (@arch == :aarch64 ? 0 : 1), "main", @arch == :aarch64 ? :aarch64_bl : :rel32)
    @emitter.call_rel32
    @target_os == :linux ? @emitter.emit_sys_exit_rax : @emitter.emit_epilogue(@stack_size)
  end

  def gen_synthetic_main(nodes)
    @linker.register_function("main", @emitter.current_pos)
    @ctx.reset_for_function("main")
    @emitter.emit_prologue(@stack_size)
    nodes.each { |c| process_node(c) }
    @emitter.emit_epilogue(@stack_size)
  end

  def gen_struct_def(node)
    fields = {}
    field_types = node[:field_types] || {}
    packed = node[:packed] || false
    offset = 0
    node[:fields].each do |f|
      fields[f] = offset
      offset += packed ? @ctx.type_size(field_types[f]) : 8
    end
    @ctx.register_struct(node[:name], offset, fields)
  end

  def gen_union_def(node)
    fields = {}
    max_size = 0
    node[:fields].each do |f|
      ts = @ctx.type_size(node[:field_types][f] || "i64")
      max_size = ts if ts > max_size
      fields[f] = 0
    end
    @ctx.register_union(node[:name], max_size == 0 ? 8 : max_size, fields)
  end
end
