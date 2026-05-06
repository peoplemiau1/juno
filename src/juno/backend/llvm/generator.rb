# llvm_generator.rb - Type-aware LLVM IR Backend for Juno
require_relative "parts/statements"
require_relative "parts/expressions"
require_relative "parts/builtins"

class LLVMGenerator
  include LLVMStatementGenerator
  include LLVMExpressionGenerator
  include LLVMBuiltinGenerator

  def initialize(ast, source: "", filename: "main.juno")
    @ast = ast
    @source = source
    @filename = filename
    @output = ""
    @strings = {}
    @string_count = 0
    @tmp_count = 0
    @label_count = 0
    @structs = {}
  end

  BUILTINS = %w(printf malloc realloc free concat trim file_read_all file_read_safe exists write read open close getpid juno_strlen juno_pow time rand srand substr syscall spin_lock spin_unlock)

  def generate
    @output = ""
    emit_header
    setup_builtins
    
    collect_metadata(@ast)
    emit_structs
    emit_strings

    @ast.each do |node|
      process_node(node)
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
    @output << "declare void @llvm.memcpy.p0i8.p0i8.i64(i8*, i8*, i64, i1)\n"
    @output << "declare void @llvm.memset.p0i8.i64(i8*, i8, i64, i1)\n"

    @output << "@fmt_s = private unnamed_addr constant [4 x i8] c\"%s\\0A\\00\"\n"
    @output << "@fmt_i = private unnamed_addr constant [5 x i8] c\"%ld\\0A\\00\"\n"
    @output << "@fmt_out = private unnamed_addr constant [4 x i8] c\"%s\\0A\\00\"\n\n"
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

  def emit_strings
    @strings.each do |val, id|
      escaped = val.chars.map { |c|
        case c
        when "\n" then "\\0A"
        when "\r" then "\\0D"
        when "\t" then "\\09"
        when "\"" then "\\22"
        when "\\" then "\\\\"
        else
          (c.ord < 32 || c.ord > 126) ? "\\#{c.ord.to_s(16).rjust(2, '0').upcase}" : c
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
    params = (node[:params] || []).map { |p| "i64 %#{p}_in" }.join(", ")
    @output << "define i64 @#{node[:name].gsub('.', '_')}(#{params}) {\n"
    @tmp_count = 0
    @label_count = 0
    
    @output << "entry:\n"
    (node[:params] || []).each do |p|
      @output << "  %#{p} = alloca i64\n"
      @output << "  store i64 %#{p}_in, i64* %#{p}\n"
    end

    locals = []
    arrays = {}
    collect_locals(node[:body] || [], locals, arrays)
    
    locals.uniq.each do |var|
      unless (node[:params] || []).include?(var)
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
    res = "t#{@tmp_count}"
    @tmp_count += 1
    res
  end

  def next_label(prefix)
    res = "#{prefix}_#{@label_count}"
    @label_count += 1
    res
  end
end
