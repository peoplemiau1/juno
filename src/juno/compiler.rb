require_relative "frontend/lexer"
require_relative "frontend/parser"
require_relative "frontend/preprocessor"
require_relative "middle/importer"
require_relative "middle/monomorphizer"
require_relative "middle/semantic"
require_relative "middle/analyzer/auto_drop"
require_relative "backend/llvm/generator"
require_relative "errors"

module Juno
  class Compiler
    attr_reader :asm_log

    @@toolchain_mutex = Mutex.new
    @@toolchain_cache = {}

    def self.compile_many(files, base_options = {})
      threads = files.map do |entry|
        file, overrides = entry.is_a?(Array) ? entry : [entry, {}]
        Thread.new do
          compiler = new(base_options.merge(overrides))
          [file, compiler.compile(file)]
        end
      end
      threads.each_with_object({}) do |t, acc|
        k, v = t.value
        acc[k] = v
      end
    end

    def initialize(options = {})
      @options = {
        arch: :x86_64,
        os: :linux,
        output: "build/output",
        stdlib_path: find_stdlib_path,
        no_std: false,
        static: ARGV.include?("--static") || ARGV.include?("-static")
      }.merge(options)
    end

    def compile_async(input_file, &block)
      Thread.new do
        result = compile(input_file)
        block.call(result) if block
        result
      end
    end

    def compile(input_file)
      begin
        code = File.read(input_file)
      rescue Errno::ENOENT
        JunoErrorReporter.report(JunoError.new("E0000", "file not found: #{input_file}"))
      end

      unless @options[:no_std]
        if input_file != File.join(@options[:stdlib_path], "std.juno") && !code.include?("import \"std\"")
          code = "import \"std.juno\"\n" + code
        end
      end

      preprocessor = Preprocessor.new
      preprocessor.define(@options[:os].to_s.upcase)
      preprocessor.define("__JUNO__")
      code = preprocessor.process(code, input_file)

      begin
        lexer = Lexer.new(code, input_file)
        tokens = lexer.tokenize
        parser = Parser.new(tokens, input_file, code)
        ast = parser.parse
      rescue JunoMultiParseError => e
        JunoErrorReporter.report(e)
      end

      importer = Importer.new(File.dirname(input_file), system_path: @options[:stdlib_path])
      ast = importer.resolve(ast, input_file)

      monomorphizer = Monomorphizer.new(ast)
      ast = monomorphizer.monomorphize

      analyzer = SemanticAnalyzer.new(ast, input_file, code)
      begin
        ast = analyzer.analyze
      rescue JunoMultiParseError => e
        JunoErrorReporter.report(e)
      end

      auto_drop = AutoDropPass.new(ast)
      ast = auto_drop.run

      generator = LLVMGenerator.new(ast, source: code, filename: input_file, arch: @options[:arch])
      llvm_ir = generator.generate
      @asm_log = [llvm_ir]

      ir_file = @options[:output] + ".ll"
      obj_file = @options[:output] + ".o"
      File.write(ir_file, llvm_ir)

      target_triple = detect_target_triple
      toolchain = resolve_toolchain
      llc_cmd = toolchain[:llc]
      opt_cmd = toolchain[:opt]

      raw_opt = (@options[:opt_level] || 2).to_s
      opt_level = (raw_opt == 's' || raw_opt == 'z') ? raw_opt : raw_opt.to_i

      runtime_obj = File.expand_path("backend/llvm/runtime_#{@options[:os]}_#{@options[:arch]}.o", __dir__)
      runtime_src = File.expand_path("backend/llvm/runtime.c", __dir__)

      if @options[:static] && @options[:os] == :macos
        $stderr.puts "Warning: macOS does not support fully static linking. Falling back to dynamic linking."
        @options[:static] = false
      end

      compile_track = Thread.new { run_llvm_pipeline(ir_file, obj_file, opt_cmd, llc_cmd, opt_level, target_triple) }
      runtime_track = Thread.new { ensure_runtime_object(runtime_obj, runtime_src) }
      libs_track = Thread.new { collect_and_resolve_libs(ast) }

      compile_track.value
      runtime_track.value
      libs_result = libs_track.value

      if @options[:target] == :flat || @options[:target].to_s == "flat"
        objcopy_cmd = RUBY_PLATFORM =~ /darwin/i ? "llvm-objcopy" : "objcopy"
        unless system("#{objcopy_cmd} -O binary #{obj_file} #{@options[:output]}")
          raise "objcopy failed"
        end
      elsif @options[:target] == :obj || @options[:target].to_s == "obj"
        File.binwrite(@options[:output], File.binread(obj_file))
      else
        link(obj_file, runtime_obj, libs_result)
      end

      @options[:output]
    end

    private

    def run_llvm_pipeline(ir_file, obj_file, opt_cmd, llc_cmd, opt_level, target_triple)
      raise "llc not found, install LLVM" if llc_cmd.nil?

      target_ir_file = ir_file

      if opt_cmd && opt_level.to_s != "0"
        optimized_ir_file = @options[:output] + ".opt.ll"
        if system("#{opt_cmd} -passes='default<O#{opt_level}>' -S -o #{optimized_ir_file} #{ir_file}")
          target_ir_file = optimized_ir_file
        elsif system("#{opt_cmd} -O#{opt_level} -S -o #{optimized_ir_file} #{ir_file}")
          target_ir_file = optimized_ir_file
        end
      end

      llc_opt = (opt_level == 's' || opt_level == 'z') ? "-O2" : "-O#{opt_level}"
      unless system("#{llc_cmd} #{llc_opt} -function-sections -data-sections -mtriple=#{target_triple} -relocation-model=pic -filetype=obj -o #{obj_file} #{target_ir_file}")
        raise "LLVM backend (llc) compilation failed"
      end

      obj_file
    end

    def ensure_runtime_object(runtime_obj, runtime_src)
      return runtime_obj if File.exist?(runtime_obj)

      if @options[:os] == :macos && RUBY_PLATFORM !~ /darwin/i && @options[:darling]
        darling_runtime_obj = "/Volumes/SystemRoot" + runtime_obj
        darling_runtime_src = "/Volumes/SystemRoot" + runtime_src
        unless system("darling shell clang -fPIC -O2 -c -o #{darling_runtime_obj} #{darling_runtime_src}")
          raise "runtime compilation failed (darling clang)"
        end
      else
        unless system("gcc -fPIC -O2 -c -o #{runtime_obj} #{runtime_src}")
          raise "runtime compilation failed (gcc)"
        end
      end

      runtime_obj
    end

    def collect_and_resolve_libs(ast)
      libs = []
      collect_libs = ->(n) do
        return unless n.is_a?(Hash)
        if n[:type] == :extern_definition && n[:lib]
          lib_clean = n[:lib].to_s.sub(/^lib/, '').sub(/\.(so|dylib|dll)(\.\d+)*$/, '')
          libs << "-l#{lib_clean}" unless %w[c libc].include?(lib_clean)
        end
        n.each_value do |v|
          if v.is_a?(Hash)
            collect_libs.call(v)
          elsif v.is_a?(Array)
            v.each { |it| collect_libs.call(it) if it.is_a?(Hash) }
          end
        end
      end
      ast.each { |n| collect_libs.call(n) }

      lib_search_paths = [
        ".",
        "/usr/lib",
        "/usr/local/lib",
        "/lib",
        "/lib64",
        "/usr/lib/x86_64-linux-gnu",
        "/usr/lib/aarch64-linux-gnu"
      ]

      static_libs = []
      dynamic_libs = []

      if @options[:static]
        exist_check = ->(lib_name) do
          lib_search_paths.any? do |dir|
            File.exist?(File.join(dir, "lib#{lib_name}.a")) || File.exist?(File.join(dir, "#{lib_name}.a"))
          end
        end

        has_external_dynamic_libs = libs.any? do |lib|
          lib_name = lib.sub(/^-l/, '')
          next false if %w[c m].include?(lib_name)
          !exist_check.call(lib_name)
        end

        (libs + ["-lm", "-lc"]).uniq.each do |lib|
          lib_name = lib.sub(/^-l/, '')
          if %w[c m].include?(lib_name)
            if has_external_dynamic_libs
              dynamic_libs << lib
            else
              static_libs << lib
            end
          else
            if exist_check.call(lib_name)
              static_libs << lib
            else
              dynamic_libs << lib
            end
          end
        end
      else
        dynamic_libs = (libs + ["-lm"]).uniq
      end

      { libs: libs, static_libs: static_libs, dynamic_libs: dynamic_libs }
    end

    def link(obj_file, runtime_obj, libs_result)
      libs = libs_result[:libs]
      static_libs = libs_result[:static_libs]
      dynamic_libs = libs_result[:dynamic_libs]

      if @options[:os] == :macos
        libs_str = (libs + ["-lm"]).uniq.join(" ")
        if RUBY_PLATFORM !~ /darwin/i && @options[:darling]
          darling_output = "/Volumes/SystemRoot" + File.expand_path(@options[:output])
          darling_obj_file = "/Volumes/SystemRoot" + File.expand_path(obj_file)
          darling_runtime_obj = "/Volumes/SystemRoot" + runtime_obj
          link_cmd = "darling shell clang -o #{darling_output} #{darling_obj_file} #{darling_runtime_obj} -L. -Wl,-rpath,'\$ORIGIN' -Wl,--gc-sections #{libs_str} -lm"
        else
          link_cmd = "gcc -o #{@options[:output]} #{obj_file} #{runtime_obj} -L. -Wl,-rpath,'\$ORIGIN' -Wl,--gc-sections #{libs_str} -lm"
        end
      else
        if @options[:static]
          libs_str = "-Wl,-Bstatic "
          libs_str << static_libs.uniq.join(" ")
          if !dynamic_libs.empty?
            libs_str << " -Wl,-Bdynamic "
            libs_str << dynamic_libs.uniq.join(" ")
          end
          link_cmd = "gcc -no-pie -o #{@options[:output]} #{obj_file} #{runtime_obj} -L. -Wl,--gc-sections #{libs_str}"
        else
          libs_str = (dynamic_libs + ["-lm"]).uniq.join(" ")
          link_cmd = "gcc -no-pie -o #{@options[:output]} #{obj_file} #{runtime_obj} -L. -Wl,-rpath,'\$ORIGIN' -Wl,--gc-sections #{libs_str}"
        end
      end

      if ENV['JUNO_DEBUG']
        $stderr.puts "DEBUG: Collected libraries: #{libs.inspect}"
        $stderr.puts "DEBUG: Static libs: #{static_libs.inspect}"
        $stderr.puts "DEBUG: Dynamic libs: #{dynamic_libs.inspect}"
        $stderr.puts "DEBUG: Linking command: #{link_cmd}"
      end

      unless system(link_cmd)
        raise "Linking failed: #{link_cmd}"
      end
    end

    def find_stdlib_path
      real_path = nil
      begin
        real_path = File.expand_path("../../stdlib", File.dirname(File.realdirpath(__FILE__)))
      rescue
        nil
      end

      paths = [
        ENV['JUNO_STDLIB'],
        File.expand_path("../../stdlib", __dir__),
        real_path,
        File.expand_path("~/juno/stdlib"),
        File.expand_path("../stdlib", Dir.pwd),
        "/usr/local/lib/juno/stdlib",
        "/usr/lib/juno/stdlib"
      ].compact

      paths.find { |p| File.directory?(p) && File.exist?(File.join(p, "std.juno")) } || File.expand_path("../../stdlib", __dir__)
    end

    def detect_target_triple
      arch = @options[:arch]
      os = @options[:os]
      return (arch == :x86_64 ? "x86_64-apple-macos" : "arm64-apple-macos") if os == :macos

      triples = {
        x86_64: "x86_64-pc-linux-gnu",
        aarch64: "aarch64-unknown-linux-gnu",
        arm: "arm-unknown-linux-gnueabi",
        riscv64: "riscv64-unknown-linux-gnu",
        riscv32: "riscv32-unknown-linux-gnu"
      }
      triples[arch] || "x86_64-pc-linux-gnu"
    end

    def resolve_toolchain
      @@toolchain_mutex.synchronize do
        @@toolchain_cache[:llc] ||= find_first_binary(%w[llc-19 llc-18 llc-17 llc])
        @@toolchain_cache[:opt] ||= find_first_binary(%w[opt-19 opt-18 opt-17 opt])
        @@toolchain_cache.dup
      end
    end

    def find_first_binary(candidates)
      candidates.each do |name|
        path = `which #{name} 2>/dev/null`.strip
        return path unless path.empty?
      end
      nil
    end
  end
end
