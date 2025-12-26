class CodegenContext
  attr_reader :variables, :var_types, :var_is_ptr, :structs, :arrays
  attr_accessor :stack_ptr, :current_fn

  def initialize
    @variables = {}   # name -> stack_offset
    @var_types = {}   # name -> struct_type_name
    @var_is_ptr = {}  # name -> bool
    @structs = {}     # name -> { size: int, fields: {name: offset} }
    @arrays = {}      # name -> { base_offset: int, size: int, ptr_offset: int }
    @stack_ptr = 64   # Start after shadow space + internal usage
    @current_fn = nil
  end

  def reset_for_function(name)
    @variables = {}
    @var_types = {}
    @var_is_ptr = {}
    @arrays = {}
    @stack_ptr = 64
    @current_fn = name
  end

  def declare_variable(name, size = 8)
    offset = (@stack_ptr += size)
    @variables[name] = offset
    offset
  end

  def get_variable_offset(name)
    @variables[name]
  end

  def register_struct(name, size, fields)
    @structs[name] = { size: size, fields: fields }
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
