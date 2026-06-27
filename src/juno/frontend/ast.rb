module AST
  class Node
    attr_accessor :line, :column, :filename, :inferred_type

    def initialize(line: nil, column: nil, filename: nil, inferred_type: nil)
      @line = line
      @column = column
      @filename = filename
      @inferred_type = inferred_type
    end

    # Обратная совместимость с синтаксисом хэшей для безопасного перехода
    def [](key)
      send(key) if respond_to?(key)
    end

    def []=(key, val)
      send("#{key}=", val) if respond_to?("#{key}=")
    end

    def key?(key)
      respond_to?(key)
    end
  end

  class Literal < Node
    attr_accessor :value
    def initialize(value, **opts)
      super(**opts)
      @value = value
    end
    def type; :literal; end
  end

  class FloatLiteral < Node
    attr_accessor :value
    def initialize(value, **opts)
      super(**opts)
      @value = value
    end
    def type; :float_literal; end
  end

  class StringLiteral < Node
    attr_accessor :value
    def initialize(value, **opts)
      super(**opts)
      @value = value
    end
    def type; :string_literal; end
  end

  class Variable < Node
    attr_accessor :name
    def initialize(name, **opts)
      super(**opts)
      @name = name
    end
    def type; :variable; end
  end

  class BinaryOp < Node
    attr_accessor :op, :left, :right
    def initialize(op, left, right, **opts)
      super(**opts)
      @op = op
      @left = left
      @right = right
    end
    def type; :binary_op; end
  end

  class UnaryOp < Node
    attr_accessor :op, :operand
    def initialize(op, operand, **opts)
      super(**opts)
      @op = op
      @operand = operand
    end
    def type; :unary_op; end
  end

  class Assignment < Node
    attr_accessor :name, :expression, :let, :mut, :var_type, :struct_name
    def initialize(name, expression, let: false, mut: false, var_type: nil, **opts)
      super(**opts)
      @name = name
      @expression = expression
      @let = let
      @mut = mut
      @var_type = var_type
      @struct_name = nil
    end
    def type; :assignment; end
  end

  class ArrayDecl < Node
    attr_accessor :name, :size
    def initialize(name, size, **opts)
      super(**opts)
      @name = name
      @size = size
    end
    def type; :array_decl; end
  end

  class ArrayAssign < Node
    attr_accessor :name, :index, :value
    def initialize(name, index, value, **opts)
      super(**opts)
      @name = name
      @index = index
      @value = value
    end
    def type; :array_assign; end
  end

  class ArrayAccess < Node
    attr_accessor :name, :index
    def initialize(name, index, **opts)
      super(**opts)
      @name = name
      @index = index
    end
    def type; :array_access; end
  end

  class FunctionDefinition < Node
    attr_accessor :name, :params, :body, :type_params, :param_types, :return_type, :stack_size
    def initialize(name, params, body, type_params: [], param_types: {}, return_type: nil, **opts)
      super(**opts)
      @name = name
      @params = params
      @body = body
      @type_params = type_params
      @param_types = param_types
      @return_type = return_type
      @stack_size = 0
    end
    def type; :function_definition; end
  end

  class StructDefinition < Node
    attr_accessor :name, :fields, :field_types, :packed, :type_params
    def initialize(name, fields, field_types: {}, packed: false, type_params: [], **opts)
      super(**opts)
      @name = name
      @fields = fields
      @field_types = field_types
      @packed = packed
      @type_params = type_params
    end
    def type; :struct_definition; end
  end

  class UnionDefinition < Node
    attr_accessor :name, :fields, :field_types, :type_params
    def initialize(name, fields, field_types: {}, type_params: [], **opts)
      super(**opts)
      @name = name
      @fields = fields
      @field_types = field_types
      @type_params = type_params
    end
    def type; :union_definition; end
  end

  class EnumDefinition < Node
    attr_accessor :name, :variants
    def initialize(name, variants, **opts)
      super(**opts)
      @name = name
      @variants = variants
    end
    def type; :enum_definition; end
  end

  class IfStatement < Node
    attr_accessor :condition, :body, :elif_branches, :else_body
    def initialize(condition, body, elif_branches: [], else_body: nil, **opts)
      super(**opts)
      @condition = condition
      @body = body
      @elif_branches = elif_branches
      @else_body = else_body
    end
    def type; :if_statement; end
  end

  class WhileStatement < Node
    attr_accessor :condition, :body
    def initialize(condition, body, **opts)
      super(**opts)
      @condition = condition
      @body = body
    end
    def type; :while_statement; end
  end

  class ForStatement < Node
    attr_accessor :init, :condition, :update, :body
    def initialize(init, condition, update, body, **opts)
      super(**opts)
      @init = init
      @condition = condition
      @update = update
      @body = body
    end
    def type; :for_statement; end
  end

  class ReturnStatement < Node
    attr_accessor :expression
    def initialize(expression, **opts)
      super(**opts)
      @expression = expression
    end
    def type; :return; end
  end

  class FnCall < Node
    attr_accessor :name, :args, :receiver_type, :type_args
    def initialize(name, args, type_args: [], **opts)
      super(**opts)
      @name = name
      @args = args
      @receiver_type = nil
      @type_args = type_args
    end
    def type; :fn_call; end
  end

  class MemberAccess < Node
    attr_accessor :receiver, :member, :receiver_type, :struct_name
    def initialize(receiver, member, **opts)
      super(**opts)
      @receiver = receiver
      @member = member
      @receiver_type = nil
      @struct_name = nil
    end
    def type; :member_access; end
  end

  class AddressOf < Node
    attr_accessor :operand
    def initialize(operand, **opts)
      super(**opts)
      @operand = operand
    end
    def type; :address_of; end
  end

  class Dereference < Node
    attr_accessor :operand
    def initialize(operand, **opts)
      super(**opts)
      @operand = operand
    end
    def type; :dereference; end
  end

  class MatchStatement < Node
    attr_accessor :expression, :cases
    def initialize(expression, cases, **opts)
      super(**opts)
      @expression = expression
      @cases = cases
    end
    def type; :match_expression; end
  end

  class ExternDefinition < Node
    attr_accessor :name, :params, :param_types, :return_type, :lib
    def initialize(name, params, param_types: {}, return_type: nil, lib: nil, **opts)
      super(**opts)
      @name = name
      @params = params
      @param_types = param_types
      @return_type = return_type
      @lib = lib
    end
    def type; :extern_definition; end
  end

  class BreakStatement < Node
    def type; :break; end
  end

  class ContinueStatement < Node
    def type; :continue; end
  end

  class PanicStatement < Node
    attr_accessor :message
    def initialize(message, **opts)
      super(**opts)
      @message = message
    end
    def type; :panic; end
  end

  class TodoStatement < Node
    attr_accessor :message
    def initialize(message, **opts)
      super(**opts)
      @message = message
    end
    def type; :todo; end
  end

  class InsertC < Node
    attr_accessor :content
    def initialize(content, **opts)
      super(**opts)
      @content = content
    end
    def type; :insertC; end
  end

  class TypeAlias < Node
    attr_accessor :name, :target
    def initialize(name, target, **opts)
      super(**opts)
      @name = name
      @target = target
    end
    def type; :type_alias; end
  end
end
