# hellion.rb - Formal IR Backend for Juno
require_relative "codegen/parts/emitter"
require_relative "codegen/parts/emitter_aarch64"
require_relative "codegen/parts/context"
require_relative "codegen/parts/linker"
require_relative "codegen/parts/print_utils"
require_relative "native/elf_builder"
require_relative "native/flat_builder"

class Hellion
  include PrintUtils
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
      @emitter.mov_stack_reg_val(get_off(ins.args[0], vreg_map), 0)
    when :LEA_STR
      dst, val = ins.args
      label = @linker.add_string(val)
      @emitter.emit_load_address(label, @linker)
      @emitter.mov_stack_reg_val(get_off(dst, vreg_map), 0)
    when :MOVE
      # Handle vregs and params
      load_src(0, ins.args[1], vreg_map)
      @emitter.mov_stack_reg_val(get_off(ins.args[0], vreg_map), 0)
    when :LOAD  then @emitter.mov_reg_stack_val(0, @ctx.get_variable_offset(ins.args[1])); @emitter.mov_stack_reg_val(get_off(ins.args[0], vreg_map), 0)
    when :STORE then load_src(0, ins.args[1], vreg_map); @emitter.mov_stack_reg_val(@ctx.get_variable_offset(ins.args[0]), 0)
    when :ARITH
      op, dst, s1, s2 = ins.args
      load_src(0, s1, vreg_map)
      load_src(2, s2, vreg_map)
      case op
      when "+", :ADD then @emitter.add_rax_rdx
      when "-", :SUB then @emitter.sub_rax_rdx
      when "*", :MUL then @emitter.imul_rax_rdx
      when "/", :DIV then @emitter.div_rax_by_rdx
      when "%", :MOD then @emitter.mod_rax_by_rdx
      when "==", "!=", "<", ">", "<=", ">=" then @emitter.cmp_rax_rdx(op)
      end
      @emitter.mov_stack_reg_val(get_off(dst, vreg_map), 0)
    when :CMP
      if ins.args.length >= 3 && ins.args[0].is_a?(String) && ins.args[0].start_with?('v')
        dst, s1, s2 = ins.args
      else
        s1, s2 = ins.args
      end
      load_src(0, s1, vreg_map)
      load_src(2, s2, vreg_map)
      @emitter.cmp_reg_reg(0, 2)
    when :JCC
      cond, label = ins.args
      case cond
      when "==" then p = @emitter.je_rel32
      when "!=" then p = @emitter.jne_rel32
      when "<"  then p = @emitter.jl_rel32
      when ">"  then p = @emitter.jg_rel32
      when "<=" then p = @emitter.jle_rel32
      when ">=" then p = @emitter.jge_rel32
      end
      @linker.add_fn_patch(p + 2, label, :rel32)
    when :JZ
      load_src(0, ins.args[0], vreg_map)
      @emitter.test_rax_rax
      p = @emitter.je_rel32
      @linker.add_fn_patch(p + 2, ins.args[1], :rel32)
    when :JMP
      p = @emitter.jmp_rel32
      @linker.add_fn_patch(p + 1, ins.args[0], :rel32)
    when :CALL
      # Builtin handling or standard call
      case ins.args[1]
      when "prints", "output", "print"
        gen_output_intrinsic(get_off(ins.args[0], vreg_map), @ctx.get_variable_offset("param_0"))
      when "output_int"
        gen_output_int_intrinsic(get_off(ins.args[0], vreg_map), @ctx.get_variable_offset("param_0"))
      when "file_read_all"
        gen_file_read_all_intrinsic(get_off(ins.args[0], vreg_map), @ctx.get_variable_offset("param_0"))
      else
        # Standard call
        @emitter.call_rel32
        @linker.add_fn_patch(@emitter.current_pos - 4, ins.args[1], :rel32)
      end
    when :RET
      load_src(0, ins.args[0], vreg_map) if ins.args[0]
      @emitter.emit_epilogue(1024)
    end
  end

  def load_src(reg, src, vreg_map)
    if src.is_a?(Integer)
      @emitter.mov_reg_imm(reg, src)
    else
      @emitter.mov_reg_stack_val(reg, get_off(src, vreg_map))
    end
  end

  def get_off(id, vreg_map)
    return nil if id.nil?
    vreg_map[id] || @ctx.get_variable_offset(id)
  end

  def gen_output_intrinsic(dst_off, src_off)
    # write(1, str, len)
    @emitter.push_reg(0); @emitter.push_reg(7); @emitter.push_reg(6)
    @emitter.push_reg(2); @emitter.push_reg(10); @emitter.push_reg(11)

    @emitter.mov_reg_stack_val(11, src_off)

    # Calculate length
    @emitter.mov_reg_reg(10, 11) # R10 = temp ptr
    l_start = @emitter.current_pos
    @emitter.xor_rax_rax
    @emitter.mov_reg_mem_idx(0, 10, 0, 1) # RAX = [R10]
    @emitter.test_rax_rax
    l_end = @emitter.je_rel32
    @emitter.add_reg_imm(10, 1) # increment temp ptr
    l_jmp = @emitter.jmp_rel32
    @emitter.patch_jmp(l_jmp, l_start)
    @emitter.patch_je(l_end, @emitter.current_pos)

    # len = R10 - original_buf
    @emitter.mov_reg_reg(2, 10) # RDX = temp_ptr
    @emitter.mov_reg_reg(0, 11) # RAX = original_buf
    @emitter.sub_reg_reg(2, 0) # RDX = len

    @emitter.mov_reg_reg(6, 11) # RSI = original_buf
    @emitter.mov_reg_imm(7, 1) # RDI = 1 (stdout)
    @emitter.mov_reg_imm(0, 1) # RAX = 1 (write)
    @emitter.syscall

    # Print newline
    @emitter.mov_reg_imm(7, 1)
    @emitter.emit_load_address("newline_char", @linker)
    @emitter.mov_reg_reg(6, 0)
    @emitter.mov_reg_imm(2, 1)
    @emitter.mov_reg_imm(0, 1)
    @emitter.syscall

    @emitter.pop_reg(11); @emitter.pop_reg(10); @emitter.pop_reg(2)
    @emitter.pop_reg(6); @emitter.pop_reg(7); @emitter.pop_reg(0)
  end

  def gen_output_int_intrinsic(dst_off, src_off)
    @emitter.mov_reg_stack_val(0, src_off) # RAX = val
    gen_print_int_compatibility(nil)
  end

  def gen_file_read_all_intrinsic(dst_off, src_off)
    # Simplified file_read_all for Hellion
    @linker.add_bss("file_read_buf", 65536)
    @emitter.mov_reg_stack_val(7, src_off) # RDI = path
    @emitter.mov_reg_imm(6, 0) # RSI = O_RDONLY
    @emitter.mov_reg_imm(2, 0) # RDX = mode
    @emitter.mov_reg_imm(0, 2) # RAX = open
    @emitter.syscall

    @emitter.mov_reg_reg(7, 0) # RDI = fd
    @emitter.emit_load_address("file_read_buf", @linker)
    @emitter.mov_reg_reg(6, 0) # RSI = buf
    @emitter.mov_reg_imm(2, 65535) # RDX = size
    @emitter.mov_reg_imm(0, 0) # RAX = read
    @emitter.syscall

    # Close
    @emitter.push_reg(0) # save read size
    @emitter.mov_reg_imm(0, 3) # RAX = close
    @emitter.syscall
    @emitter.pop_reg(2) # RDX = read size

    @emitter.emit_load_address("file_read_buf", @linker)
    # Null terminate
    @emitter.push_reg(0)
    @emitter.add_reg_reg(0, 2)
    @emitter.mov_reg_reg(7, 0) # RDI = buf + read_size
    @emitter.xor_rax_rax
    @emitter.mov_mem_rax_sized(1) # [RDI] = 0
    @emitter.pop_reg(0)

    @emitter.mov_stack_reg_val(dst_off, 0)
  end
end
