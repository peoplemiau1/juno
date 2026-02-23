# hellion.rb - Juno IR to Machine Code translator
require_relative "codegen/parts/emitter"
require_relative "codegen/parts/emitter_aarch64"
require_relative "../optimizer/register_allocator"

class Hellion
  def initialize(arch, target_os)
    @arch = arch
    @target_os = target_os
    @allocator = RegisterAllocator.new(arch)
  end

  def translate(ir, ctx, emitter, linker)
    # 1. First pass: Handle type definitions and externs
    ir.each do |ins|
      case ins.op
      when :TYPE_DEF
        register_type(ins.args[0], ctx)
      when :EXTERN
        linker.declare_import(ins.args[0], ins.args[1])
      end
    end

    # 2. Second pass: Translation
    # We should split IR into functions for register allocation
    functions = split_into_functions(ir)

    functions.each do |name, func_ir|
      translate_function(name, func_ir, ctx, emitter, linker)
    end
  end

  private

  def register_type(node, ctx)
    case node[:type]
    when :struct_definition
      fields = {}
      offset = 0
      node[:fields].each do |f|
        fields[f] = offset
        offset += 8 # Juno default
      end
      ctx.register_struct(node[:name], offset, fields)
    when :enum_definition
      variants = {}
      max_payload = 0
      node[:variants].each_with_index do |v, idx|
        payload_size = (v[:params] || []).length * 8
        max_payload = payload_size if payload_size > max_payload
        variants[v[:name]] = { tag: idx, params: v[:params] || [] }
      end
      ctx.register_enum(node[:name], 8 + max_payload, variants)
    end
  end

  def split_into_functions(ir)
    funcs = {}
    current_fn = nil
    current_ir = []

    ir.each do |ins|
      if ins.op == :LABEL && ins.metadata[:type] == :function
        funcs[current_fn] = current_ir if current_fn
        current_fn = ins.args[0]
        current_ir = [ins]
      else
        current_ir << ins
      end
    end
    funcs[current_fn] = current_ir if current_fn
    funcs
  end

  def translate_function(name, ir, ctx, emitter, linker)
    linker.register_function(name, emitter.current_pos)
    ctx.reset_for_function(name)

    # Simple register allocation for vregs
    # In a real impl, we'd use @allocator on the IR
    vreg_map = {}
    vregs = ir.map { |i| i.args.grep(String).select { |s| s.start_with?('v') } }.flatten.uniq
    vregs.each do |vr|
      vreg_map[vr] = ctx.declare_variable(vr)
    end

    ir.each do |ins|
      translate_instruction(ins, vreg_map, ctx, emitter, linker)
    end
  end

  def translate_instruction(ins, vreg_map, ctx, emitter, linker)
    case ins.op
    when :LABEL
      if ins.metadata[:type] != :function
        linker.register_label(ins.args[0], emitter.current_pos)
      else
        emitter.emit_prologue(1024) # Placeholder
      end
    when :SET
      val = ins.args[1]
      # Handle complex objects (like enum metadata in IR)
      if val.is_a?(Hash) && val[:enum]
         tag = ctx.enums[val[:enum]][:variants][val[:variant]][:tag]
         emitter.mov_rax(tag)
      else
         emitter.mov_rax(val)
      end
      emitter.mov_stack_reg_val(vreg_map[ins.args[0]], 0)
    when :MOVE
      dst = ins.args[0]
      src = ins.args[1]
      if src.is_a?(Integer)
        emitter.mov_rax(src)
      elsif vreg_map[src]
        emitter.mov_reg_stack_val(0, vreg_map[src])
      else
        emitter.mov_reg_stack_val(0, ctx.get_variable_offset(src))
      end

      if vreg_map[dst]
        emitter.mov_stack_reg_val(vreg_map[dst], 0)
      else
        emitter.mov_stack_reg_val(ctx.get_variable_offset(dst), 0)
      end
    when :LOAD
      src_off = ctx.get_variable_offset(ins.args[1])
      emitter.mov_reg_stack_val(0, src_off)
      emitter.mov_stack_reg_val(vreg_map[ins.args[0]], 0)
    when :STORE
      emitter.mov_reg_stack_val(0, vreg_map[ins.args[1]])
      dst_off = ctx.get_variable_offset(ins.args[0])
      emitter.mov_stack_reg_val(dst_off, 0)
    when :ADD, :SUB, :MUL, :DIV, :MOD, :AND, :OR, :XOR, :SHL, :SHR, :ARITH
      if ins.op == :ARITH
        op = ins.args[0]
        dst = ins.args[1]
        src1 = ins.args[2]
        src2 = ins.args[3]
      else
        op = ins.op
        dst = ins.args[0]
        src1 = ins.args[1]
        src2 = ins.args[2]
      end

      emitter.mov_reg_stack_val(0, vreg_map[src1])
      emitter.mov_reg_stack_val(2, vreg_map[src2])

      case op
      when :ADD, "+" then emitter.add_rax_rdx
      when :SUB, "-" then emitter.sub_rax_rdx
      when :MUL, "*" then emitter.imul_rax_rdx
      when :DIV, "/" then emitter.div_rax_by_rdx
      when :MOD, "%" then emitter.mod_rax_by_rdx
      when :AND, "&" then emitter.and_rax_rdx
      when :OR, "|"  then emitter.or_rax_rdx
      when :XOR, "^" then emitter.xor_rax_rdx
      when :SHL, "<<" then emitter.shl_rax_cl
      when :SHR, ">>" then emitter.shr_rax_cl
      when :CMP, "==" then emitter.cmp_rax_rdx("==")
      when "!=" then emitter.cmp_rax_rdx("!=")
      when "<" then emitter.cmp_rax_rdx("<")
      when ">" then emitter.cmp_rax_rdx(">")
      when "<=" then emitter.cmp_rax_rdx("<=")
      when ">=" then emitter.cmp_rax_rdx(">=")
      end
      emitter.mov_stack_reg_val(vreg_map[dst], 0)
    when :CMP
      emitter.mov_reg_stack_val(0, vreg_map[ins.args[0]])
      if ins.args[1].is_a?(Integer)
        emitter.mov_reg_imm(2, ins.args[1])
      else
        emitter.mov_reg_stack_val(2, vreg_map[ins.args[1]])
      end
      emitter.cmp_reg_reg(0, 2)
    when :JCC
      cond = ins.args[0]
      label = ins.args[1]
      patch_pos = case cond
                  when "==", "JZ" then emitter.je_rel32
                  when "!=", "JNZ" then emitter.jne_rel32
                  when "<" then emitter.jl_rel32
                  when ">" then emitter.jg_rel32
                  when "<=" then emitter.jle_rel32
                  when ">=" then emitter.jge_rel32
                  else emitter.je_rel32
                  end
      linker.add_fn_patch(patch_pos + (@arch == :aarch64 ? 0 : 2), label, @arch == :aarch64 ? :aarch64_bl : :rel32)
    when :JZ
      emitter.mov_reg_stack_val(0, vreg_map[ins.args[0]])
      emitter.test_rax_rax
      patch_pos = emitter.je_rel32
      linker.add_fn_patch(patch_pos + (emitter.is_a?(AArch64Emitter) ? 0 : 2), ins.args[1], emitter.is_a?(AArch64Emitter) ? :aarch64_bl : :rel32) # Wait, JMP not BL
      # Need a real JMP patch helper here
    when :JMP
      patch_pos = emitter.jmp_rel32
      linker.add_fn_patch(patch_pos + (emitter.is_a?(AArch64Emitter) ? 0 : 1), ins.args[0], emitter.is_a?(AArch64Emitter) ? :aarch64_bl : :rel32)
    when :RET
      emitter.mov_reg_stack_val(0, vreg_map[ins.args[0]])
      emitter.emit_epilogue(1024)
    when :LOAD_MEM
      emitter.mov_reg_stack_val(0, vreg_map[ins.args[1]]) # base
      emitter.mov_reg_mem_idx(0, 0, ins.args[2], ins.args[3])
      emitter.mov_stack_reg_val(vreg_map[ins.args[0]], 0)
    when :CALL
      # ins.args = [dst, name, args_count]
      args_count = ins.args[2]
      regs = [7, 6, 2, 1, 8, 9] # RDI, RSI, RDX, RCX, R8, R9

      [args_count, regs.length].min.times do |i|
        # Load from param_i
        # For simplicity, we assume param_i was stored as a variable/vreg
        # In IRGenerator we emitted MOVE param_i, arg
        emitter.mov_reg_stack_val(regs[i], ctx.get_variable_offset("param_#{i}"))
      end

      emitter.call_rel32
      linker.add_fn_patch(emitter.current_pos - 4, ins.args[1], :rel32)
      emitter.mov_stack_reg_val(vreg_map[ins.args[0]], 0)
    when :ALLOC_STACK
      emitter.emit_sub_rsp(ins.args[0])
    when :FREE_STACK
      emitter.emit_add_rsp(ins.args[0])
    when :RAW_BYTES
      emitter.emit(ins.args[0])
    end
  end
end
