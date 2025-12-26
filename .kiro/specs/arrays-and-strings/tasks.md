# Implementation Plan

- [x] 1. Extend Lexer for array syntax






  - [x] 1.1 Add recognition for `[` and `]` as separate tokens (verify existing)

    - Check if `[` and `]` are already tokenized correctly
    - Ensure they produce `:lbracket` and `:rbracket` tokens
    - _Requirements: 1.1, 1.2_

- [x] 2. Extend Parser for arrays











  - [x] 2.1 Add `parse_array_decl` for `let arr[N]` syntax








    - Detect `[` after identifier in `parse_let`
    - Parse size as literal integer
    - Return `{ type: :array_decl, name:, size: }` AST node
    - _Requirements: 1.1_
  

  - [x] 2.2 Add `parse_array_access` for `arr[i]` syntax







    - Detect `[` after identifier in expression parsing
    - Parse index as expression
    - Return `{ type: :array_access, name:, index: }` AST node
    - _Requirements: 1.2_

  

  - [x] 2.3 Add `parse_array_assign` for `arr[i] = value` syntax






    - Detect array access on left side of assignment
    - Return `{ type: :array_assign, name:, index:, value: }` AST node
    - _Requirements: 1.3_


  - [x] 2.4 Write property test for array parsing round-trip


    - **Property 3: String round-trip** (adapted for arrays)
    - Generate random array declarations, verify AST structure
    - **Validates: Requirements 1.1, 2.4**

- [x] 3. Extend CodeGen Context for arrays




  - [x] 3.1 Add `@ctx.arrays` hash to track array metadata

    - Store offset, size, ptr_offset for each array
    - Add `declare_array(name, size)` method
    - _Requirements: 1.1_

  

  - [x] 3.2 Implement stack allocation for arrays

    - Allocate N * 8 bytes on stack
    - Store pointer to arr[0] in variable
    - _Requirements: 1.1, 1.4_


- [-] 4. Implement array operations in CodeGen


  - [x] 4.1 Implement `gen_array_decl` in logic.rb

    - Allocate stack space
    - Initialize all elements to zero
    - _Requirements: 1.1, 1.4_
  

  - [x] 4.2 Implement `gen_array_access` in logic.rb

    - Compute address: base + index * 8
    - Load value into RAX
    - _Requirements: 1.2_

  
  - [x] 4.3 Implement `gen_array_assign` in logic.rb

    - Compute address: base + index * 8
    - Store value from RAX
    - _Requirements: 1.3_

  - [x] 4.4 Write property test for array store/load round-trip

    - **Property 1: Array bounds consistency**
    - Store value at index, load it back, verify equality

    - **Validates: Requirements 1.2, 1.3**



  - [ ] 4.5 Write property test for array zero initialization
    - **Property 2: Array initialization**
    - Declare array, read all elements, verify all are 0
    - **Validates: Requirements 1.4**


- [ ] 5. Checkpoint - Verify arrays work
  - Ensure all tests pass, ask the user if questions arise.

- [x] 6. Implement string literals



  - [x] 6.1 Add string storage in Linker data section

    - Add `add_string(label, content)` method to Linker
    - Store strings with null terminator
    - Track offsets for each string
    - _Requirements: 2.1_
  

  - [x] 6.2 Implement `gen_string_literal` in logic.rb

    - Add string to data section
    - Load address into RAX
    - _Requirements: 2.1, 2.4_
  
  - [x] 6.3 Implement string character access `s[i]`

    - Load byte at string_ptr + i
    - Zero-extend to 64-bit
    - _Requirements: 2.2_
  

  - [ ] 6.4 Implement string character assignment `s[i] = c`
    - Store byte at string_ptr + i
    - _Requirements: 2.3_


  - [ ] 6.5 Write property test for string round-trip
    - **Property 3: String round-trip**
    - Parse string literal, verify in generated binary
    - **Validates: Requirements 2.1, 2.4**

- [ ] 7. Implement built-in functions
  - [x] 7.1 Implement `len(arr)` for arrays

    - Return compile-time constant (array size)
    - _Requirements: 3.1_
  

  - [x] 7.2 Implement `len(s)` for strings

    - Loop until null byte, count characters
    - _Requirements: 3.2_
  
  - [x] 7.3 Implement `print(s)` for strings

    - Call sys_write(1, s, len(s)) on Linux
    - Call WriteConsoleA on Windows
    - _Requirements: 3.3_
  

  - [ ] 7.4 Implement `print(n)` for integers
    - Convert integer to ASCII string

    - Call print(s) with converted string
    - _Requirements: 3.4_

  - [x] 7.5 Write property test for string length

    - **Property 4: String length computation**
    - Generate strings, verify len() returns correct count
    - **Validates: Requirements 3.2**

- [ ] 8. Checkpoint - Verify strings and print work
  - Ensure all tests pass, ask the user if questions arise.

- [ ] 9. Implement array/string passing to functions
  - [ ] 9.1 Detect array/string arguments in function calls
    - Pass base address instead of value
    - _Requirements: 5.1, 5.2_
  
  - [ ] 9.2 Allow index access on function parameters
    - Treat parameter as pointer
    - Support `param[i]` syntax
    - _Requirements: 5.3_

  - [ ] 9.3 Write property test for pass-by-reference
    - **Property 5: Array/String pass-by-reference**
    - Modify array in function, verify change in caller
    - **Validates: Requirements 5.1, 5.2, 5.3**

- [x] 10. Integration and documentation




  - [x] 10.1 Create demo program using all array/string features

    - Arrays with loops
    - String manipulation
    - print() for output
    - _Requirements: 4.1, 4.2, 4.3_
  

  - [ ] 10.2 Update docs.md with array/string documentation
    - Syntax examples
    - Built-in functions
    - Memory layout explanation
    - _Requirements: All_

- [ ] 11. Final Checkpoint - Make sure all tests are passing
  - Ensure all tests pass, ask the user if questions arise.
