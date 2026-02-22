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
  STACK_SIZE = 1024 # Smaller default stack frame

  include GeneratorLogic
  include GeneratorCalls
  include SyscallMapper
  include BaseGenerator
  include PrintUtils

  def initialize(ast, target_os: :linux, arch: :x86_64, source: "", filename: "main.juno")
    @ast = ast
    @source = source
    @filename = filename
    @target_os = target_os
    @arch = arch
    @ctx = CodegenContext.new(arch)
    @emitter = (arch == :aarch64) ? AArch64Emitter.new : CodeEmitter.new
    @allocator = RegisterAllocator.new(arch)
    @stack_size = STACK_SIZE
    @loop_stack = []

    base_rva = if target_os == :linux
                 (arch == :aarch64) ? 0x1000 : 0x401000
               else
                 0x1000
               end

    @linker = Linker.new(base_rva, arch)
    setup_data
  end

  def setup_data
    @linker.add_bss("int_buffer", 64)
    @linker.add_bss("file_buffer", 4096)
    @linker.add_data("concat_buffer_idx", [0].pack("Q<"))
    @linker.add_bss("concat_buffer_pool", 32768) # 16 * 2048
    @linker.add_bss("substr_buffer", 1024)
    @linker.add_bss("chr_buffer", 4)
    @linker.add_bss("input_buffer", 1024)
    @linker.add_data("rand_seed", [12345].pack("Q<"))
    @linker.add_data("newline_char", "\n")
  end

  def generate(output_path)
    # FIRST PASS: SYMBOL TABLE & TYPE REGISTRATION
    # Ensure all functions, structs and unions are known before generation starts
    @ast.each do |n|
      case n[:type]
      when :function_definition
        @linker.declare_function(n[:name])
      when :struct_definition
        gen_struct_def(n)
      when :union_definition
        gen_union_def(n)
      when :assignment
        # Register top-level let as global
        if n[:let] && n[:name]
           name = n[:name]
           label = "global_#{name}"
           @linker.add_data(label, "\0" * 8)
           @ctx.register_global(name, label)
        end
      end
    end

    top_level = []
    @ast.each do |n|
      case n[:type]
      when :struct_definition, :union_definition, :function_definition
        next
      else
        top_level << n
      end
    end

    has_main = @ast.any? { |n| n[:type] == :function_definition && n[:name] == "main" }
    has_top_level = !top_level.empty?
    gen_entry_point(has_top_level, has_main)
    gen_synthetic_main(top_level) if has_top_level

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
          when :je_rel32, :jne_rel32, :jae_rel32
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

    result = @linker.finalize(@emitter.bytes)
    final_bytes = result[:combined]

    builder = case @target_os
              when :linux
                ELFBuilder.new(final_bytes, @arch, result[:code].length, result[:data].length, result[:bss_len])
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

  def error_undefined(name, node)
    error = JunoUndefinedError.new(
      "Undefined variable or symbol: '#{name}'",
      filename: @filename,
      line_num: node[:line],
      column: node[:column],
      source: @source
    )
    JunoErrorReporter.report(error)
  end

  def gen_function(node)
    @linker.register_function(node[:name], @emitter.current_pos); @ctx.reset_for_function(node[:name])

    # Run register allocator for function body, skip globals
    res = @allocator.allocate(node[:body], @ctx.globals.keys)
    res[:allocations].each { |var, reg| @ctx.assign_register(var, reg) }

    params = node[:params].map { |p| p.is_a?(Hash) ? p[:name] : p }
    param_types = node[:param_types] || {}
    params.each do |p|
      if param_types[p]
        @ctx.var_types[p] = param_types[p]
        @ctx.var_is_ptr[p] = true if param_types[p] == "ptr" || @ctx.structs.key?(param_types[p])
      end
    end

    if node[:name].include?('.') then @ctx.var_types["self"] = node[:name].split('.')[0]; @ctx.var_is_ptr["self"] = true end

    # Calculate needed stack size
    needed_stack = @stack_size
    node[:body].each do |stmt|
      if stmt[:type] == :array_decl
        needed_stack += (stmt[:size] * 8 + 16)
      end
    end
    # Ensure 16-byte alignment
    needed_stack = (needed_stack + 15) & ~15
    @ctx.stack_ptr = 64 # Reset ptr but track for prologue
    @ctx.current_fn_stack_size = needed_stack

    @emitter.emit_prologue(needed_stack)

    # Save callee-saved registers to allow builtins and allocator to use them safely
    callee_saved = @emitter.callee_saved_regs
    @emitter.push_callee_saved(callee_saved)

    # Stack alignment for x86_64 (16 bytes)
    # push rbp (8) + sub rsp, stack_size (even) + push N regs (N*8)
    # Total must be multiple of 16. Total pushed = 1 (RBP) + N (callee_saved).
    # If 1 + N is odd, we need 8 bytes padding.
    if @arch == :x86_64 && (callee_saved.length + 1) % 2 == 1
      @emitter.emit_sub_rsp(8)
    end

    regs = (@arch == :aarch64) ? [0,1,2,3,4,5,6,7] : [7,6,2,1,8,9]
    params.each_with_index do |p, i|
      if @ctx.in_register?(p)
        reg = @emitter.class.reg_code(@ctx.get_register(p))
        if i < regs.length
          @emitter.mov_reg_reg(reg, regs[i])
        else
          @emitter.mov_rax_rbp_disp32(16 + 8 * (i - regs.length))
          @emitter.mov_reg_from_rax(reg)
        end
      else
        off = @ctx.declare_variable(p)
        if i < regs.length
          @emitter.mov_stack_reg_val(off, regs[i])
        else
          @emitter.mov_rax_rbp_disp32(16 + 8 * (i - regs.length))
          @emitter.mov_stack_reg_val(off, 0) # RAX
        end
      end
    end

    has_ret = false
    node[:body].each do |c|
      process_node(c)
      if c[:type] == :return
        has_ret = true
        break
      end
    end

    unless has_ret
      if @arch == :x86_64 && (@emitter.callee_saved_regs.length + 1) % 2 == 1
        @emitter.emit_add_rsp(8)
      end
      @emitter.pop_callee_saved(@emitter.callee_saved_regs)
      @emitter.emit_epilogue(needed_stack)
    end
  end


end
