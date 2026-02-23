class CodegenContext
  attr_reader :variables, :globals, :var_types, :var_is_ptr, :arrays
  attr_reader :var_registers, :used_callee_saved
  attr_accessor :stack_ptr, :current_fn, :current_fn_stack_size, :structs, :unions, :enums

  # Sized types: name -> { size: bytes, signed: bool }
  SIZED_TYPES = {
    "i8"  => { size: 1, signed: true },
    "u8"  => { size: 1, signed: false },
    "i16" => { size: 2, signed: true },
    "u16" => { size: 2, signed: false },
    "i32" => { size: 4, signed: true },
    "u32" => { size: 4, signed: false },
    "i64" => { size: 8, signed: true },
    "u64" => { size: 8, signed: false },
    "int" => { size: 8, signed: true },
    "ptr" => { size: 8, signed: false },
    "bool" => { size: 1, signed: false },
    "real" => { size: 8, signed: true }, # Placeholder for floats
  }

  def initialize(arch = :x86_64)
    @arch = arch
    @variables = {}   # name -> stack_offset
    @globals = {}     # name -> label_id
    @var_types = {}   # name -> type name (string)
    @var_is_ptr = {}  # name -> bool
    @structs = {}     # name -> { size: int, fields: {name: offset}, packed: bool }
    @unions = {}      # name -> { size: int, fields: {name: type} }
    @enums = {}       # name -> { size: int, variants: { name: { tag, params } } }
    @arrays = {}      # name -> { base_offset: int, size: int, ptr_offset: int }
    @var_registers = {} # name -> register symbol (:rbx, :r12, etc.)
    @used_callee_saved = [] # list of callee-saved regs used in current function
    @stack_ptr = 64   # Start after shadow space + internal usage
    @current_fn = nil
    @available_scratch = (arch == :aarch64) ? (9..15).to_a : [10, 11]
    @used_scratch = []
  end

  def acquire_scratch
    reg = @available_scratch.shift
    return nil unless reg
    @used_scratch << reg
    reg
  end

  def release_scratch(reg)
    @used_scratch.delete(reg)
    @available_scratch.unshift(reg) unless @available_scratch.include?(reg)
  end

  def type_size(type_name)
    return 8 if type_name.nil?
    if SIZED_TYPES[type_name]
      SIZED_TYPES[type_name][:size]
    elsif @structs[type_name]
      @structs[type_name][:size]
    elsif @unions[type_name]
      @unions[type_name][:size]
    else
      8  # default
    end
  end

  def type_signed?(type_name)
    return true if type_name.nil?
    SIZED_TYPES[type_name] ? SIZED_TYPES[type_name][:signed] : true
  end

  def register_union(name, size, fields)
    @unions[name] = { size: size, fields: fields }
  end

  def reset_for_function(name)
    @variables = {}
    @var_types = {}
    @var_is_ptr = {}
    @arrays = {}
    @var_registers = {}
    @used_callee_saved = []
    @stack_ptr = 64
    @current_fn = name
  end

  # Assign register to variable (from register allocator)
  def assign_register(var_name, reg)
    @var_registers[var_name] = reg
    @used_callee_saved << reg unless @used_callee_saved.include?(reg)
  end

  # Check if variable is in a register
  def in_register?(var_name)
    @var_registers.key?(var_name)
  end

  # Get register for variable
  def get_register(var_name)
    @var_registers[var_name]
  end

  def declare_variable(name, size = 8)
    offset = (@stack_ptr += size)
    @variables[name] = offset
    offset
  end

  def get_variable_offset(name)
    # Auto-declare if not exists (bulletproof)
    unless @variables[name]
      declare_variable(name, 8)
    end
    @variables[name]
  end

  def register_struct(name, size, fields)
    @structs[name] = { size: size, fields: fields }
  end

  def register_enum(name, size, variants)
    @enums[name] = { size: size, variants: variants }
  end

  def register_global(name, label_id)
    @globals[name] = label_id
  end

  # Declare array: allocates N * 8 bytes on stack
  # Returns { base_offset, size, ptr_offset }
  def declare_array(name, size)
    # Allocate space for array elements (N * 8 bytes)
    array_bytes = size * 8
    @stack_ptr += array_bytes
    base_offset = @stack_ptr
    
    # Allocate space for pointer variable
    @stack_ptr += 8
    ptr_offset = @stack_ptr
    @variables[name] = ptr_offset
    
    @arrays[name] = {
      base_offset: base_offset,
      size: size,
      ptr_offset: ptr_offset
    }
    @arrays[name]
  end

  def get_array(name)
    @arrays[name]
  end

  def is_array?(name)
    @arrays.key?(name)
  end
end
