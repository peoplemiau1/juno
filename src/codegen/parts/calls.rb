# Function call dispatcher for Juno compiler
require_relative "builtins/strings"
require_relative "builtins/math"
require_relative "builtins/memory"
require_relative "builtins/utils"
require_relative "builtins/io"
require_relative "builtins/network"
require_relative "builtins/syscalls"
require_relative "builtins/threads"
require_relative "builtins/types"
require_relative "builtins/https"
require_relative "builtins/heap"
require_relative "builtins/strings_v2"
require_relative "builtins/file_api"
require_relative "builtins/collections"

module GeneratorCalls
  include BuiltinStrings
  include BuiltinMath
  include BuiltinMemory
  include BuiltinUtils
  include BuiltinIO
  include BuiltinNetwork
  include BuiltinSyscalls
  include BuiltinThreads
  include BuiltinTypes
  include BuiltinHTTPS
  include BuiltinHeap
  include BuiltinStringsV2
  include BuiltinFileAPI
  include BuiltinCollections

  BUILTINS = {
    # I/O
    "print" => :gen_print,
    "prints" => :gen_prints,
    "len" => :gen_len,
    "open" => :gen_open,
    "read" => :gen_read,
    "close" => :gen_close,
    "syscall" => :gen_syscall,
    "getbuf" => :gen_getbuf,
    
    # Strings
    "concat" => :gen_concat,
    "substr" => :gen_substr,
    "chr" => :gen_chr,
    "ord" => :gen_ord,
    
    # Math
    "abs" => :gen_abs,
    "min" => :gen_min,
    "max" => :gen_max,
    "pow" => :gen_pow,
    
    # Memory
    "alloc" => :gen_alloc,
    "free" => :gen_free,
    
    # Utils
    "exit" => :gen_exit,
    "sleep" => :gen_sleep,
    "time" => :gen_time,
    "rand" => :gen_rand,
    "srand" => :gen_srand,
    "input" => :gen_input,
    "write" => :gen_write,
    
    # Network
    "socket" => :gen_socket,
    "connect" => :gen_connect,
    "send" => :gen_send,
    "recv" => :gen_recv,
    "bind" => :gen_bind,
    "listen" => :gen_listen,
    "accept" => :gen_accept,
    "ip" => :gen_ip,
    
    # System calls
    "fork" => :gen_fork,
    "getpid" => :gen_getpid,
    "getppid" => :gen_getppid,
    "getuid" => :gen_getuid,
    "getgid" => :gen_getgid,
    "kill" => :gen_kill,
    "wait" => :gen_wait,
    "pipe" => :gen_pipe,
    "dup" => :gen_dup,
    "dup2" => :gen_dup2,
    "mkdir" => :gen_mkdir,
    "rmdir" => :gen_rmdir,
    "unlink" => :gen_unlink,
    "chmod" => :gen_chmod,
    "chdir" => :gen_chdir,
    "getcwd" => :gen_getcwd,
    "mmap" => :gen_mmap,
    "munmap" => :gen_munmap,
    "memcpy" => :gen_memcpy,
    "memset" => :gen_memset,
    "execve" => :gen_execve,
    
    # HTTPS
    "curl_get" => :gen_curl_get,
    "curl_post" => :gen_curl_post,
    
    # Heap (malloc/free)
    "malloc" => :gen_malloc,
    "free" => :gen_free,
    "realloc" => :gen_realloc,
    "heap_init" => :gen_heap_init,
    
    # String API v2
    "str_len" => :gen_str_len,
    "str_copy" => :gen_str_copy,
    "str_cat" => :gen_str_cat,
    "str_cmp" => :gen_str_cmp,
    "str_find" => :gen_str_find,
    "str_to_int" => :gen_str_to_int,
    "int_to_str" => :gen_int_to_str,
    "itoa" => :gen_int_to_str,
    "atoi" => :gen_str_to_int,
    "str_upper" => :gen_str_upper,
    "str_lower" => :gen_str_lower,
    "str_trim" => :gen_str_trim,
    
    # File API
    "file_open" => :gen_file_open,
    "file_close" => :gen_file_close,
    "file_read" => :gen_file_read,
    "file_write" => :gen_file_write,
    "file_writeln" => :gen_file_writeln,
    "file_read_all" => :gen_file_read_all,
    "file_exists" => :gen_file_exists,
    "file_size" => :gen_file_size,
    
    # Collections (Vector)
    "vec_new" => :gen_vec_new,
    "vec_push" => :gen_vec_push,
    "vec_pop" => :gen_vec_pop,
    "vec_get" => :gen_vec_get,
    "vec_set" => :gen_vec_set,
    "vec_len" => :gen_vec_len,
    "vec_cap" => :gen_vec_cap,
    "vec_clear" => :gen_vec_clear,
    
    # mmap constants
    "PROT_READ" => :gen_PROT_READ,
    "PROT_WRITE" => :gen_PROT_WRITE,
    "PROT_EXEC" => :gen_PROT_EXEC,
    "MAP_PRIVATE" => :gen_MAP_PRIVATE,
    "MAP_ANONYMOUS" => :gen_MAP_ANONYMOUS,
    "MAP_ANON" => :gen_MAP_ANON,
    
    # Signal constants
    "SIGTERM" => :gen_SIGTERM,
    "SIGKILL" => :gen_SIGKILL,
    "SIGINT" => :gen_SIGINT,
    "SIGUSR1" => :gen_SIGUSR1,
    "SIGUSR2" => :gen_SIGUSR2,
    
    # Threading
    "thread_create" => :gen_thread_create,
    "thread_exit" => :gen_thread_exit,
    "alloc_stack" => :gen_alloc_stack,
    "usleep" => :gen_usleep,
    "clone" => :gen_clone,
    "futex" => :gen_futex,
    "FUTEX_WAIT" => :gen_FUTEX_WAIT,
    "FUTEX_WAKE" => :gen_FUTEX_WAKE,
    "atomic_load" => :gen_atomic_load,
    "atomic_store" => :gen_atomic_store,
    "atomic_add" => :gen_atomic_add,
    "atomic_sub" => :gen_atomic_sub,
    "atomic_cas" => :gen_atomic_cas,
    "spin_lock" => :gen_spin_lock,
    "spin_unlock" => :gen_spin_unlock,
    "CLONE_VM" => :gen_CLONE_VM,
    "CLONE_FS" => :gen_CLONE_FS,
    "CLONE_FILES" => :gen_CLONE_FILES,
    "CLONE_SIGHAND" => :gen_CLONE_SIGHAND,
    "CLONE_THREAD" => :gen_CLONE_THREAD,
    
    # Pointer arithmetic helpers
    "ptr_add" => :gen_ptr_add,
    "ptr_sub" => :gen_ptr_sub,
    "ptr_diff" => :gen_ptr_diff,
    
    # Sized type casts
    "i8" => :gen_cast_i8,
    "u8" => :gen_cast_u8,
    "i16" => :gen_cast_i16,
    "u16" => :gen_cast_u16,
    "i32" => :gen_cast_i32,
    "u32" => :gen_cast_u32,
    "i64" => :gen_cast_i64,
    "u64" => :gen_cast_u64,
    
    # sizeof
    "sizeof" => :gen_sizeof
  }

  # Constants for magic numbers
  STACK_RESERVE = 32
  INT_BUFFER_OFFSET = 62
  NEWLINE_CHAR = 10
  ASCII_ZERO = 0x30
  DECIMAL_BASE = 10

  def gen_fn_call(node)
    name = node[:name]
    
    # Legacy output functions
    if name == "output" || name == "output_int"
      @target_os == :linux ? handle_linux_io(node) : handle_windows_io_stub(node)
      return
    end

    # Built-in functions
    if BUILTINS.key?(name)
      send(BUILTINS[name], node)
      return
    end

    # Method call
    if name.include?('.')
      gen_method_call(node)
      return
    end

    # User-defined function call
    gen_user_fn_call(node)
  end

  def gen_user_fn_call(node)
    num_args = node[:args] ? node[:args].length : 0
    linux_like = (@target_os == :linux || @target_os == :flat)
    regs = linux_like ?
      [CodeEmitter::REG_RDI, CodeEmitter::REG_RSI, CodeEmitter::REG_RDX, CodeEmitter::REG_RCX, CodeEmitter::REG_R8, CodeEmitter::REG_R9] :
      [CodeEmitter::REG_RCX, CodeEmitter::REG_RDX, CodeEmitter::REG_R8, CodeEmitter::REG_R9]
    
    num_stack_args = [0, num_args - regs.length].max
    
    # alignment: RSP % 16 must be 8 before 'call' (because call pushes 8 bytes)
    # Actually, RSP % 16 should be 0 at function entry.
    # Our prologue/epilogue sub_rsp(256) maintains alignment.
    # So we just need to ensure our pushes/subs here maintain it.
    padding = (num_stack_args % 2 == 1) ? 8 : 0
    @emitter.emit_sub_rsp(padding) if padding > 0

    if num_args > 0
      # FIX: Evaluate all arguments first and save to temporary registers/stack
      # to avoid register clobbering during eval_expression
      
      # Evaluate and push ALL arguments in reverse order
      node[:args].reverse_each do |arg|
        eval_expression(arg)
        @emitter.emit([0x50]) # push rax
      end
      
      # Pop first N into registers (in forward order now)
      num_pop = [num_args, regs.length].min
      num_pop.times do |i|
        @emitter.emit([0x58]) # pop rax
        @emitter.mov_reg_reg(regs[i], CodeEmitter::REG_RAX)
      end
      # num_stack_args remain on stack in correct order
    end

    @emitter.emit_sub_rsp(STACK_RESERVE)
    @linker.add_fn_patch(@emitter.current_pos + 1, node[:name])
    @emitter.call_rel32
    
    # Cleanup
    total_cleanup = STACK_RESERVE + (num_stack_args * 8) + padding
    @emitter.emit_add_rsp(total_cleanup)
  end

  def gen_method_call(node)
    v, m = node[:name].split('.')
    st = @ctx.var_types[v]
    num_args = node[:args] ? node[:args].length : 0
    linux_like = (@target_os == :linux || @target_os == :flat)
    
    # Linux: this=RDI, args: RSI, RDX, RCX, R8, R9 (5 slots)
    # Win:   this=RCX, args: RDX, R8, R9 (3 slots)
    if linux_like
      reg_this = CodeEmitter::REG_RDI
      regs = [CodeEmitter::REG_RSI, CodeEmitter::REG_RDX, CodeEmitter::REG_RCX, CodeEmitter::REG_R8, CodeEmitter::REG_R9]
    else
      reg_this = CodeEmitter::REG_RCX
      regs = [CodeEmitter::REG_RDX, CodeEmitter::REG_R8, CodeEmitter::REG_R9]
    end

    num_stack_args = [0, num_args - regs.length].max
    padding = (num_stack_args % 2 == 1) ? 8 : 0
    @emitter.emit_sub_rsp(padding) if padding > 0

    # FIX: Evaluate all arguments first before loading 'this'
    if num_args > 0
      node[:args].reverse_each do |arg|
        eval_expression(arg)
        @emitter.emit([0x50])
      end
      
      num_pop = [num_args, regs.length].min
      num_pop.times do |i|
        @emitter.emit([0x58])
        @emitter.mov_reg_reg(regs[i], CodeEmitter::REG_RAX)
      end
    end

    # Load 'this' AFTER evaluating arguments
    off = @ctx.variables[v]
    @emitter.mov_reg_stack_val(reg_this, off)
    
    @emitter.emit_sub_rsp(STACK_RESERVE)
    @linker.add_fn_patch(@emitter.current_pos + 1, "#{st}.#{m}")
    @emitter.call_rel32
    
    total_cleanup = STACK_RESERVE + (num_stack_args * 8) + padding
    @emitter.emit_add_rsp(total_cleanup)
  end

  # print(s) or print(n)
  def gen_print(node)
    return unless node[:args] && node[:args][0]
    
    arg = node[:args][0]
    
    if arg[:type] == :string_literal
      print_string(arg)
    else
      print_number(arg)
    end
  end

  # Helper method for printing strings
  def print_string(arg)
    content = arg[:value]
    label = @linker.add_string(content + "\n")

    linux_like = (@target_os == :linux || @target_os == :flat)
    if linux_like
      @emitter.mov_rax(1)
      @emitter.mov_reg_reg(CodeEmitter::REG_RDI, CodeEmitter::REG_RAX)
      @emitter.emit([0x48, 0x8d, 0x35])
      @linker.add_data_patch(@emitter.current_pos, label)
      @emitter.emit([0x00, 0x00, 0x00, 0x00])
      @emitter.emit([0x48, 0xc7, 0xc2] + [content.length + 1].pack("l<").bytes)
      @emitter.emit([0x0f, 0x05])
    else
      # Windows string printing
      content = arg[:value] + "\n"
      label = @linker.add_string(content)
      
      # 1. GetStdHandle(-11)
      @emitter.emit_sub_rsp(STACK_RESERVE + 8) # Shadow space + align
      @emitter.mov_rax(0xFFFFFFFFFFFFFFF5) # -11
      @emitter.mov_reg_reg(CodeEmitter::REG_RCX, CodeEmitter::REG_RAX)
      @linker.add_import_patch(@emitter.current_pos + 2, "GetStdHandle")
      @emitter.call_ind_rel32
      
      # 2. WriteFile(handle, buffer, length, &written, NULL)
      @emitter.mov_reg_reg(CodeEmitter::REG_RCX, CodeEmitter::REG_RAX) # RCX = handle
      
      # Buffer (RDX)
      @emitter.emit([0x48, 0x8d, 0x15]) # lea rdx, [rip + offset]
      @linker.add_data_patch(@emitter.current_pos, label)
      @emitter.emit([0x00, 0x00, 0x00, 0x00])
      
      # Length (R8)
      @emitter.mov_rax(content.length)
      @emitter.mov_reg_reg(CodeEmitter::REG_R8, CodeEmitter::REG_RAX)
      
      # &written (R9) - use some stack space
      @emitter.lea_reg_stack(CodeEmitter::REG_RAX, 8)
      @emitter.mov_reg_reg(CodeEmitter::REG_R9, CodeEmitter::REG_RAX)
      
      # NULL (lpOverlapped) - on stack at [rsp+40]
      @emitter.emit([0x48, 0xc7, 0x44, 0x24, 0x20, 0, 0, 0, 0]) # mov qword ptr [rsp+32], 0
      
      @linker.add_import_patch(@emitter.current_pos + 2, "WriteFile")
      @emitter.call_ind_rel32
      
      @emitter.emit_add_rsp(STACK_RESERVE + 8)
    end
  end

  # Helper method for printing numbers
  def print_number(arg)
    eval_expression(arg)

    linux_like = (@target_os == :linux || @target_os == :flat)
    if linux_like
      # Save registers
      @emitter.emit([0x50, 0x53, 0x56, 0x52])
      
      # Load buffer address
      @emitter.emit([0x48, 0x8d, 0x1d])
      @linker.add_data_patch(@emitter.current_pos, "int_buffer")
      @emitter.emit([0x00, 0x00, 0x00, 0x00])
      
      # Position to end of buffer and add newline
      @emitter.emit([0x48, 0x83, 0xc3, INT_BUFFER_OFFSET])
      @emitter.emit([0xc6, 0x03, NEWLINE_CHAR])
      
      # Setup for conversion
      @emitter.emit([0x48, 0x89, 0xde])
      @emitter.emit([0x49, 0xc7, 0xc0, 1, 0, 0, 0])
      @emitter.emit([0x48, 0xb9, DECIMAL_BASE, 0, 0, 0, 0, 0, 0, 0])
      
      # Convert number to string
      l_start = @emitter.current_pos
      @emitter.emit([0x48, 0x31, 0xd2, 0x48, 0xf7, 0xf1])
      @emitter.emit([0x80, 0xc2, ASCII_ZERO, 0x48, 0xff, 0xce, 0x88, 0x16, 0x49, 0xff, 0xc0])
      @emitter.emit([0x48, 0x85, 0xc0])
      
      off = l_start - (@emitter.current_pos + 2)
      @emitter.emit([0x75, off & 0xFF])
      
      # Write syscall
      @emitter.mov_rax(1)
      @emitter.mov_reg_reg(CodeEmitter::REG_RDI, CodeEmitter::REG_RAX)
      @emitter.emit([0x4c, 0x89, 0xc2])
      @emitter.emit([0x0f, 0x05])
      
      # Restore registers
      @emitter.emit([0x5a, 0x5e, 0x5b, 0x58])
    else
      # Windows number printing (reusing conversion logic)
      eval_expression(arg)
      @emitter.emit([0x50, 0x51, 0x52, 0x53]) # Save RAX, RCX, RDX, RBX
      
      # Load buffer address
      @emitter.emit([0x48, 0x8d, 0x1d])
      @linker.add_data_patch(@emitter.current_pos, "int_buffer")
      @emitter.emit([0x00, 0x00, 0x00, 0x00])
      
      @emitter.emit([0x48, 0x83, 0xc3, INT_BUFFER_OFFSET])
      @emitter.emit([0xc6, 0x03, NEWLINE_CHAR])
      
      @emitter.emit([0x48, 0x89, 0xde])
      @emitter.emit([0x49, 0xc7, 0xc0, 1, 0, 0, 0])
      @emitter.emit([0x48, 0xb9, DECIMAL_BASE, 0, 0, 0, 0, 0, 0, 0])
      
      l_start = @emitter.current_pos
      @emitter.emit([0x48, 0x31, 0xd2, 0x48, 0xf7, 0xf1, 0x80, 0xc2, ASCII_ZERO])
      @emitter.emit([0x48, 0xff, 0xce, 0x88, 0x16, 0x49, 0xff, 0xc0, 0x48, 0x85, 0xc0])
      off = l_start - (@emitter.current_pos + 2)
      @emitter.emit([0x75, off & 0xFF])
      
      # Now print the resulting string in 'int_buffer'
      # RSI = start of string, R8 (from R10/R12?) = length
      # Actually R10 contains length in the conversion logic above (49 C7 C0 01...)
      # Wait, the conversion logic uses R8 as counter? Let's check:
      # 49 C7 C0 01 -> mov r8, 1
      # 49 FF C0 -> inc r8
      
      # GetStdHandle
      @emitter.emit_sub_rsp(STACK_RESERVE)
      @emitter.mov_rax(0xFFFFFFFFFFFFFFF5)
      @emitter.mov_reg_reg(CodeEmitter::REG_RCX, CodeEmitter::REG_RAX)
      @linker.add_import_patch(@emitter.current_pos + 2, "GetStdHandle")
      @emitter.call_ind_rel32
      
      # WriteFile
      @emitter.mov_reg_reg(CodeEmitter::REG_RCX, CodeEmitter::REG_RAX) # handle
      @emitter.mov_reg_reg(CodeEmitter::REG_RDX, CodeEmitter::REG_RSI) # buffer (from conversion)
      @emitter.emit([0x4d, 0x89, 0xc0]) # mov r8, r8 (length)
      @emitter.lea_reg_stack(CodeEmitter::REG_RAX, 8)
      @emitter.mov_reg_reg(CodeEmitter::REG_R9, CodeEmitter::REG_RAX) # &written
      @emitter.emit([0x48, 0xc7, 0x44, 0x24, 0x20, 0, 0, 0, 0]) # NULL overlapped
      
      @linker.add_import_patch(@emitter.current_pos + 2, "WriteFile")
      @emitter.call_ind_rel32
      @emitter.emit_add_rsp(STACK_RESERVE)
      
      @emitter.emit([0x5b, 0x5a, 0x59, 0x58]) # Restore RBX, RDX, RCX, RAX
    end
  end

  # len(arr) or len(s)
  def gen_len(node)
    return unless node[:args] && node[:args][0]
    
    arg = node[:args][0]
    
    case arg[:type]
    when :variable
      gen_len_variable(arg)
    when :string_literal
      @emitter.mov_rax(arg[:value].length)
    else
      # Unsupported type - return 0
      @emitter.mov_rax(0)
    end
  end

  # Helper for getting length of variable
  def gen_len_variable(arg)
    name = arg[:name]
    arr_info = @ctx.get_array(name)
    
    if arr_info
      @emitter.mov_rax(arr_info[:size])
      return
    end
    
    off = @ctx.get_variable_offset(name)
    return unless off
    
    @emitter.mov_reg_stack_val(CodeEmitter::REG_RAX, off)
    @emitter.emit([0x48, 0x89, 0xc6])       # mov rsi, rax (preserve base)
    @emitter.emit([0x48, 0x31, 0xc9])       # xor rcx, rcx

    loop_start = @emitter.current_pos
    @emitter.emit([0x0f, 0xb6, 0x04, 0x0e]) # movzx eax, byte [rsi+rcx]
    @emitter.emit([0x84, 0xc0])             # test al, al
    @emitter.emit([0x74, 0x05])             # je -> done (skip inc+jmp)
    @emitter.emit([0x48, 0xff, 0xc1])       # inc rcx
    back_off = loop_start - (@emitter.current_pos + 2)
    @emitter.emit([0xeb, back_off & 0xFF])  # jmp loop_start
    @emitter.emit([0x48, 0x89, 0xc8])       # done: mov rax, rcx
  end

  def handle_linux_io(node)
    if node[:name] == "output"
      str = node[:args][0][:value]
      id = "str_#{@emitter.current_pos}"
      @linker.add_data(id, str + "\n")
      
      @emitter.mov_rax(1)
      @emitter.mov_reg_reg(CodeEmitter::REG_RDI, CodeEmitter::REG_RAX)
      @linker.add_data_patch(@emitter.current_pos + 3, id)
      @emitter.emit([0x48, 0x8d, 0x35, 0, 0, 0, 0])
      @emitter.emit([0x48, 0xc7, 0xc2] + [str.length + 1].pack("l<").bytes)
      @emitter.emit([0x0f, 0x05])
      
    elsif node[:name] == "output_int"
      eval_expression(node[:args][0])
      
      # Save registers
      @emitter.emit([0x50, 0x53, 0x56, 0x52])
      
      # Load buffer
      @linker.add_data_patch(@emitter.current_pos + 3, "int_buffer")
      @emitter.emit([0x48, 0x8d, 0x1d, 0, 0, 0, 0])
      @emitter.emit([0x48, 0x83, 0xc3, INT_BUFFER_OFFSET, 0xc6, 0x03, NEWLINE_CHAR, 0x48, 0x89, 0xde])
      @emitter.emit([0x49, 0xc7, 0xc0, 1, 0, 0, 0])
      @emitter.emit([0x48, 0xb9, DECIMAL_BASE, 0, 0, 0, 0, 0, 0, 0])
      
      l_start = @emitter.current_pos
      @emitter.emit([0x48, 0x31, 0xd2, 0x48, 0xf7, 0xf1])
      @emitter.emit([0x80, 0xc2, ASCII_ZERO, 0x48, 0xff, 0xce, 0x88, 0x16, 0x49, 0xff, 0xc0])
      @emitter.emit([0x48, 0x85, 0xc0])
      
      off = l_start - (@emitter.current_pos + 2)
      @emitter.emit([0x75, off & 0xFF])
      
      @emitter.mov_rax(1)
      @emitter.mov_reg_reg(CodeEmitter::REG_RDI, CodeEmitter::REG_RAX)
      @emitter.emit([0x4c, 0x89, 0xc2, 0x0f, 0x05])
      
      # Restore registers
      @emitter.emit([0x5a, 0x5e, 0x5b, 0x58])
    end
  end

  def handle_windows_io_stub(node)
    # Redirect legacy output to gen_print
    gen_print(node)
  end
end