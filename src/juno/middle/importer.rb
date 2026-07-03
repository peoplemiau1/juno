require_relative "../frontend/lexer"
require_relative "../frontend/parser"
require_relative "../errors"
require "set"

class CHeaderParser
  @@seen = {}

  def self.clear_seen!
    @@seen = {}
  end

  def self.parse(header_path, lib_name)
    if header_path == "vulkan/vulkan.h" || header_path == "vulkan/vulkan_core.h"
      header_path = "vulkan/vulkan_core.h"
      lib_name = "libvulkan.so"
    elsif header_path == "GL/gl.h"
      lib_name = "libGL.so"
    elsif header_path == "GLFW/glfw3.h"
      lib_name = "libglfw.so"
    end

    path = find_header(header_path)
    return [] unless path && File.exist?(path)

    content = File.read(path)
    content.gsub!(/\/\*.*?\*\//m, '')
    content.gsub!(/\/\/.*$/, '')
    content.gsub!(/^#.*$/, '')

    nodes = []
    decl_regex = /([\w\s\*]+?)\s+(\w+)\s*\(([^\)]*)\)[^;]*;/

    content.scan(decl_regex) do |ret_type, func_name, args_str|
      next if %w[if else return while for switch do].include?(func_name)
      next if @@seen.key?(func_name)

      args = []
      param_types = {}
      args_str = args_str.strip

      if args_str != "void" && !args_str.empty?
        args_str.split(',').each_with_index do |arg, idx|
          parts = arg.strip.split(/\s+/)
          next if parts.empty?

          param_name = parts.last
          type_parts = parts[0...-1]

          if param_name.include?('*')
            type_parts << "*"
            param_name = param_name.sub('*', '')
          end

          if type_parts.empty?
            type_str = param_name
            param_name = "arg#{idx}"
          else
            type_str = type_parts.join(' ')
          end

          param_name = param_name.gsub(/[^\w]/, '')
          param_name = "arg#{idx}" if param_name.empty? || param_name =~ /^\d/

          mapped_type = map_type(type_str)
          args << param_name
          param_types[param_name] = mapped_type
        end
      end

      @@seen[func_name] = true
      nodes << {
        type: :extern_definition,
        name: func_name,
        symbol: func_name,
        params: args,
        param_types: param_types,
        return_type: map_type(ret_type),
        lib: lib_name
      }
    end

    if ENV['JUNO_DEBUG']
      $stderr.puts "DEBUG: CHeaderParser parsed #{nodes.size} functions from #{header_path} (resolved to #{path})"
    end

    nodes
  end

  def self.find_header(header_path)
    if header_path.include?('/') && File.exist?(header_path)
      return header_path
    end
    search_paths = [
      ".",
      "/usr/include",
      "/usr/local/include",
      "/usr/lib/clang/include",
      "/Library/Developer/CommandLineTools/usr/include"
    ]
    search_paths.each do |dir|
      full_path = File.join(dir, header_path)
      return full_path if File.exist?(full_path)
    end
    File.exist?(header_path) ? header_path : nil
  end

  def self.map_type(c_type)
    c_type = c_type.strip.gsub(/\s+/, ' ')
    c_type = c_type.gsub(/\b(extern|const|volatile|restrict|__restrict|__const|inline|VKAPI_ATTR|VKAPI_CALL|GLAPI|APIENTRY)\b/, '').strip
    return "ptr" if c_type.include?('*')
    case c_type
    when "float", "double" then "float"
    when "void" then "void"
    when "int", "char", "short", "long", "size_t", "int32_t", "uint32_t", "int64_t", "uint64_t" then "int"
    else "int"
    end
  end
end

class CppHeaderParser
  FUNDAMENTAL_MANGLE = {
    "void" => "v",
    "bool" => "b",
    "char" => "c",
    "signed char" => "a",
    "unsigned char" => "h",
    "wchar_t" => "w",
    "short" => "s",
    "short int" => "s",
    "unsigned short" => "t",
    "unsigned short int" => "t",
    "int" => "i",
    "unsigned" => "j",
    "unsigned int" => "j",
    "long" => "l",
    "long int" => "l",
    "unsigned long" => "m",
    "unsigned long int" => "m",
    "long long" => "x",
    "long long int" => "x",
    "unsigned long long" => "y",
    "unsigned long long int" => "y",
    "float" => "f",
    "double" => "d",
    "long double" => "e",
    "size_t" => "m",
    "ssize_t" => "l",
    "int8_t" => "a",
    "uint8_t" => "h",
    "int16_t" => "s",
    "uint16_t" => "t",
    "int32_t" => "i",
    "uint32_t" => "j",
    "int64_t" => "l",
    "uint64_t" => "m"
  }.freeze

  JUNO_TYPE_FOR = Hash.new("int").merge(
    "void" => "void",
    "float" => "float",
    "double" => "float",
    "long double" => "float"
  ).freeze

  @@seen = {}

  def self.clear_seen!
    @@seen = {}
  end

  def self.parse(header_path, lib_name)
    if header_path == "vulkan/vulkan.h" || header_path == "vulkan/vulkan_core.h"
      header_path = "vulkan/vulkan_core.h"
      lib_name = "libvulkan.so"
    elsif header_path == "GL/gl.h"
      lib_name = "libGL.so"
    elsif header_path == "GLFW/glfw3.h"
      lib_name = "libglfw.so"
    end

    path = CHeaderParser.find_header(header_path)
    return [] unless path && File.exist?(path)

    raw = File.read(path)
    content = strip_comments(raw)

    nodes = []
    nodes.concat(parse_extern_c_blocks(content, lib_name))

    remainder = remove_extern_c_blocks(content)
    remainder = strip_templates(remainder)
    remainder = strip_class_bodies(remainder)
    nodes.concat(parse_decls(remainder, lib_name, mangle: true))

    if ENV['JUNO_DEBUG']
      $stderr.puts "DEBUG: CppHeaderParser parsed #{nodes.size} functions from #{header_path} (resolved to #{path})"
    end

    nodes
  end

  def self.strip_comments(content)
    content = content.gsub(/\/\*.*?\*\//m, '')
    content = content.gsub(/\/\/.*$/, '')
    content.gsub(/^\s*#.*$/, '')
  end

  def self.remove_extern_c_blocks(content)
    content.gsub(/extern\s+"C"\s*\{.*?\}/m, '')
           .gsub(/extern\s+"C"\s*[^{};]+;/, '')
  end

  def self.parse_extern_c_blocks(content, lib_name)
    nodes = []

    content.scan(/extern\s+"C"\s*\{(.*?)\}/m) do |body|
      nodes.concat(parse_decls(body.first, lib_name, mangle: false))
    end

    content.scan(/extern\s+"C"\s*([^{};]+;)/) do |decl|
      nodes.concat(parse_decls(decl.first, lib_name, mangle: false))
    end

    nodes
  end

  def self.strip_templates(content)
    result = +""
    i = 0
    len = content.length

    while i < len
      boundary_ok = i == 0 || content[i - 1] !~ /[A-Za-z0-9_]/
      is_template = boundary_ok && content[i, 8] == "template" &&
                    (i + 8 == len || content[i + 8] !~ /[A-Za-z0-9_]/)

      if is_template
        j = i + 8
        j += 1 while j < len && content[j] =~ /\s/

        if j < len && content[j] == '<'
          angle_depth = 0
          while j < len
            angle_depth += 1 if content[j] == '<'
            angle_depth -= 1 if content[j] == '>'
            j += 1
            break if angle_depth == 0
          end
        end

        j += 1 while j < len && content[j] != '{' && content[j] != ';'

        if j < len && content[j] == '{'
          depth = 1
          j += 1
          while j < len && depth > 0
            depth += 1 if content[j] == '{'
            depth -= 1 if content[j] == '}'
            j += 1
          end
        elsif j < len && content[j] == ';'
          j += 1
        end

        i = j
      else
        result << content[i]
        i += 1
      end
    end

    result
  end

  def self.strip_class_bodies(content)
    result = +""
    i = 0
    len = content.length

    while i < len
      boundary_ok = i == 0 || content[i - 1] !~ /[A-Za-z0-9_]/
      is_class = boundary_ok && content[i, 6] == "class "
      is_struct = boundary_ok && content[i, 7] == "struct "

      if is_class || is_struct
        brace_idx = content.index('{', i)
        semi_idx = content.index(';', i)

        if brace_idx && (semi_idx.nil? || brace_idx < semi_idx)
          depth = 1
          j = brace_idx + 1
          while j < len && depth > 0
            depth += 1 if content[j] == '{'
            depth -= 1 if content[j] == '}'
            j += 1
          end
          j += 1 while j < len && content[j] != ';' && content[j] != "\n"
          i = j
          next
        end
      end

      result << content[i]
      i += 1
    end

    result
  end

  def self.parse_decls(content, lib_name, mangle:)
    nodes = []
    decl_regex = /([\w:\s\*&]+?)\s+(\w+)\s*\(([^\)]*)\)[^;{]*;/

    content.scan(decl_regex) do |ret_type, func_name, args_str|
      next if %w[if else return while for switch do sizeof].include?(func_name)
      next if @@seen.key?(func_name)

      cpp_params = []
      args_str = args_str.strip
      ok = true

      if args_str != "void" && !args_str.empty?
        args_str.split(',').each do |arg|
          arg = arg.strip.sub(/=.*/, '').strip
          next if arg.empty?
          info = parse_cpp_param_type(arg)
          if info.nil?
            ok = false
            break
          end
          cpp_params << info
        end
      end

      next unless ok

      ret_info = parse_cpp_return_type(ret_type)
      next if ret_info.nil?

      symbol = mangle ? mangle_itanium(func_name, cpp_params) : func_name

      params = cpp_params.each_index.map { |idx| "arg#{idx}" }
      param_types = params.each_with_index.to_h { |p, idx| [p, cpp_params[idx][:juno_type]] }

      @@seen[func_name] = true
      nodes << {
        type: :extern_definition,
        name: func_name,
        symbol: symbol,
        params: params,
        param_types: param_types,
        return_type: ret_info[:juno_type],
        lib: lib_name
      }
    end

    nodes
  end

  def self.parse_cpp_return_type(raw)
    raw = raw.strip.gsub(/\s+/, ' ')
    raw = raw.gsub(/\b(extern|static|inline|virtual|explicit|friend|constexpr)\b/, '').strip
    return { juno_type: "void" } if raw == "void"
    return nil if raw.count('*') > 1

    if raw.end_with?('*') || raw.end_with?('&')
      { juno_type: "ptr" }
    else
      base = raw.gsub(/\bconst\b/, '').strip
      return nil unless FUNDAMENTAL_MANGLE.key?(base)
      { juno_type: JUNO_TYPE_FOR[base] }
    end
  end

  def self.parse_cpp_param_type(arg)
    arg = arg.strip
    return nil if arg.empty?
    return nil if arg.include?('(') || arg.include?('[')

    type_part = strip_trailing_identifier(arg)
    return nil if type_part.count('*') > 1

    is_ref = type_part.include?('&')
    is_ptr = type_part.include?('*')
    cleaned = type_part.gsub(/[\*&]/, ' ')
    is_const = !!(cleaned =~ /\bconst\b/)
    base = cleaned.gsub(/\bconst\b/, '').strip.gsub(/\s+/, ' ')

    return nil unless FUNDAMENTAL_MANGLE.key?(base)
    code = FUNDAMENTAL_MANGLE[base]

    mangled =
      if is_ptr
        is_const ? "PK#{code}" : "P#{code}"
      elsif is_ref
        is_const ? "RK#{code}" : "R#{code}"
      else
        code
      end

    juno_type = (is_ptr || is_ref) ? "ptr" : JUNO_TYPE_FOR[base]
    { mangle: mangled, juno_type: juno_type }
  end

  def self.strip_trailing_identifier(arg)
    if arg =~ /^(.*?[\*&\s])([a-zA-Z_]\w*)\s*$/
      candidate = $1.strip
      return candidate unless candidate.empty?
    end
    arg
  end

  def self.mangle_itanium(func_name, cpp_params)
    subs = []
    body =
      if cpp_params.empty?
        "v"
      else
        cpp_params.map { |p| encode_with_substitution(p[:mangle], subs) }.join
      end

    "_Z#{func_name.length}#{func_name}#{body}"
  end

  def self.encode_with_substitution(mangled, subs)
    return mangled if mangled.length <= 1

    existing = subs.index(mangled)
    if existing
      return existing.zero? ? "S_" : "S#{to_base36(existing - 1)}_"
    end

    subs << mangled
    mangled
  end

  def self.to_base36(n)
    digits = "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ"
    return "0" if n == 0
    s = +""
    while n > 0
      s = digits[n % 36] + s
      n /= 36
    end
    s
  end
end

class BuiltinLibm
  SIGNATURES = {
    "sin"          => { params: ["float"],          return_type: "float" },
    "cos"          => { params: ["float"],          return_type: "float" },
    "tan"          => { params: ["float"],          return_type: "float" },
    "asin"         => { params: ["float"],          return_type: "float" },
    "acos"         => { params: ["float"],          return_type: "float" },
    "atan"         => { params: ["float"],          return_type: "float" },
    "atan2"        => { params: ["float", "float"], return_type: "float" },
    "sqrt"         => { params: ["float"],          return_type: "float" },
    "cbrt"         => { params: ["float"],          return_type: "float" },
    "pow"          => { params: ["float", "float"], return_type: "float" },
    "exp"          => { params: ["float"],          return_type: "float" },
    "log"          => { params: ["float"],          return_type: "float" },
    "log2"         => { params: ["float"],          return_type: "float" },
    "log10"        => { params: ["float"],          return_type: "float" },
    "floor"        => { params: ["float"],          return_type: "float" },
    "ceil"         => { params: ["float"],          return_type: "float" },
    "round"        => { params: ["float"],          return_type: "float" },
    "trunc"        => { params: ["float"],          return_type: "float" },
    "fabs"         => { params: ["float"],          return_type: "float" },
    "fmod"         => { params: ["float", "float"], return_type: "float" },
    "hypot"        => { params: ["float", "float"], return_type: "float" },
    "float_to_int" => { params: ["float"],          return_type: "int" }
  }.freeze

  LIB_NAME = "m"

  def self.known?(name) = SIGNATURES.key?(name)
  def self.signature_for(name) = SIGNATURES[name]
end

class AutoExternPass
  def self.run(ast)
    declared = Set.new
    called   = {}

    walk(ast) do |node|
      case node[:type]
      when :function_definition, :extern_definition
        declared << node[:name]
      when :fn_call
        if BuiltinLibm.known?(node[:name])
          node[:name] = (node[:name] == "pow") ? "juno_fpow" : "juno_#{node[:name]}"
        end
        called[node[:name]] = node unless node[:name].to_s.include?('.')
      end
    end

    missing = []

    called.each_key do |name|
      next if declared.include?(name)
      base_name = (name == "juno_fpow") ? "pow" : name.sub(/^juno_/, '')
      sig = BuiltinLibm.signature_for(base_name)
      next unless sig

      params = Array.new(sig[:params].size) { |i| "arg#{i}" }
      param_types = params.each_with_index.to_h { |p, i| [p, "int"] }

      missing << {
        type: :extern_definition,
        name: name,
        symbol: name,
        params: params,
        param_types: param_types,
        return_type: "int",
        lib: BuiltinLibm::LIB_NAME
      }
      declared << name
    end

    missing + ast
  end

  def self.walk(nodes, &block)
    Array(nodes).each { |n| walk_node(n, &block) }
  end

  def self.walk_node(node, &block)
    return unless node.is_a?(Hash)
    block.call(node) if node.key?(:type)
    node.each_value do |v|
      if v.is_a?(Hash)
        walk_node(v, &block)
      elsif v.is_a?(Array)
        v.each { |item| walk_node(item, &block) }
      end
    end
  end
end

class CppManglePass
  def self.run(ast)
    symbol_map = {}
    walk(ast) do |node|
      if node[:type] == :extern_definition && node[:symbol] && node[:name] != node[:symbol]
        symbol_map[node[:name]] = node[:symbol]
      end
    end

    return ast if symbol_map.empty?

    walk(ast) do |node|
      if node[:type] == :fn_call && symbol_map.key?(node[:name])
        node[:name] = symbol_map[node[:name]]
      elsif node[:type] == :extern_definition && symbol_map.key?(node[:name])
        node[:name] = symbol_map[node[:name]]
      end
    end

    ast
  end

  def self.walk(nodes, &block)
    Array(nodes).each { |n| walk_node(n, &block) }
  end

  def self.walk_node(node, &block)
    return unless node.is_a?(Hash)
    block.call(node) if node.key?(:type)
    node.each_value do |v|
      if v.is_a?(Hash)
        walk_node(v, &block)
      elsif v.is_a?(Array)
        v.each { |item| walk_node(item, &block) }
      end
    end
  end
end

class UndefinedCallCheckPass
  BUILTIN_CONTROL = %w[
    free malloc alloc os_alloc mem_malloc stack_alloc reuse_alloc
    arena_create arena_alloc arena_reset arena_destroy
    realloc dup drop rc_dec printf syscall str_len concat substr
    time rand srand max min abs pow ord chr
    i8 u8 i16 u16 i32 u32 i64 u64 ptr_add byte_add ptr_sub ptr_diff
    memcpy memset write read open close spin_lock spin_unlock
    store_i64 store_ptr load_i64 load_ptr store_i8 load_i8
    byte_at byte_set prints len sizeof
  ].freeze

  def self.run(ast, filename: "unknown")
    known = Set.new(BUILTIN_CONTROL)

    AutoExternPass.walk(ast) do |node|
      known << node[:name] if %i[function_definition extern_definition].include?(node[:type])
    end

    AutoExternPass.walk(ast) do |node|
      next unless node[:type] == :fn_call
      name = node[:name]
      next if name.to_s.include?('.')
      next if known.include?(name)

      raise JunoImportError.new(
        "Undefined function '#{name}' - did you forget an 'import_c' " \
        "or a function definition? The compiler will not guess its signature.",
        filename: filename,
        line_num: node[:line]
      )
    end

    ast
  end
end

class Importer
  CPP_EXTENSIONS = %w[.hpp .hh .hxx .h++ .hp .cc .cpp].freeze

  def initialize(base_path = ".", system_path: nil)
    @base_path = base_path
    @system_path = system_path
    @imported = {}
    @import_stack = []
  end

  def resolve(ast, current_file = nil)
    result = []

    if @import_stack.empty?
      CHeaderParser.clear_seen!
      CppHeaderParser.clear_seen!
    end

    ast.each do |node|
      if node[:type] == :import || node[:type] == :use_statement
        begin
          imported_ast = process_import(node[:path], current_file, node[:system] || node[:type] == :use_statement)
        rescue JunoImportError => e
          if !node[:system] && node[:type] != :use_statement
            begin
              imported_ast = process_import(node[:path], current_file, true)
            rescue JunoImportError
              raise e
            end
          else
            raise e
          end
        end
        result.concat(imported_ast)
      elsif node[:type] == :import_c
        parser_class = cpp_header?(node) ? CppHeaderParser : CHeaderParser
        result.concat(parser_class.parse(node[:header_path], node[:lib_name]))
      else
        result << node
      end
    end

    if @import_stack.empty?
      result = AutoExternPass.run(result)
      result = CppManglePass.run(result)
      result = UndefinedCallCheckPass.run(result, filename: current_file || "unknown")
    end

    result
  end

  private

  def cpp_header?(node)
    return true if node[:cpp]
    ext = File.extname(node[:header_path].to_s).downcase
    CPP_EXTENSIONS.include?(ext)
  end

  def process_import(path, current_file, is_system = false)
    if is_system && @system_path
      check_path = (path == "std/std") ? "std" : path
      full_path = File.join(@system_path, check_path)
    elsif current_file
      base_dir = File.dirname(current_file)
      full_path = File.join(base_dir, path)
    else
      full_path = File.join(@base_path, path)
    end

    full_path = File.expand_path(full_path)

    unless File.file?(full_path)
      if File.exist?(full_path + ".juno")
        full_path += ".juno"
      elsif File.exist?(full_path + ".wt")
        full_path += ".wt"
      end
    end

    if @import_stack.include?(full_path)
      cycle = @import_stack.drop_while { |p| p != full_path } + [full_path]
      raise JunoImportError.new(
        "Circular import detected: #{cycle.join(' -> ')}",
        filename: current_file || "unknown"
      )
    end

    return [] if @imported.key?(full_path)

    unless File.exist?(full_path)
      raise JunoImportError.new(
        "Cannot find module '#{path}'",
        filename: current_file || "unknown"
      )
    end

    @import_stack.push(full_path)
    begin
      source = File.read(full_path)
      lexer = Lexer.new(source, full_path)
      tokens = lexer.tokenize
      parser = Parser.new(tokens, full_path, source)
      imported_ast = parser.parse

      resolved_ast = resolve(imported_ast, full_path)

      definitions = resolved_ast.select do |node|
        case node[:type]
        when :struct_definition, :enum_definition, :type_alias, :extern_definition, :union_definition
          true
        when :function_definition
          node[:name] != "main"
        when :assignment
          node[:let] == true
        else
          false
        end
      end

      @imported[full_path] = definitions
      definitions
    ensure
      @import_stack.pop
    end
  end
end

class JunoImportError < JunoError
  def initialize(message, filename: "unknown", line_num: nil)
    super("E0002", message, filename: filename, line_num: line_num)
  end
end
