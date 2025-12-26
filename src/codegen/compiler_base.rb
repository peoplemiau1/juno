class CompilerBase
  attr_accessor :code_bytes, :variables, :var_types, :structs, :stack_ptr, :functions, :fn_patches, :target_os, :var_is_ptr

  def initialize(ast, target_os)
    @ast = ast
    @target_os = target_os
    @code_bytes = []
    @functions = {}
    @fn_patches = []
    @variables = {}
    @var_types = {}
    @var_is_ptr = {}
    @structs = {}
    @stack_ptr = 128 # Увеличиваем начальный отступ для Shadow Space и IO
  end

  # Синхронизированные адреса с PEBuilder
  IAT = { 
    get_std_handle: 0x2060, 
    write_file: 0x2068, 
    read_file: 0x2070, 
    create_thread: 0x2078, 
    sleep: 0x2080, 
    exit_process: 0x2088 
  }

  def apply_fn_patches
    @fn_patches.each do |patch|
      target_addr = @functions[patch[:name]]
      next unless target_addr
      if patch[:type] == :absolute
        abs_addr = 0x140000000 + target_addr
        @code_bytes[patch[:pos]..patch[:pos]+7] = [abs_addr].pack("Q<").bytes
      else
        instr_end_rva = 0x1000 + patch[:pos] + 4
        offset = target_addr - instr_end_rva
        @code_bytes[patch[:pos]..patch[:pos]+3] = [offset].pack("l<").bytes
      end
    end
  end
end
