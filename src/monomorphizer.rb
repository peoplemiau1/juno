# Monomorphizer - Полиморфная компиляция через мономорфизацию
# Создаёт специализированные версии generic функций и структур для каждого типа
class Monomorphizer
  def initialize(ast)
    @ast = ast
    @generic_fns = {}      # name -> node
    @generic_structs = {}  # name -> node
    @instantiated = {}     # "name<types>" -> specialized_name
    @new_nodes = []        # Новые специализированные узлы
  end

  def monomorphize
    # Фаза 1: Собрать все generic определения
    collect_generics
    
    # Фаза 2: Найти все использования и создать специализации
    @ast.each { |node| scan_for_instantiations(node) }
    
    # Фаза 3: Заменить все generic вызовы на специализированные
    result = @ast.map { |node| rewrite_node(node) }.compact
    
    # Фаза 4: Удалить generic определения, добавить специализации
    result = result.reject { |node| is_generic?(node) }
    
    result + @new_nodes
  end

  private

  def collect_generics
    @ast.each do |node|
      if node[:type] == :function_definition && node[:type_params]&.any?
        @generic_fns[node[:name]] = node
      elsif node[:type] == :struct_definition && node[:type_params]&.any?
        @generic_structs[node[:name]] = node
      end
    end
    
    # Собрать методы generic структур
    @generic_methods = {}  # "StructName" -> [method_nodes]
    @ast.each do |node|
      if node[:type] == :function_definition && node[:name].include?('.')
        struct_name = node[:name].split('.')[0]
        if @generic_structs[struct_name]
          @generic_methods[struct_name] ||= []
          @generic_methods[struct_name] << node
        end
      end
    end
  end

  def is_generic?(node)
    return false unless node.is_a?(Hash)
    
    # Generic функции и структуры
    if (node[:type] == :function_definition || node[:type] == :struct_definition) &&
       node[:type_params]&.any?
      return true
    end
    
    # Методы generic структур (без собственных type_params)
    if node[:type] == :function_definition && node[:name].include?('.')
      struct_name = node[:name].split('.')[0]
      return true if @generic_structs[struct_name]
    end
    
    false
  end

  def scan_for_instantiations(node)
    return unless node.is_a?(Hash)
    
    case node[:type]
    when :fn_call
      if node[:type_args]&.any? && @generic_fns[node[:name]]
        instantiate_fn(node[:name], node[:type_args])
      end
      node[:args]&.each { |arg| scan_for_instantiations(arg) }
      
    when :variable
      if node[:type_args]&.any? && @generic_structs[node[:name]]
        instantiate_struct(node[:name], node[:type_args])
      end
      
    when :assignment
      scan_for_instantiations(node[:expression])
      
    when :function_definition
      node[:body]&.each { |stmt| scan_for_instantiations(stmt) }
      
    when :if_statement
      scan_for_instantiations(node[:condition])
      node[:body]&.each { |stmt| scan_for_instantiations(stmt) }
      node[:else_body]&.each { |stmt| scan_for_instantiations(stmt) }
      
    when :while_statement, :for_statement
      scan_for_instantiations(node[:condition])
      node[:body]&.each { |stmt| scan_for_instantiations(stmt) }
      
    when :return
      scan_for_instantiations(node[:expression])
      
    when :binary_op
      scan_for_instantiations(node[:left])
      scan_for_instantiations(node[:right])
    end
  end

  # Переписать узел, заменяя все generic вызовы на специализированные
  def rewrite_node(node, var_types = {})
    return node unless node.is_a?(Hash)
    
    result = node.dup
    
    case node[:type]
    when :fn_call
      # Проверить вызов метода на специализированном типе
      if node[:name].include?('.')
        var_name, method_name = node[:name].split('.')
        if var_types[var_name]
          # Переписать на специализированный метод, сохраняя receiver
          result[:name] = "#{var_types[var_name]}.#{method_name}"
          result[:receiver] = var_name  # Сохранить оригинальную переменную
        end
      elsif node[:type_args]&.any?
        key = "#{node[:name]}<#{node[:type_args].join(',')}>"
        if @instantiated[key]
          result[:name] = @instantiated[key]
          result[:type_args] = []
        end
      end
      result[:args] = node[:args]&.map { |a| rewrite_node(a, var_types) }
      
    when :variable
      if node[:type_args]&.any?
        key = "#{node[:name]}<#{node[:type_args].join(',')}>"
        if @instantiated[key]
          result[:name] = @instantiated[key]
          result[:type_args] = []
        end
      end
      
    when :assignment
      rewritten_expr = rewrite_node(node[:expression], var_types)
      result[:expression] = rewritten_expr
      # Отслеживать тип переменной если это generic struct
      if rewritten_expr[:type] == :variable && rewritten_expr[:name]&.include?('__')
        var_types[node[:name]] = rewritten_expr[:name]
      end
      
    when :function_definition
      local_var_types = {}
      result[:body] = node[:body]&.map { |stmt| rewrite_node(stmt, local_var_types) }
      
    when :if_statement
      result[:condition] = rewrite_node(node[:condition], var_types)
      result[:body] = node[:body]&.map { |stmt| rewrite_node(stmt, var_types) }
      result[:else_body] = node[:else_body]&.map { |stmt| rewrite_node(stmt, var_types) }
      
    when :while_statement
      result[:condition] = rewrite_node(node[:condition], var_types)
      result[:body] = node[:body]&.map { |stmt| rewrite_node(stmt, var_types) }
      
    when :for_statement
      result[:init] = rewrite_node(node[:init], var_types)
      result[:condition] = rewrite_node(node[:condition], var_types)
      result[:update] = rewrite_node(node[:update], var_types)
      result[:body] = node[:body]&.map { |stmt| rewrite_node(stmt, var_types) }
      
    when :return
      result[:expression] = rewrite_node(node[:expression], var_types)
      
    when :binary_op
      result[:left] = rewrite_node(node[:left], var_types)
      result[:right] = rewrite_node(node[:right], var_types)
      
    when :member_access
      result[:receiver] = node[:receiver]
    end
    
    result
  end

  def instantiate_fn(name, type_args)
    key = "#{name}<#{type_args.join(',')}>"
    return @instantiated[key] if @instantiated[key]
    
    template = @generic_fns[name]
    specialized_name = "#{name}__#{type_args.join('_')}"
    
    # Создать mapping типов
    type_map = {}
    template[:type_params].each_with_index do |param, i|
      type_map[param] = type_args[i]
    end
    
    # Клонировать и специализировать тело
    specialized = deep_clone(template)
    specialized[:name] = specialized_name
    specialized[:type_params] = []
    specialized[:body] = specialize_body(specialized[:body], type_map)
    
    @new_nodes << specialized
    @instantiated[key] = specialized_name
    specialized_name
  end

  def instantiate_struct(name, type_args)
    key = "#{name}<#{type_args.join(',')}>"
    return @instantiated[key] if @instantiated[key]
    
    template = @generic_structs[name]
    specialized_name = "#{name}__#{type_args.join('_')}"
    
    # Создать type_map для специализации методов
    type_map = {}
    template[:type_params].each_with_index do |param, i|
      type_map[param] = type_args[i]
    end
    
    specialized = deep_clone(template)
    specialized[:name] = specialized_name
    specialized[:type_params] = []
    
    @new_nodes << specialized
    @instantiated[key] = specialized_name
    
    # Также специализировать методы этой структуры
    if @generic_methods[name]
      @generic_methods[name].each do |method_node|
        method_name = method_node[:name].split('.')[1]
        specialized_method_name = "#{specialized_name}.#{method_name}"
        
        specialized_method = deep_clone(method_node)
        specialized_method[:name] = specialized_method_name
        specialized_method[:type_params] = []
        specialized_method[:body] = specialize_body(specialized_method[:body], type_map)
        
        @new_nodes << specialized_method
      end
    end
    
    specialized_name
  end

  def specialize_body(body, type_map)
    body.map { |stmt| specialize_node(stmt, type_map) }
  end

  def specialize_node(node, type_map)
    return node unless node.is_a?(Hash)
    
    result = node.dup
    
    case node[:type]
    when :fn_call
      if node[:type_args]&.any?
        resolved_args = node[:type_args].map { |t| type_map[t] || t }
        if @generic_fns[node[:name]]
          spec_name = instantiate_fn(node[:name], resolved_args)
          result[:name] = spec_name
          result[:type_args] = []
        end
      end
      result[:args] = node[:args]&.map { |a| specialize_node(a, type_map) }
      
    when :variable
      if node[:type_args]&.any?
        resolved_args = node[:type_args].map { |t| type_map[t] || t }
        if @generic_structs[node[:name]]
          spec_name = instantiate_struct(node[:name], resolved_args)
          result[:name] = spec_name
          result[:type_args] = []
        end
      end
      
    when :assignment
      result[:expression] = specialize_node(node[:expression], type_map)
      
    when :if_statement
      result[:condition] = specialize_node(node[:condition], type_map)
      result[:body] = specialize_body(node[:body], type_map)
      result[:else_body] = node[:else_body] ? specialize_body(node[:else_body], type_map) : nil
      
    when :while_statement
      result[:condition] = specialize_node(node[:condition], type_map)
      result[:body] = specialize_body(node[:body], type_map)
      
    when :for_statement
      result[:init] = specialize_node(node[:init], type_map)
      result[:condition] = specialize_node(node[:condition], type_map)
      result[:update] = specialize_node(node[:update], type_map)
      result[:body] = specialize_body(node[:body], type_map)
      
    when :return
      result[:expression] = specialize_node(node[:expression], type_map)
      
    when :binary_op
      result[:left] = specialize_node(node[:left], type_map)
      result[:right] = specialize_node(node[:right], type_map)
    end
    
    result
  end

  def deep_clone(obj)
    case obj
    when Hash
      obj.transform_values { |v| deep_clone(v) }
    when Array
      obj.map { |v| deep_clone(v) }
    else
      obj
    end
  end
end
