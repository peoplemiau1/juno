require_relative "../../frontend/ast"

module Juno
  module Memory
    ALLOCATORS = %w[malloc alloc os_alloc mem_malloc].freeze

    module Scan
      def self.linear_name?(name)
        name.is_a?(String) && !name.include?('.')
      end

      def self.resource_type?(type_name)
        return false if type_name.nil?
        type_str = type_name.to_s
        !%w[int float real i8 u8 i16 u16 i32 u32 i64 u64 bool void].include?(type_str)
      end

      def self.references?(target, name)
        case target
        when Array
          target.any? { |t| references?(t, name) }
        when Hash
          return true if target[:type] == :variable && target[:name] == name
          target.each_value.any? { |v| references?(v, name) }
        else
          false
        end
      end

      def self.allocator_call?(expr)
        expr.is_a?(Hash) && expr[:type] == :fn_call &&
          (ALLOCATORS.include?(expr[:name]) ||
           (expr[:name].is_a?(String) && (expr[:name].end_with?(".init") || expr[:name].end_with?(".new"))))
      end

      def self.allocates_result?(expr)
        allocator_call?(expr) || (expr.is_a?(Hash) && expr[:type] == :binary_op && expr[:allocates])
      end

      def self.diverges?(body)
        return false unless body.is_a?(Array) && !body.empty?
        last = body.last
        last.is_a?(Hash) && %i[return break continue].include?(last[:type])
      end
    end

    class OwnershipInference
      def initialize(ast)
        @ast = ast
      end

      def run
        signatures = {}
        @ast.each do |node|
          next unless node.is_a?(Hash) && node[:type] == :function_definition
          params = node[:params] || []
          signatures[node[:name]] = params.map do |p|
            p_name = p.is_a?(Hash) ? p[:name] : p
            type_name = p.is_a?(Hash) ? p[:type_name] : nil
            if Scan.resource_type?(type_name)
              !consumes?(node[:body], p_name)
            else
              true
            end
          end
        end
        signatures
      end

      private

      def consumes?(body, name)
        return false unless body.is_a?(Array) && name
        scan_stmts(body, name)
      end

      def scan_stmts(stmts, name)
        return false unless stmts.is_a?(Array)
        stmts.any? { |s| scan_stmt(s, name) }
      end

      def scan_stmt(stmt, name)
        return false unless stmt.is_a?(Hash)
        case stmt[:type]
        when :return
          var_ref?(stmt[:expression], name) || scan_expr(stmt[:expression], name)
        when :assignment
          if var_ref?(stmt[:expression], name)
            true
          else
            scan_expr(stmt[:expression], name)
          end
        when :if_statement
          scan_expr(stmt[:condition], name) || scan_stmts(stmt[:body], name) || scan_stmts(stmt[:else_body], name)
        when :while_statement
          scan_expr(stmt[:condition], name) || scan_stmts(stmt[:body], name)
        when :for_statement
          scan_stmts(stmt[:body], name)
        when :match_expression
          scan_expr(stmt[:expression], name) ||
            (stmt[:cases] || []).any? { |c| c.is_a?(Hash) && scan_stmts(c[:body], name) }
        else
          scan_expr(stmt, name)
        end
      end

      def var_ref?(expr, name)
        expr.is_a?(Hash) && expr[:type] == :variable && expr[:name] == name
      end

      def scan_expr(expr, name)
        return false unless expr.is_a?(Hash)
        if expr[:type] == :fn_call && expr[:args].is_a?(Array)
          return expr[:args].any? do |arg|
            next false if arg.is_a?(Hash) && arg[:type] == :borrow
            var_ref?(arg, name) || scan_expr(arg, name)
          end
        end
        expr.each_value.any? do |v|
          if v.is_a?(Hash)
            var_ref?(v, name) || scan_expr(v, name)
          elsif v.is_a?(Array)
            v.any? { |it| it.is_a?(Hash) && scan_call_args(it, name) }
          else
            false
          end
        end
      end
    end

    class EscapeAnalysis
      def initialize(ast)
        @ast = ast
      end

      def run
        @ast.each { |n| analyze(n) if n.is_a?(Hash) && n[:type] == :function_definition }
        @ast
      end

      private

      def analyze(fn)
        candidates = {}
        (fn[:body] || []).each do |s|
          next unless s.is_a?(Hash) && s[:type] == :assignment && s[:let] && Scan.allocator_call?(s[:expression])
          candidates[s[:name]] = s
        end
        candidates.each { |name, decl| decl[:stack_promotable] = !escapes?(fn[:body], name) }
        nested_functions(fn[:body]).each { |f| analyze(f) }
      end

      def nested_functions(body)
        return [] unless body.is_a?(Array)
        out = []
        body.each do |s|
          next unless s.is_a?(Hash)
          out << s if s[:type] == :function_definition
          %i[body else_body].each { |k| out.concat(nested_functions(s[k])) if s[k].is_a?(Array) }
          (s[:cases] || []).each { |c| out.concat(nested_functions(c[:body])) if c.is_a?(Hash) } if s[:cases].is_a?(Array)
        end
        out
      end

      def escapes?(body, name)
        scan_stmts(body, name)
      end

      def scan_stmts(stmts, name)
        return false unless stmts.is_a?(Array)
        stmts.any? { |s| scan_stmt(s, name) }
      end

      def scan_stmt(stmt, name)
        return false unless stmt.is_a?(Hash)
        case stmt[:type]
        when :return
          Scan.references?(stmt[:expression], name)
        when :assignment
          if stmt[:name].to_s.include?('.')
            Scan.references?(stmt[:expression], name)
          elsif stmt[:expression].is_a?(Hash) && stmt[:expression][:type] == :variable &&
                stmt[:expression][:name] == name && stmt[:name] != name
            true
          else
            scan_call_args(stmt[:expression], name)
          end
        when :if_statement
          scan_call_args(stmt[:condition], name) || scan_stmts(stmt[:body], name) || scan_stmts(stmt[:else_body], name)
        when :while_statement
          scan_call_args(stmt[:condition], name) || scan_stmts(stmt[:body], name)
        when :for_statement
          scan_stmts(stmt[:body], name)
        when :match_expression
          scan_call_args(stmt[:expression], name) ||
            (stmt[:cases] || []).any? { |c| c.is_a?(Hash) && scan_stmts(c[:body], name) }
        else
          scan_call_args(stmt, name)
        end
      end

      def scan_call_args(expr, name)
        return false unless expr.is_a?(Hash)
        if expr[:type] == :fn_call && expr[:args].is_a?(Array)
          is_release = expr[:name] == "free" ||
                       (expr[:name].is_a?(String) && (expr[:name].end_with?(".free") || expr[:name].end_with?(".deinit")))
          return expr[:args].any? do |arg|
            next false if arg.is_a?(Hash) && arg[:type] == :borrow
            if arg.is_a?(Hash) && arg[:type] == :variable && arg[:name] == name
              next !is_release
            end
            scan_call_args(arg, name)
          end
        end
        expr.each_value.any? do |v|
          if v.is_a?(Hash)
            scan_call_args(v, name)
          elsif v.is_a?(Array)
            v.any? { |it| it.is_a?(Hash) && scan_call_args(it, name) }
          else
            false
          end
        end
      end
    end

    class StructResourceGen
      def initialize(ast)
        @ast = ast
        @structs = {}
        @existing_fns = {}
      end

      def run
        collect
        return @ast if @structs.empty?
        build_graph
        detect_cycles

        generated = []
        @structs.each_key do |name|
          generated << gen_drop(name) unless @existing_fns["#{name}_drop"]
          generated << gen_dup(name) unless @existing_fns["#{name}_dup"]
        end
        @ast.concat(generated)
        @ast
      end

      private

      def collect
        @ast.each do |n|
          next unless n.is_a?(Hash)
          if n[:type] == :struct_definition
            fields = (n[:fields] || []).map do |f|
              if f.is_a?(Hash)
                { name: f[:name], type: (f[:type] || f[:type_name]).to_s }
              else
                { name: f.to_s, type: "int" }
              end
            end
            @structs[n[:name]] = fields
          elsif n[:type] == :function_definition
            @existing_fns[n[:name]] = true
          end
        end
      end

      def build_graph
        @graph = {}
        @structs.each do |name, fields|
          @graph[name] = fields.map { |f| f[:type] }.uniq.select { |t| @structs.key?(t) }
        end
      end

      def detect_cycles
        @recursive = {}
        @structs.each_key { |name| @recursive[name] = path_exists?(name, name, {}) }
      end

      def path_exists?(from, to, visited)
        (@graph[from] || []).each do |nxt|
          return true if nxt == to
          next if visited[nxt]
          visited[nxt] = true
          return true if path_exists?(nxt, to, visited)
        end
        false
      end

      def field_size
        8
      end

      def struct_size(name)
        (@structs[name]&.size || 0) * field_size
      end

      def is_ptr_type?(t)
        !@structs.key?(t) && Scan.resource_type?(t)
      end

      def v(name)
        { type: :variable, name: name }
      end

      def member(receiver, field_name)
        { type: :member_access, receiver: receiver, member: field_name }
      end

      def call(name, args)
        { type: :fn_call, name: name, args: args }
      end

      def assign(name, expr, let: false)
        { type: :assignment, let: let, name: name, expression: expr }
      end

      def lit_null
        { type: :null_literal }
      end

      def lit_int(n)
        { type: :int_literal, value: n }
      end

      def bin(op, l, r)
        { type: :binary_op, op: op, left: l, right: r }
      end

      def stack_helpers(prefix, word_count)
        buf = "#{prefix}_buf"
        cap = "#{prefix}_cap"
        sp  = "#{prefix}_sp"
        init_cap = 64

        init = [
          assign(buf, call("malloc", [lit_int(init_cap * word_count * 8)]), let: true),
          assign(cap, lit_int(init_cap), let: true),
          assign(sp, lit_int(0), let: true)
        ]

        grow_stmt = lambda do
          newcap = "#{prefix}_newcap"
          newbuf = "#{prefix}_newbuf"
          ci = "#{prefix}_ci"
          {
            type: :if_statement,
            condition: bin("==", v(sp), v(cap)),
            body: [
              assign(newcap, bin("*", v(cap), lit_int(2)), let: true),
              assign(newbuf, call("malloc", [bin("*", bin("*", v(newcap), lit_int(word_count)), lit_int(8))]), let: true),
              assign(ci, lit_int(0), let: true),
              {
                type: :while_statement,
                condition: bin("<", v(ci), bin("*", v(sp), lit_int(word_count))),
                body: [
                  call("store_i64", [
                    bin("+", v(newbuf), bin("*", v(ci), lit_int(8))),
                    call("load_i64", [bin("+", v(buf), bin("*", v(ci), lit_int(8)))])
                  ]),
                  assign(ci, bin("+", v(ci), lit_int(1)))
                ]
              },
              call("free", [v(buf)]),
              assign(buf, v(newbuf)),
              assign(cap, v(newcap))
            ],
            else_body: []
          }
        end

        push = lambda do |value_exprs|
          stmts = [grow_stmt.call]
          value_exprs.each_with_index do |val, i|
            stmts << call("store_i64", [
              bin("+", v(buf), bin("*", bin("+", bin("*", v(sp), lit_int(word_count)), lit_int(i)), lit_int(8))),
              val
            ])
          end
          stmts << assign(sp, bin("+", v(sp), lit_int(1)))
          stmts
        end

        pop = lambda do |target_names|
          stmts = [assign(sp, bin("-", v(sp), lit_int(1)))]
          target_names.each_with_index do |name, i|
            stmts << assign(name, call("load_i64", [
              bin("+", v(buf), bin("*", bin("+", bin("*", v(sp), lit_int(word_count)), lit_int(i)), lit_int(8)))
            ]), let: true)
          end
          stmts
        end

        {
          buf: buf, sp: sp, cap: cap,
          init: init, push: push, pop: pop,
          empty_cond: bin("==", v(sp), lit_int(0)),
          not_empty_cond: bin("!=", v(sp), lit_int(0)),
          free: call("free", [v(buf)])
        }
      end

      def gen_drop(name)
        fields = @structs[name]
        body =
          if @recursive[name]
            iterative_drop_body(name, fields)
          else
            b = []
            fields.each do |f|
              t = f[:type]
              if @structs.key?(t)
                b << call("#{t}_drop", [member("self", f[:name])])
              elsif is_ptr_type?(t)
                b << call("free", [member("self", f[:name])])
              end
            end
            b << call("free", [v("self")])
            b
          end

        {
          type: :function_definition, name: "#{name}_drop",
          params: ["self"], param_types: { "self" => name },
          body: body, skip_perceus: true
        }
      end

      def iterative_drop_body(name, fields)
        self_ref_fields = fields.select { |f| f[:type] == name }
        other_fields = fields.reject { |f| f[:type] == name }

        st = stack_helpers("__ds_#{name}", 1)
        cur = "__cur_#{name}"

        body = []
        body.concat(st[:init])
        body.concat(st[:push].call([v("self")]))

        inner = []
        other_fields.each do |f|
          t = f[:type]
          if @structs.key?(t)
            inner << call("#{t}_drop", [member(cur, f[:name])])
          elsif is_ptr_type?(t)
            inner << call("free", [member(cur, f[:name])])
          end
        end
        self_ref_fields.each do |f|
          inner.concat(st[:push].call([member(cur, f[:name])]))
        end
        inner << call("free", [v(cur)])

        loop_body = st[:pop].call([cur])
        loop_body << {
          type: :if_statement,
          condition: bin("!=", v(cur), lit_null),
          body: inner,
          else_body: []
        }

        body << { type: :while_statement, condition: st[:not_empty_cond], body: loop_body }
        body << st[:free]
        body
      end

      def gen_dup(name)
        fields = @structs[name]
        self_ref_fields = fields.select { |f| f[:type] == name }

        if @recursive[name] && !self_ref_fields.empty?
          return gen_iterative_dup_nary(name, fields, self_ref_fields)
        end

        body = []
        body << assign("__new", call("malloc", [lit_int(struct_size(name))]), let: true)
        fields.each do |f|
          t = f[:type]
          src = member("self", f[:name])
          value =
            if @structs.key?(t)
              call("#{t}_dup", [src])
            elsif %w[str string].include?(t) || is_ptr_type?(t)
              call("strdup", [src])
            else
              src
            end
          body << assign("__new.#{f[:name]}", value)
        end
        body << { type: :return, expression: v("__new") }

        {
          type: :function_definition, name: "#{name}_dup",
          params: ["self"], param_types: { "self" => name },
          body: body, skip_perceus: true
        }
      end

      def gen_iterative_dup_nary(name, fields, self_ref_fields)
        other_fields = fields.reject { |f| f[:type] == name }
        k = self_ref_fields.size

        st = stack_helpers("__dp_#{name}", 3)
        orig = "__orig_#{name}"
        parent = "__parent_#{name}"
        tag = "__tag_#{name}"
        newn = "__newn_#{name}"

        body = []
        body << assign("__head", lit_null, let: true)
        body.concat(st[:init])
        body.concat(st[:push].call([v("self"), lit_null, lit_int(-1)]))

        build_new = []
        other_fields.each do |f|
          t = f[:type]
          src = member(orig, f[:name])
          value =
            if @structs.key?(t)
              call("#{t}_dup", [src])
            elsif %w[str string].include?(t) || is_ptr_type?(t)
              call("strdup", [src])
            else
              src
            end
          build_new << assign("#{newn}.#{f[:name]}", value)
        end
        self_ref_fields.each_with_index do |f, i|
          build_new.concat(st[:push].call([member(orig, f[:name])]))
        end

        non_null_branch = [assign(newn, call("malloc", [lit_int(struct_size(name))]), let: true)]
        non_null_branch.concat(build_new)

        null_branch = [assign(newn, lit_null, let: true)]

        dispatch =
          if k == 1
            f = self_ref_fields[0]
            {
              type: :if_statement,
              condition: bin("==", v(tag), lit_int(-1)),
              body: [assign("__head", v(newn))],
              else_body: [assign("#{parent}.#{f[:name]}", v(newn))]
            }
          else
            elif_branches = self_ref_fields.each_with_index.filter_map do |f, i|
              next nil if i == 0
              { condition: bin("==", v(tag), lit_int(i)), body: [assign("#{parent}.#{f[:name]}", v(newn))] }
            end
            {
              type: :if_statement,
              condition: bin("==", v(tag), lit_int(-1)),
              body: [assign("__head", v(newn))],
              elif_branches: [
                { condition: bin("==", v(tag), lit_int(0)), body: [assign("#{parent}.#{self_ref_fields[0][:name]}", v(newn))] },
                *elif_branches
              ],
              else_body: []
            }
          end

        loop_body = st[:pop].call([orig, parent, tag])
        loop_body << {
          type: :if_statement,
          condition: bin("==", v(orig), lit_null),
          body: null_branch,
          else_body: non_null_branch
        }
        loop_body << dispatch

        body << { type: :while_statement, condition: st[:not_empty_cond], body: loop_body }
        body << st[:free]
        body << { type: :return, expression: v("__head") }

        {
          type: :function_definition, name: "#{name}_dup",
          params: ["self"], param_types: { "self" => name },
          body: body, skip_perceus: true
        }
      end
    end

    class Perceus
      ScopeFrame = Struct.new(:kind, :bindings)
      Binding = Struct.new(:shared, :stack, :type_name, :aliased)

      def initialize(ast, signatures = {})
        @ast = ast
        @signatures = signatures
        @scopes = []
        @counter = 0
      end

      def run
        @ast.map { |n| process_top(n) }.compact
      end

      private

      def push_scope(kind) = @scopes.push(ScopeFrame.new(kind, {}))
      def pop_scope = @scopes.pop
      def current_frame = @scopes.last

      def find(name)
        return nil unless Scan.linear_name?(name)
        @scopes.reverse_each { |f| return f.bindings[name] if f.bindings.key?(name) }
        nil
      end

      def scope_of(name)
        return nil unless Scan.linear_name?(name)
        @scopes.reverse_each { |f| return f if f.bindings.key?(name) }
        nil
      end

      def owner_frame_for(name)
        base = name.to_s.split('.').first
        scope_of(base) || current_frame
      end

      def forget_with_fields(name)
        return unless Scan.linear_name?(name)
        prefix = "#{name}."
        @scopes.each do |f|
          f.bindings.keys.each do |k|
            f.bindings.delete(k) if k == name || k.start_with?(prefix)
          end
        end
      end

      def ordered_keys(bindings)
        bindings.keys.sort_by { |k| -k.count('.') }
      end

      def clone_scopes(frames)
        frames.map { |f| ScopeFrame.new(f.kind, f.bindings.transform_values(&:dup)) }
      end

      def fresh_name(prefix)
        @counter += 1
        "__#{prefix}_#{@counter}"
      end

      def borrowed_param?(fn_name, index)
        sig = @signatures[fn_name]
        return true if sig.nil? || index >= sig.size
        sig[index]
      end

      def dup_node(name, ref, binding)
        l = ref.is_a?(Hash) ? ref[:line] : nil
        c = ref.is_a?(Hash) ? ref[:column] : nil
        {
          type: :fn_call, name: "dup",
          args: [{ type: :variable, name: name, line: l, column: c }],
          stack: binding&.stack, resource_type: binding&.type_name,
          line: l, column: c
        }
      end

      def drop_node(name, ref, binding)
        l = ref.is_a?(Hash) ? ref[:line] : nil
        c = ref.is_a?(Hash) ? ref[:column] : nil
        {
          type: :fn_call, name: "drop",
          args: [{ type: :variable, name: name, line: l, column: c }],
          stack: binding&.stack, shared: binding&.shared, resource_type: binding&.type_name,
          line: l, column: c
        }
      end

      def null_node(name, ref)
        l = ref.is_a?(Hash) ? ref[:line] : nil
        c = ref.is_a?(Hash) ? ref[:column] : nil
        { type: :assignment, let: false, name: name,
          expression: { type: :null_literal, line: l, column: c }, line: l, column: c }
      end

      def let_node(name, expr, ref)
        { type: :assignment, let: true, name: name, expression: expr, line: ref[:line], column: ref[:column] }
      end

      def var_node(name, ref)
        { type: :variable, name: name, line: ref[:line], column: ref[:column] }
      end

      def handle_variable_use(name, node, remaining, pending, owning:)
        binding = find(name)
        return nil unless binding
        return nil unless owning

        if binding.aliased
          return { moved: false, shared: true, stack: binding.stack, type_name: binding.type_name }
        end

        if Scan.references?(remaining, name)
          tmp = fresh_name("dup")
          pending << let_node(tmp, dup_node(name, node, binding), node)
          binding.shared = true
          node[:name] = tmp if node.is_a?(Hash)
          { moved: false, shared: true, stack: false, type_name: binding.type_name }
        else
          info = { moved: true, shared: binding.shared, stack: binding.stack, type_name: binding.type_name }
          forget_with_fields(name)
          info
        end
      end

      def release_call?(node)
        return false unless node.is_a?(Hash) && node[:type] == :fn_call
        return true if node[:name] == "free" && node[:args]&.first.is_a?(Hash) && node[:args].first[:type] == :variable
        node[:name].is_a?(String) && node[:name].include?('.') &&
          %w[free deinit].include?(node[:name].split('.', 2).last)
      end

      def visit_expr(expr, remaining, pending, owning: false)
        return expr unless expr.is_a?(Hash) && expr.key?(:type)

        case expr[:type]
        when :variable
          handle_variable_use(expr[:name], expr, remaining, pending, owning: owning)
          expr
        when :fn_call
          visit_call(expr, remaining, pending)
        when :binary_op
          expr[:left]  = visit_expr(expr[:left], remaining, pending, owning: false)
          expr[:right] = visit_expr(expr[:right], remaining, pending, owning: false)
          expr
        when :unary_op
          expr[:expression] = visit_expr(expr[:expression], remaining, pending, owning: false)
          expr
        when :borrow
          inner = expr[:expression]
          if inner.is_a?(Hash) && inner[:type] == :variable
            b = find(inner[:name])
            b.aliased = true if b
          end
          expr[:expression] = visit_expr(inner, remaining, pending, owning: false)
          expr
        when :match_expression
          process_match(expr, remaining, pending)
        else
          generic_visit(expr, remaining, pending)
          expr
        end
      end

      def visit_call(node, remaining, pending)
        if release_call?(node)
          var = nil
          if node[:name] == "free" && node[:args]&.first.is_a?(Hash)
            var = node[:args].first[:name]
          elsif node[:name].is_a?(String) && node[:name].include?('.')
            var = node[:name].split('.', 2).first
          end

          if var && find(var)
            if Scan.references?(remaining, var)
              return nil
            else
              b = find(var)
              forget_with_fields(var)
              return drop_node(var, node, b)
            end
          end
        end

        if node[:args].is_a?(Array)
          node[:args] = node[:args].each_with_index.map do |arg, i|
            if arg.is_a?(Hash) && arg[:type] == :borrow
              visit_expr(arg, remaining, pending, owning: false)
            else
              visit_expr(arg, remaining, pending, owning: !borrowed_param?(node[:name], i))
            end
          end.compact
        end
        node
      end

      def generic_visit(node, remaining, pending)
        node.each_key do |k|
          v = node[k]
          if v.is_a?(Hash)
            node[k] = visit_expr(v, remaining, pending, owning: false)
          elsif v.is_a?(Array)
            node[k] = v.map { |it| it.is_a?(Hash) ? visit_expr(it, remaining, pending, owning: false) : it }.compact
          end
        end
      end

      def process_top(node)
        return nil if node.nil?
        return node unless node.is_a?(Hash) && node.key?(:type)
        node[:type] == :function_definition ? process_function(node) : node
      end

      def process_function(node)
        return node if node[:skip_perceus]

        push_scope(:function)
        (node[:params] || []).each_with_index do |p, i|
          p_name = p.is_a?(Hash) ? p[:name] : p
          next unless p_name
          next if borrowed_param?(node[:name], i)
          type_name = p.is_a?(Hash) ? p[:type_name] : nil
          next unless Scan.resource_type?(type_name)
          current_frame.bindings[p_name] = Binding.new(false, false, type_name, false)
        end
        node[:body] = process_statements(node[:body] || [], [])
        drain_scope(node[:body], current_frame)
        pop_scope
        node
      end

      def process_statements(stmts, continuation)
        return [] unless stmts.is_a?(Array)
        out = []
        stmts.each_with_index do |stmt, i|
          next if stmt.nil?
          remaining = stmts[(i + 1)..] + continuation
          pending = []
          result = process_stmt(stmt, remaining, pending)
          out.concat(pending)
          if result.is_a?(Array)
            out.concat(result.compact)
          elsif result
            out << result
          end
        end
        out
      end

      def process_stmt(stmt, remaining, pending)
        return stmt unless stmt.is_a?(Hash) && stmt.key?(:type)
        case stmt[:type]
        when :function_definition then process_function(stmt)
        when :return               then process_return(stmt, remaining, pending)
        when :break, :continue     then process_break_continue(stmt, pending)
        when :assignment           then process_assignment(stmt, remaining, pending)
        when :if_statement         then process_if(stmt, remaining, pending)
        when :while_statement      then process_while(stmt, remaining, pending)
        when :for_statement        then process_for(stmt, remaining, pending)
        when :match_expression     then process_match(stmt, remaining, pending)
        when :fn_call              then visit_call(stmt, remaining, pending)
        else
          generic_visit(stmt, remaining, pending)
          stmt
        end
      end

      def process_return(stmt, remaining, pending)
        ret = stmt[:expression]
        bare_var = (ret.is_a?(Hash) && ret[:type] == :variable) ? ret[:name] : nil

        if bare_var && Scan.linear_name?(bare_var)
          handle_variable_use(bare_var, ret, [], pending, owning: true)
        elsif ret
          stmt[:expression] = visit_expr(ret, remaining, pending, owning: false)
        end

        drops = []
        @scopes.each do |f|
          ordered_keys(f.bindings).each do |n|
            b = f.bindings[n]
            drops << drop_node(n, stmt, b) unless b.aliased
            f.bindings.delete(n)
          end
        end

        return stmt if drops.empty?
        return drops + [stmt] if bare_var || ret.nil?

        tmp = fresh_name("ret_tmp")
        [let_node(tmp, ret, stmt), *drops, stmt.merge(expression: var_node(tmp, stmt))]
      end

      def process_break_continue(stmt, pending)
        @scopes.reverse_each do |frame|
          ordered_keys(frame.bindings).each do |n|
            b = frame.bindings[n]
            pending << drop_node(n, stmt, b) unless b.aliased
            frame.bindings.delete(n)
          end
          break if frame.kind == :loop
        end
        stmt
      end

      def process_assignment(stmt, remaining, pending)
        name = stmt[:name]
        expr = stmt[:expression]
        bare_var = (expr.is_a?(Hash) && expr[:type] == :variable) ? expr[:name] : nil

        info = nil
        if bare_var && Scan.linear_name?(bare_var)
          info = handle_variable_use(bare_var, expr, remaining, pending, owning: true)
        elsif expr
          stmt[:expression] = visit_expr(expr, remaining, pending, owning: false)
        end

        return stmt unless Scan.linear_name?(name)

        frame = stmt[:let] ? current_frame : (scope_of(name) || owner_frame_for(name))

        old_alive = !stmt[:let] && frame.bindings.key?(name)
        post = []
        if old_alive
          old_b = frame.bindings[name]
          post << drop_node(name, stmt, old_b) unless old_b.aliased
          frame.bindings.delete(name)
        end

        if Scan.allocator_call?(stmt[:expression])
          frame.bindings[name] = Binding.new(false, !!stmt[:expression][:stack_promotable] || !!stmt[:stack_promotable], stmt[:type_name], false)
        elsif Scan.allocates_result?(stmt[:expression])
          frame.bindings[name] = Binding.new(false, false, stmt[:type_name], false)
        elsif info
          frame.bindings[name] = Binding.new(info[:shared], info[:moved] ? info[:stack] : false, info[:type_name], false)
        end

        post.empty? ? stmt : [stmt, *post]
      end

      def drain_scope(body, frame)
        return body if Scan.diverges?(body)
        ordered_keys(frame.bindings).each do |n|
          b = frame.bindings[n]
          body << drop_node(n, body.last || {}, b) unless b.aliased
          frame.bindings.delete(n)
        end
        body
      end

      def process_if(node, remaining, pending)
        body = node[:body] || []
        else_body = node[:else_body]
        cond_remaining = body + (else_body || []) + remaining
        node[:condition] = visit_expr(node[:condition], cond_remaining, pending, owning: false)

        saved = @scopes

        @scopes = clone_scopes(saved)
        push_scope(:block)
        node[:body] = process_statements(body, remaining)
        drain_scope(node[:body], current_frame)
        pop_scope
        then_scopes = @scopes

        else_scopes =
          if else_body
            @scopes = clone_scopes(saved)
            push_scope(:block)
            node[:else_body] = process_statements(else_body, remaining)
            drain_scope(node[:else_body], current_frame)
            pop_scope
            @scopes
          else
            clone_scopes(saved)
          end

        then_nulls, else_nulls = reconcile!(saved, then_scopes, else_scopes)
        then_nulls.each { |n| node[:body] << null_node(n, node) }
        if else_nulls.any?
          node[:else_body] ||= []
          else_nulls.each { |n| node[:else_body] << null_node(n, node) }
        end

        @scopes = saved
        node
      end

      def reconcile!(before, then_scopes, else_scopes)
        then_nulls, else_nulls = [], []
        before.each_with_index do |frame, idx|
          frame.bindings.keys.dup.each do |name|
            t = then_scopes[idx].bindings[name]
            e = else_scopes[idx].bindings[name]
            if t.nil? && e.nil?
              frame.bindings.delete(name)
            else
              frame.bindings[name].shared ||= (t&.shared || e&.shared || false)
              then_nulls << name if t.nil?
              else_nulls << name if e.nil?
            end
          end
        end
        [then_nulls, else_nulls]
      end

      def process_match(node, remaining, pending)
        node[:expression] = visit_expr(node[:expression], remaining, pending, owning: false)
        return node unless node[:cases].is_a?(Array)

        saved = @scopes
        branch_scopes = []

        node[:cases].each do |c|
          next unless c.is_a?(Hash)
          @scopes = clone_scopes(saved)
          push_scope(:match_arm)
          c[:body] = process_statements(c[:body] || [], remaining)
          drain_scope(c[:body], current_frame)
          pop_scope
          branch_scopes << @scopes
        end
        @scopes = saved

        saved.each_with_index do |frame, idx|
          frame.bindings.keys.dup.each do |name|
            present = branch_scopes.map { |bs| bs[idx].bindings.key?(name) }
            if present.all?
              frame.bindings[name].shared ||= branch_scopes.any? { |bs| bs[idx].bindings[name]&.shared }
            elsif present.none?
              frame.bindings.delete(name)
            else
              node[:cases].each_with_index do |c, ci|
                next unless c.is_a?(Hash)
                c[:body] << null_node(name, node) unless present[ci]
              end
            end
          end
        end

        node
      end

      def process_while(node, remaining, pending)
        loop_continuation = node[:body] || []
        node[:condition] = visit_expr(node[:condition], loop_continuation + remaining, pending, owning: false)
        push_scope(:loop)
        node[:body] = process_statements(node[:body] || [], loop_continuation + remaining)
        drain_scope(node[:body], current_frame)
        pop_scope
        node
      end

      def process_for(node, remaining, pending)
        push_scope(:loop)
        loop_continuation = node[:body] || []
        node[:init]      = visit_expr(node[:init], loop_continuation + remaining, pending, owning: true) if node[:init]
        node[:condition] = visit_expr(node[:condition], loop_continuation + remaining, pending, owning: false) if node[:condition]
        node[:body]      = process_statements(node[:body] || [], loop_continuation + remaining)
        node[:update]    = visit_expr(node[:update], loop_continuation + remaining, pending, owning: false) if node[:update]
        drain_scope(node[:body], current_frame)
        pop_scope
        node
      end
    end

    class DropSpecialization
      def initialize(ast)
        @ast = ast
      end

      def run
        walk(@ast)
      end

      private

      def walk(nodes)
        return nodes unless nodes.is_a?(Array)
        nodes.each { |n| walk_node(n) }
        nodes.reject! { |n| n.is_a?(Hash) && n[:type] == :fn_call && %w[__noop __dup_noop].include?(n[:name]) }
        nodes
      end

      def walk_node(node)
        return unless node.is_a?(Hash)
        if node[:type] == :fn_call
          if node[:name] == "drop"
            specialize_drop!(node)
          elsif node[:name] == "dup"
            specialize_dup!(node)
          end
        end
        node.each_value do |v|
          walk(v) if v.is_a?(Array)
          walk_node(v) if v.is_a?(Hash)
        end
      end

      def specialize_drop!(node)
        if node[:stack]
          node[:name] = "__noop"
        elsif node[:resource_type] && node[:resource_type].to_s != "ptr"
          node[:name] = "#{node[:resource_type]}_drop"
        else
          node[:name] = "free"
        end
      end

      def specialize_dup!(node)
        if node[:stack]
          node[:name] = "__dup_noop"
        elsif node[:resource_type] && %w[str string].include?(node[:resource_type].to_s)
          node[:name] = "strdup"
        elsif node[:resource_type] && node[:resource_type].to_s != "ptr"
          node[:name] = "#{node[:resource_type]}_dup"
        else
          node[:name] = "strdup"
        end
      end
    end

    class Pipeline
      def self.run(ast)
        ast = StructResourceGen.new(ast).run
        signatures = OwnershipInference.new(ast).run
        EscapeAnalysis.new(ast).run
        ast = Perceus.new(ast, signatures).run
        ast = DropSpecialization.new(ast).run
        ast
      end
    end
  end

  class AutoDropPass
    def initialize(ast)
      @ast = ast
    end

    def run
      Memory::Pipeline.run(@ast)
    end
  end
end
