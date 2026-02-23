# Function call dispatcher for Juno compiler
require_relative "builtins/strings"
require_relative "builtins/math"
require_relative "builtins/memory"
require_relative "builtins/utils"
require_relative "builtins/io"
require_relative "builtins/network"
require_relative "builtins/syscalls"
require_relative "builtins/threads"
require_relative "builtins/types"
require_relative "builtins/https"
require_relative "builtins/heap"
require_relative "builtins/strings_v2"
require_relative "builtins/file_api"
require_relative "builtins/collections"
require_relative "builtins/lib_linux"
require_relative "builtins/fs_ops"
require_relative "builtins/process_ops"

module GeneratorCalls
  include BuiltinStrings
  include BuiltinMath
  include BuiltinMemory
  include BuiltinUtils
  include BuiltinIO
  include BuiltinNetwork
  include BuiltinSyscalls
  include BuiltinThreads
  include BuiltinTypes
  include BuiltinHTTPS
  include BuiltinHeap
  include BuiltinStringsV2
  include BuiltinFileAPI
  include BuiltinCollections
  include BuiltinLibLinux
  include BuiltinFS
  include BuiltinProcess

  def gen_fn_call(node)
    name = node[:name]

    if @ctx.variables.key?(name) || @ctx.in_register?(name)
      return gen_indirect_fn_call(node)
    end

    if name.include?('.')
      parts = name.split('.')
      if @ctx.enums.key?(parts[0])
        return gen_enum_variant_init(parts[0], parts[1], node[:args])
      end
    end

    builtin_method = "gen_#{name}"
    return send(builtin_method, node) if respond_to?(builtin_method)
    aliases = {
      "itoa" => :gen_int_to_str, "atoi" => :gen_str_to_int,
      "i8" => :gen_cast_i8, "u8" => :gen_cast_u8,
      "i16" => :gen_cast_i16, "u16" => :gen_cast_u16,
      "i32" => :gen_cast_i32, "u32" => :gen_cast_u32,
      "i64" => :gen_cast_i64, "u64" => :gen_cast_u64,
      "malloc" => :gen_malloc, "realloc" => :gen_realloc, "free" => :gen_free,
      "ptr_add" => :gen_ptr_add, "ptr_sub" => :gen_ptr_sub,
      "len" => :gen_str_len, "sizeof" => :gen_sizeof
    }
    return send(aliases[name], node) if aliases.key?(name)
    return gen_method_call(node) if name.include?('.')
    gen_user_fn_call(node)
  end

  def gen_user_fn_call(node)
    args = node[:args] || []
    linux_like = (@target_os == :linux || @target_os == :flat)
    regs = if @arch == :aarch64 then [0,1,2,3,4,5,6,7]
           elsif linux_like then [7,6,2,1,8,9]
           else [1,2,8,9] end

    num_stack = [0, args.length - regs.length].max

    padding = 0
    if @arch == :x86_64
      # Calculate current stack alignment
      # Frame (8 for RBP + stack_size) + Callee-saved + Alignment padding + Temp pushes
      callee_saved_count = @emitter.callee_saved_regs.length
      align_pad = ((callee_saved_count + 1) % 2 == 0) ? 8 : 0
      current_total = 8 + @ctx.current_fn_stack_size + callee_saved_count * 8 + align_pad + @ctx.stack_depth

      # We will push num_stack * 8 bytes.
      # We want (current_total + padding + num_stack * 8) % 16 == 0
      padding = (16 - (current_total + num_stack * 8) % 16) % 16
    end

    if padding > 0
      @emitter.emit_sub_rsp(padding)
      @ctx.stack_depth += padding
    end
    args.reverse_each do |a|
      eval_expression(a)
      @emitter.push_reg(0)
      @ctx.stack_depth += 8
    end

    num_pop = [args.length, regs.length].min
    num_pop.times { |i| @emitter.pop_reg(regs[i]); @ctx.stack_depth -= 8 }

    if @target_os == :windows
      @emitter.emit_sub_rsp(32)
      @ctx.stack_depth += 32
    end
    if @linker.instance_variable_get(:@got_slots).key?(node[:name])
      if @arch == :aarch64
         @emitter.emit_call_indirect(node[:name], @linker)
      else
         @emitter.xor_rax_rax if @arch == :x86_64
         # FF 15 disp32 -> disp32 is at +2 from start of call_ind_rel32
         @linker.add_import_patch(@emitter.current_pos + 2, node[:name], :rel32)
         @emitter.call_ind_rel32
      end
    else
      @linker.add_fn_patch(@emitter.current_pos + (@arch == :aarch64 ? 0 : 1), node[:name], @arch == :aarch64 ? :aarch64_bl : :rel32)
      @emitter.call_rel32
    end
    if @target_os == :windows
      @emitter.emit_add_rsp(32)
      @ctx.stack_depth -= 32
    end

    byte_size = num_stack * (@arch == :aarch64 ? 16 : 8) + padding
    @ctx.stack_depth -= byte_size
    @emitter.emit_add_rsp(byte_size) if byte_size > 0
  end

  def gen_method_call(node)
    v, m = node[:name].split('.')
    st = @ctx.var_types[v]
    args = node[:args] || []

    linux_like = (@target_os == :linux || @target_os == :flat)
    regs = if @arch == :aarch64 then [0,1,2,3,4,5,6,7]
           elsif linux_like then [7,6,2,1,8,9]
           else [1,2,8,9] end

    num_stack = [0, (args.length + 1) - regs.length].max

    padding = 0
    if @arch == :x86_64
      callee_saved_count = @emitter.callee_saved_regs.length
      align_pad = ((callee_saved_count + 1) % 2 == 0) ? 8 : 0
      current_total = 8 + @ctx.current_fn_stack_size + callee_saved_count * 8 + align_pad + @ctx.stack_depth
      padding = (16 - (current_total + num_stack * 8) % 16) % 16
    end

    if padding > 0
      @emitter.emit_sub_rsp(padding)
      @ctx.stack_depth += padding
    end

    # Push args first
    args.reverse_each do |a|
      eval_expression(a)
      @emitter.push_reg(0)
      @ctx.stack_depth += 8
    end

    # Push 'this' LAST so it's on top
    if @ctx.in_register?(v)
      @emitter.mov_rax_from_reg(@emitter.class.reg_code(@ctx.get_register(v)))
    else
      @emitter.mov_reg_stack_val(0, @ctx.variables[v])
    end
    @emitter.push_reg(0)
    @ctx.stack_depth += 8

    num_pop = [args.length + 1, regs.length].min
    num_pop.times { |i| @emitter.pop_reg(regs[i]); @ctx.stack_depth -= 8 }

    if @target_os == :windows
      @emitter.emit_sub_rsp(32)
      @ctx.stack_depth += 32
    end
    @linker.add_fn_patch(@emitter.current_pos + (@arch == :aarch64 ? 0 : 1), "#{st}.#{m}", @arch == :aarch64 ? :aarch64_bl : :rel32)
    @emitter.call_rel32
    if @target_os == :windows
      @emitter.emit_add_rsp(32)
      @ctx.stack_depth -= 32
    end

    byte_size = num_stack * (@arch == :aarch64 ? 16 : 8) + padding
    @ctx.stack_depth -= byte_size
    @emitter.emit_add_rsp(byte_size) if byte_size > 0
  end

  def handle_linux_io(node)
    eval_expression(node[:args][0])
    gen_print_int_compatibility(node)
  end

  def handle_windows_io_stub(node)
    eval_expression(node[:args][0])
  end

  def gen_indirect_fn_call(node)
    name = node[:name]
    args = node[:args] || []

    # Load fn pointer into R11
    if @ctx.in_register?(name)
      @emitter.mov_reg_reg(11, @emitter.class.reg_code(@ctx.get_register(name)))
    else
      @emitter.mov_reg_stack_val(11, @ctx.variables[name])
    end

    linux_like = (@target_os == :linux || @target_os == :flat)
    regs = if @arch == :aarch64 then [0,1,2,3,4,5,6,7]
           elsif linux_like then [7,6,2,1,8,9]
           else [1,2,8,9] end

    num_stack = [0, args.length - regs.length].max

    padding = 0
    if @arch == :x86_64
      callee_saved_count = @emitter.callee_saved_regs.length
      align_pad = ((callee_saved_count + 1) % 2 == 0) ? 8 : 0
      # Include +8 for the fn ptr we are about to push
      current_total = 8 + @ctx.current_fn_stack_size + callee_saved_count * 8 + align_pad + @ctx.stack_depth + 8
      padding = (16 - (current_total + num_stack * 8) % 16) % 16
    end

    @emitter.push_reg(11) # Save fn ptr
    @ctx.stack_depth += 8
    if padding > 0
      @emitter.emit_sub_rsp(padding)
      @ctx.stack_depth += padding
    end
    args.reverse_each do |a|
      eval_expression(a)
      @emitter.push_reg(0)
      @ctx.stack_depth += 8
    end

    num_pop = [args.length, regs.length].min
    num_pop.times { |i| @emitter.pop_reg(regs[i]); @ctx.stack_depth -= 8 }

    # Load saved fn ptr back to R11. It is now at [RSP + num_stack*8 + padding]
    offset = num_stack * (@arch == :aarch64 ? 16 : 8) + padding
    # Using mov_reg_mem_idx(11, REG_RSP, offset)
    @emitter.mov_reg_mem_idx(11, 4, offset)

    @emitter.call_reg(11)

    byte_size = num_stack * (@arch == :aarch64 ? 16 : 8) + padding
    @ctx.stack_depth -= (byte_size + 8)
    @emitter.emit_add_rsp(byte_size + 8) # +8 for the pushed R11
  end

  def gen_enum_variant_init(enum_name, variant_name, args)
    enum_info = @ctx.enums[enum_name]
    variant_info = enum_info[:variants][variant_name]

    # Allocate on heap
    eval_expression({ type: :fn_call, name: "malloc", args: [{ type: :literal, value: enum_info[:size] }] })

    ptr_reg = @ctx.acquire_scratch
    @emitter.mov_reg_reg(ptr_reg, 0)

    @emitter.mov_reg_imm(1, variant_info[:tag])
    @emitter.mov_mem_reg_idx(ptr_reg, 0, 1)

    (args || []).each_with_index do |a, i|
      eval_expression(a)
      @emitter.mov_mem_reg_idx(ptr_reg, 8 + i * 8, 0)
    end

    @emitter.mov_reg_reg(0, ptr_reg)
    @ctx.release_scratch(ptr_reg)
  end
end
