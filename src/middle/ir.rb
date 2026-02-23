# ir.rb - Juno Intermediate Representation definition

module JunoIR
  class Instruction
    attr_reader :op, :args, :metadata
    def initialize(op, *args, **metadata)
      @op = op
      @args = args
      @metadata = metadata
    end

    def to_s
      "#{@op.to_s.ljust(10)} #{@args.map(&:to_s).join(', ')}"
    end
  end

  # Operations:
  # SET       dest, imm          (dest = imm)
  # MOV       dest, src          (dest = src)
  # LOAD      dest, var_name     (dest = [var_name])
  # STORE     var_name, src      ([var_name] = src)
  # ADD/SUB/MUL/DIV/MOD/AND/OR/XOR/SHL/SHR dest, src1, src2
  # CMP       dest, src1, src2, cond
  # JMP       label
  # JZ/JNZ    src, label
  # CALL      dest, fn_name, [args]
  # CALL_IND  dest, src_ptr, [args]
  # RET       src
  # LABEL     name
  # LEA       dest, label_name
  # LEA_STACK dest, offset
  # LOAD_MEM  dest, base_ptr, offset, size
  # STORE_MEM base_ptr, offset, src, size
  # SYSCALL   dest, num, [args]
  # PANIC/TODO [message]
  # EXTERN    name, lib_name
  # TYPE_DEF  node_info
end
