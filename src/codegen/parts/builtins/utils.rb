# Utility built-in functions for Juno

module BuiltinUtils
  def gen_exit(node)
    eval_expression(node[:args][0])
    @emitter.mov_reg_reg(@arch == :aarch64 ? 0 : 7, 0)
    emit_syscall(:exit)
  end

  def gen_sleep(node)
    eval_expression(node[:args][0])
    # timespec { tv_sec = ms / 1000, tv_nsec = (ms % 1000) * 1000000 }
    @emitter.push_reg(0) # ms
    @emitter.mov_rax(1000); @emitter.mov_reg_reg(2, 0); @emitter.pop_reg(0)
    @emitter.push_reg(0); @emitter.div_rax_by_rdx; @emitter.push_reg(0) # tv_sec
    @emitter.pop_reg(0); @emitter.pop_reg(0); @emitter.push_reg(0)
    @emitter.mov_rax(1000); @emitter.mov_reg_reg(2, 0); @emitter.pop_reg(0)
    @emitter.mod_rax_by_rdx
    @emitter.mov_reg_reg(2, 0); @emitter.mov_rax(1000000); @emitter.imul_rax_rdx; @emitter.push_reg(0) # tv_nsec

    @emitter.emit_sub_rsp(16)
    @emitter.pop_reg(0); @emitter.mov_mem_idx(@arch == :aarch64 ? 31 : 4, 8, 0, 8) # nsec
    @emitter.pop_reg(0); @emitter.mov_mem_idx(@arch == :aarch64 ? 31 : 4, 0, 0, 8) # sec

    @emitter.mov_reg_sp(@arch == :aarch64 ? 0 : 7)
    @emitter.mov_rax(0); @emitter.mov_reg_reg(@arch == :aarch64 ? 1 : 6, 0) # rem=NULL
    emit_syscall(:nanosleep)
    @emitter.emit_add_rsp(16)
  end

  def gen_time(node)
    @emitter.mov_rax(0); @emitter.mov_reg_reg(@arch == :aarch64 ? 0 : 7, 0)
    emit_syscall(@arch == :aarch64 ? :time : :time) # wait, x86-64 has time(201)
    # Actually time() is often implemented via gettimeofday or clock_gettime on arm
  end

  def gen_rand(node)
    # Linear congruential generator
    @emitter.emit_load_address("rand_seed", @linker)
    @emitter.mov_rax_mem(0); @emitter.push_reg(0)
    @emitter.mov_rax(1103515245); @emitter.mov_reg_reg(2, 0); @emitter.pop_reg(0)
    @emitter.imul_rax_rdx
    @emitter.emit_add_rax(12345)
    @emitter.push_reg(0)
    @emitter.emit_load_address("rand_seed", @linker)
    @emitter.pop_reg(2) # val
    @emitter.mov_mem_idx(@arch == :aarch64 ? 2 : 2, 0, 0, 8) # save to seed (wait, regs)
    @emitter.mov_rax_from_reg(0)
    @emitter.shr_rax_imm(1)
  end

  def gen_srand(node)
    eval_expression(node[:args][0])
    @emitter.push_reg(0)
    @emitter.emit_load_address("rand_seed", @linker)
    @emitter.pop_reg(2)
    @emitter.mov_mem_idx(@arch == :aarch64 ? 2 : 2, 0, 0, 8)
  end

  def gen_input(node)
    @emitter.mov_rax(0); @emitter.mov_reg_reg(@arch == :aarch64 ? 0 : 7, 0) # fd=0
    @emitter.emit_load_address("input_buffer", @linker)
    @emitter.mov_reg_reg(@arch == :aarch64 ? 1 : 6, 0) # buf
    @emitter.mov_rax(1024); @emitter.mov_reg_reg(@arch == :aarch64 ? 2 : 2, 0) # size
    emit_syscall(:read)
    @emitter.emit_load_address("input_buffer", @linker)
  end
end
