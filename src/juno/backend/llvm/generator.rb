require_relative "parts/statements"
require_relative "parts/expressions"
require_relative "parts/builtins"

class LLVMGenerator
  include LLVMStatementGenerator
  include LLVMExpressionGenerator
  include LLVMBuiltinGenerator

  ESCAPE_MAP = {
    "\n".ord => "\\0A",
    "\r".ord => "\\0D",
    "\t".ord => "\\09",
    "\"".ord => "\\22",
    "\\".ord => "\\\\"
  }.freeze

  def initialize(ast, source: "", filename: "main.juno", arch: :x86_64)
    @ast = ast
    @source = source
    @filename = filename
    @arch = arch
    @output = ""
    @strings = {}
    @string_count = 0
    @tmp_count = 0
    @label_count = 0
    @structs = {}
    @enums = {}
    @globals = {}
    @global_types = {}
  end

  BUILTINS = %w(printf malloc realloc free concat trim file_read_all file_read_safe exists write read open close getpid juno_strlen juno_pow time rand srand substr syscall prints)

  def generate
    @output = ""
    emit_header
    setup_builtins

    @globals = {}
    @global_types = {}
    @ast.each do |node|
      if node.is_a?(Hash) && node[:type] == :assignment && node[:let]
        val = node[:expression] && node[:expression][:type] == :literal ? node[:expression][:value] : 0
        @globals[node[:name]] = val
        @global_types[node[:name]] = node[:var_type] if node[:var_type]
      end
    end

    collect_metadata(@ast)
    emit_structs
    emit_strings
    emit_globals

    # Разделение глобальных объявлений и свободных инструкций верхнего уровня
    defs = []
    stmts = []
    @ast.each do |node|
      next if node.nil?
      case node[:type]
      when :function_definition, :extern_definition, :struct_definition, :union_definition, :enum_definition
        defs << node
      when :assignment, :return, :fn_call, :method_call, :if_statement, :while_statement, :for_statement, :increment, :insertC
        stmts << node
      end
    end

    # Генерация глобальных определений
    defs.each { |node| process_node(node) }

    # Определение точки входа
    has_main = defs.any? { |n| n[:type] == :function_definition && n[:name] == "main" }

    if has_main
      # Если функция main уже объявлена пользователем, генерация идет штатно
    elsif !stmts.empty?
      # Если обнаружен код на верхнем уровне — автоматически упаковываем его в @main()
      main_fn = AST::FunctionDefinition.new("main", [], stmts, line: 1, column: 1, filename: @filename)
      gen_function(main_fn)
    else
      # Если свободных инструкций нет, запускаем механизм фоллбека на первую функцию
      first_root_func = defs.find { |n| n[:type] == :function_definition && (n[:filename] == @filename || n[:filename].nil?) }
      if first_root_func
        entry_name = first_root_func[:name].gsub('.', '_')
        params = first_root_func[:params] || []
        args = params.map { "i64 0" }.join(", ")

        @output << "define i64 @main() {\n"
        @output << "entry:\n"
        @output << "  %res = call i64 @#{entry_name}(#{args})\n"
        @output << "  ret i64 %res\n"
        @output << "}\n\n"
      end
    end

    @output
  end

  def emit_header
    @output << "; ModuleID = '#{@filename}'\n"
    @output << "source_filename = \"#{@filename}\"\n"
    @output << "target datalayout = \"e-m:e-p270:32:32-p271:32:32-p272:64:64-i64:64-f80:128-n8:16:32:64-S128\"\n"
    @output << "target triple = \"x86_64-pc-linux-gnu\"\n\n"
  end

  def setup_builtins
    @output << "declare i32 @printf(i8*, ...)\n"
    @output << "declare i64 @malloc(i64)\n"
    @output << "declare i64 @realloc(i8*, i64)\n"
    @output << "declare void @free(i8*)\n"
    @output << "declare i64 @concat(i64, i64)\n"
    @output << "declare i64 @trim(i64)\n"
    @output << "declare i64 @file_read_all(i64)\n"
    @output << "declare i64 @file_read_safe(i64)\n"
    @output << "declare i64 @exists(i64)\n"
    @output << "declare i64 @write(i32, i8*, i64)\n"
    @output << "declare i64 @read(i32, i8*, i64)\n"
    @output << "declare i32 @open(i8*, i32, ...)\n"
    @output << "declare i32 @close(i32)\n"
    @output << "declare i32 @getpid()\n"
    @output << "declare i64 @juno_strlen(i64)\n"
    @output << "declare i64 @juno_pow(i64, i64)\n"
    @output << "declare i64 @time(i64)\n"
    @output << "declare i32 @rand()\n"
    @output << "declare void @srand(i32)\n"
    @output << "declare i64 @substr(i64, i64, i64)\n"
    @output << "declare i64 @syscall(i64, ...)\n"
    @output << "declare i64 @prints(i64)\n"
    @output << "declare void @llvm.memcpy.p0i8.p0i8.i64(i8*, i8*, i64, i1)\n"
    @output << "declare void @llvm.memset.p0i8.i64(i8*, i8, i64, i1)\n"
    @output << "declare void @exit(i32)\n"

    @output << "@fmt_s = private unnamed_addr constant [3 x i8] c\"%s\\00\"\n"
    @output << "@fmt_i = private unnamed_addr constant [4 x i8] c\"%ld\\00\"\n"
    @output << "@fmt_out = private unnamed_addr constant [3 x i8] c\"%s\\00\"\n\n"
  end

  def collect_metadata(node)
    return if node.nil?
    if node.is_a?(Array)
      node.each { |n| collect_metadata(n) }
    elsif node.is_a?(Hash)
      case node[:type]
      when :string_literal
        val = node[:value]
        unless @strings.key?(val)
          id = "str_#{@string_count}"
          @strings[val] = id
          @string_count += 1
        end
      when :struct_definition
        @structs[node[:name]] = {
          fields: node[:fields],
          field_types: node[:field_types] || {}
        }
      when :enum_definition
        @enums ||= {}
        variants = {}
        max_payload = 0
        node[:variants].each_with_index do |v, idx|
          payload_size = (v[:params] || []).length * 8
          max_payload = payload_size if payload_size > max_payload
          variants[v[:name]] = { tag: idx, params: v[:params] || [] }
        end
        @enums[node[:name]] = { size: 8 + max_payload, variants: variants }
      end
      node.each { |k, v| collect_metadata(v) if v.is_a?(Hash) || v.is_a?(Array) }
    end
  end

  def emit_structs
    @structs.each do |name, info|
      fields = info[:fields].map { "i64" }.join(", ")
      @output << "%struct.#{name} = type { #{fields} }\n"
    end
    @output << "\n"
  end

  def emit_globals
    @globals.each do |name, val|
      @output << "@#{name} = global i64 #{val}\n"
    end
    @output << "\n"
  end

  def emit_strings
    @strings.each do |val, id|
      escaped = val.bytes.map { |b|
        if escaped_char = ESCAPE_MAP[b]
          escaped_char
        elsif b < 32 || b > 126
          "\\%02X" % b
        else
          b.chr
        end
      }.join
      len = val.bytesize + 1
      @output << "@#{id} = private unnamed_addr constant [#{len} x i8] c\"#{escaped}\\00\"\n"
    end
    @output << "\n"
  end

  def process_node(node)
    return if node.nil?
    case node[:type]
    when :function_definition
      gen_function(node)
    when :extern_definition
      gen_extern(node)
    end
  end

  def gen_extern(node)
    return if BUILTINS.include?(node[:name])
    params = (node[:params] || []).map { "i64" }.join(", ")
    @output << "declare i64 @#{node[:name]}(#{params})\n"
  end

  def gen_function(node)
    @current_function = node
    fn_params = (node[:params] || []).dup
    if node[:name].include?('.') && !fn_params.include?("self")
      fn_params.unshift("self")
    end
    params = fn_params.map { |p| "i64 %#{p}_in" }.join(", ")
    
    has_insertC = node[:body]&.any? { |s| s.is_a?(Hash) && s[:type] == :insertC }
    attrs = has_insertC ? " noinline" : ""
    
    @output << "define i64 @#{node[:name].gsub('.', '_')}(#{params})#{attrs} {\n"
    @tmp_count = 0
    @label_count = 0

    @output << "entry:\n"
    fn_params.each do |p|
      @output << "  %#{p} = alloca i64\n"
      @output << "  store i64 %#{p}_in, i64* %#{p}\n"
    end

    locals = []
    arrays = {}
    collect_locals(node[:body] || [], locals, arrays)

    locals.uniq.each do |var|
      # Исключаем глобальные переменные из аллокации на локальном стеке
      unless fn_params.include?(var) || (@globals && @globals.key?(var))
        @output << "  %#{var} = alloca i64\n"
      end
    end

    arrays.each do |var, size|
      @output << "  %#{var} = alloca [#{size} x i64]\n"
    end
    @current_arrays = arrays

    node[:body].each { |stmt| gen_statement(stmt) }

    unless node[:body].last&.[](:type) == :return
      @output << "  ret i64 0\n"
    end
    @output << "}\n\n"
  end

  def next_tmp
    res = "tmp#{@tmp_count}" 
    @tmp_count += 1
    res
  end

  def next_label(prefix)
    res = "#{prefix}_#{@label_count}"
    @label_count += 1
    res
  end
end
