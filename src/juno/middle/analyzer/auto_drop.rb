require_relative "../../frontend/ast"

module Juno
  class AutoDropPass
    ALLOCATORS = %w[malloc alloc os_alloc mem_malloc].freeze

    def initialize(ast)
      @ast = ast
      @scopes = []
    end

    def run
      @ast.map { |node| process_node(node) }
    end

    private

    def push_scope
      @scopes.push({ owned: [] })
    end

    def pop_scope
      @scopes.pop
    end

    def add_ownership(var_name)
      @scopes.last[:owned] << var_name if @scopes.last
    end

    def remove_ownership(var_name)
      @scopes.reverse_each do |scope|
        if scope[:owned].include?(var_name)
          scope[:owned].delete(var_name)
          break
        end
      end
    end

    def owned?(var_name)
      @scopes.any? { |scope| scope[:owned].include?(var_name) }
    end

    def allocates?(expr)
      return false unless expr.is_a?(Hash)
      if expr[:type] == :fn_call
        return true if ALLOCATORS.include?(expr[:name])
        return true if expr[:name].end_with?(".init") || expr[:name].end_with?(".new")
      end
      false
    end

    def create_free_node(var_name, original_node)
      AST::FnCall.new(
        "free", 
        [AST::Variable.new(var_name, line: original_node[:line], column: original_node[:column])],
        line: original_node[:line],
        column: original_node[:column]
      )
    end

    def process_node(node)
      return nil if node.nil?
      return node unless node.is_a?(Hash)

      case node[:type]
      when :function_definition then process_function(node)
      when :assignment          then process_assignment(node)
      when :if_statement        then process_if(node)
      when :while_statement     then process_while(node)
      when :for_statement       then process_for(node)
      when :return              then process_return(node)
      else
        process_children(node)
        node
      end
    end

    def process_statements(stmts)
      return [] unless stmts.is_a?(Array)
      new_stmts = []
      stmts.each do |stmt|
        res = process_node(stmt)
        if res.is_a?(Array)
          new_stmts.concat(res)
        elsif res
          new_stmts << res
        end
      end
      new_stmts
    end

    def process_function(node)
      push_scope
      node[:body] = process_statements(node[:body])

      unless node[:body].last&.[](:type) == :return
        leftovers = @scopes.last[:owned].dup
        leftovers.each do |var|
          node[:body] << create_free_node(var, node)
        end
      end

      pop_scope
      node
    end

    def process_assignment(node)
      name = node[:name]
      expr = node[:expression]

      if node[:let]
        if allocates?(expr)
          add_ownership(name)
        elsif expr && expr[:type] == :variable && owned?(expr[:name])
          remove_ownership(expr[:name])
          add_ownership(name)
        end
        node[:expression] = process_node(expr)
        node
      else
        injected = []
        if owned?(name)
          injected << create_free_node(name, node)
          remove_ownership(name)
        end

        if allocates?(expr)
          add_ownership(name)
        elsif expr && expr[:type] == :variable && owned?(expr[:name])
          remove_ownership(expr[:name])
          add_ownership(name)
        end

        node[:expression] = process_node(expr)
        injected << node
        injected
      end
    end

    def process_if(node)
      node[:condition] = process_node(node[:condition])

      push_scope
      node[:body] = process_statements(node[:body])
      unless node[:body].last&.[](:type) == :return
        @scopes.last[:owned].dup.each do |var|
          node[:body] << create_free_node(var, node)
        end
      end
      pop_scope

      if node[:else_body]
        push_scope
        node[:else_body] = process_statements(node[:else_body])
        unless node[:else_body].last&.[](:type) == :return
          @scopes.last[:owned].dup.each do |var|
            node[:else_body] << create_free_node(var, node)
          end
        end
        pop_scope
      end

      node
    end

    def process_while(node)
      node[:condition] = process_node(node[:condition])
      push_scope
      node[:body] = process_statements(node[:body])
      @scopes.last[:owned].dup.each do |var|
        node[:body] << create_free_node(var, node)
      end
      pop_scope
      node
    end

    def process_for(node)
      push_scope
      node[:init] = process_node(node[:init])
      node[:condition] = process_node(node[:condition])
      node[:update] = process_node(node[:update])
      
      node[:body] = process_statements(node[:body])
      @scopes.last[:owned].dup.each do |var|
        node[:body] << create_free_node(var, node)
      end
      pop_scope
      node
    end

    def process_return(node)
      ret_expr = node[:expression]
      returned_var = nil
      if ret_expr && ret_expr[:type] == :variable
        returned_var = ret_expr[:name]
      end

      injected_frees = []
      @scopes.reverse_each do |scope|
        scope[:owned].each do |var|
          next if var == returned_var 
          injected_frees << create_free_node(var, node)
        end
      end

      injected_frees + [node]
    end

    def process_children(node)
      node.each do |k, v|
        if v.is_a?(Hash)
          node[k] = process_node(v)
        elsif v.is_a?(Array)
          node[k] = v.map { |item| process_node(item) }.compact
        end
      end
    end
  end
end
