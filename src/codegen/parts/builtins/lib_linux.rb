# lib_linux.rb - Convenient Linux system wrappers

module BuiltinLibLinux
  
  def setup_lib_linux_buf
    return if @lib_linux_buf_setup
    @lib_linux_buf_setup = true
    @linker.add_data("lib_linux_buf", "\x00" * 1024)
    @linker.add_data("termux_pref", "/data/data/com.termux/files/usr\x00")
  end

  # termux_prefix() -> returns pointer to string
  def gen_termux_prefix(node)
    setup_lib_linux_buf
    @emitter.emit_load_address("termux_pref", @linker)
  end

  # hostname() -> returns pointer to string in lib_linux_buf
  def gen_hostname(node)
    setup_lib_linux_buf
    @emitter.emit_load_address("lib_linux_buf", @linker)
    @emitter.mov_reg_reg(@arch == :aarch64 ? 0 : 7, 0)
    emit_syscall(:uname)
    @emitter.emit_load_address("lib_linux_buf", @linker)
    @emitter.emit_add_rax(65)
  end

  # kernel_version() -> returns pointer to string in lib_linux_buf
  def gen_kernel_version(node)
    setup_lib_linux_buf
    @emitter.emit_load_address("lib_linux_buf", @linker)
    @emitter.mov_reg_reg(@arch == :aarch64 ? 0 : 7, 0)
    emit_syscall(:uname)
    @emitter.emit_load_address("lib_linux_buf", @linker)
    @emitter.emit_add_rax(130)
  end

  # get_battery() -> returns %
  def gen_get_battery(node)
    @emitter.mov_rax(100)
  end

  def gen_is_root(node)
    emit_syscall(:getuid)
    @emitter.mov_reg_reg(2, 0) # RDX = UID
    @emitter.mov_rax(0)        # RAX = 0
    @emitter.cmp_rax_rdx("==") # returns 1 if UID == 0
  end

  def gen_pid(node)
    emit_syscall(:getpid)
  end

  def gen_uid(node)
    emit_syscall(:getuid)
  end
end
