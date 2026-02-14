# lib_linux.rb - Convenient Linux system wrappers

module BuiltinLibLinux
  
  def setup_lib_linux_buf
    return if @lib_linux_buf_setup
    @lib_linux_buf_setup = true
    @linker.add_data("lib_linux_buf", "\x00" * 1024)
    @linker.add_data("termux_pref", "/data/data/com.termux/files/usr\x00")
  end

  # Helper: emit LEA with RIP-relative addressing
  def emit_lea_rdi_data(label)
    if @arch == :aarch64
       @emitter.emit_load_address(label, @linker)
       @emitter.mov_reg_reg(7, 0) # RDI map
    else
       @linker.add_data_patch(@emitter.current_pos + 3, label)
       @emitter.emit([0x48, 0x8d, 0x3d, 0x00, 0x00, 0x00, 0x00])
    end
  end

  def emit_lea_rsi_data(label)
    if @arch == :aarch64
       @emitter.emit_load_address(label, @linker)
       @emitter.mov_reg_reg(6, 0) # RSI map
    else
       @linker.add_data_patch(@emitter.current_pos + 3, label)
       @emitter.emit([0x48, 0x8d, 0x35, 0x00, 0x00, 0x00, 0x00])
    end
  end

  # termux_prefix() -> returns pointer to string
  def gen_termux_prefix(node)
    setup_lib_linux_buf
    @emitter.emit_load_address("termux_pref", @linker)
  end

  # hostname()
  def gen_hostname(node)
    @emitter.mov_rax(0) # todo: improve
  end

  def gen_kernel_version(node)
    @emitter.mov_rax(0)
  end

  # get_battery() -> returns %
  def gen_get_battery(node)
    @emitter.mov_rax(100) # stub
  end

  def gen_is_root(node)
    @emitter.mov_rax(0); @emitter.mov_reg_reg(@arch == :aarch64 ? 0 : 7, 0)
    if @arch == :aarch64
       @emitter.mov_rax(174); @emitter.mov_reg_reg(8, 0); @emitter.syscall
    else
       @emitter.mov_rax(102); @emitter.syscall
    end
    @emitter.cmp_rax_rdx("==") # compare with 0
  end

  def gen_pid(node)
    if @arch == :aarch64
      @emitter.mov_rax(172); @emitter.mov_reg_reg(8, 0); @emitter.syscall
    else
      @emitter.mov_rax(39); @emitter.syscall
    end
  end

  def gen_uid(node)
    if @arch == :aarch64
      @emitter.mov_rax(174); @emitter.mov_reg_reg(8, 0); @emitter.syscall
    else
      @emitter.mov_rax(102); @emitter.syscall
    end
  end
end
