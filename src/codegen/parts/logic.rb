module GeneratorLogic
  def process_node(node)
    case node[:type]
    when :assignment
       process_assignment(node)
    when :deref_assign
       process_deref_assign(node)
    when :fn_call
       gen_fn_call(node)
    when :return
       eval_expression(node[:expression])
       # Restore callee-saved registers before return
       used_regs = @ctx.used_callee_saved
       padding = (used_regs.length % 2 == 1) ? 8 : 0

       @emitter.pop_callee_saved(used_regs) unless used_regs.empty?
       @emitter.emit_add_rsp(padding) if padding > 0
       @emitter.emit_epilogue(@stack_size || 256)
    when :if_statement
       gen_if(node)
    when :while_statement
       gen_while(node)
    when :for_statement
       gen_for(node)
    when :increment
       gen_increment(node)
    when :insertC
       gen_insertC(node)
    when :array_decl
       gen_array_decl(node)
    when :array_assign
       gen_array_assign(node)
    end
  end

  def process_assignment(node)
    # 1. Struct Init: var = Type
    if node[:expression][:type] == :variable && @ctx.structs.key?(node[:expression][:name])
      st_name = node[:expression][:name]
      st_size = @ctx.structs[st_name][:size]
       @ctx.stack_ptr += st_size
       d_off = @ctx.stack_ptr

       var_off = @ctx.declare_variable(node[:name])
       @ctx.var_types[node[:name]] = st_name
       # Mark as PTR!
       @ctx.var_is_ptr[node[:name]] = true

       @emitter.lea_reg_stack(@emitter.class::REG_RAX, d_off)
       @emitter.mov_stack_reg_val(var_off, @emitter.class::REG_RAX)
       return
    end

    # 2. Assign
    eval_expression(node[:expression])
    if node[:name].include?('.')
       save_member_rax(node[:name])
    else
       # Store type annotation if present
       if node[:var_type]
         @ctx.var_types[node[:name]] = node[:var_type]
       end

       # Check if variable is in a register
       if @ctx.in_register?(node[:name])
         reg = @emitter.class.reg_code(@ctx.get_register(node[:name]))
         @emitter.mov_reg_from_rax(reg)
       else
         off = @ctx.variables[node[:name]] || @ctx.declare_variable(node[:name])
         @emitter.mov_stack_reg_val(off, @emitter.class::REG_RAX)
       end
    end
  end

  def gen_if(node)
    eval_expression(node[:condition])
    if @arch == :aarch64
      @emitter.emit32(0xf100001f) # cmp x0, #0
    else
      @emitter.emit([0x48, 0x85, 0xc0]) # test rax, rax
    end

    patch_pos = @emitter.current_pos
    @emitter.je_rel32

    node[:body].each { |c| process_node(c) }

    end_patch_pos = nil
    if node[:else_body]
       end_patch_pos = @emitter.current_pos
       @emitter.jmp_rel32
    end

    target = @emitter.current_pos
    if @arch == :aarch64
       offset = (target - patch_pos) / 4
       @emitter.bytes[patch_pos..patch_pos+3] = [0x54000000 | (offset << 5)].pack("L<").bytes
    else
       offset = target - (patch_pos + 6)
       @emitter.bytes[patch_pos+2..patch_pos+5] = [offset].pack("l<").bytes
    end

    if node[:else_body]
       node[:else_body].each { |c| process_node(c) }
       target = @emitter.current_pos
       if @arch == :aarch64
         offset = (target - end_patch_pos) / 4
         @emitter.bytes[end_patch_pos..end_patch_pos+3] = [0x14000000 | (offset & 0x3FFFFFF)].pack("L<").bytes
       else
         offset = target - (end_patch_pos + 5)
         @emitter.bytes[end_patch_pos+1..end_patch_pos+4] = [offset].pack("l<").bytes
       end
    end
  end

  def gen_while(node)
    # Loop start
    loop_start = @emitter.current_pos

    # Evaluate condition
    eval_expression(node[:condition])
    if @arch == :aarch64
      @emitter.emit32(0xf100001f) # cmp x0, #0
    else
      @emitter.emit([0x48, 0x85, 0xc0]) # test rax, rax
    end

    # Jump to end if zero
    patch_pos = @emitter.current_pos
    @emitter.je_rel32

    # Body
    node[:body].each { |c| process_node(c) }

    # Jump back to start
    jmp_back = @emitter.current_pos
    @emitter.jmp_rel32
    if @arch == :aarch64
      back_offset = (loop_start - jmp_back) / 4
      @emitter.bytes[jmp_back..jmp_back+3] = [0x14000000 | (back_offset & 0x3FFFFFF)].pack("L<").bytes
    else
      back_offset = loop_start - (jmp_back + 5)
      @emitter.bytes[jmp_back+1..jmp_back+4] = [back_offset].pack("l<").bytes
    end

    # Patch forward jump
    target = @emitter.current_pos
    if @arch == :aarch64
      offset = (target - patch_pos) / 4
      @emitter.bytes[patch_pos..patch_pos+3] = [0x54000000 | (offset << 5)].pack("L<").bytes
    else
      offset = target - (patch_pos + 6)
      @emitter.bytes[patch_pos+2..patch_pos+5] = [offset].pack("l<").bytes
    end
  end

  def gen_increment(node)
    # Check if variable is in a register
    if @ctx.in_register?(node[:name])
      reg = @emitter.class.reg_code(@ctx.get_register(node[:name]))
      if @arch == :aarch64
        if node[:op] == "++"
          @emitter.emit32(0x91000400 | (reg << 5) | reg) # add reg, reg, #1
        else
          @emitter.emit32(0xd1000400 | (reg << 5) | reg) # sub reg, reg, #1
        end
      else
        if node[:op] == "++"
          if reg >= 8
            @emitter.emit([0x49, 0xff, 0xc0 + (reg - 8)])
          else
            @emitter.emit([0x48, 0xff, 0xc0 + reg])
          end
        else
          if reg >= 8
            @emitter.emit([0x49, 0xff, 0xc8 + (reg - 8)])
          else
            @emitter.emit([0x48, 0xff, 0xc8 + reg])
          end
        end
      end
    else
      off = @ctx.get_variable_offset(node[:name])
      @emitter.mov_reg_stack_val(@emitter.class::REG_RAX, off)
      if @arch == :aarch64
        if node[:op] == "++"
          @emitter.emit32(0x91000400) # add x0, x0, #1
        else
          @emitter.emit32(0xd1000400) # sub x0, x0, #1
        end
      else
        if node[:op] == "++"
          @emitter.emit([0x48, 0xff, 0xc0])
        else
          @emitter.emit([0x48, 0xff, 0xc8])
        end
      end
      @emitter.mov_stack_reg_val(off, @emitter.class::REG_RAX)
    end
  end

  def gen_for(node)
    # Init
    process_node(node[:init])

    # Loop start
    loop_start = @emitter.current_pos

    # Condition
    eval_expression(node[:condition])
    if @arch == :aarch64
      @emitter.emit32(0xf100001f)
    else
      @emitter.emit([0x48, 0x85, 0xc0])
    end

    # Jump to end if zero
    patch_pos = @emitter.current_pos
    @emitter.je_rel32

    # Body
    node[:body].each { |c| process_node(c) }

    # Update
    process_node(node[:update])

    # Jump back to start
    jmp_back = @emitter.current_pos
    @emitter.jmp_rel32
    if @arch == :aarch64
      back_offset = (loop_start - jmp_back) / 4
      @emitter.bytes[jmp_back..jmp_back+3] = [0x14000000 | (back_offset & 0x3FFFFFF)].pack("L<").bytes
    else
      back_offset = loop_start - (jmp_back + 5)
      @emitter.bytes[jmp_back+1..jmp_back+4] = [back_offset].pack("l<").bytes
    end

    # Patch forward jump
    target = @emitter.current_pos
    if @arch == :aarch64
      offset = (target - patch_pos) / 4
      @emitter.bytes[patch_pos..patch_pos+3] = [0x54000000 | (offset << 5)].pack("L<").bytes
    else
      offset = target - (patch_pos + 6)
      @emitter.bytes[patch_pos+2..patch_pos+5] = [offset].pack("l<").bytes
    end
  end

  def eval_expression(expr)
    case expr[:type]
    when :literal
      @emitter.mov_rax(expr[:value])
    when :variable
      if @ctx.in_register?(expr[:name])
        reg = @emitter.class.reg_code(@ctx.get_register(expr[:name]))
        @emitter.mov_rax_from_reg(reg)
      elsif @ctx.variables.key?(expr[:name])
        off = @ctx.variables[expr[:name]]
        @emitter.mov_reg_stack_val(@emitter.class::REG_RAX, off)
      else
        if @arch == :aarch64
          @emitter.emit32(0x58000000) # ldr x0, [pc, #0] (patched later)
          @linker.add_fn_patch(@emitter.current_pos - 4, expr[:name])
        else
          @emitter.emit([0x48, 0x8d, 0x05]) # lea rax, [rip + disp32]
          @linker.add_fn_patch(@emitter.current_pos, expr[:name])
          @emitter.emit([0x00, 0x00, 0x00, 0x00])
        end
      end
    when :binary_op
      if string_concat?(expr)
        gen_fn_call({ type: :fn_call, name: "concat", args: [expr[:left], expr[:right]] })
      elsif pointer_arith?(expr)
        gen_pointer_arith(expr)
      else
        eval_expression(expr[:left])
        @emitter.push_reg(@emitter.class::REG_RAX)
        eval_expression(expr[:right])
        @emitter.pop_reg(@emitter.class::REG_RDX)
        # xchg rax, rdx
        if @arch == :aarch64
          @emitter.mov_reg_reg(9, 0) # x9 = rax
          @emitter.mov_reg_reg(0, 2) # x0 = x2 (rdx)
          @emitter.mov_reg_reg(2, 9) # x2 = x9
        else
          @emitter.emit([0x48, 0x92])
        end

        case expr[:op]
        when "+" then @emitter.add_rax_rdx
        when "-" then @emitter.sub_rax_rdx
        when "*"
          if expr[:shift_opt]
            @emitter.shl_rax_imm(expr[:shift_opt])
          else
            @emitter.imul_rax_rdx
          end
        when "/"
          if expr[:shift_opt]
            @emitter.shr_rax_imm(expr[:shift_opt])
          else
            @emitter.div_rax_by_rdx
          end
        when "%" then @emitter.mod_rax_by_rdx
        when "==", "!=", "<", ">", "<=", ">="
          @emitter.cmp_rax_rdx(expr[:op])
        when "&" then @emitter.and_rax_rdx
        when "|" then @emitter.or_rax_rdx
        when "^" then @emitter.xor_rax_rdx
        when "<<"
          if @arch == :aarch64
             # lsl x0, x0, x2
             @emitter.emit32(0x9ac22000)
          else
            @emitter.emit([0x48, 0x89, 0xd1])
            @emitter.shl_rax_cl
          end
        when ">>"
          if @arch == :aarch64
             # lsr x0, x0, x2
             @emitter.emit32(0x9ac22400)
          else
            @emitter.emit([0x48, 0x89, 0xd1])
            @emitter.shr_rax_cl
          end
        end
      end
    when :member_access
       load_member_rax("#{expr[:receiver]}.#{expr[:member]}")
    when :fn_call
       gen_fn_call(expr)
    when :array_access
       gen_array_access(expr)
    when :string_literal
       gen_string_literal(expr)
    when :address_of
       gen_address_of(expr)
    when :dereference
       gen_dereference(expr)
    when :unary_op
       gen_unary_op(expr)
    end
  end

  def gen_unary_op(expr)
    eval_expression(expr[:operand])
    case expr[:op]
    when '~'
      @emitter.not_rax
    when '!'
      if @arch == :aarch64
        @emitter.emit32(0xf100001f) # cmp x0, #0
        @emitter.emit32(0x1a9f17e0) # cset x0, eq
      else
        @emitter.emit([0x48, 0x85, 0xc0])
        @emitter.emit([0x0f, 0x94, 0xc0])
        @emitter.emit([0x48, 0x0f, 0xb6, 0xc0])
      end
    end
  end

  def load_member_rax(full)
    v, f = full.split('.')
    st = @ctx.var_types[v]
    f_off = @ctx.structs[st][:fields][f]

    if @ctx.in_register?(v)
      reg = @emitter.class.reg_code(@ctx.get_register(v))
      @emitter.mov_rax_from_reg(reg)
    else
      off = @ctx.variables[v]
      @emitter.mov_reg_stack_val(@emitter.class::REG_RAX, off)
    end
    @emitter.mov_rax_mem(f_off)
  end

  def save_member_rax(full)
     v, f = full.split('.')
     st = @ctx.var_types[v]
     f_off = @ctx.structs[st][:fields][f]

     @emitter.mov_r11_rax

     if @ctx.in_register?(v)
       reg = @emitter.class.reg_code(@ctx.get_register(v))
       @emitter.mov_rax_from_reg(reg)
     else
       off = @ctx.variables[v]
       @emitter.mov_reg_stack_val(@emitter.class::REG_RAX, off)
     end
     @emitter.mov_mem_r11(f_off)
  end

  def gen_insertC(node)
    content = node[:content].strip
    bytes = []
    content.split(/[\s,]+/).each do |token|
      next if token.empty?
      hex = token.sub(/^0x/i, '')
      bytes << hex.to_i(16)
    end
    @emitter.emit(bytes) unless bytes.empty?
  end

  def gen_array_decl(node)
    name = node[:name]
    size = node[:size]
    arr_info = @ctx.declare_array(name, size)

    # Initialize to zero
    if @arch == :aarch64
      @emitter.mov_rax(0)
    else
      @emitter.emit([0x48, 0x31, 0xc0])
    end

    size.times do |i|
      element_offset = arr_info[:base_offset] - (i * 8)
      @emitter.mov_stack_reg_val(element_offset, @emitter.class::REG_RAX)
    end

    @emitter.lea_reg_stack(@emitter.class::REG_RAX, arr_info[:base_offset])
    @emitter.mov_stack_reg_val(arr_info[:ptr_offset], @emitter.class::REG_RAX)
  end

  def gen_array_assign(node)
    name = node[:name]
    eval_expression(node[:value])
    @emitter.mov_r11_rax

    eval_expression(node[:index])
    @emitter.shl_rax_imm(3)

    arr_info = @ctx.get_array(name)
    if arr_info
      @emitter.push_reg(@emitter.class::REG_RAX)
      @emitter.mov_reg_stack_val(@emitter.class::REG_RAX, arr_info[:ptr_offset])
      @emitter.pop_reg(@emitter.class::REG_RDX)
      @emitter.add_rax_rdx
    else
      @emitter.push_reg(@emitter.class::REG_RAX)
      if @ctx.in_register?(name)
        reg = @emitter.class.reg_code(@ctx.get_register(name))
        @emitter.mov_rax_from_reg(reg)
      else
        off = @ctx.get_variable_offset(name)
        @emitter.mov_reg_stack_val(@emitter.class::REG_RAX, off)
      end
      @emitter.pop_reg(@emitter.class::REG_RDX)
      @emitter.add_rax_rdx
    end

    # Store R11 to [RAX]
    if @arch == :aarch64
      @emitter.emit32(0xf9000009) # str x9, [x0]
    else
      @emitter.emit([0x4c, 0x89, 0x18])
    end
  end

  def gen_array_access(node)
    name = node[:name]
    eval_expression(node[:index])
    @emitter.shl_rax_imm(3)

    arr_info = @ctx.get_array(name)
    if arr_info
      @emitter.push_reg(@emitter.class::REG_RAX)
      @emitter.mov_reg_stack_val(@emitter.class::REG_RAX, arr_info[:ptr_offset])
      @emitter.pop_reg(@emitter.class::REG_RDX)
      @emitter.add_rax_rdx
    else
      @emitter.push_reg(@emitter.class::REG_RAX)
      if @ctx.in_register?(name)
        reg = @emitter.class.reg_code(@ctx.get_register(name))
        @emitter.mov_rax_from_reg(reg)
      else
        off = @ctx.get_variable_offset(name)
        @emitter.mov_reg_stack_val(@emitter.class::REG_RAX, off)
      end
      @emitter.pop_reg(@emitter.class::REG_RDX)
      @emitter.add_rax_rdx
    end
    @emitter.mov_rax_mem(0)
  end

  def gen_string_literal(node)
    content = node[:value]
    label = @linker.add_string(content)

    if @arch == :aarch64
       @emitter.emit32(0x58000000) # ldr x0, [pc]
       @linker.add_data_patch(@emitter.current_pos - 4, label)
    else
       @emitter.emit([0x48, 0x8d, 0x05])
       @linker.add_data_patch(@emitter.current_pos, label)
       @emitter.emit([0x00, 0x00, 0x00, 0x00])
    end
  end

  def gen_address_of(expr)
    operand = expr[:operand]
    if operand[:type] == :variable
      if @ctx.in_register?(operand[:name])
        reg = @emitter.class.reg_code(@ctx.get_register(operand[:name]))
        off = @ctx.declare_variable("__addr_tmp_#{operand[:name]}")
        @emitter.mov_stack_reg_val(off, reg)
        @emitter.lea_reg_stack(@emitter.class::REG_RAX, off)
      else
        off = @ctx.get_variable_offset(operand[:name])
        @emitter.lea_reg_stack(@emitter.class::REG_RAX, off)
      end
    elsif operand[:type] == :array_access
      name = operand[:name]
      eval_expression(operand[:index])
      @emitter.shl_rax_imm(3)
      arr_info = @ctx.get_array(name)
      if arr_info
        @emitter.push_reg(@emitter.class::REG_RAX)
        @emitter.mov_reg_stack_val(@emitter.class::REG_RAX, arr_info[:ptr_offset])
        @emitter.pop_reg(@emitter.class::REG_RDX)
        @emitter.add_rax_rdx
      else
        @emitter.push_reg(@emitter.class::REG_RAX)
        if @ctx.in_register?(name)
          reg = @emitter.class.reg_code(@ctx.get_register(name))
          @emitter.mov_rax_from_reg(reg)
        else
          off = @ctx.get_variable_offset(name)
          @emitter.mov_reg_stack_val(@emitter.class::REG_RAX, off)
        end
        @emitter.pop_reg(@emitter.class::REG_RDX)
        @emitter.add_rax_rdx
      end
    end
  end

  def gen_dereference(expr)
    eval_expression(expr[:operand])
    @emitter.mov_rax_mem(0)
  end

  def process_deref_assign(node)
    eval_expression(node[:value])
    @emitter.mov_r11_rax
    eval_expression(node[:target])
    if @arch == :aarch64
      @emitter.emit32(0xf9000009) # str x9, [x0]
    else
      @emitter.emit([0x4c, 0x89, 0x18])
    end
  end

  def string_concat?(expr)
    expr[:op] == "+" && (string_node?(expr[:left]) || string_node?(expr[:right]))
  end

  def string_node?(node)
    node && node[:type] == :string_literal
  end

  def pointer_arith?(expr)
    return false unless expr[:op] == "+" || expr[:op] == "-"
    lptr = pointer_node?(expr[:left])
    rptr = pointer_node?(expr[:right])
    lptr ^ rptr
  end

  def pointer_node?(node)
    return false unless node.is_a?(Hash)
    case node[:type]
    when :address_of
      true
    when :variable
      @ctx.var_is_ptr[node[:name]] == true
    else
      false
    end
  end

  def gen_pointer_arith(expr)
    base_ptr = pointer_node?(expr[:left]) ? expr[:left] : expr[:right]
    offset_expr = (base_ptr == expr[:left]) ? expr[:right] : expr[:left]
    op = expr[:op]

    eval_expression(base_ptr)
    @emitter.push_reg(@emitter.class::REG_RAX)

    eval_expression(offset_expr)
    @emitter.shl_rax_imm(3)

    @emitter.mov_reg_reg(@emitter.class::REG_RDX, @emitter.class::REG_RAX)
    @emitter.pop_reg(@emitter.class::REG_RBX)

    if op == "+"
      if @arch == :aarch64
        @emitter.add_rax_rdx # Actually rax is already offset, rdx is now offset?
        # Wait, I popped base to RBX (X19)
        @emitter.mov_reg_reg(0, 19) # rax = base
        @emitter.add_rax_rdx # rax = base + offset
      else
        @emitter.emit([0x48, 0x01, 0xd8])
      end
    else
      if @arch == :aarch64
        @emitter.mov_reg_reg(0, 19) # rax = base
        @emitter.sub_rax_rdx # rax = base - offset
      else
        @emitter.emit([0x48, 0x29, 0xd0])
      end
    end
  end
end
