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
    builtin_method = "gen_#{name}"
    return send(builtin_method, node) if respond_to?(builtin_method)
    aliases = {
      "itoa" => :gen_int_to_str, "atoi" => :gen_str_to_int,
      "i8" => :gen_cast_i8, "u8" => :gen_cast_u8,
      "i16" => :gen_cast_i16, "u16" => :gen_cast_u16,
      "i32" => :gen_cast_i32, "u32" => :gen_cast_u32,
      "i64" => :gen_cast_i64, "u64" => :gen_cast_u64,
      "malloc" => :gen_malloc, "realloc" => :gen_realloc, "free" => :gen_free,
      "ptr_add" => :gen_ptr_add, "ptr_sub" => :gen_ptr_sub
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
    stack_step = (@arch == :aarch64) ? 16 : 8
    padding = (@arch == :aarch64) ? 0 : (num_stack % 2 == 1 ? 8 : 0)

    @emitter.emit_sub_rsp(padding) if padding > 0
    args.reverse_each { |a| eval_expression(a); @emitter.push_reg(0) }

    num_pop = [args.length, regs.length].min
    num_pop.times { |i| @emitter.pop_reg(regs[i]) }

    @emitter.emit_sub_rsp(32) if @target_os == :windows
    @linker.add_fn_patch(@emitter.current_pos + (@arch == :aarch64 ? 0 : 1), node[:name], @arch == :aarch64 ? :aarch64_bl : :rel32)
    @emitter.call_rel32
    @emitter.emit_add_rsp(32) if @target_os == :windows

    @emitter.emit_add_rsp(num_stack * stack_step + padding) if (num_stack * stack_step + padding) > 0
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
    stack_step = (@arch == :aarch64) ? 16 : 8
    padding = (@arch == :aarch64) ? 0 : (num_stack % 2 == 1 ? 8 : 0)

    @emitter.emit_sub_rsp(padding) if padding > 0

    # Push args first
    args.reverse_each { |a| eval_expression(a); @emitter.push_reg(0) }

    # Push 'this' LAST so it's on top
    if @ctx.in_register?(v)
      @emitter.mov_rax_from_reg(@emitter.class.reg_code(@ctx.get_register(v)))
    else
      @emitter.mov_reg_stack_val(0, @ctx.variables[v])
    end
    @emitter.push_reg(0)

    num_pop = [args.length + 1, regs.length].min
    num_pop.times { |i| @emitter.pop_reg(regs[i]) }

    @emitter.emit_sub_rsp(32) if @target_os == :windows
    @linker.add_fn_patch(@emitter.current_pos + (@arch == :aarch64 ? 0 : 1), "#{st}.#{m}", @arch == :aarch64 ? :aarch64_bl : :rel32)
    @emitter.call_rel32
    @emitter.emit_add_rsp(32) if @target_os == :windows

    @emitter.emit_add_rsp(num_stack * stack_step + padding) if (num_stack * stack_step + padding) > 0
  end

  def handle_linux_io(node)
    eval_expression(node[:args][0])
    gen_print_int_compatibility(node)
  end

  def handle_windows_io_stub(node)
    eval_expression(node[:args][0])
  end
end
