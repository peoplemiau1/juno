require_relative "../native/pe_builder"
require_relative "../native/elf_builder"
require_relative "../native/flat_builder"
require_relative "parts/context"
require_relative "parts/linker"
require_relative "parts/emitter"
require_relative "parts/emitter_aarch64"
require_relative "parts/logic"
require_relative "parts/calls"
require_relative "../optimizer/register_allocator"

class NativeGenerator
STACK_SIZE = 65536
FLAT_STACK_PTR = 0x90000
  include GeneratorLogic
  include GeneratorCalls

  attr_accessor :hell_mode

  def initialize(ast, target_os, arch = :x86_64)
    @ast = ast
    @target_os = target_os
    @arch = arch

    @ctx = CodegenContext.new
    @emitter = (arch == :aarch64) ? AArch64Emitter.new : CodeEmitter.new
    @allocator = RegisterAllocator.new
    base_rva =
      case target_os
      when :windows then 0x1000
      when :linux then 0x401000
      else 0x0
      end
    @linker = Linker.new(base_rva)
    @stack_size = STACK_SIZE

    if target_os == :windows
      # Register hardcoded imports from PEBuilder
      @linker.register_import("GetStdHandle", 0x2060)
      @linker.register_import("WriteFile", 0x2068)
      @linker.register_import("ReadFile", 0x2070)
      @linker.register_import("CreateThread", 0x2078)
      @linker.register_import("Sleep", 0x2080)
      @linker.register_import("ExitProcess", 0x2088)
    end

    @linker.add_data("int_buffer", "\0" * 64)
    @linker.add_data("file_buffer", "\0" * 4096)
    @linker.add_data("concat_buffer", "\0" * 2048)
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
        # skip here, generate later
      else
        top_level << n
      end
    end

    has_main = @ast.any? { |n| n[:type] == :function_definition && n[:name] == "main" }

    gen_entry_point
    if has_main
      # main already exists
    elsif !top_level.empty?
      gen_synthetic_main(top_level)
    else
      gen_synthetic_main([])
    end
    @ast.each { |n| gen_function(n) if n[:type] == :function_definition }

    final_bytes = @linker.finalize(@emitter.bytes)
    builder =
      case @target_os
      when :windows then PEBuilder.new(final_bytes)
      when :linux then ELFBuilder.new(final_bytes, @arch)
      else FlatBuilder.new(final_bytes)
      end
    File.binwrite(output_path, builder.build)
    File.chmod(0755, output_path) if @target_os == :linux
  end

  private

  def gen_struct_def(node)
    fields = {}
    field_types = node[:field_types] || {}
    packed = node[:packed] || false

    if packed
      offset = 0
      node[:fields].each do |f|
        fields[f] = offset
        type_name = field_types[f]
        offset += @ctx.type_size(type_name)
      end
    else
      offset = 0
      node[:fields].each do |f|
        fields[f] = offset
        offset += 8
      end
    end

    @ctx.register_struct(node[:name], offset, fields)
  end

  def gen_union_def(node)
    fields = {}
    field_types = node[:field_types] || {}
    max_size = 0

    node[:fields].each do |f|
      fields[f] = field_types[f] || "i64"
      type_size = @ctx.type_size(fields[f])
      max_size = type_size if type_size > max_size
    end

    max_size = 8 if max_size == 0
    @ctx.register_union(node[:name], max_size, fields)
  end

  def gen_entry_point
    if @target_os == :flat
      @emitter.mov_rax(FLAT_STACK_PTR)
      @emitter.mov_reg_reg(@emitter.class::REG_RSP, @emitter.class::REG_RAX)
    end

    @emitter.emit_prologue(@stack_size)
    @linker.add_fn_patch(@emitter.current_pos + (@arch == :aarch64 ? 0 : 1), "main")
    @emitter.call_rel32
    @emitter.mov_rax(0)
    if @target_os == :windows
      @emitter.emit_epilogue(@stack_size)
      @emitter.emit([0x48, 0x31, 0xc0, 0xc3])
    elsif @target_os == :linux
      @emitter.emit_sys_exit_rax
    else
      @emitter.emit_epilogue(@stack_size)
      if @arch == :x86_64
        @emitter.emit([0xf4, 0xeb, 0xfd])
      else
        @emitter.emit32(0xd503205f) # wfe
        @emitter.emit32(0x17ffffff) # b .
      end
    end
  end

  def gen_function(node)
    @linker.register_function(node[:name], @emitter.current_pos)
    @ctx.reset_for_function(node[:name])
    @allocator.reset

    allocation_result = @allocator.allocate(node[:body])
    allocation_result[:allocations].each do |var_name, reg|
      @ctx.assign_register(var_name, reg)
    end

    used_regs = @ctx.used_callee_saved
    padding = (used_regs.length % 2 == 1) ? 8 : 0

    @emitter.emit_prologue(@stack_size)
    @emitter.emit_sub_rsp(padding) if padding > 0
    @emitter.push_callee_saved(used_regs) unless used_regs.empty?
    @emitter.mov_rax(0)

    if node[:name].include?('.')
       @ctx.var_types["self"] = node[:name].split('.')[0]
       @ctx.var_is_ptr["self"] = true
    end

    regs, stack_base =
      if @arch == :aarch64
        [[0, 1, 2, 3, 4, 5, 6, 7], 16] # X0-X7
      elsif @target_os == :windows
        [[CodeEmitter::REG_RCX, CodeEmitter::REG_RDX, CodeEmitter::REG_R8, CodeEmitter::REG_R9], 16 + 8 * 4]
      else
        [[CodeEmitter::REG_RDI, CodeEmitter::REG_RSI, CodeEmitter::REG_RDX, CodeEmitter::REG_RCX, CodeEmitter::REG_R8, CodeEmitter::REG_R9], 16]
      end

    node[:params].each_with_index do |param, i|
      if @ctx.in_register?(param) && i < regs.length
        allocated_reg = @emitter.class.reg_code(@ctx.get_register(param))
        @emitter.mov_reg_reg(allocated_reg, regs[i])
      else
        off = @ctx.declare_variable(param)
        if i < regs.length
          reg = regs[i]
          @emitter.mov_stack_reg_val(off, reg) if reg
        else
          disp = stack_base + 8 * (i - regs.length)
          @emitter.mov_rax_rbp_disp32(disp)
          @emitter.mov_stack_reg_val(off, @emitter.class::REG_RAX)
        end
      end
    end

    node[:body].each { |child| process_node(child) }

    @emitter.pop_callee_saved(used_regs) unless used_regs.empty?
    @emitter.emit_add_rsp(padding) if padding > 0
    @emitter.emit_epilogue(@stack_size)
  end

  def gen_synthetic_main(nodes)
    @linker.register_function("main", @emitter.current_pos)
    @ctx.reset_for_function("main")
    @allocator.reset

    allocation_result = @allocator.allocate(nodes)
    allocation_result[:allocations].each do |var_name, reg|
      @ctx.assign_register(var_name, reg)
    end

    used_regs = @ctx.used_callee_saved
    padding = (used_regs.length % 2 == 1) ? 8 : 0

    @emitter.emit_prologue(@stack_size)
    @emitter.emit_sub_rsp(padding) if padding > 0
    @emitter.push_callee_saved(used_regs) unless used_regs.empty?
    @emitter.mov_rax(0)
    nodes.each { |child| process_node(child) }
    @emitter.pop_callee_saved(used_regs) unless used_regs.empty?
    @emitter.emit_add_rsp(padding) if padding > 0
    @emitter.emit_epilogue(@stack_size)
  end
end
