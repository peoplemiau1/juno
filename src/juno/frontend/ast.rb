module AST
  class Node < Hash
    attr_accessor :line, :column, :filename, :inferred_type

    def initialize(line: nil, column: nil, filename: nil, inferred_type: nil)
      super()
      @line = line
      @column = column
      @filename = filename
      @inferred_type = inferred_type
      
      self[:line] = line if line
      self[:column] = column if column
      self[:filename] = filename if filename
      self[:inferred_type] = inferred_type if inferred_type
      self[:type] = type if respond_to?(:type)
    end

    def [](key)
      key_sym = key.to_sym
      if respond_to?(key_sym) && key_sym != :[]
        send(key_sym)
      else
        super(key)
      end
    end

    def []=(key, val)
      key_sym = key.to_sym
      setter = "#{key_sym}="
      if respond_to?(setter) && setter != "[]="
        send(setter, val)
      end
      super(key, val)
    end

    def key?(key)
      respond_to?(key.to_sym) || super(key)
    end
  end

  class Import < Node
    attr_accessor :path, :system
    def initialize(path, system: false, **opts)
      super(**opts)
      @path = path
      @system = system
      self[:path] = path
      self[:system] = system
    end
    def type; :import; end
  end

  class Literal < Node
    attr_accessor :value
    def initialize(value, **opts)
      super(**opts)
      @value = value
      self[:value] = value
    end
    def type; :literal; end
  end

  class FloatLiteral < Node
    attr_accessor :value
    def initialize(value, **opts)
      super(**opts)
      @value = value
      self[:value] = value
    end
    def type; :float_literal; end
  end

  class StringLiteral < Node
    attr_accessor :value
    def initialize(value, **opts)
      super(**opts)
      @value = value
      self[:value] = value
    end
    def type; :string_literal; end
  end

  class Variable < Node
    attr_accessor :name
    def initialize(name, **opts)
      super(**opts)
      @name = name
      self[:name] = name
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
      self[:op] = op
      self[:left] = left
      self[:right] = right
    end
    def type; :binary_op; end
  end

  class UnaryOp < Node
    attr_accessor :op, :operand
    def initialize(op, operand, **opts)
      super(**opts)
      @op = op
      @operand = operand
      self[:op] = op
      self[:operand] = operand
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
      self[:name] = name
      self[:expression] = expression
      self[:let] = let
      self[:mut] = mut
      self[:var_type] = var_type
    end
    def type; :assignment; end
  end

  class ArrayDecl < Node
    attr_accessor :name, :size
    def initialize(name, size, **opts)
      super(**opts)
      @name = name
      @size = size
      self[:name] = name
      self[:size] = size
    end
    def type; :array_decl; end
  end

  class ImportC < Node
    attr_accessor :header_path, :lib_name
    def initialize(header_path, lib_name, **opts)
      super(**opts)
      @header_path = header_path
      @lib_name = lib_name
      self[:header_path] = header_path
      self[:lib_name] = lib_name
    end
    def type; :import_c; end
  end

  class ArrayAssign < Node
    attr_accessor :name, :index, :value
    def initialize(name, index, value, **opts)
      super(**opts)
      @name = name
      @index = index
      @value = value
      self[:name] = name
      self[:index] = index
      self[:value] = value
    end
    def type; :array_assign; end
  end

  class ArrayAccess < Node
    attr_accessor :name, :index
    def initialize(name, index, **opts)
      super(**opts)
      @name = name
      @index = index
      self[:name] = name
      self[:index] = index
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
      self[:name] = name
      self[:params] = params
      self[:body] = body
      self[:type_params] = type_params
      self[:param_types] = param_types
      self[:return_type] = return_type
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
      self[:name] = name
      self[:fields] = fields
      self[:field_types] = field_types
      self[:packed] = packed
      self[:type_params] = type_params
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
      self[:name] = name
      self[:fields] = fields
      self[:field_types] = field_types
      self[:type_params] = type_params
    end
    def type; :union_definition; end
  end

  class EnumDefinition < Node
    attr_accessor :name, :variants
    def initialize(name, variants, **opts)
      super(**opts)
      @name = name
      @variants = variants
      self[:name] = name
      self[:variants] = variants
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
      self[:condition] = condition
      self[:body] = body
      self[:elif_branches] = elif_branches
      self[:else_body] = else_body
    end
    def type; :if_statement; end
  end

  class WhileStatement < Node
    attr_accessor :condition, :body
    def initialize(condition, body, **opts)
      super(**opts)
      @condition = condition
      @body = body
      self[:condition] = condition
      self[:body] = body
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
      self[:init] = init
      self[:condition] = condition
      self[:update] = update
      self[:body] = body
    end
    def type; :for_statement; end
  end

  class ReturnStatement < Node
    attr_accessor :expression
    def initialize(expression, **opts)
      super(**opts)
      @expression = expression
      self[:expression] = expression
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
      self[:name] = name
      self[:args] = args
      self[:type_args] = type_args
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
      self[:receiver] = receiver
      self[:member] = member
    end
    def type; :member_access; end
  end

  class AddressOf < Node
    attr_accessor :operand
    def initialize(operand, **opts)
      super(**opts)
      @operand = operand
      self[:operand] = operand
    end
    def type; :address_of; end
  end

  class Dereference < Node
    attr_accessor :operand
    def initialize(operand, **opts)
      super(**opts)
      @operand = operand
      self[:operand] = operand
    end
    def type; :dereference; end
  end

  class MatchStatement < Node
    attr_accessor :expression, :cases
    def initialize(expression, cases, **opts)
      super(**opts)
      @expression = expression
      @cases = cases
      self[:expression] = expression
      self[:cases] = cases
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
      self[:name] = name
      self[:params] = params
      self[:param_types] = param_types
      self[:return_type] = return_type
      self[:lib] = lib
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
      self[:message] = message
    end
    def type; :panic; end
  end

  class TodoStatement < Node
    attr_accessor :message
    def initialize(message, **opts)
      super(**opts)
      @message = message
      self[:message] = message
    end
    def type; :todo; end
  end

  class InsertC < Node
    attr_accessor :content
    def initialize(content, **opts)
      super(**opts)
      @content = content
      self[:content] = content
    end
    def type; :insertC; end
  end

  class TypeAlias < Node
    attr_accessor :name, :target
    def initialize(name, target, **opts)
      super(**opts)
      @name = name
      @target = target
      self[:name] = name
      self[:target] = target
    end
    def type; :type_alias; end
  end

  class Increment < Node
    attr_accessor :name, :op
    def initialize(name, op, **opts)
      super(**opts)
      @name = name
      @op = op
      self[:name] = name
      self[:op] = op
    end
    def type; :increment; end
  end

  class DerefAssign < Node
    attr_accessor :target, :value
    def initialize(target, value, **opts)
      super(**opts)
      @target = target
      @value = value
      self[:target] = target
      self[:value] = value
    end
    def type; :deref_assign; end
  end
end
