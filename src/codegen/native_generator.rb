# require_relative "../native/pe_builder"
require_relative "../native/elf_builder"
require_relative "../native/flat_builder"
require_relative "parts/context"
require_relative "parts/linker"
require_relative "parts/emitter"
require_relative "parts/emitter_aarch64"
require_relative "parts/logic"
require_relative "parts/calls"
require_relative "parts/syscall_mapper"
require_relative "parts/base_gen"
require_relative "parts/print_utils"
require_relative "../optimizer/register_allocator"

class NativeGenerator
  attr_accessor :hell_mode
  STACK_SIZE = 65536

  include GeneratorLogic
  include GeneratorCalls
  include SyscallMapper
  include BaseGenerator
  include PrintUtils

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

    if @hell_mode && (@arch == :x86_64 || @arch == :aarch64)
      # Apply global obfuscation to all generated code before finalizing
      mutated_bytes, mapping = @hell_mode.mutator.inject_junk(@emitter.bytes)
      @emitter.instance_variable_set(:@bytes, mutated_bytes)
      @linker.apply_mapping(mapping)

      # Re-apply internal patches using the mapping
      @emitter.internal_patches.each do |p|
        new_pos = mapping[p[:pos]]
        new_target = mapping[p[:target]]
        next unless new_pos && new_target

        if @arch == :x86_64
          case p[:type]
          when :je_rel32, :jne_rel32
            offset = new_target - (new_pos + 6)
            @emitter.bytes[new_pos+2..new_pos+5] = [offset].pack("l<").bytes
          when :jmp_rel32
            offset = new_target - (new_pos + 5)
            @emitter.bytes[new_pos+1..new_pos+4] = [offset].pack("l<").bytes
          end
        elsif @arch == :aarch64
          @emitter.patch_jmp(new_pos, new_target) if p[:type] == :jmp_rel32
          @emitter.patch_je(new_pos, new_target)  if p[:type] == :je_rel32
          @emitter.patch_jne(new_pos, new_target) if p[:type] == :jne_rel32
        end
      end
    end

    final_bytes = @linker.finalize(@emitter.bytes)

    builder = case @target_os
              when :linux
                ELFBuilder.new(final_bytes, @arch)
              when :flat
                FlatBuilder.new(final_bytes)
              when :windows
                require_relative "../native/pe_builder"
                PEBuilder.new(final_bytes)
              else
                raise "Unsupported target OS: #{@target_os}"
              end

    File.binwrite(output_path, builder.build)
    File.chmod(0755, output_path) if @target_os == :linux
  end

  private

  def gen_function(node)
    @linker.register_function(node[:name], @emitter.current_pos); @ctx.reset_for_function(node[:name])
    params = node[:params].map { |p| p.is_a?(Hash) ? p[:name] : p }
    if node[:name].include?('.') then @ctx.var_types["self"] = node[:name].split('.')[0]; @ctx.var_is_ptr["self"] = true end

    @emitter.emit_prologue(@stack_size)

    # Save callee-saved registers to allow builtins and allocator to use them safely
    callee_saved = @emitter.callee_saved_regs
    @emitter.push_callee_saved(callee_saved)

    # Stack alignment for x86_64 (16 bytes)
    # push rbp (8) + sub rsp, stack_size (even) + push N regs (N*8)
    # Total must be multiple of 16. If N is odd, we need 8 bytes padding.
    if @arch == :x86_64 && callee_saved.length % 2 == 1
      @emitter.emit_sub_rsp(8)
    end

    regs = (@arch == :aarch64) ? [0,1,2,3,4,5,6,7] : [7,6,2,1,8,9]
    params.each_with_index do |p, i|
      off = @ctx.declare_variable(p)
      if i < regs.length then @emitter.mov_stack_reg_val(off, regs[i])
      else @emitter.mov_rax_rbp_disp32(16 + 8 * (i - regs.length)); @emitter.mov_stack_reg_val(off, 0) end
    end

    node[:body].each { |c| process_node(c) }

    if @arch == :x86_64 && @emitter.callee_saved_regs.length % 2 == 1
      @emitter.emit_add_rsp(8)
    end
    @emitter.pop_callee_saved(@emitter.callee_saved_regs)
    @emitter.emit_epilogue(@stack_size)
  end


end
