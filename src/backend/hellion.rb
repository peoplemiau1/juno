# hellion.rb - Formal IR Backend for Juno
require_relative "codegen/parts/emitter"
require_relative "codegen/parts/emitter_aarch64"
require_relative "codegen/parts/context"
require_relative "codegen/parts/linker"
require_relative "native/elf_builder"
require_relative "native/flat_builder"
require_relative "codegen/parts/print_utils"
require_relative "codegen/parts/builtins/strings"
require_relative "../optimizer/register_allocator"

require_relative "codegen/parts/builtins/strings_v2"

class Hellion
  include PrintUtils
  include BuiltinStrings
  include BuiltinStringsV2

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
    @linker.add_bss("file_buffer", 8192)
    @linker.add_data("newline_char", "\n")
    @linker.add_data("concat_buffer_idx", [0].pack("Q<"))
    @linker.add_bss("concat_buffer_pool", 65536)
  end

  def generate(ir, output_path)
    # 1. Registration
    ir.each do |ins|
      case ins.op
      when :TYPE_DEF then register_type(ins.args[0])
      when :EXTERN   then @linker.declare_import(ins.args[0], ins.args[1])
      end
    end

    # Implicit libc imports
    ["open", "read", "write", "close", "malloc", "realloc", "free", "strlen", "exit", "sleep", "time"].each do |f|
      @linker.declare_import(f, "libc.so.6")
    end

    # Register builtins
    @linker.declare_function("__juno_concat")

    # 2. Entry Point
    gen_entry_point(ir)

    # 3. Functions
    split_into_functions(ir).each do |name, func_ir|
      # Skip already generated labels (like __juno_init)
      next if ["__juno_init", "main"].include?(name) && ir.any? { |ins| ins.op == :LABEL && ins.args[0] == name && ins.metadata[:type] != :function }
      translate_function(name, func_ir)
    end

    # 3.5 Builtins
    gen_builtins

    # 4. Finalize
    result = @linker.finalize(@emitter.bytes)
    builder = case @target_os
              when :linux then ELFBuilder.new(result[:combined], @arch, result[:code].length, result[:data].length, result[:bss_len],
                                             external_symbols: result[:external_symbols], got_slots: result[:got_slots], label_rvas: result[:label_rvas])
              when :flat  then FlatBuilder.new(result[:combined])
              end

    File.binwrite(output_path, builder.build)
    File.chmod(0755, output_path) if @target_os == :linux

    # Save assembly log for debugging
    File.write("#{output_path}.s", @emitter.asm_log.join("\n")) if @emitter.respond_to?(:asm_log)
  end

  private

  def load_vreg(reg, vreg_name)
    val = @vreg_map[vreg_name]
    if val.is_a?(Symbol)
      @emitter.mov_reg_reg(reg, CodeEmitter.reg_code(val))
    elsif val.is_a?(Integer)
      @emitter.mov_reg_stack_val(reg, val)
    elsif vreg_name.is_a?(Integer) # Already an offset
      @emitter.mov_reg_stack_val(reg, vreg_name)
    end
  end

  def store_vreg(vreg_name, reg)
    val = @vreg_map[vreg_name]
    if val.is_a?(Symbol)
      @emitter.mov_reg_reg(CodeEmitter.reg_code(val), reg)
    elsif val.is_a?(Integer)
      @emitter.mov_stack_reg_val(val, reg)
    elsif vreg_name.is_a?(Integer) # Already an offset
      @emitter.mov_stack_reg_val(vreg_name, reg)
    end
  end

  def gen_entry_point(ir)
    # Entry point aligned to 16 before calls
    entry_stack = 1024 + 8
    @emitter.emit_prologue(entry_stack)

    has_init = ir.any? { |ins| ins.op == :LABEL && ins.args[0] == "__juno_init" }
    if has_init
      @emitter.call_rel32
      @linker.add_fn_patch(@emitter.current_pos - 4, "__juno_init", :rel32)
    end

    has_main = ir.any? { |ins| ins.op == :LABEL && ins.args[0] == "main" }
    if has_main
      @emitter.call_rel32
      @linker.add_fn_patch(@emitter.current_pos - 4, "main", :rel32)
    end

    @emitter.emit_sys_exit_rax
  end

  def register_type(node)
    case node[:type]
    when :struct_definition
      fields = {}
      off = 0
      node[:fields].each do |f|
        fields[f] = off
        off += 8
      end
      @ctx.register_struct(node[:name], off, fields)
    when :array_decl
      # Metadata for array, backend uses it to reserve space
    end
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
    @vreg_map = {}

    # Identify parameters in IR
    params = []
    ir.each { |ins| ins.args.each { |a| params << a if a.is_a?(String) && a.start_with?('param_') } }
    params.uniq!
    params.sort_by! { |p| p.split('_')[1].to_i }

    # 1. Register Allocation
    allocator = RegisterAllocator.new(@arch)
    # Filter IR for allocation: labels don't define vars usually, and we need strings
    # RegisterAllocator find_vars handles Instruction objects already.
    # Exclude scratch registers from general allocation
    # allocator.instance_variable_set(:@allocatable_regs,
    #   (@arch == :aarch64) ? allocator.class::AARCH64_REGS : allocator.class::X86_64_REGS)
    res = allocator.allocate(ir)
    res[:allocations].each { |var, reg| @ctx.assign_register(var, reg) }

    # 2. Variable Mapping (Vregs and Params)
    ir.each do |ins|
      # Handle array declarations explicitly to reserve multiple slots
      if ins.op == :TYPE_DEF && ins.args[0].is_a?(Hash) && ins.args[0][:type] == :array_decl
        name = ins.args[0][:name]
        (ins.args[0][:size]).times do |i|
          @vreg_map["#{name}__elem_#{i}"] = @ctx.declare_variable("#{name}__elem_#{i}")
        end
        next
      end

      # Handle struct stack allocation (LEA_STACK with __struct_data)
      if ins.op == :LEA_STACK && ins.args[1].is_a?(String) && ins.args[1].end_with?("__struct_data")
        var_name = ins.args[1].sub("__struct_data", "")
        # Find struct type
        type_name = @ctx.var_types[var_name]
        struct_info = @ctx.structs[type_name]
        if struct_info
          # Allocate space for struct members
          struct_info[:fields].each do |field_name, offset|
            @vreg_map["#{var_name}.#{field_name}"] = @ctx.declare_variable("#{var_name}.#{field_name}")
          end
        end
        # Map the LEA_STACK internal label to the first member's offset
        if struct_info && !struct_info[:fields].empty?
          @vreg_map[ins.args[1]] = @ctx.get_variable_offset("#{var_name}.#{struct_info[:fields].keys.first}")
        end
      end

      ins.args.each do |a|
        next unless a.is_a?(String)
        # Any string starting with v, param_, or a local name should be mapped
        if a.start_with?('v') || a.start_with?('param_') || (!a.include?('.') && !a.include?('_'))
           @vreg_map[a] ||= @ctx.in_register?(a) ? @ctx.get_register(a) : @ctx.declare_variable(a)
        end
      end
    end
    # Ensure all vregs are mapped if they were skipped by heuristic
    res[:allocations].keys.each do |v|
      @vreg_map[v] ||= @ctx.in_register?(v) ? @ctx.get_register(v) : @ctx.declare_variable(v)
    end

    func_label = ir.find { |ins| ins.op == :LABEL && ins.args[0] == name }
    stack_size = (func_label && func_label.metadata[:stack_size]) || 0
    # Add space for all identified vregs/locals
    stack_size += @vreg_map.length * 8
    stack_size = (stack_size + 15) & ~15

    @emitter.emit_prologue(stack_size)
    @current_stack_size = stack_size

    # 2.5 Load parameters into their assigned locations
    # Use CodeEmitter constants for registers
    regs = [CodeEmitter::REG_RDI, CodeEmitter::REG_RSI, CodeEmitter::REG_RDX,
            CodeEmitter::REG_RCX, CodeEmitter::REG_R8, CodeEmitter::REG_R9]
    params.each do |p|
      idx = p.split('_')[1].to_i
      dst = @vreg_map[p]
      if idx < 6
        if dst.is_a?(Symbol)
          @emitter.mov_reg_reg(CodeEmitter.reg_code(dst), regs[idx])
        else
          @emitter.mov_stack_reg_val(dst, regs[idx])
        end
      else
        @emitter.mov_rax_rbp_disp32(16 + (idx - 6) * 8)
        if dst.is_a?(Symbol)
          @emitter.mov_reg_reg(CodeEmitter.reg_code(dst), CodeEmitter::REG_RAX)
        else
          @emitter.mov_stack_reg_val(dst, CodeEmitter::REG_RAX)
        end
      end
    end

    # Save callee-saved registers
    # ABI: RSP must be 16-byte aligned BEFORE call.
    # Initial RSP = 16n + 8.
    # push rbp -> RSP = 16n.
    # sub rsp, stack_size (multiple of 16) -> RSP = 16n.
    # Now we push saved_regs.
    # To keep aligned, we need to push an EVEN number of 8-byte values.
    saved_regs = @ctx.used_callee_saved
    padding = (saved_regs.length % 2 != 0) ? 8 : 0

    @emitter.emit_sub_rsp(padding) if padding > 0
    @current_padding = padding # Corrected to ensure epilogue knows about it
    @emitter.push_callee_saved(saved_regs)
    @current_padding = padding

    ir.each do |ins|
      method_name = "visit_#{ins.op.to_s.downcase}"
      if respond_to?(method_name, true)
        send(method_name, ins)
      end
    end

    unless ir.any? { |ins| ins.op == :RET }
      @emitter.xor_rax_rax
      @emitter.emit_epilogue(stack_size)
    end
  end

  # --- Visitors ---

  def visit_label(ins)
    if @linker.respond_to?(:register_label)
      @linker.register_label(ins.args[0], @emitter.current_pos)
    else
      @linker.register_function(ins.args[0], @emitter.current_pos)
    end
    @emitter.log_asm("#{ins.args[0]}:")
  end


  def visit_set(ins)
    dst = @vreg_map[ins.args[0]]
    # Store type if available
    @ctx.var_types[ins.args[0]] = ins.metadata[:inferred_type] if ins.metadata[:inferred_type]

    if dst.is_a?(Symbol)
      @emitter.mov_reg_imm(CodeEmitter.reg_code(dst), ins.args[1])
    else
      @emitter.mov_rax(ins.args[1])
      @emitter.mov_stack_reg_val(dst, CodeEmitter::REG_RAX)
    end
  end

  def visit_move(ins)
    src = ins.args[1]
    dst = @vreg_map[ins.args[0]]

    if src.is_a?(Integer)
      if dst.is_a?(Symbol)
        @emitter.mov_reg_imm(CodeEmitter.reg_code(dst), src)
      else
        @emitter.mov_rax(src)
        @emitter.mov_stack_reg_val(dst, CodeEmitter::REG_RAX)
      end
    else
      src_val = @vreg_map[src]
      if src_val.is_a?(Symbol)
        if dst.is_a?(Symbol)
          @emitter.mov_reg_reg(CodeEmitter.reg_code(dst), CodeEmitter.reg_code(src_val))
        else
          @emitter.mov_stack_reg_val(dst, CodeEmitter.reg_code(src_val))
        end
      else
        # src_val is stack offset
        if dst.is_a?(Symbol)
          @emitter.mov_reg_stack_val(CodeEmitter.reg_code(dst), src_val)
        else
          @emitter.mov_reg_stack_val(CodeEmitter::REG_RAX, src_val)
          @emitter.mov_stack_reg_val(dst, CodeEmitter::REG_RAX)
        end
      end
    end
  end

  def visit_mov(ins); visit_move(ins); end

  def visit_load(ins)
    src_v = @vreg_map[ins.args[1]]
    dst_v = @vreg_map[ins.args[0]]
    @ctx.var_types[ins.args[0]] = ins.metadata[:inferred_type] if ins.metadata[:inferred_type]

    if src_v.is_a?(Symbol)
      if dst_v.is_a?(Symbol)
        @emitter.mov_reg_reg(CodeEmitter.reg_code(dst_v), CodeEmitter.reg_code(src_v))
      else
        @emitter.mov_stack_reg_val(dst_v, CodeEmitter.reg_code(src_v))
      end
    else
      # src_v is stack offset
      if dst_v.is_a?(Symbol)
        @emitter.mov_reg_stack_val(CodeEmitter.reg_code(dst_v), src_v)
      else
        @emitter.mov_reg_stack_val(CodeEmitter::REG_RAX, src_v)
        @emitter.mov_stack_reg_val(dst_v, CodeEmitter::REG_RAX)
      end
    end
  end

  def visit_store(ins)
    src_v = @vreg_map[ins.args[1]]
    dst_v = @vreg_map[ins.args[0]]

    if dst_v.is_a?(Symbol)
      if src_v.is_a?(Symbol)
        @emitter.mov_reg_reg(CodeEmitter.reg_code(dst_v), CodeEmitter.reg_code(src_v))
      else
        @emitter.mov_reg_stack_val(CodeEmitter.reg_code(dst_v), src_v)
      end
    else
      # dst_v is stack offset
      if src_v.is_a?(Symbol)
        @emitter.mov_stack_reg_val(dst_v, CodeEmitter.reg_code(src_v))
      else
        @emitter.mov_reg_stack_val(CodeEmitter::REG_RAX, src_v)
        @emitter.mov_stack_reg_val(dst_v, CodeEmitter::REG_RAX)
      end
    end
  end

  def visit_arith(ins)
    op, dst, s1, s2 = ins.args
    # Scaling is already handled by IRGenerator for JIR,
    # but we might still have some old-style calls or special cases.

    src1_val = @vreg_map[s1]
    if src1_val.is_a?(Symbol)
      @emitter.mov_reg_reg(CodeEmitter::REG_RAX, CodeEmitter.reg_code(src1_val))
    else
      @emitter.mov_reg_stack_val(CodeEmitter::REG_RAX, src1_val)
    end

    if s2.is_a?(Integer)
      @emitter.mov_reg_imm(CodeEmitter::REG_RDX, s2)
    else
      src2_val = @vreg_map[s2]
      if src2_val.is_a?(Symbol)
        @emitter.mov_reg_reg(CodeEmitter::REG_RDX, CodeEmitter.reg_code(src2_val))
      else
        @emitter.mov_reg_stack_val(CodeEmitter::REG_RDX, src2_val)
      end
    end
    case op.to_s
    when "+", "ADD" then @emitter.add_rax_rdx
    when "-", "SUB" then @emitter.sub_rax_rdx
    when "*", "MUL" then @emitter.imul_rax_rdx
    when "/", "DIV" then @emitter.div_rax_by_rdx
    when "%", "MOD" then @emitter.mod_rax_by_rdx
    when "&", "AND" then @emitter.and_rax_rdx
    when "|", "OR"  then @emitter.or_rax_rdx
    when "^", "XOR" then @emitter.xor_rax_rdx
    when "<<", "SHL" then @emitter.shl_rax_cl
    when ">>", "SHR" then @emitter.shr_rax_cl
    when "CONCAT" then gen_concat_safe
    end
    dst_val = @vreg_map[dst]
    if dst_val.is_a?(Symbol)
      @emitter.mov_reg_reg(CodeEmitter.reg_code(dst_val), CodeEmitter::REG_RAX)
    else
      @emitter.mov_stack_reg_val(dst_val, CodeEmitter::REG_RAX)
    end
  end

  def visit_add(ins); visit_arith([:ADD] + ins.args); end
  def visit_sub(ins); visit_arith([:SUB] + ins.args); end
  def visit_mul(ins); visit_arith([:MUL] + ins.args); end

  def visit_lea(ins)
    dst = @vreg_map[ins.args[0]]
    @emitter.emit_load_address(ins.args[1], @linker)
    if dst.is_a?(Symbol)
      @emitter.mov_reg_reg(CodeEmitter.reg_code(dst), CodeEmitter::REG_RAX)
    elsif dst.is_a?(Integer)
      @emitter.mov_stack_reg_val(dst, CodeEmitter::REG_RAX)
    end
  end

  def visit_lea_str(ins)
    dst = @vreg_map[ins.args[0]]
    # emit_load_address puts result in RAX.
    @emitter.emit_load_address(@linker.add_string(ins.args[1]), @linker)
    if dst.is_a?(Symbol)
      @emitter.mov_reg_reg(CodeEmitter.reg_code(dst), CodeEmitter::REG_RAX)
    elsif dst.is_a?(Integer)
      @emitter.mov_stack_reg_val(dst, CodeEmitter::REG_RAX)
    end
  end

  def visit_lea_stack(ins)
    dst = @vreg_map[ins.args[0]]
    # Check if second arg is a variable name or already an offset
    off = ins.args[1].is_a?(String) ? @ctx.get_variable_offset(ins.args[1]) : ins.args[1]

    @emitter.lea_reg_stack(CodeEmitter::REG_RAX, off)
    if dst.is_a?(Symbol)
      @emitter.mov_reg_reg(CodeEmitter.reg_code(dst), CodeEmitter::REG_RAX)
    elsif dst.is_a?(Integer)
      @emitter.mov_stack_reg_val(dst, CodeEmitter::REG_RAX)
    end
  end

  def visit_cmp(ins)
    src1_v = @vreg_map[ins.args[0]]
    if src1_v.is_a?(Symbol)
      @emitter.mov_reg_reg(CodeEmitter::REG_RAX, CodeEmitter.reg_code(src1_v))
    else
      @emitter.mov_reg_stack_val(CodeEmitter::REG_RAX, src1_v)
    end

    if ins.args[1].is_a?(Integer)
      @emitter.cmp_reg_imm(CodeEmitter::REG_RAX, ins.args[1])
    else
      src2_v = @vreg_map[ins.args[1]]
      if src2_v.is_a?(Symbol)
        @emitter.mov_reg_reg(CodeEmitter::REG_RDX, CodeEmitter.reg_code(src2_v))
      else
        @emitter.mov_reg_stack_val(CodeEmitter::REG_RDX, src2_v)
      end
      @emitter.cmp_reg_reg(CodeEmitter::REG_RAX, CodeEmitter::REG_RDX)
    end
  end

  def visit_jcc(ins)
    pos = case ins.args[0].to_s
          when "==", "EQ" then @emitter.je_rel32
          when "!=", "NE" then @emitter.jne_rel32
          when "<",  "LT" then @emitter.jl_rel32
          when ">",  "GT" then @emitter.jg_rel32
          when "<=", "LE" then @emitter.jle_rel32
          when ">=", "GE" then @emitter.jge_rel32
          else @emitter.je_rel32
          end
    @linker.add_fn_patch(pos + 2, ins.args[1], :rel32)
  end

  def visit_jmp(ins)
    pos = @emitter.jmp_rel32
    @linker.add_fn_patch(pos + 1, ins.args[0], :rel32)
  end

  def visit_jz(ins)
    src_v = @vreg_map[ins.args[0]]
    if src_v.is_a?(Symbol)
      @emitter.mov_reg_reg(CodeEmitter::REG_RAX, CodeEmitter.reg_code(src_v))
    else
      @emitter.mov_reg_stack_val(CodeEmitter::REG_RAX, src_v)
    end
    @emitter.test_reg_reg(CodeEmitter::REG_RAX, CodeEmitter::REG_RAX)
    pos = @emitter.je_rel32
    @linker.add_fn_patch(pos + 2, ins.args[1], :rel32)
  end

  def visit_jnz(ins)
    src_v = @vreg_map[ins.args[0]]
    if src_v.is_a?(Symbol)
      @emitter.mov_reg_reg(CodeEmitter::REG_RAX, CodeEmitter.reg_code(src_v))
    else
      @emitter.mov_reg_stack_val(CodeEmitter::REG_RAX, src_v)
    end
    @emitter.test_reg_reg(CodeEmitter::REG_RAX, CodeEmitter::REG_RAX)
    pos = @emitter.jne_rel32
    @linker.add_fn_patch(pos + 2, ins.args[1], :rel32)
  end

  def gen_concat_safe
    @emitter.log_asm("; Intrinsic Concat Safe")
    @emitter.push_reg(CodeEmitter::REG_RAX)
    @emitter.push_reg(CodeEmitter::REG_RDX)
    @emitter.emit_load_address("concat_buffer_idx", @linker)
    @emitter.mov_rax_mem(0)
    @emitter.cmp_reg_imm(0, 64000)
    p_ok = @emitter.jl_rel32
    @emitter.mov_rax(1); @emitter.emit_sys_exit_rax
    @emitter.patch_jl(p_ok, @emitter.current_pos)
    @emitter.pop_reg(CodeEmitter::REG_RSI) # right
    @emitter.pop_reg(CodeEmitter::REG_RDI) # left
    @emitter.call_rel32
    @linker.add_fn_patch(@emitter.current_pos - 4, "__juno_concat", :rel32)
  end

  def visit_call(ins)
    name = ins.args[1]
    case name
    when "prints", "print", "output"
      @emitter.log_asm("; Print function")
      # Force spill RAX if needed? No, we use RAX here.
      src_v = @vreg_map["param_0"]
      if src_v.is_a?(Symbol)
        @emitter.mov_reg_reg(CodeEmitter::REG_RAX, CodeEmitter.reg_code(src_v))
      else
        @emitter.mov_reg_stack_val(CodeEmitter::REG_RAX, src_v)
      end
      @emitter.test_reg_reg(CodeEmitter::REG_RAX, CodeEmitter::REG_RAX)
      p_ok = @emitter.jne_rel32
      @emitter.mov_rax(1); @emitter.emit_sys_exit_rax
      @emitter.patch_jne(p_ok, @emitter.current_pos)

      @emitter.mov_reg_reg(CodeEmitter::REG_RSI, CodeEmitter::REG_RAX)
      @emitter.mov_reg_imm(CodeEmitter::REG_RCX, 0)
      l = @emitter.current_pos
      @emitter.cmp_mem8_imm8(CodeEmitter::REG_RSI, CodeEmitter::REG_RCX, 0)
      p_done = @emitter.je_rel32
      @emitter.add_reg_imm(CodeEmitter::REG_RCX, 1)
      lj = @emitter.jmp_rel32
      @emitter.patch_jmp(lj, l)
      @emitter.patch_je(p_done, @emitter.current_pos)

      @emitter.mov_reg_reg(CodeEmitter::REG_RDX, CodeEmitter::REG_RCX)
      # RSI already has buf
      @emitter.mov_reg_imm(CodeEmitter::REG_RDI, 1)
      @emitter.mov_reg_imm(CodeEmitter::REG_RAX, 1)
      @emitter.syscall

      @emitter.emit_load_address("newline_char", @linker)
      @emitter.mov_reg_reg(CodeEmitter::REG_RSI, CodeEmitter::REG_RAX)
      @emitter.mov_reg_imm(CodeEmitter::REG_RDI, 1)
      @emitter.mov_reg_imm(CodeEmitter::REG_RDX, 1)
      @emitter.mov_reg_imm(CodeEmitter::REG_RAX, 1)
      @emitter.syscall
    when "output_int"
      src_val = @vreg_map["param_0"]
      if src_val.is_a?(Symbol)
        @emitter.mov_reg_reg(CodeEmitter::REG_RAX, CodeEmitter.reg_code(src_val))
      else
        @emitter.mov_reg_stack_val(CodeEmitter::REG_RAX, src_val)
      end
      gen_print_int_compatibility(nil)
    when "syscall"
      load_vreg(CodeEmitter::REG_RAX, "param_0")
      load_vreg(CodeEmitter::REG_RDI, "param_1")
      load_vreg(CodeEmitter::REG_RSI, "param_2")
      load_vreg(CodeEmitter::REG_RDX, "param_3")
      @emitter.syscall
      store_vreg(ins.args[0], CodeEmitter::REG_RAX) if ins.args[0]
    when "malloc"
      load_vreg(CodeEmitter::REG_RDI, "param_0")
      @emitter.call_rel32
      @linker.add_fn_patch(@emitter.current_pos - 4, "malloc", :rel32)
      store_vreg(ins.args[0], CodeEmitter::REG_RAX) if ins.args[0]
    when "open"
      load_vreg(CodeEmitter::REG_RDI, "param_0")
      @emitter.call_rel32
      @linker.add_fn_patch(@emitter.current_pos - 4, "open", :rel32)
      store_vreg(ins.args[0], CodeEmitter::REG_RAX) if ins.args[0]
    when "read"
      load_vreg(CodeEmitter::REG_RDI, "param_0")
      load_vreg(CodeEmitter::REG_RSI, "param_1")
      load_vreg(CodeEmitter::REG_RDX, "param_2")
      @emitter.call_rel32
      @linker.add_fn_patch(@emitter.current_pos - 4, "read", :rel32)
      store_vreg(ins.args[0], CodeEmitter::REG_RAX) if ins.args[0]
    when "write"
      load_vreg(CodeEmitter::REG_RDI, "param_0")
      load_vreg(CodeEmitter::REG_RSI, "param_1")
      load_vreg(CodeEmitter::REG_RDX, "param_2")
      @emitter.call_rel32
      @linker.add_fn_patch(@emitter.current_pos - 4, "write", :rel32)
      store_vreg(ins.args[0], CodeEmitter::REG_RAX) if ins.args[0]
    when "close"
      load_vreg(CodeEmitter::REG_RDI, "param_0")
      @emitter.call_rel32
      @linker.add_fn_patch(@emitter.current_pos - 4, "close", :rel32)
      store_vreg(ins.args[0], CodeEmitter::REG_RAX) if ins.args[0]
    when "free"
      load_vreg(CodeEmitter::REG_RDI, "param_0")
      @emitter.call_rel32
      @linker.add_fn_patch(@emitter.current_pos - 4, "free", :rel32)
    when "alloc"
      load_vreg(CodeEmitter::REG_RDI, "param_0")
      @emitter.call_rel32
      @linker.add_fn_patch(@emitter.current_pos - 4, "malloc", :rel32)
      store_vreg(ins.args[0], CodeEmitter::REG_RAX) if ins.args[0]
    when "realloc"
      load_vreg(CodeEmitter::REG_RDI, "param_0")
      load_vreg(CodeEmitter::REG_RSI, "param_1")
      @emitter.call_rel32
      @linker.add_fn_patch(@emitter.current_pos - 4, "realloc", :rel32)
      store_vreg(ins.args[0], CodeEmitter::REG_RAX) if ins.args[0]
    when "getbuf"
      @emitter.emit_load_address("file_buffer", @linker)
      dst = @vreg_map[ins.args[0]]
      if dst.is_a?(Symbol)
        @emitter.mov_reg_reg(CodeEmitter.reg_code(dst), CodeEmitter::REG_RAX)
      else
        @emitter.mov_stack_reg_val(dst, CodeEmitter::REG_RAX)
      end
    when "str_cmp"
      gen_str_cmp(node_from_ins(ins))
      dst = @vreg_map[ins.args[0]]
      if dst.is_a?(Symbol)
        @emitter.mov_reg_reg(CodeEmitter.reg_code(dst), CodeEmitter::REG_RAX)
      else
        @emitter.mov_stack_reg_val(dst, CodeEmitter::REG_RAX)
      end
    when "ptr_add"
      # param_0 + param_1
      v0 = @vreg_map["param_0"]
      if v0.is_a?(Symbol)
        @emitter.mov_reg_reg(CodeEmitter::REG_RAX, CodeEmitter.reg_code(v0))
      else
        @emitter.mov_reg_stack_val(CodeEmitter::REG_RAX, v0)
      end
      v1 = @vreg_map["param_1"]
      if v1.is_a?(Symbol)
        @emitter.mov_reg_reg(CodeEmitter::REG_RDX, CodeEmitter.reg_code(v1))
      else
        @emitter.mov_reg_stack_val(CodeEmitter::REG_RDX, v1)
      end
      @emitter.add_rax_rdx
      dst = @vreg_map[ins.args[0]]
      if dst.is_a?(Symbol)
        @emitter.mov_reg_reg(CodeEmitter.reg_code(dst), CodeEmitter::REG_RAX)
      else
        @emitter.mov_stack_reg_val(dst, CodeEmitter::REG_RAX)
      end
    when "u8", "i8", "i32"
      src_val = @vreg_map["param_0"]
      if src_val.is_a?(Symbol)
        @emitter.mov_reg_reg(CodeEmitter::REG_RAX, CodeEmitter.reg_code(src_val))
      else
        @emitter.mov_reg_stack_val(CodeEmitter::REG_RAX, src_val)
      end
      op = { "u8" => [0x48, 0x0f, 0xb6, 0xc0], "i8" => [0x48, 0x0f, 0xbe, 0xc0], "i32" => [0x48, 0x63, 0xc0] }[name]
      @emitter.emit(op)
      dst = @vreg_map[ins.args[0]]
      if dst.is_a?(Symbol)
        @emitter.mov_reg_reg(CodeEmitter.reg_code(dst), CodeEmitter::REG_RAX)
      else
        @emitter.mov_stack_reg_val(dst, CodeEmitter::REG_RAX)
      end
    else
      # System V ABI for x86_64
      regs = [CodeEmitter::REG_RDI, CodeEmitter::REG_RSI, CodeEmitter::REG_RDX,
              CodeEmitter::REG_RCX, CodeEmitter::REG_R8, CodeEmitter::REG_R9]
      (ins.args[2] || 0).times do |i|
        if i < 6
          src_val = @vreg_map["param_#{i}"]
          if src_val.is_a?(Symbol)
            @emitter.mov_reg_reg(regs[i], CodeEmitter.reg_code(src_val))
          else
            @emitter.mov_reg_stack_val(regs[i], src_val)
          end
        end
      end
      @emitter.call_rel32
      @linker.add_fn_patch(@emitter.current_pos - 4, name, :rel32)

      dst = @vreg_map[ins.args[0]]
      if dst
        if dst.is_a?(Symbol)
          @emitter.mov_reg_reg(CodeEmitter.reg_code(dst), CodeEmitter::REG_RAX)
        elsif dst.is_a?(Integer)
          @emitter.mov_stack_reg_val(dst, CodeEmitter::REG_RAX)
        end
      end
    end
  end

  def visit_alloc_stack(ins); @emitter.emit_sub_rsp(ins.args[0]); end
  def visit_free_stack(ins); @emitter.emit_add_rsp(ins.args[0]); end

  def visit_load_mem(ins)
    # dest, base, offset, size
    base_v = @vreg_map[ins.args[1]]
    dst_v = @vreg_map[ins.args[0]]
    @ctx.var_types[ins.args[0]] = ins.metadata[:inferred_type] if ins.metadata[:inferred_type]

    if base_v.is_a?(Symbol)
      @emitter.mov_reg_reg(CodeEmitter::REG_RAX, CodeEmitter.reg_code(base_v))
    else
      @emitter.mov_reg_stack_val(CodeEmitter::REG_RAX, base_v)
    end
    @emitter.mov_reg_mem_idx(CodeEmitter::REG_RDX, CodeEmitter::REG_RAX, ins.args[2], ins.args[3] || 8)
    if dst_v.is_a?(Symbol)
      @emitter.mov_reg_reg(CodeEmitter.reg_code(dst_v), CodeEmitter::REG_RDX)
    else
      @emitter.mov_stack_reg_val(dst_v, CodeEmitter::REG_RDX)
    end
  end

  def visit_store_mem(ins)
    # base, offset, src, size
    base_v = @vreg_map[ins.args[0]]
    src_v = @vreg_map[ins.args[2]]
    if base_v.is_a?(Symbol)
      @emitter.mov_reg_reg(CodeEmitter::REG_RAX, CodeEmitter.reg_code(base_v))
    else
      @emitter.mov_reg_stack_val(CodeEmitter::REG_RAX, base_v)
    end
    if src_v.is_a?(Symbol)
      @emitter.mov_reg_reg(CodeEmitter::REG_RDX, CodeEmitter.reg_code(src_v))
    else
      @emitter.mov_reg_stack_val(CodeEmitter::REG_RDX, src_v)
    end
    @emitter.mov_mem_reg_idx(CodeEmitter::REG_RAX, ins.args[1], CodeEmitter::REG_RDX, ins.args[3] || 8)
  end

  def visit_panic(ins); @emitter.mov_rax(1); @emitter.emit_sys_exit_rax; end
  def visit_todo(ins); @emitter.mov_rax(2); @emitter.emit_sys_exit_rax; end

  def visit_ret(ins)
    src_val = @vreg_map[ins.args[0]]
    if src_val.is_a?(Symbol)
      @emitter.mov_reg_reg(CodeEmitter::REG_RAX, CodeEmitter.reg_code(src_val))
    elsif src_val.is_a?(Integer)
      @emitter.mov_reg_stack_val(CodeEmitter::REG_RAX, src_val)
    end
    @emitter.pop_callee_saved(@ctx.used_callee_saved)
    @emitter.emit_add_rsp(@current_padding) if @current_padding > 0
    @emitter.emit_epilogue(@current_stack_size)
  end

  def visit_func_addr(ins)
    @emitter.emit_load_address(ins.args[1], @linker)
    @emitter.mov_stack_reg_val(@vreg_map[ins.args[0]], 0)
  end

  def node_from_ins(ins)
    args = []
    # Collect param_0, param_1... up to arg_count if available
    count = ins.args[2].is_a?(Integer) ? ins.args[2] : 2
    count.times { |i| args << { type: :vreg, name: "param_#{i}" } }
    { type: :fn_call, name: ins.args[1], args: args }
  end

  def eval_expression(node)
    if node[:type] == :vreg
      load_vreg(CodeEmitter::REG_RAX, node[:name])
    else
      # Fallback for simple values
      @emitter.mov_rax(node[:value]) if node[:type] == :literal
    end
  end

  def gen_builtins
    @linker.register_function("__juno_concat", @emitter.current_pos)
    @emitter.log_asm("__juno_concat:")
    @emitter.push_reg(CodeEmitter::REG_RDI)
    @emitter.push_reg(CodeEmitter::REG_RSI)
    @emitter.push_reg(CodeEmitter::REG_RBX)

    # 1. Dest buffer
    @emitter.emit_load_address("concat_buffer_idx", @linker)
    @emitter.mov_reg_mem_idx(CodeEmitter::REG_RDX, CodeEmitter::REG_RAX, 0) # RDX = offset
    @emitter.mov_reg_reg(CodeEmitter::REG_RBX, CodeEmitter::REG_RAX) # RBX = &idx

    @emitter.emit_load_address("concat_buffer_pool", @linker)
    @emitter.add_reg_reg(CodeEmitter::REG_RAX, CodeEmitter::REG_RDX) # RAX = dest
    @emitter.mov_reg_reg(CodeEmitter::REG_R8, CodeEmitter::REG_RAX)  # R8 = start of result

    # 2. Copy left (RDI)
    l1 = @emitter.current_pos
    @emitter.mov_reg_mem_idx(CodeEmitter::REG_RCX, CodeEmitter::REG_RDI, 0, 1)
    @emitter.test_reg_reg(CodeEmitter::REG_RCX, CodeEmitter::REG_RCX)
    p_end1 = @emitter.je_rel32
    @emitter.mov_mem_reg_idx(CodeEmitter::REG_RAX, 0, CodeEmitter::REG_RCX, 1)
    @emitter.add_reg_imm(CodeEmitter::REG_RAX, 1)
    @emitter.add_reg_imm(CodeEmitter::REG_RDI, 1)
    lj1 = @emitter.jmp_rel32; @emitter.patch_jmp(lj1, l1)
    @emitter.patch_je(p_end1, @emitter.current_pos)

    # 3. Copy right (RSI)
    l2 = @emitter.current_pos
    @emitter.mov_reg_mem_idx(CodeEmitter::REG_RCX, CodeEmitter::REG_RSI, 0, 1)
    @emitter.test_reg_reg(CodeEmitter::REG_RCX, CodeEmitter::REG_RCX)
    p_end2 = @emitter.je_rel32
    @emitter.mov_mem_reg_idx(CodeEmitter::REG_RAX, 0, CodeEmitter::REG_RCX, 1)
    @emitter.add_reg_imm(CodeEmitter::REG_RAX, 1)
    @emitter.add_reg_imm(CodeEmitter::REG_RSI, 1)
    lj2 = @emitter.jmp_rel32; @emitter.patch_jmp(lj2, l2)
    @emitter.patch_je(p_end2, @emitter.current_pos)

    # 4. Null terminator and update idx
    @emitter.mov_mem8_imm8(CodeEmitter::REG_RAX, 0)
    @emitter.add_reg_imm(CodeEmitter::REG_RAX, 1)

    # Update index: offset = current_rax - pool_start
    @emitter.push_reg(CodeEmitter::REG_RAX)
    @emitter.emit_load_address("concat_buffer_pool", @linker)
    @emitter.mov_reg_reg(CodeEmitter::REG_RDX, CodeEmitter::REG_RAX)
    @emitter.pop_reg(CodeEmitter::REG_RAX)
    @emitter.mov_reg_reg(CodeEmitter::REG_RCX, CodeEmitter::REG_RAX)
    @emitter.sub_reg_reg(CodeEmitter::REG_RCX, CodeEmitter::REG_RDX)
    @emitter.mov_mem_reg_idx(CodeEmitter::REG_RBX, 0, CodeEmitter::REG_RCX)

    @emitter.mov_reg_reg(CodeEmitter::REG_RAX, CodeEmitter::REG_R8) # Return start
    @emitter.pop_reg(CodeEmitter::REG_RBX)
    @emitter.pop_reg(CodeEmitter::REG_RSI)
    @emitter.pop_reg(CodeEmitter::REG_RDI)
    @emitter.log_asm("ret")
    @emitter.emit([0xc3])
  end
end
