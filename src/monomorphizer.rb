# Monomorphizer - Creates specialized versions of generic functions/structs
# for each unique combination of type arguments

class Monomorphizer
  def initialize(ast)
    @ast = ast
    @generic_fns = {}
    @generic_structs = {}
    @specializations = []
  end

  def monomorphize
    collect_generics
    process_calls
    inject_specializations
    @ast
  end

  private

  def collect_generics
    @ast.each do |node|
      case node[:type]
      when :function_definition
        if node[:type_params] && !node[:type_params].empty?
          @generic_fns[node[:name]] = node
        end
      when :struct_definition
        if node[:type_params] && !node[:type_params].empty?
          @generic_structs[node[:name]] = node
        end
      end
    end
  end

  def process_calls
    @ast.each do |node|
      process_node(node)
    end
  end

  def process_node(node)
    return unless node.is_a?(Hash)

    case node[:type]
    when :fn_call
      if node[:type_args] && !node[:type_args].empty?
        specialize_call(node)
      end
    when :variable
      if node[:type_args] && !node[:type_args].empty?
        specialize_type(node)
      end
    when :function_definition
      node[:body]&.each { |n| process_node(n) }
    when :if_statement
      process_node(node[:condition])
      node[:body]&.each { |n| process_node(n) }
      node[:else_body]&.each { |n| process_node(n) }
    when :while_statement, :for_statement
      process_node(node[:condition])
      node[:body]&.each { |n| process_node(n) }
    when :assignment, :let
      process_node(node[:expression])
    when :return_statement
      process_node(node[:expression])
    when :binary_op
      process_node(node[:left])
      process_node(node[:right])
    end

    node[:args]&.each { |arg| process_node(arg) }
  end

  def specialize_call(node)
    base_name = node[:name]
    type_args = node[:type_args]
    
    return unless @generic_fns[base_name]
    
    specialized_name = "#{base_name}__#{type_args.join('_')}"
    node[:name] = specialized_name
    node.delete(:type_args)
    
    unless @specializations.any? { |s| s[:name] == specialized_name }
      create_specialization(base_name, type_args, specialized_name)
    end
  end

  def specialize_type(node)
    base_name = node[:name]
    type_args = node[:type_args]
    
    return unless @generic_structs[base_name]
    
    specialized_name = "#{base_name}__#{type_args.join('_')}"
    node[:name] = specialized_name
    node.delete(:type_args)
    
    unless @specializations.any? { |s| s[:name] == specialized_name }
      create_struct_specialization(base_name, type_args, specialized_name)
    end
  end

  def create_specialization(base_name, type_args, specialized_name)
    template = @generic_fns[base_name]
    type_params = template[:type_params]
    
    type_map = {}
    type_params.each_with_index do |param, i|
      type_map[param] = type_args[i] if type_args[i]
    end
    
    specialized = deep_clone(template)
    specialized[:name] = specialized_name
    specialized.delete(:type_params)
    
    rewrite_types(specialized, type_map)
    @specializations << specialized
  end

  def create_struct_specialization(base_name, type_args, specialized_name)
    template = @generic_structs[base_name]
    type_params = template[:type_params]
    
    type_map = {}
    type_params.each_with_index do |param, i|
      type_map[param] = type_args[i] if type_args[i]
    end
    
    specialized = deep_clone(template)
    specialized[:name] = specialized_name
    specialized.delete(:type_params)
    
    if specialized[:field_types]
      specialized[:field_types].each do |field, type|
        specialized[:field_types][field] = type_map[type] || type
      end
    end
    
    @specializations << specialized
  end

  def rewrite_types(node, type_map)
    return unless node.is_a?(Hash)
    
    if node[:param_types]
      node[:param_types].each do |param, type|
        node[:param_types][param] = type_map[type] || type
      end
    end
    
    if node[:return_type]
      node[:return_type] = type_map[node[:return_type]] || node[:return_type]
    end
    
    node[:body]&.each { |n| rewrite_types(n, type_map) }
    node[:args]&.each { |n| rewrite_types(n, type_map) }
  end

  def inject_specializations
    @ast.reject! do |node|
      (node[:type] == :function_definition && @generic_fns[node[:name]]) ||
      (node[:type] == :struct_definition && @generic_structs[node[:name]])
    end
    
    @ast.concat(@specializations)
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
