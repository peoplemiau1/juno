# hellion.rb - Formal IR Backend for Juno
require_relative "codegen/parts/emitter"
require_relative "codegen/parts/emitter_aarch64"
require_relative "codegen/parts/context"
require_relative "codegen/parts/linker"
require_relative "native/elf_builder"
require_relative "native/flat_builder"

class Hellion
  def initialize(arch, target_os)
    @arch = arch
    @target_os = target_os
    @emitter = (arch == :aarch64) ? AArch64Emitter.new : CodeEmitter.new
    @ctx = CodegenContext.new(arch)
    @linker = Linker.new(target_os == :linux ? (arch == :aarch64 ? 0x1000 : 0x401000) : 0x1000, arch)
    setup_standard_bss
  end

  def setup_standard_bss
    @linker.add_bss("int_buffer", 64)
    @linker.add_data("newline_char", "\n")
  end

  def generate(ir, output_path)
    # 1. Registration
    ir.each do |ins|
      case ins.op
      when :TYPE_DEF then register_type(ins.args[0])
      when :EXTERN   then @linker.declare_import(ins.args[0], ins.args[1])
      end
    end

    # 2. Entry Point
    gen_entry_point(ir)

    # 3. Functions
    split_into_functions(ir).each do |name, func_ir|
      translate_function(name, func_ir)
    end

    # 4. Finalize
    result = @linker.finalize(@emitter.bytes)
    builder = case @target_os
              when :linux then ELFBuilder.new(result[:combined], @arch, result[:code].length, result[:data].length, result[:bss_len],
                                             external_symbols: result[:external_symbols], got_slots: result[:got_slots], label_rvas: result[:label_rvas])
              when :flat  then FlatBuilder.new(result[:combined])
              end

    File.binwrite(output_path, builder.build)
    File.chmod(0755, output_path) if @target_os == :linux
  end

  private

  def gen_entry_point(ir)
    @emitter.emit_prologue(1024)
    has_init = ir.any? { |ins| ins.op == :LABEL && ins.args[0] == "__juno_init" }
    if has_init
      @emitter.call_rel32
      @linker.add_fn_patch(@emitter.current_pos - 4, "__juno_init", :rel32)
    end
    @emitter.call_rel32
    @linker.add_fn_patch(@emitter.current_pos - 4, "main", :rel32)
    @emitter.emit_sys_exit_rax
  end

  def register_type(node)
    # ... (same as before)
  end

  def split_into_functions(ir)
    funcs = {}
    current_fn = nil
    ir.each do |ins|
      if ins.op == :LABEL && ins.metadata[:type] == :function
        current_fn = ins.args[0]
        funcs[current_fn] = []
      elsif current_fn
        funcs[current_fn] << ins
      end
    end
    funcs
  end

  def translate_function(name, ir)
    @linker.register_function(name, @emitter.current_pos)
    @ctx.reset_for_function(name)
    vreg_map = {}
    ir.each do |ins|
      ins.args.grep(String).each { |a| vreg_map[a] ||= @ctx.declare_variable(a) if a.start_with?('v') }
      translate_instruction(ins, vreg_map)
    end
  end

  def translate_instruction(ins, vreg_map)
    case ins.op
    when :LABEL
      @linker.register_label(ins.args[0], @emitter.current_pos)
    when :SET
      @emitter.mov_rax(ins.args[1])
      @emitter.mov_stack_reg_val(vreg_map[ins.args[0]], 0)
    when :MOVE
      # Handle vregs and params
      src = ins.args[1]
      if src.is_a?(Integer) then @emitter.mov_rax(src)
      elsif vreg_map[src]    then @emitter.mov_reg_stack_val(0, vreg_map[src])
      else                      @emitter.mov_reg_stack_val(0, @ctx.get_variable_offset(src))
      end
      dst = ins.args[0]
      if vreg_map[dst]    then @emitter.mov_stack_reg_val(vreg_map[dst], 0)
      else                      @emitter.mov_stack_reg_val(@ctx.get_variable_offset(dst), 0)
      end
    when :LOAD  then @emitter.mov_reg_stack_val(0, @ctx.get_variable_offset(ins.args[1])); @emitter.mov_stack_reg_val(vreg_map[ins.args[0]], 0)
    when :STORE then @emitter.mov_reg_stack_val(0, vreg_map[ins.args[1]]); @emitter.mov_stack_reg_val(@ctx.get_variable_offset(ins.args[0]), 0)
    when :ARITH
      op, dst, s1, s2 = ins.args
      @emitter.mov_reg_stack_val(0, vreg_map[s1])
      @emitter.mov_reg_stack_val(2, vreg_map[s2])
      case op
      when "+", :ADD then @emitter.add_rax_rdx
      when "-", :SUB then @emitter.sub_rax_rdx
      when "*", :MUL then @emitter.imul_rax_rdx
      end
      @emitter.mov_stack_reg_val(vreg_map[dst], 0)
    when :CALL
      # Builtin handling or standard call
      if ins.args[1] == "prints"
        gen_prints_intrinsic(vreg_map[ins.args[0]], vreg_map["param_0"])
      else
        # Standard call
        @emitter.call_rel32
        @linker.add_fn_patch(@emitter.current_pos - 4, ins.args[1], :rel32)
      end
    when :RET
      @emitter.mov_reg_stack_val(0, vreg_map[ins.args[0]]) if vreg_map[ins.args[0]]
      @emitter.emit_epilogue(1024)
    end
  end

  def gen_prints_intrinsic(dst_off, src_off)
    # write(1, str, len)
    # We need string length. For now assume it's null-terminated or we just do a loop.
    # To keep it simple, call a helper or emit syscall.
    @emitter.mov_reg_stack_val(1, src_off) # RSI = buf
    # ... (omitting full syscall logic for brevity, using existing prints if possible)
    # Actually let's just use the linker to patch it to a real 'prints' function in stdlib
    @emitter.call_rel32
    @linker.add_fn_patch(@emitter.current_pos - 4, "prints", :rel32)
  end
end
