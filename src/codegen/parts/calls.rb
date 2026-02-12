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
require_relative "builtins/lib_linux"

module GeneratorCalls
  include BuiltinStrings; include BuiltinMath; include BuiltinMemory; include BuiltinUtils; include BuiltinIO; include BuiltinNetwork; include BuiltinSyscalls; include BuiltinThreads; include BuiltinTypes; include BuiltinHTTPS; include BuiltinHeap; include BuiltinStringsV2; include BuiltinFileAPI; include BuiltinCollections; include BuiltinLibLinux

  BUILTINS = {
    "print" => :gen_print, "prints" => :gen_prints, "len" => :gen_len, "open" => :gen_open, "read" => :gen_read, "close" => :gen_close, "syscall" => :gen_syscall, "getbuf" => :gen_getbuf, "concat" => :gen_concat, "substr" => :gen_substr, "chr" => :gen_chr, "ord" => :gen_ord, "abs" => :gen_abs, "min" => :gen_min, "max" => :gen_max, "pow" => :gen_pow, "alloc" => :gen_alloc, "free" => :gen_free, "exit" => :gen_exit, "sleep" => :gen_sleep, "time" => :gen_time, "rand" => :gen_rand, "srand" => :gen_srand, "input" => :gen_input, "write" => :gen_write, "socket" => :gen_socket, "connect" => :gen_connect, "send" => :gen_send, "recv" => :gen_recv, "bind" => :gen_bind, "listen" => :gen_listen, "accept" => :gen_accept, "ip" => :gen_ip, "fork" => :gen_fork, "getpid" => :gen_getpid, "getppid" => :gen_getppid, "getuid" => :gen_getuid, "getgid" => :gen_getgid, "kill" => :gen_kill, "wait" => :gen_wait, "pipe" => :gen_pipe, "dup" => :gen_dup, "dup2" => :gen_dup2, "mkdir" => :gen_mkdir, "rmdir" => :gen_rmdir, "unlink" => :gen_unlink, "chmod" => :gen_chmod, "chdir" => :gen_chdir, "getcwd" => :gen_getcwd, "mmap" => :gen_mmap, "munmap" => :gen_munmap, "memcpy" => :gen_memcpy, "memset" => :gen_memset, "execve" => :gen_execve, "lseek" => :gen_lseek, "memfd_create" => :gen_memfd_create, "SEEK_SET" => :gen_SEEK_SET, "SEEK_CUR" => :gen_SEEK_CUR, "SEEK_END" => :gen_SEEK_END, "MFD_CLOEXEC" => :gen_MFD_CLOEXEC, "MFD_ALLOW_SEALING" => :gen_MFD_ALLOW_SEALING, "curl_get" => :gen_curl_get, "curl_post" => :gen_curl_post, "https_request" => :gen_https_request, "malloc" => :gen_malloc, "realloc" => :gen_realloc, "heap_init" => :gen_heap_init, "str_len" => :gen_str_len, "str_copy" => :gen_str_copy, "str_cat" => :gen_str_cat, "str_cmp" => :gen_str_cmp, "str_find" => :gen_str_find, "str_to_int" => :gen_str_to_int, "int_to_str" => :gen_int_to_str, "itoa" => :gen_int_to_str, "atoi" => :gen_str_to_int, "str_upper" => :gen_str_upper, "str_lower" => :gen_str_lower, "str_trim" => :gen_str_trim, "file_open" => :gen_file_open, "file_close" => :gen_file_close, "file_read" => :gen_file_read, "file_write" => :gen_file_write, "file_writeln" => :gen_file_writeln, "file_read_all" => :gen_file_read_all, "file_exists" => :gen_file_exists, "file_size" => :gen_file_size, "vec_new" => :gen_vec_new, "vec_push" => :gen_vec_push, "vec_pop" => :gen_vec_pop, "vec_get" => :gen_vec_get, "vec_set" => :gen_vec_set, "vec_len" => :gen_vec_len, "vec_cap" => :gen_vec_cap, "vec_clear" => :gen_vec_clear, "PROT_READ" => :gen_PROT_READ, "PROT_WRITE" => :gen_PROT_WRITE, "PROT_EXEC" => :gen_PROT_EXEC, "MAP_PRIVATE" => :gen_MAP_PRIVATE, "MAP_ANONYMOUS" => :gen_MAP_ANONYMOUS, "MAP_ANON" => :gen_MAP_ANON, "SIGTERM" => :gen_SIGTERM, "SIGKILL" => :gen_SIGKILL, "SIGINT" => :gen_SIGINT, "SIGUSR1" => :gen_SIGUSR1, "SIGUSR2" => :gen_SIGUSR2, "thread_create" => :gen_thread_create, "thread_exit" => :gen_thread_exit, "alloc_stack" => :gen_alloc_stack, "usleep" => :gen_usleep, "clone" => :gen_clone, "futex" => :gen_futex, "FUTEX_WAIT" => :gen_FUTEX_WAIT, "FUTEX_WAKE" => :gen_FUTEX_WAKE, "atomic_load" => :gen_atomic_load, "atomic_store" => :gen_atomic_store, "atomic_add" => :gen_atomic_add, "atomic_sub" => :gen_atomic_sub, "atomic_cas" => :gen_atomic_cas, "spin_lock" => :gen_spin_lock, "spin_unlock" => :gen_spin_unlock, "CLONE_VM" => :gen_CLONE_VM, "CLONE_FS" => :gen_CLONE_FS, "CLONE_FILES" => :gen_CLONE_FILES, "CLONE_SIGHAND" => :gen_CLONE_SIGHAND, "CLONE_THREAD" => :gen_CLONE_THREAD, "ptr_add" => :gen_ptr_add, "ptr_sub" => :gen_ptr_sub, "ptr_diff" => :gen_ptr_diff, "i8" => :gen_cast_i8, "u8" => :gen_cast_u8, "i16" => :gen_cast_i16, "u16" => :gen_cast_u16, "i32" => :gen_cast_i32, "u32" => :gen_cast_u32, "i64" => :gen_cast_i64, "u64" => :gen_cast_u64, "sizeof" => :gen_sizeof, "exec_cmd" => :gen_exec_cmd, "hostname" => :gen_hostname, "uptime" => :gen_uptime, "loadavg" => :gen_loadavg, "kernel_version" => :gen_kernel_version, "num_cpus" => :gen_num_cpus, "env_get" => :gen_env_get, "is_root" => :gen_is_root, "pid" => :gen_pid, "uid" => :gen_uid, "cwd" => :gen_cwd
  }

  STACK_RESERVE = 32; INT_BUFFER_OFFSET = 62; NEWLINE_CHAR = 10; ASCII_ZERO = 0x30; DECIMAL_BASE = 10

  def gen_fn_call(node)
    name = node[:name]
    return (@target_os == :linux ? handle_linux_io(node) : handle_windows_io_stub(node)) if name == "output" || name == "output_int"
    return send(BUILTINS[name], node) if BUILTINS.key?(name)
    return gen_method_call(node) if name.include?('.')
    gen_user_fn_call(node)
  end

  def gen_user_fn_call(node)
    num_args = node[:args] ? node[:args].length : 0; linux_like = (@target_os == :linux || @target_os == :flat)
    regs = @arch == :aarch64 ? [0, 1, 2, 3, 4, 5, 6, 7] : (linux_like ? [7, 6, 2, 1, 8, 9] : [1, 2, 8, 9])
    num_stack_args = [0, num_args - regs.length].max; padding = (num_stack_args % 2 == 1) ? 8 : 0; @emitter.emit_sub_rsp(padding) if padding > 0
    if num_args > 0
      node[:args].reverse_each { |arg| eval_expression(arg); @emitter.push_reg(@emitter.class::REG_RAX) }
      [num_args, regs.length].min.times { |i| @emitter.pop_reg(@emitter.class::REG_RAX); @emitter.mov_reg_reg(regs[i], @emitter.class::REG_RAX) }
    end
    @emitter.emit_sub_rsp(STACK_RESERVE)
    if @arch == :aarch64 then @emitter.emit32(0x10000000); @linker.add_fn_patch(@emitter.current_pos - 4, node[:name], :aarch64_adr); @emitter.emit32(0xd63f0000)
    else @linker.add_fn_patch(@emitter.current_pos + 1, node[:name], :rel32); @emitter.call_rel32
    end
    @emitter.emit_add_rsp(STACK_RESERVE + (num_stack_args * 8) + padding)
  end

  def gen_method_call(node)
    v, m = node[:name].split('.'); st = @ctx.var_types[v]; num_args = node[:args] ? node[:args].length : 0; linux_like = (@target_os == :linux || @target_os == :flat)
    if @arch == :aarch64 then reg_this = 0; regs = [1, 2, 3, 4, 5, 6, 7]
    elsif linux_like then reg_this = 7; regs = [6, 2, 1, 8, 9]
    else reg_this = 1; regs = [2, 8, 9]
    end
    num_stack_args = [0, num_args - regs.length].max; padding = (num_stack_args % 2 == 1) ? 8 : 0; @emitter.emit_sub_rsp(padding) if padding > 0
    if num_args > 0
      node[:args].reverse_each { |arg| eval_expression(arg); @emitter.push_reg(@emitter.class::REG_RAX) }
      [num_args, regs.length].min.times { |i| @emitter.pop_reg(@emitter.class::REG_RAX); @emitter.mov_reg_reg(regs[i], @emitter.class::REG_RAX) }
    end
    @emitter.mov_reg_stack_val(reg_this, @ctx.variables[v]); @emitter.emit_sub_rsp(STACK_RESERVE)
    if @arch == :aarch64 then @emitter.emit32(0x10000000); @linker.add_fn_patch(@emitter.current_pos - 4, "#{st}.#{m}", :aarch64_adr); @emitter.emit32(0xd63f0000)
    else @linker.add_fn_patch(@emitter.current_pos + 1, "#{st}.#{m}", :rel32); @emitter.call_rel32
    end
    @emitter.emit_add_rsp(STACK_RESERVE + (num_stack_args * 8) + padding)
  end

  def gen_print(node); arg = node[:args][0]; arg[:type] == :string_literal ? print_string(arg) : print_number(arg); end

  def print_string(arg)
    content = arg[:value] + "\n"; label = @linker.add_string(content); linux_like = (@target_os == :linux || @target_os == :flat)
    if linux_like
      if @arch == :aarch64
        @emitter.mov_rax(1); @emitter.mov_reg_reg(0, 0); @emitter.emit32(0x10000000); @linker.add_data_patch(@emitter.current_pos - 4, label, :aarch64_adr); @emitter.mov_reg_reg(1, 0); @emitter.mov_rax(content.length); @emitter.mov_reg_reg(2, 0); @emitter.mov_rax(64); @emitter.mov_reg_reg(8, 0); @emitter.emit32(0xd4000001)
      else
        @emitter.mov_rax(1); @emitter.mov_reg_reg(7, 0); @emitter.emit([0x48, 0x8d, 0x35]); @linker.add_data_patch(@emitter.current_pos, label, :rel32); @emitter.emit([0,0,0,0, 0x48, 0xc7, 0xc2] + [content.length].pack("l<").bytes + [0x0f, 0x05])
      end
    end
  end

  def print_number(arg)
    eval_expression(arg)
    if @target_os == :linux && @arch != :aarch64
      @emitter.emit([0x50, 0x53, 0x56, 0x52, 0x48, 0x8d, 0x1d]); @linker.add_data_patch(@emitter.current_pos, "int_buffer", :rel32); @emitter.emit([0,0,0,0, 0x48, 0x83, 0xc3, 62, 0xc6, 0x03, 10, 0x48, 0x89, 0xde, 0x49, 0xc7, 0xc0, 1, 0, 0, 0, 0x48, 0xb9, 10, 0, 0, 0, 0, 0, 0, 0])
      l_start = @emitter.current_pos; @emitter.emit([0x48, 0x31, 0xd2, 0x48, 0xf7, 0xf1, 0x80, 0xc2, 48, 0x48, 0xff, 0xce, 0x88, 0x16, 0x49, 0xff, 0xc0, 0x48, 0x85, 0xc0])
      @emitter.emit([0x75, (l_start - (@emitter.current_pos + 2)) & 0xFF]); @emitter.mov_rax(1); @emitter.mov_reg_reg(7, 0); @emitter.emit([0x4c, 0x89, 0xc2, 0x0f, 0x05, 0x5a, 0x5e, 0x5b, 0x58])
    end
  end

  def gen_len(node); arg = node[:args][0]; arg[:type] == :variable ? gen_len_variable(arg) : @emitter.mov_rax(arg[:value].length); end
  def gen_len_variable(arg)
    name = arg[:name]; arr_info = @ctx.get_array(name); return @emitter.mov_rax(arr_info[:size]) if arr_info
    off = @ctx.get_variable_offset(name); @emitter.mov_reg_stack_val(0, off); @emitter.mov_reg_reg(3, 0); @emitter.mov_rax(0); @emitter.mov_reg_reg(1, 0)
    l_start = @emitter.current_pos; @arch == :aarch64 ? @emitter.emit32(0x38616860) : @emitter.emit([0x0f, 0xb6, 0x04, 0x0e])
    @emitter.test_rax_rax; jz = @emitter.je_rel32
    if @arch == :aarch64 then @emitter.emit32(0x91000421) else @emitter.emit([0x48, 0xff, 0xc1]) end
    @emitter.patch_jmp(@emitter.jmp_rel32, l_start); @emitter.patch_je(jz, @emitter.current_pos); @emitter.mov_reg_reg(0, 1)
  end
  def handle_linux_io(node); gen_print(node); end
  def handle_windows_io_stub(node); gen_print(node); end
end
