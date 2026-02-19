# base_gen.rb - Common code generation helpers for Juno

module BaseGenerator
  def gen_entry_point(has_top_level, has_user_main)
    @emitter.emit_prologue(@stack_size)
    if has_top_level
      @linker.add_fn_patch(@emitter.current_pos + (@arch == :aarch64 ? 0 : 1), "__juno_init", @arch == :aarch64 ? :aarch64_bl : :rel32)
      @emitter.call_rel32
    end
    if has_user_main
      @linker.add_fn_patch(@emitter.current_pos + (@arch == :aarch64 ? 0 : 1), "main", @arch == :aarch64 ? :aarch64_bl : :rel32)
      @emitter.call_rel32
    end
    @target_os == :linux ? @emitter.emit_sys_exit_rax : @emitter.emit_epilogue(@stack_size)
  end

  def gen_synthetic_main(nodes)
    @linker.register_function("__juno_init", @emitter.current_pos)
    @ctx.reset_for_function("__juno_init")

    # Register allocation for top-level code
    res = @allocator.allocate(nodes)
    res[:allocations].each { |var, reg| @ctx.assign_register(var, reg) }

    @emitter.emit_prologue(@stack_size)

    callee_saved = @emitter.callee_saved_regs
    @emitter.push_callee_saved(callee_saved)
    if @arch == :x86_64 && (1 + callee_saved.length) % 2 == 1
      @emitter.emit_sub_rsp(8)
    end

    nodes.each { |c| process_node(c) }

    if @arch == :x86_64 && (1 + @emitter.callee_saved_regs.length) % 2 == 1
      @emitter.emit_add_rsp(8)
    end
    @emitter.pop_callee_saved(@emitter.callee_saved_regs)
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
