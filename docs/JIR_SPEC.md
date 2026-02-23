# Juno Intermediate Representation (JIR) Specification v3.0

JIR is a low-level, platform-neutral instruction set used by the Juno compiler to decouple the frontend from architecture-specific backends.

## Instructions

### Data Movement
- `MOVE dst, src`: Moves value from `src` to `dst`. `src` can be a literal, a variable, or a virtual register.
- `SET dst, imm`: Sets `dst` to immediate value `imm`.
- `LOAD dst, var`: Loads value of variable `var` into `dst`.
- `STORE var, src`: Stores value of `src` into variable `var`.
- `LEA dst, label`: Loads the address of `label` into `dst`.

### Arithmetic & Logic
- `ARITH op, dst, src1, src2`: Performs arithmetic operation `op` on `src1` and `src2`, storing result in `dst`.
  - Supported ops: `+`, `-`, `*`, `/`, `%`, `&`, `|`, `^`, `<<`, `>>`.
- `CMP src1, src2`: Compares `src1` and `src2` and sets internal flags.

### Control Flow
- `LABEL name`: Defines a symbolic label.
- `JMP label`: Unconditional jump to `label`.
- `JCC cond, label`: Conditional jump to `label` based on last `CMP`.
  - Supported conds: `==`, `!=`, `<`, `>`, `<=`, `>=`.
- `JZ src, label`: Jump to `label` if `src` is zero.
- `RET src`: Returns from current function with value `src`.

### Functions & Stack
- `CALL dst, name, args_count`: Calls function `name` with `args_count`. Result is stored in `dst`.
- `ALLOC_STACK size`: Allocates `size` bytes on the stack frame.
- `FREE_STACK size`: Frees `size` bytes from the stack frame.

### Memory Access
- `LOAD_MEM dst, base, offset, size`: Loads `size` bytes from `[base + offset]` into `dst`.
- `STORE_MEM base, offset, src, size`: Stores `size` bytes from `src` into `[base + offset]`.

### Miscellaneous
- `SYSCALL dst, num, args`: Performs a system call.
- `PANIC msg`: Terminates with error.
- `RAW_BYTES data`: Injects raw machine code bytes (used in Hell Mode).

## Conventions
- Virtual registers are named `v1`, `v2`, etc.
- Variables are named identifiers.
- Functions are defined starting with `LABEL name, type: :function`.
