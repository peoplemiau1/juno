require_relative "native_generator"

module Compiler 
  def self.compileRun(path, ast, mode = :native)
    if mode == :native
      target = RUBY_PLATFORM =~ /mswin|mingw|cygwin/ ? :windows : :linux
      ext = target == :windows ? ".exe" : ""
      out_file = "juno_bin" + ext
      
      gen = NativeGenerator.new(ast, target)
      gen.generate(out_file)
      return
    end

    # Старый код (TCC/GCC)
    c_code = File.read(path) if File.exist?(path)
    # Сокращенный вызов TCC (предполагаем, что он в PATH или пробуем прямой путь)
    tcc_path = 'C:/Users/QABAQ/Downloads/tcc-0.9.26-win64-bin/tcc/tcc.exe'
    
    # 1. Пробуем tcc из PATH
    system("tcc #{path} -o compiler.exe")
    
    # 2. Если не вышло, пробуем прямой путь
    if !File.exist?("compiler.exe")
      system("\"#{tcc_path}\" #{path} -o compiler.exe")
    end
    
    # 3. Если TCC нет, пробуем gcc
    if !File.exist?("compiler.exe")
      system("gcc #{path} -o compiler.exe")
    end
    
    if File.exist?("compiler.exe")
      # Успех!
      # puts "Success! compiler.exe created."
      File.delete("out.c") if File.exist?("out.c")
    else 
      puts "Compiler error".red + ": compiler.exe was not created."
      puts "Please check if 'tcc' or 'gcc' is in your PATH."
    end 
  end 
end