# Juno Intermediate Representation (JIR) Specification

JIR is a low-level, platform-neutral instruction set used by the Juno compiler to decouple the frontend from architecture-specific backends. It uses a virtual register machine model with infinite virtual registers.

## Architecture Model

### Virtual Registers
Virtual registers are denoted as `vN` (e.g., `v1`, `v102`). These are mapped to physical registers or spilled to the stack by the backend's register allocator.

### Memory Layout
JIR assumes a linear address space.
- **Stack**: Managed via `ALLOC_STACK` and `FREE_STACK`.
- **Heap**: Managed via external `malloc`/`free` calls.
- **Global Data**: Accessed via labels and `LEA` instructions.

### Calling Convention (Lowering)
While JIR is architecture-neutral, the `CALL` instruction is lowered by the backend to follow the target ABI (e.g., System V AMD64 or ARM AAPCS). JIR callers assume registers are clobbered across calls unless they are callee-saved by the allocator's policy.

---

## Instruction Set Details

### 1. Data Movement

| Instruction | Parameters | Description |
|-------------|------------|-------------|
| `MOVE` | `dst, src` | Copies value from `src` to `dst`. `src` can be a literal, variable, or virtual register. |
| `SET` | `dst, imm` | Loads an immediate integer value into `dst`. |
| `LOAD` | `dst, var` | Loads the value of a local/global variable into `dst`. |
| `STORE` | `var, src` | Stores the value of `src` into a local/global variable. |
| `LEA` | `dst, label` | Loads the effective address of a code or data label. |
| `LEA_STR` | `dst, "val"` | Inlines a string literal and loads its address into `dst`. |

### 2. Arithmetic & Logic

| Instruction | Parameters | Description |
|-------------|------------|-------------|
| `ARITH` | `op, dst, s1, s2`| `dst = s1 op s2`. Ops: `+`, `-`, `*`, `/`, `%`, `&`, `\|`, `^`, `<<`, `>>`. |
| `CMP` | `s1, s2` | Compares two values and updates internal backend flags for subsequent `JCC`. |

### 3. Control Flow

| Instruction | Parameters | Description |
|-------------|------------|-------------|
| `LABEL` | `name` | Defines a destination for jumps. |
| `JMP` | `label` | Unconditional branch to `label`. |
| `JCC` | `cond, label`| Conditional branch. Conds: `==`, `!=`, `<`, `>`, `<=`, `>=`. |
| `JZ` | `src, label` | Jump to `label` if `src == 0`. |
| `JNZ` | `src, label` | Jump to `label` if `src != 0`. |
| `RET` | `src` | Exits the current function, returning `src`. |

### 4. Function & Stack Management

| Instruction | Parameters | Description |
|-------------|------------|-------------|
| `CALL` | `dst, name, n`| Calls function `name` with `n` arguments. Result in `dst`. |
| `CALL_IND`| `dst, ptr, n` | Indirect call via function pointer `ptr`. |
| `ALLOC_STACK`| `size` | Increases stack frame by `size`. Used for large arrays or spills. |
| `FREE_STACK` | `size` | Decreases stack frame by `size`. |

### 5. Memory Access (Raw)

| Instruction | Parameters | Description |
|-------------|------------|-------------|
| `LOAD_MEM` | `dst, base, off, sz` | Loads `sz` bytes from `[base + off]` into `dst`. |
| `STORE_MEM`| `base, off, src, sz` | Stores `sz` bytes from `src` into `[base + off]`. |

---

## Translation Examples

### C-style Loop
**Source:**
```watt
let mut i = 0
while (i < 10) {
    print(i)
    i = i + 1
}
```

**JIR:**
```jir
    SET v1, 0
    STORE i, v1
LABEL loop_start:
    LOAD v2, i
    SET v3, 10
    CMP v2, v3
    JCC >=, loop_end

    LOAD v4, i
    CALL v5, print, 1 (v4)

    LOAD v6, i
    SET v7, 1
    ARITH +, v8, v6, v7
    STORE i, v8

    JMP loop_start
LABEL loop_end:
```

### Struct Member Access
**Source:**
```watt
struct Point { x: int, y: int }
let p: Point = malloc(16)
p.y = 42
```

**JIR:**
```jir
    SET v1, 16
    CALL v2, malloc, 1 (v1)
    STORE p, v2

    LOAD v3, p
    SET v4, 42
    STORE_MEM v3, 8, v4, 8  ; Offset 8 for 'y'
```

---

## Backend Implementation Notes

### x86_64 Mapping
- `MOVE v1, v2` often results in `mov rax, rbx` if both are in registers.
- `CALL` handles the `RDI, RSI, RDX, RCX, R8, R9` argument sequence.
- `ARITH` mappings:
  - `+` -> `add`
  - `-` -> `sub`
  - `*` -> `imul`
  - `/` -> `idiv` (requires `cdq` and `rax/rdx` management)

### AArch64 Mapping
- `MOVE v1, v2` -> `mov x0, x1`.
- `CALL` uses `X0-X7` for arguments and `BL` for jumping.
- `LEA` -> `adrp` + `add` or `ldr`.
