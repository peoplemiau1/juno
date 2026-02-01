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
       
       @emitter.lea_reg_stack(CodeEmitter::REG_RAX, d_off)
       @emitter.mov_stack_reg_val(var_off, CodeEmitter::REG_RAX)
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
         reg = CodeEmitter.reg_code(@ctx.get_register(node[:name]))
         @emitter.mov_reg_from_rax(reg)
       else
         off = @ctx.variables[node[:name]] || @ctx.declare_variable(node[:name])
         @emitter.mov_stack_reg_val(off, CodeEmitter::REG_RAX)
       end
    end
  end

  def gen_if(node)
    eval_expression(node[:condition])
    @emitter.emit([0x48, 0x85, 0xc0])
    
    patch_pos = @emitter.current_pos
    @emitter.je_rel32
    
    node[:body].each { |c| process_node(c) }
    
    end_patch_pos = nil
    if node[:else_body]
       end_patch_pos = @emitter.current_pos
       @emitter.jmp_rel32
    end
    
    target = @emitter.current_pos
    offset = target - (patch_pos + 6)
    @emitter.bytes[patch_pos+2..patch_pos+5] = [offset].pack("l<").bytes
    
    if node[:else_body]
       node[:else_body].each { |c| process_node(c) }
       target = @emitter.current_pos
       offset = target - (end_patch_pos + 5)
       @emitter.bytes[end_patch_pos+1..end_patch_pos+4] = [offset].pack("l<").bytes
    end
  end

  def gen_while(node)
    # Loop start
    loop_start = @emitter.current_pos
    
    # Evaluate condition
    eval_expression(node[:condition])
    @emitter.emit([0x48, 0x85, 0xc0]) # test rax, rax
    
    # Jump to end if zero
    patch_pos = @emitter.current_pos
    @emitter.je_rel32
    
    # Body
    node[:body].each { |c| process_node(c) }
    
    # Jump back to start
    jmp_back = @emitter.current_pos
    @emitter.jmp_rel32
    back_offset = loop_start - (jmp_back + 5)
    @emitter.bytes[jmp_back+1..jmp_back+4] = [back_offset].pack("l<").bytes
    
    # Patch forward jump
    target = @emitter.current_pos
    offset = target - (patch_pos + 6)
    @emitter.bytes[patch_pos+2..patch_pos+5] = [offset].pack("l<").bytes
  end

  def gen_increment(node)
    # Check if variable is in a register
    if @ctx.in_register?(node[:name])
      reg = CodeEmitter.reg_code(@ctx.get_register(node[:name]))
      # Increment/decrement directly in register
      if node[:op] == "++"
        if reg >= 8
          @emitter.emit([0x49, 0xff, 0xc0 + (reg - 8)]) # inc r8-r15
        else
          @emitter.emit([0x48, 0xff, 0xc0 + reg]) # inc rax-rdi
        end
      else
        if reg >= 8
          @emitter.emit([0x49, 0xff, 0xc8 + (reg - 8)]) # dec r8-r15
        else
          @emitter.emit([0x48, 0xff, 0xc8 + reg]) # dec rax-rdi
        end
      end
    else
      off = @ctx.get_variable_offset(node[:name])
      unless off
        puts "Error: Undefined variable '#{node[:name]}'"
        exit 1
      end
      
      # Load variable
      @emitter.mov_reg_stack_val(CodeEmitter::REG_RAX, off)
      
      # Increment or decrement
      if node[:op] == "++"
        @emitter.emit([0x48, 0xff, 0xc0]) # inc rax
      else
        @emitter.emit([0x48, 0xff, 0xc8]) # dec rax
      end
      
      # Store back
      @emitter.mov_stack_reg_val(off, CodeEmitter::REG_RAX)
    end
  end

  def gen_for(node)
    # Init
    process_node(node[:init])
    
    # Loop start
    loop_start = @emitter.current_pos
    
    # Condition
    eval_expression(node[:condition])
    @emitter.emit([0x48, 0x85, 0xc0]) # test rax, rax
    
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
    back_offset = loop_start - (jmp_back + 5)
    @emitter.bytes[jmp_back+1..jmp_back+4] = [back_offset].pack("l<").bytes
    
    # Patch forward jump
    target = @emitter.current_pos
    offset = target - (patch_pos + 6)
    @emitter.bytes[patch_pos+2..patch_pos+5] = [offset].pack("l<").bytes
  end
  
  def eval_expression(expr)
    case expr[:type]
    when :literal
      @emitter.mov_rax(expr[:value])
    when :variable
      # Check if variable is in a register
      if @ctx.in_register?(expr[:name])
        reg = CodeEmitter.reg_code(@ctx.get_register(expr[:name]))
        @emitter.mov_rax_from_reg(reg)
      else
        off = @ctx.get_variable_offset(expr[:name])
        unless off
          puts "Error: Undefined variable '#{expr[:name]}'. Known: #{@ctx.variables.keys}"
          exit 1
        end
        @emitter.mov_reg_stack_val(CodeEmitter::REG_RAX, off)
      end
    when :binary_op
      if string_concat?(expr)
        gen_fn_call({ type: :fn_call, name: "concat", args: [expr[:left], expr[:right]] })
      elsif pointer_arith?(expr)
        gen_pointer_arith(expr)
      else
        eval_expression(expr[:left])
        @emitter.emit([0x50]) # push rax (save left)
        eval_expression(expr[:right])
        @emitter.emit([0x5a]) # pop rdx (restore left to rdx)
        @emitter.emit([0x48, 0x92]) # xchg rax, rdx
        case expr[:op]
        when "+"
          @emitter.add_rax_rdx
        when "-"
          @emitter.sub_rax_rdx
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
        when "==", "!=", "<", ">", "<=", ">="
          @emitter.cmp_rax_rdx(expr[:op])
        when "&"
          @emitter.and_rax_rdx
        when "|"
          @emitter.or_rax_rdx
        when "^"
          @emitter.xor_rax_rdx
        when "<<"
          @emitter.emit([0x48, 0x89, 0xd1]) # mov rcx, rdx
          @emitter.shl_rax_cl
        when ">>"
          @emitter.emit([0x48, 0x89, 0xd1]) # mov rcx, rdx
          @emitter.shr_rax_cl
        when "&&"
          @emitter.emit([0x48, 0x85, 0xc0]) # test rax, rax
          @emitter.emit([0x0f, 0x95, 0xc0]) # setne al
          @emitter.emit([0x48, 0x0f, 0xb6, 0xc0]) # movzx rax, al
          @emitter.emit([0x48, 0x85, 0xd2]) # test rdx, rdx
          @emitter.emit([0x0f, 0x95, 0xc2]) # setne dl
          @emitter.emit([0x20, 0xd0]) # and al, dl
          @emitter.emit([0x48, 0x0f, 0xb6, 0xc0]) # movzx rax, al
        when "||"
          @emitter.emit([0x48, 0x09, 0xd0]) # or rax, rdx
          @emitter.emit([0x48, 0x85, 0xc0]) # test rax, rax
          @emitter.emit([0x0f, 0x95, 0xc0]) # setne al
          @emitter.emit([0x48, 0x0f, 0xb6, 0xc0]) # movzx rax, al
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
      # Logical NOT: 0 -> 1, non-zero -> 0
      @emitter.emit([0x48, 0x85, 0xc0]) # test rax, rax
      @emitter.emit([0x0f, 0x94, 0xc0]) # sete al
      @emitter.emit([0x48, 0x0f, 0xb6, 0xc0]) # movzx rax, al
    end
  end

  def load_member_rax(full)
    v, f = full.split('.')
    st = @ctx.var_types[v]
    unless st && @ctx.structs[st]
       puts "Error: Unknown struct type for '#{v}'"
       exit 1
    end
    f_off = @ctx.structs[st][:fields][f]
    off = @ctx.variables[v]
    
    @emitter.mov_reg_stack_val(CodeEmitter::REG_RAX, off)
    @emitter.mov_rax_mem(f_off)
  end

  def save_member_rax(full)
     v, f = full.split('.')
     st = @ctx.var_types[v]
     unless st && @ctx.structs[st]
        puts "Error: Unknown struct type for variable '#{v}'"
        exit 1
     end
     f_off = @ctx.structs[st][:fields][f]
     off = @ctx.variables[v]
     
     @emitter.mov_r11_rax 
     @emitter.mov_reg_stack_val(CodeEmitter::REG_RAX, off)
     @emitter.mov_mem_r11(f_off) 
  end

  # insertC { 0x48 0x31 0xc0 } - raw machine code injection
  def gen_insertC(node)
    content = node[:content].strip
    bytes = []
    
    # Parse hex bytes: "0x48 0x31 0xc0" or "48 31 c0" or comma-separated
    content.split(/[\s,]+/).each do |token|
      next if token.empty?
      # Remove 0x prefix if present
      hex = token.sub(/^0x/i, '')
      bytes << hex.to_i(16)
    end
    
    @emitter.emit(bytes) unless bytes.empty?
  end

  # Array declaration: let arr[N]
  # Allocates N * 8 bytes on stack and initializes to zero
  def gen_array_decl(node)
    name = node[:name]
    size = node[:size]
    
    # Declare array in context (allocates stack space)
    arr_info = @ctx.declare_array(name, size)
    
    # Initialize all elements to zero
    # xor rax, rax
    @emitter.emit([0x48, 0x31, 0xc0])
    
    # Store 0 to each element
    size.times do |i|
      element_offset = arr_info[:base_offset] - (i * 8)
      @emitter.mov_stack_reg_val(element_offset, CodeEmitter::REG_RAX)
    end
    
    # Store pointer to arr[0] in the variable
    @emitter.lea_reg_stack(CodeEmitter::REG_RAX, arr_info[:base_offset])
    @emitter.mov_stack_reg_val(arr_info[:ptr_offset], CodeEmitter::REG_RAX)
  end

  # Array element assignment: arr[i] = value
  def gen_array_assign(node)
    name = node[:name]
    
    # Evaluate value first, save to R11
    eval_expression(node[:value])
    @emitter.mov_r11_rax
    
    # Evaluate index
    eval_expression(node[:index])
    # RAX = index
    
    # Compute address: base_ptr + index * 8
    # First, multiply index by 8 (shift left 3)
    @emitter.emit([0x48, 0xc1, 0xe0, 0x03]) # shl rax, 3
    
    # Load base pointer
    arr_info = @ctx.get_array(name)
    if arr_info
      # It's a declared array - load pointer from stack
      @emitter.emit([0x50]) # push rax (save index*8)
      @emitter.mov_reg_stack_val(CodeEmitter::REG_RAX, arr_info[:ptr_offset])
      @emitter.emit([0x5a]) # pop rdx (index*8 to rdx)
      @emitter.add_rax_rdx # rax = base + index*8
    else
      # It's a pointer parameter
      off = @ctx.get_variable_offset(name)
      @emitter.emit([0x50]) # push rax
      @emitter.mov_reg_stack_val(CodeEmitter::REG_RAX, off)
      @emitter.emit([0x5a]) # pop rdx
      @emitter.add_rax_rdx
    end
    
    # Store R11 to [RAX]
    @emitter.emit([0x4c, 0x89, 0x18]) # mov [rax], r11
  end

  # Array element access: arr[i]
  def gen_array_access(node)
    name = node[:name]
    
    # Evaluate index
    eval_expression(node[:index])
    # RAX = index
    
    # Multiply by 8
    @emitter.emit([0x48, 0xc1, 0xe0, 0x03]) # shl rax, 3
    
    # Load base pointer
    arr_info = @ctx.get_array(name)
    if arr_info
      @emitter.emit([0x50]) # push rax
      @emitter.mov_reg_stack_val(CodeEmitter::REG_RAX, arr_info[:ptr_offset])
      @emitter.emit([0x5a]) # pop rdx
      @emitter.add_rax_rdx
    else
      off = @ctx.get_variable_offset(name)
      @emitter.emit([0x50]) # push rax
      @emitter.mov_reg_stack_val(CodeEmitter::REG_RAX, off)
      @emitter.emit([0x5a]) # pop rdx
      @emitter.add_rax_rdx
    end
    
    # Load value from [RAX]
    @emitter.emit([0x48, 0x8b, 0x00]) # mov rax, [rax]
  end

  # String literal: "hello"
  # Adds string to data section and loads address into RAX
  def gen_string_literal(node)
    content = node[:value]
    
    # Add string to linker data section
    label = @linker.add_string(content)
    
    # LEA RAX, [RIP + offset] - load address of string
    # We need to patch this later, so emit placeholder
    @emitter.emit([0x48, 0x8d, 0x05]) # lea rax, [rip + disp32]
    @linker.add_data_patch(@emitter.current_pos, label)
    @emitter.emit([0x00, 0x00, 0x00, 0x00]) # placeholder for offset
  end

  # Address-of: &x -> load address of variable into RAX
  def gen_address_of(expr)
    operand = expr[:operand]
    
    if operand[:type] == :variable
      # If variable is in register, we need to spill it to stack first
      if @ctx.in_register?(operand[:name])
        reg = CodeEmitter.reg_code(@ctx.get_register(operand[:name]))
        # Allocate stack slot and store there
        off = @ctx.declare_variable("__addr_tmp_#{operand[:name]}")
        @emitter.mov_stack_reg_val(off, reg)
        @emitter.lea_reg_stack(CodeEmitter::REG_RAX, off)
      else
        off = @ctx.get_variable_offset(operand[:name])
        unless off
          puts "Error: Undefined variable '#{operand[:name]}' in address-of"
          exit 1
        end
        # LEA RAX, [RBP - offset]
        @emitter.lea_reg_stack(CodeEmitter::REG_RAX, off)
      end
    elsif operand[:type] == :array_access
      # &arr[i] - get address of array element
      name = operand[:name]
      eval_expression(operand[:index])
      @emitter.emit([0x48, 0xc1, 0xe0, 0x03]) # shl rax, 3
      
      arr_info = @ctx.get_array(name)
      if arr_info
        @emitter.emit([0x50]) # push rax
        @emitter.mov_reg_stack_val(CodeEmitter::REG_RAX, arr_info[:ptr_offset])
        @emitter.emit([0x5a]) # pop rdx
        @emitter.add_rax_rdx
      else
        off = @ctx.get_variable_offset(name)
        @emitter.emit([0x50]) # push rax
        @emitter.mov_reg_stack_val(CodeEmitter::REG_RAX, off)
        @emitter.emit([0x5a]) # pop rdx
        @emitter.add_rax_rdx
      end
      # RAX now contains address, don't dereference
    else
      puts "Error: Cannot take address of expression type #{operand[:type]}"
      exit 1
    end
  end

  # Dereference: *ptr -> load value at address in ptr
  def gen_dereference(expr)
    eval_expression(expr[:operand])
    # RAX = address, load value from [RAX]
    @emitter.emit([0x48, 0x8b, 0x00]) # mov rax, [rax]
  end

  # Dereference assignment: *ptr = value
  def process_deref_assign(node)
    # Evaluate value first, save to R11
    eval_expression(node[:value])
    @emitter.mov_r11_rax
    
    # Load pointer value (address) from variable
    target = node[:target]
    if target[:type] == :variable
      off = @ctx.get_variable_offset(target[:name])
      unless off
        puts "Error: Undefined variable '#{target[:name]}'"
        exit 1
      end
      @emitter.mov_reg_stack_val(CodeEmitter::REG_RAX, off)
    else
      eval_expression(target)
    end
    # RAX = address
    
    # Store R11 to [RAX]
    @emitter.emit([0x4c, 0x89, 0x18]) # mov [rax], r11
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
    lptr ^ rptr  # exactly one pointer operand
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

    # Evaluate base pointer -> RAX
    eval_expression(base_ptr)
    @emitter.emit([0x50]) # push rax (save base)

    # Evaluate offset -> RAX, scale by 8 (pointer to 8-byte values)
    eval_expression(offset_expr)
    @emitter.emit([0x48, 0xc1, 0xe0, 0x03]) # shl rax, 3

    # Preserve offset in RDX, restore base to RBX
    @emitter.mov_reg_reg(CodeEmitter::REG_RDX, CodeEmitter::REG_RAX)
    @emitter.emit([0x5b]) # pop rbx (base)

    if op == "+"
      # rax = offset, rbx = base
      @emitter.emit([0x48, 0x01, 0xd8]) # add rax, rbx  => rax = offset + base
    else
      # rdx = offset, rbx = base
      @emitter.mov_reg_reg(CodeEmitter::REG_RAX, CodeEmitter::REG_RBX) # rax = base
      @emitter.emit([0x48, 0x29, 0xd0]) # sub rax, rdx => base - offset
    end
  end
end
