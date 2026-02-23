# ir_generator.rb - Translates Juno/Watt AST to Juno IR
require_relative "ir"

class IRGenerator
  def initialize
    @vreg_counter = 0
    @labels_counter = 0
    @ir = []
  end

  def generate(ast)
    @ir = []
    ast.each { |node| process_top_level(node) }
    @ir
  end

  private

  def emit(op, *args, **metadata)
    @ir << JunoIR::Instruction.new(op, *args, **metadata)
  end

  def next_vreg; "v#{@vreg_counter += 1}"; end
  def next_label(prefix = "L"); "#{prefix}_#{@labels_counter += 1}"; end

  def process_top_level(node)
    case node[:type]
    when :function_definition
      emit(:LABEL, node[:name], type: :function)
      node[:body].each { |stmt| process_node(stmt) }
      emit(:RET, "v0") # Implicit return 0 if no ret
    when :extern_definition
      # Externs are handled by linker, but IR can track them
      emit(:EXTERN, node[:name], node[:lib])
    when :struct_definition, :union_definition, :enum_definition
      # Metadata for types
      emit(:TYPE_DEF, node)
    else
      process_node(node)
    end
  end

  def process_node(node)
    return if node.nil?
    case node[:type]
    when :assignment
      src = eval_expression(node[:expression])
      emit(:STORE, node[:name], src, let: node[:let], mut: node[:mut])
    when :if_statement
      process_if(node)
    when :while_statement
      process_while(node)
    when :for_statement
      process_for(node)
    when :return
      src = eval_expression(node[:expression])
      emit(:RET, src)
    when :break
      emit(:JMP, @current_break_label)
    when :continue
      emit(:JMP, @current_continue_label)
    when :fn_call
      eval_expression(node)
    when :panic
      emit(:PANIC, node[:message])
    when :todo
      emit(:TODO, node[:message])
    end
  end

  def eval_expression(expr)
    case expr[:type]
    when :literal
      dst = next_vreg
      emit(:SET, dst, expr[:value])
      dst
    when :variable
      dst = next_vreg
      emit(:LOAD, dst, expr[:name])
      dst
    when :binary_op
      left = eval_expression(expr[:left])
      right = eval_expression(expr[:right])
      dst = next_vreg
      op = case expr[:op]
           when "+" then :ADD when "-" then :SUB when "*" then :MUL when "/" then :DIV
           when "%" then :MOD when "&" then :AND when "|" then :OR  when "^" then :XOR
           when "<<" then :SHL when ">>" then :SHR
           when "==", "!=", "<", ">", "<=", ">=" then :CMP
           when "<>" then :CONCAT
           end
      emit(op, dst, left, right, cond: (op == :CMP ? expr[:op] : nil))
      dst
    when :fn_call
      args = (expr[:args] || []).map { |a| eval_expression(a) }
      dst = next_vreg
      emit(:CALL, dst, expr[:name], args)
      dst
    when :member_access
      dst = next_vreg
      emit(:LOAD_MEMBER, dst, expr[:receiver], expr[:member])
      dst
    when :string_literal
      dst = next_vreg
      emit(:LEA_STR, dst, expr[:value])
      dst
    when :match_expression
      process_match(expr)
    when :cast
      src = eval_expression(expr[:expression])
      dst = next_vreg
      emit(:CAST, dst, src, expr[:target_type])
      dst
    when :anonymous_function
      dst = next_vreg
      label = next_label("anon")
      # Define the function at the label
      # Note: This is simplified IR representation
      emit(:FUNC_ADDR, dst, label, node: expr)
      dst
    end
  end

  def process_if(node)
    else_l = next_label("if_else")
    end_l = next_label("if_end")

    cond = eval_expression(node[:condition])
    emit(:JZ, cond, else_l)

    node[:body].each { |s| process_node(s) }
    emit(:JMP, end_l)

    emit(:LABEL, else_l)
    node[:else_body]&.each { |s| process_node(s) }

    emit(:LABEL, end_l)
  end

  def process_while(node)
    start_l = next_label("while_start")
    end_l = next_label("while_end")

    old_break = @current_break_label
    old_continue = @current_continue_label
    @current_break_label = end_l
    @current_continue_label = start_l

    emit(:LABEL, start_l)
    cond = eval_expression(node[:condition])
    emit(:JZ, cond, end_l)

    node[:body].each { |s| process_node(s) }
    emit(:JMP, start_l)

    emit(:LABEL, end_l)
    @current_break_label = old_break
    @current_continue_label = old_continue
  end

  def process_for(node)
    # init
    process_node(node[:init])

    start_l = next_label("for_start")
    update_l = next_label("for_update")
    end_l = next_label("for_end")

    old_break = @current_break_label
    old_continue = @current_continue_label
    @current_break_label = end_l
    @current_continue_label = update_l

    emit(:LABEL, start_l)
    cond = eval_expression(node[:condition])
    emit(:JZ, cond, end_l)

    node[:body].each { |s| process_node(s) }

    emit(:LABEL, update_l)
    process_node(node[:update])
    emit(:JMP, start_l)

    emit(:LABEL, end_l)
    @current_break_label = old_break
    @current_continue_label = old_continue
  end

  def process_match(node)
    matched = eval_expression(node[:expression])
    end_l = next_label("match_end")
    dst = next_vreg
    match_res = next_vreg

    node[:cases].each do |c|
      next_c = next_label("case")
      process_pattern(matched, c[:pattern], next_c)

      # Case body
      res = if c[:body].is_a?(Array)
              c[:body].each { |s| process_node(s) }
              "v0"
            else
              eval_expression(c[:body])
            end
      emit(:MOV, match_res, res)
      emit(:JMP, end_l)
      emit(:LABEL, next_c)
    end

    emit(:LABEL, end_l)
    emit(:MOV, dst, match_res)
    dst
  end

  def process_pattern(matched, pattern, fail_label)
    case pattern[:type]
    when :wildcard_pattern
      # Always matches, do nothing
    when :literal_pattern
      val_reg = next_vreg
      emit(:SET, val_reg, pattern[:value])
      cmp_reg = next_vreg
      emit(:CMP, cmp_reg, matched, val_reg, cond: "==")
      emit(:JZ, cmp_reg, fail_label)
    when :bind_pattern
      emit(:STORE, pattern[:name], matched)
    when :variant_pattern
      # Check tag
      tag_reg = next_vreg
      emit(:LOAD_MEM, tag_reg, matched, 0, 8)

      target_tag_reg = next_vreg
      # We need tag value from somewhere. Let's assume metadata for now.
      # In a real impl, IRGenerator would know the enum layout.
      emit(:SET, target_tag_reg, {enum: pattern[:enum], variant: pattern[:variant]})

      cmp_reg = next_vreg
      emit(:CMP, cmp_reg, tag_reg, target_tag_reg, cond: "==")
      emit(:JZ, cmp_reg, fail_label)

      # Bind fields
      (pattern[:fields] || []).each_with_index do |f, i|
        field_reg = next_vreg
        emit(:LOAD_MEM, field_reg, matched, 8 + i * 8, 8)
        emit(:STORE, f, field_reg)
      end
    end
  end
end
