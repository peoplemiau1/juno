require_relative "../native/pe_builder"
require_relative "../native/elf_builder"
require_relative "../native/flat_builder"
require_relative "parts/context"
require_relative "parts/linker"
require_relative "parts/emitter"
require_relative "parts/emitter_aarch64"
require_relative "parts/logic"
require_relative "parts/calls"
require_relative "parts/syscall_mapper"
require_relative "../optimizer/register_allocator"

class NativeGenerator
  STACK_SIZE = 65536

  include GeneratorLogic
  include GeneratorCalls
  include SyscallMapper

  def initialize(ast, target_os, arch = :x86_64)
    @ast = ast
    @target_os = target_os
    @arch = arch
    @ctx = CodegenContext.new
    @emitter = (arch == :aarch64) ? AArch64Emitter.new : CodeEmitter.new
    @allocator = RegisterAllocator.new
    @stack_size = STACK_SIZE

    base_rva = if target_os == :linux
                 (arch == :aarch64) ? 0x1000 : 0x401000
               else
                 0x1000
               end

    @linker = Linker.new(base_rva, arch)
    setup_data
  end

  def setup_data
    @linker.add_data("int_buffer", "\0" * 64)
    @linker.add_data("file_buffer", "\0" * 4096)
    @linker.add_data("concat_buffer_idx", [0].pack("Q<"))
    @linker.add_data("concat_buffer_pool", "\0" * 32768) # 16 * 2048
    @linker.add_data("substr_buffer", "\0" * 1024)
    @linker.add_data("chr_buffer", "\0" * 4)
    @linker.add_data("input_buffer", "\0" * 1024)
    @linker.add_data("rand_seed", [12345].pack("Q<"))
    @linker.add_data("newline_char", "\n")
  end

  def generate(output_path)
    top_level = []
    @ast.each do |n|
      case n[:type]
      when :struct_definition
        gen_struct_def(n)
      when :union_definition
        gen_union_def(n)
      when :function_definition
        nil
      else
        top_level << n
      end
    end

    has_main = @ast.any? { |n| n[:type] == :function_definition && n[:name] == "main" }
    gen_entry_point
    gen_synthetic_main(top_level) if !has_main || !top_level.empty?

    @ast.each do |n|
      gen_function(n) if n[:type] == :function_definition
    end

    final_bytes = @linker.finalize(@emitter.bytes)
    builder = (@target_os == :linux) ? ELFBuilder.new(final_bytes, @arch) : PEBuilder.new(final_bytes)

    File.binwrite(output_path, builder.build)
    File.chmod(0755, output_path) if @target_os == :linux
  end

  private

  def gen_struct_def(node)
    fields = {}; field_types = node[:field_types] || {}; packed = node[:packed] || false; offset = 0
    node[:fields].each { |f| fields[f] = offset; offset += packed ? @ctx.type_size(field_types[f]) : 8 }
    @ctx.register_struct(node[:name], offset, fields)
  end

  def gen_union_def(node)
    fields = {}; max_size = 0
    node[:fields].each { |f| ts = @ctx.type_size(node[:field_types][f] || "i64"); max_size = ts if ts > max_size; fields[f] = 0 }
    @ctx.register_union(node[:name], max_size == 0 ? 8 : max_size, fields)
  end

  def gen_entry_point
    @emitter.emit_prologue(@stack_size)
    @linker.add_fn_patch(@emitter.current_pos + (@arch == :aarch64 ? 0 : 1), "main", @arch == :aarch64 ? :aarch64_bl : :rel32)
    @emitter.call_rel32
    @target_os == :linux ? @emitter.emit_sys_exit_rax : @emitter.emit_epilogue(@stack_size)
  end

  def gen_function(node)
    @linker.register_function(node[:name], @emitter.current_pos); @ctx.reset_for_function(node[:name])
    params = node[:params].map { |p| p.is_a?(Hash) ? p[:name] : p }
    if node[:name].include?('.') then @ctx.var_types["self"] = node[:name].split('.')[0]; @ctx.var_is_ptr["self"] = true end
    @emitter.emit_prologue(@stack_size)
    regs = (@arch == :aarch64) ? [0,1,2,3,4,5,6,7] : [7,6,2,1,8,9]
    params.each_with_index do |p, i|
      off = @ctx.declare_variable(p)
      if i < regs.length then @emitter.mov_stack_reg_val(off, regs[i])
      else @emitter.mov_rax_rbp_disp32(16 + 8 * (i - regs.length)); @emitter.mov_stack_reg_val(off, 0) end
    end
    node[:body].each { |c| process_node(c) }
    @emitter.emit_epilogue(@stack_size)
  end

  def gen_synthetic_main(nodes)
    @linker.register_function("main", @emitter.current_pos); @ctx.reset_for_function("main")
    @emitter.emit_prologue(@stack_size)
    nodes.each { |c| process_node(c) }
    @emitter.emit_epilogue(@stack_size)
  end

  def gen_print_int_compatibility(node)
    if @arch == :aarch64
       @emitter.push_reg(0); @emitter.push_reg(1); @emitter.push_reg(2); @emitter.push_reg(3); @emitter.push_reg(4)
       @emitter.emit_load_address("int_buffer", @linker)
       @emitter.mov_reg_reg(4, 0); @emitter.emit_add_imm(4, 4, 62) # X4 = buf + 62
       @emitter.mov_rax(10); @emitter.emit32(0x39000080) # [x4] = '\n'
       @emitter.mov_rax(10); @emitter.mov_reg_reg(1, 0) # X1 = 10
       @emitter.emit32(0xf94013e0) # ldr x0, [sp, #32] (original value)
       l = @emitter.current_pos
       @emitter.emit32(0x9ac10802) # sdiv x2, x0, x1
       @emitter.emit32(0x9b018043) # msub x3, x2, x1, x0 (rem)
       @emitter.emit32(0x9100c063) # add x3, x3, #48 ('0')
       @emitter.emit32(0xd1000484) # sub x4, x4, #1
       @emitter.emit32(0x39000083) # strb w3, [x4]
       @emitter.mov_reg_reg(0, 2) # x0 = quot
       @emitter.emit32(0xeb1f001f) # cmp x0, #0
       pos = @emitter.current_pos
       @emitter.emit32(0x54000001) # b.ne placeholder
       @emitter.patch_jne(pos, l)
       @emitter.mov_reg_reg(1, 4) # X1 = buffer start
       @emitter.emit_load_address("int_buffer", @linker)
       @emitter.emit_add_imm(2, 0, 63) # X2 = buf + 63
       @emitter.emit32(0xcb010042) # X2 = X2 - X1 = len
       @emitter.mov_rax(1) # X0 = 1 (stdout)
       @emitter.mov_x8(64) # X8 = 64 (write)
       @emitter.syscall
       @emitter.pop_reg(4); @emitter.pop_reg(3); @emitter.pop_reg(2); @emitter.pop_reg(1); @emitter.pop_reg(0)
    else
      @emitter.push_reg(0); @emitter.push_reg(7); @emitter.push_reg(6); @emitter.push_reg(2); @emitter.push_reg(1)
      @emitter.emit_load_address("int_buffer", @linker)
      @emitter.emit([0x48, 0x83, 0xc0, 62, 0xc6, 0x00, 10, 0x48, 0x89, 0xc6, 0x48, 0xc7, 0xc1, 10, 0, 0, 0, 0x48, 0x8b, 0x44, 0x24, 32])
      l = @emitter.current_pos
      @emitter.emit([0x48, 0x31, 0xd2, 0x48, 0xf7, 0xf1, 0x80, 0xc2, 0x30, 0x48, 0xff, 0xce, 0x88, 0x16, 0x48, 0x85, 0xc0, 0x75])
      @emitter.emit([(l - (@emitter.current_pos + 1)) & 0xFF])
      @emitter.mov_reg_reg(11, 6); @emitter.emit_load_address("int_buffer", @linker)
      @emitter.emit([0x48, 0x83, 0xc0, 63, 0x4c, 0x29, 0xd8, 0x48, 0x89, 0xc2, 0x4c, 0x89, 0xde, 0xb8, 1, 0, 0, 0, 0xbf, 1, 0, 0, 0, 0x0f, 0x05])
      @emitter.pop_reg(1); @emitter.pop_reg(2); @emitter.pop_reg(6); @emitter.pop_reg(7); @emitter.pop_reg(0)
    end
  end
end
