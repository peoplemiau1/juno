require_relative "../../frontend/ast"

module Juno
  class AutoDropPass
    ALLOCATORS = %w[malloc alloc os_alloc mem_malloc].freeze

    def initialize(ast)
      @ast = ast
      @scopes = []
    end

    def run
      @ast.map { |node| process_node(node) }.compact
    end

    private

    def push_scope
      @scopes.push({ owned: [] })
    end

    def pop_scope
      @scopes.pop
    end

    def add_ownership(var_name)
      return unless var_name
      return if var_name.include?('.')
      @scopes.last[:owned] << var_name if @scopes.last
    end

    def remove_ownership(var_name)
      return unless var_name
      return if var_name.include?('.')
      @scopes.reverse_each do |scope|
        if scope[:owned].include?(var_name)
          scope[:owned].delete(var_name)
          break
        end
      end
    end

    def owned?(var_name)
      return false unless var_name
      return false if var_name.include?('.')
      @scopes.any? { |scope| scope[:owned].include?(var_name) }
    end

    def allocates?(expr)
      return false unless expr.is_a?(Hash) && expr.key?(:type)
      case expr[:type]
      when :fn_call
        return true if ALLOCATORS.include?(expr[:name])
        return true if expr[:name].is_a?(String) && (expr[:name].end_with?(".init") || expr[:name].end_with?(".new"))
      end
      false
    end

    def create_free_node(var_name, original_node)
      orig_line = original_node.is_a?(Hash) ? original_node[:line] : nil
      orig_col = original_node.is_a?(Hash) ? original_node[:column] : nil
      AST::FnCall.new(
        "free",
        [AST::Variable.new(var_name, line: orig_line, column: orig_col)],
        line: orig_line,
        column: orig_col
      )
    end

    def returns?(stmt)
      stmt.is_a?(Hash) && stmt.key?(:type) && stmt[:type] == :return
    end

    def process_node(node)
      return nil if node.nil?
      return node unless node.is_a?(Hash) && node.key?(:type)

      case node[:type]
      when :function_definition then process_function(node)
      when :assignment          then process_assignment(node)
      when :if_statement        then process_if(node)
      when :while_statement     then process_while(node)
      when :for_statement       then process_for(node)
      when :match_expression    then process_match(node)
      when :fn_call             then process_fn_call(node)
      when :return
        node[:expression] = process_node(node[:expression]) if node[:expression]
        node
      else
        process_children(node)
        node
      end
    end

    def process_statements(stmts)
      return [] unless stmts.is_a?(Array)
      new_stmts = []

      stmts.each do |stmt|
        next if stmt.nil?

        if stmt.is_a?(Hash) && stmt.key?(:type)
          if stmt[:type] == :return
            stmt[:expression] = process_node(stmt[:expression]) if stmt[:expression]
            ret_expr = stmt[:expression]
            returned_var = ret_expr && ret_expr.is_a?(Hash) && ret_expr[:type] == :variable ? ret_expr[:name] : nil

            @scopes.reverse_each do |scope|
              scope[:owned].each do |var|
                next if var == returned_var
                new_stmts << create_free_node(var, stmt)
              end
            end
            new_stmts << stmt

          elsif stmt[:type] == :assignment && !stmt[:let]
            name = stmt[:name]
            expr = stmt[:expression]

            if owned?(name)
              new_stmts << create_free_node(name, stmt)
              remove_ownership(name)
            end

            stmt[:expression] = process_node(expr)

            if allocates?(expr)
              add_ownership(name)
            elsif expr.is_a?(Hash) && expr.key?(:type) && expr[:type] == :variable && owned?(expr[:name])
              remove_ownership(expr[:name])
              add_ownership(name)
            end

            new_stmts << stmt

          else
            res = process_node(stmt)
            new_stmts << res if res
          end
        else
          new_stmts << stmt
        end
      end

      new_stmts
    end

    def drain_scope_frees(body, scope)
      return body if body.last && returns?(body.last)
      scope[:owned].dup.each do |var|
        body << create_free_node(var, body.last || {})
      end
      body
    end

    def process_function(node)
      push_scope
      node[:body] = process_statements(node[:body])
      drain_scope_frees(node[:body], @scopes.last)
      pop_scope
      node
    end

    def process_assignment(node)
      node[:expression] = process_node(node[:expression])
      name = node[:name]
      expr = node[:expression]

      if node[:let]
        if allocates?(expr)
          add_ownership(name)
        elsif expr.is_a?(Hash) && expr.key?(:type) && expr[:type] == :variable && owned?(expr[:name])
          remove_ownership(expr[:name])
          add_ownership(name)
        end
      end
      node
    end

    def process_if(node)
      node[:condition] = process_node(node[:condition])

      push_scope
      node[:body] = process_statements(node[:body])
      drain_scope_frees(node[:body], @scopes.last)
      pop_scope

      if node[:else_body]
        push_scope
        node[:else_body] = process_statements(node[:else_body])
        drain_scope_frees(node[:else_body], @scopes.last)
        pop_scope
      end

      node
    end

    def process_while(node)
      node[:condition] = process_node(node[:condition])
      push_scope
      node[:body] = process_statements(node[:body])
      drain_scope_frees(node[:body], @scopes.last)
      pop_scope
      node
    end

    def process_for(node)
      push_scope
      node[:init] = process_node(node[:init])
      node[:condition] = process_node(node[:condition])
      node[:update] = process_node(node[:update])

      node[:body] = process_statements(node[:body])
      drain_scope_frees(node[:body], @scopes.last)
      pop_scope
      node
    end

    def process_match(node)
      node[:expression] = process_node(node[:expression])
      if node[:cases].is_a?(Array)
        node[:cases].each do |c|
          next unless c.is_a?(Hash)
          push_scope
          c[:body] = process_statements(c[:body])
          drain_scope_frees(c[:body], @scopes.last)
          pop_scope
        end
      end
      node
    end

    def process_fn_call(node)
      name = node[:name]
      if name == "free" && node[:args]&.any? && node[:args].first.is_a?(Hash) && node[:args].first[:type] == :variable
        remove_ownership(node[:args].first[:name])
      elsif name.is_a?(String) && name.include?('.')
        parts = name.split('.')
        if parts[1] == "free"
          remove_ownership(parts[0])
        end
      end

      if node[:args].is_a?(Array)
        node[:args] = node[:args].map { |arg| process_node(arg) }.compact
      end

      node
    end

    def process_children(node)
      return unless node.is_a?(Hash)
      node.keys.each do |k|
        v = node[k]
        if v.is_a?(Hash)
          node[k] = process_node(v)
        elsif v.is_a?(Array)
          node[k] = v.map { |item| process_node(item) }.compact
        end
      end
    end
  end
end
