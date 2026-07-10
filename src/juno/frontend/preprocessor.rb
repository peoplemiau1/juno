require "thread"
require "etc"

class Preprocessor
  SIZE_REGS = {
    64 => { 'rax'=>0,'rcx'=>1,'rdx'=>2,'rbx'=>3,'rsp'=>4,'rbp'=>5,'rsi'=>6,'rdi'=>7,
            'r8'=>8,'r9'=>9,'r10'=>10,'r11'=>11,'r12'=>12,'r13'=>13,'r14'=>14,'r15'=>15 },
    32 => { 'eax'=>0,'ecx'=>1,'edx'=>2,'ebx'=>3,'esp'=>4,'ebp'=>5,'esi'=>6,'edi'=>7,
            'r8d'=>8,'r9d'=>9,'r10d'=>10,'r11d'=>11,'r12d'=>12,'r13d'=>13,'r14d'=>14,'r15d'=>15 },
    16 => { 'ax'=>0,'cx'=>1,'dx'=>2,'bx'=>3,'sp'=>4,'bp'=>5,'si'=>6,'di'=>7,
            'r8w'=>8,'r9w'=>9,'r10w'=>10,'r11w'=>11,'r12w'=>12,'r13w'=>13,'r14w'=>14,'r15w'=>15 },
    8  => { 'al'=>0,'cl'=>1,'dl'=>2,'bl'=>3,'spl'=>4,'bpl'=>5,'sil'=>6,'dil'=>7,
            'r8b'=>8,'r9b'=>9,'r10b'=>10,'r11b'=>11,'r12b'=>12,'r13b'=>13,'r14b'=>14,'r15b'=>15 }
  }.freeze

  REG_LOOKUP = {}
  SIZE_REGS.each { |size, h| h.each { |name, idx| REG_LOOKUP[name] = [size, idx] } }
  REG_LOOKUP.freeze

  REGS64 = SIZE_REGS[64].each_with_object({}) { |(k, v), h| h[k.to_sym] = v }.freeze

  REG_ALT_ALL = REG_LOOKUP.keys.join('|')
  REG64_ALT   = SIZE_REGS[64].keys.join('|')
  NUM_RE      = '-?(?:0x[0-9a-fA-F]+|\d+)'
  LABEL_RE    = '[A-Za-z_.$][A-Za-z0-9_.$]*'
  LABEL_DEF_RE = /^(#{LABEL_RE}):$/

  ALU_RR_OP     = { 'add' => 0x01, 'or' => 0x09, 'and' => 0x21, 'sub' => 0x29, 'xor' => 0x31, 'cmp' => 0x39, 'test' => 0x85 }
  ALU_IMM_DIGIT = { 'add' => 0,    'or' => 1,    'and' => 4,    'sub' => 5,    'xor' => 6,    'cmp' => 7 }
  SHIFT_DIGIT   = { 'rol' => 0, 'ror' => 1, 'rcl' => 2, 'rcr' => 3, 'shl' => 4, 'shr' => 5, 'sar' => 7 }
  SYS_MEM_DIGIT = { 'sgdt' => 0, 'sidt' => 1, 'lgdt' => 2, 'lidt' => 3, 'smsw' => 4, 'lmsw' => 6, 'invlpg' => 7 }
  SYS_REG_DIGIT = { 'lldt' => 2, 'ltr' => 3, 'verr' => 4, 'verw' => 5 }

  JCC_OP = {
    'je' => 0x84, 'jz' => 0x84, 'jne' => 0x85, 'jnz' => 0x85,
    'jg' => 0x8F, 'jnle' => 0x8F, 'jge' => 0x8D, 'jnl' => 0x8D,
    'jl' => 0x8C, 'jnge' => 0x8C, 'jle' => 0x8E, 'jng' => 0x8E,
    'ja' => 0x87, 'jnbe' => 0x87, 'jae' => 0x83, 'jnb' => 0x83, 'jnc' => 0x83,
    'jb' => 0x82, 'jnae' => 0x82, 'jc' => 0x82, 'jbe' => 0x86, 'jna' => 0x86,
    'js' => 0x88, 'jns' => 0x89, 'jo' => 0x80, 'jno' => 0x81,
    'jp' => 0x8A, 'jpe' => 0x8A, 'jnp' => 0x8B, 'jpo' => 0x8B
  }.freeze
  JCC_ALT = JCC_OP.keys.sort_by { |k| -k.length }.join('|')

  def self.parallel_map(items)
    return [] if items.empty?
    pool_size = [Etc.nprocessors, items.size].min
    pool_size = 1 if pool_size < 1
    results = Array.new(items.size)
    errors = Array.new(items.size)
    queue = Queue.new
    items.each_with_index { |it, i| queue << [it, i] }

    workers = Array.new(pool_size) do
      Thread.new do
        loop do
          job = begin
            queue.pop(true)
          rescue ThreadError
            nil
          end
          break unless job
          item, idx = job
          begin
            results[idx] = yield(item)
          rescue Exception => e
            errors[idx] = e
          end
        end
      end
    end
    workers.each(&:join)

    first_error = errors.compact.first
    raise first_error if first_error
    results
  end

  def self.process_many(entries, base_defines: {})
    return [] if entries.empty?
    parallel_map(entries) do |entry|
      code, filename = entry
      pp = new
      base_defines.each { |name, value| pp.define(name, value) }
      pp.process(code, filename || "")
    end
  end

  def initialize
    @defines = {}
    @define_values = {}
  end

  def define(name, value = nil)
    key = name.to_s
    @defines[key] = true
    @define_values[key] = value
  end

  def defined?(name)
    @defines[name.to_s] == true
  end

  def get_value(name)
    @define_values[name.to_s]
  end

  def process(code, filename = "")
    lines = code.lines
    result = []
    cond_stack = []
    asm_mode = false
    asm_lines = []
    asm_clobbers = nil

    lines.each do |line|
      stripped = line.strip

      if stripped =~ /^#(ifdef|ifndef|if|elif|else|endif)\b/
        handle_conditional(stripped, cond_stack)
        next
      end

      next unless active?(cond_stack)

      if asm_mode
        if stripped == '#endasm'
          asm_mode = false
          bytes, clobbers = assemble_block(asm_lines, asm_clobbers)
          clobber_str = clobbers.empty? ? '' : " clobbers(#{clobbers.join(', ')})"
          result << "insertC#{clobber_str} { #{bytes.map { |b| "0x%02X" % b }.join(', ')} }\n"
          asm_lines = []
          asm_clobbers = nil
        else
          asm_lines << stripped
        end
        next
      end

      if stripped == '#asm'
        asm_mode = true
        asm_lines = []
        asm_clobbers = nil
        next
      end

      if stripped =~ /^#asm\s+clobbers\s*\(([^)]*)\)\s*$/i
        asm_mode = true
        asm_lines = []
        asm_clobbers = $1.split(',').map(&:strip).reject(&:empty?)
        next
      end

      if stripped.start_with?('#')
        process_directive(stripped, result, filename)
      else
        result << replace_macros(line)
      end
    end

    unless cond_stack.empty?
      raise "Preprocessor error in #{filename}: unterminated #if/#ifdef/#ifndef (missing #endif)"
    end
    raise "Preprocessor error in #{filename}: unterminated #asm block (missing #endasm)" if asm_mode

    result.join
  end

  private

  def active?(cond_stack)
    cond_stack.empty? || cond_stack.last[:active]
  end

  def handle_conditional(stripped, cond_stack)
    case stripped
    when /^#ifdef\s+(\w+)$/
      push_frame(cond_stack, @defines[$1] == true)
    when /^#ifndef\s+(\w+)$/
      push_frame(cond_stack, !(@defines[$1] == true))
    when /^#if\s+(.+)$/
      push_frame(cond_stack, eval_condition($1.strip))
    when /^#elif\s+(.+)$/
      handle_elif(cond_stack, $1.strip)
    when /^#else\b/
      handle_else(cond_stack)
    when /^#endif\b/
      raise "Preprocessor error: #endif without matching #if/#ifdef/#ifndef" if cond_stack.empty?
      cond_stack.pop
    end
  end

  def push_frame(cond_stack, cond)
    parent_active = active?(cond_stack)
    frame_active = parent_active && cond
    cond_stack.push(active: frame_active, taken: frame_active, parent_active: parent_active)
  end

  def handle_elif(cond_stack, expr)
    return if cond_stack.empty?
    frame = cond_stack.last
    if frame[:parent_active] && !frame[:taken] && eval_condition(expr)
      frame[:active] = true
      frame[:taken] = true
    else
      frame[:active] = false
    end
  end

  def handle_else(cond_stack)
    return if cond_stack.empty?
    frame = cond_stack.last
    if frame[:parent_active] && !frame[:taken]
      frame[:active] = true
      frame[:taken] = true
    else
      frame[:active] = false
    end
  end

  def eval_condition(expr)
    e = expr.dup
    e = e.gsub(/defined\s*\(\s*([A-Za-z_]\w*)\s*\)/) { @defines[$1] == true ? '1' : '0' }
    e = e.gsub(/defined\s+([A-Za-z_]\w*)/)          { @defines[$1] == true ? '1' : '0' }

    e = e.gsub(/\b[A-Za-z_]\w*\b/) do |ident|
      next ident if %w[true false].include?(ident)
      val = @define_values[ident]
      if val && val.to_s =~ /\A-?\d+\z/
        val.to_s
      elsif @defines[ident]
        '1'
      else
        '0'
      end
    end

    return false unless e =~ /\A[\s0-9()!&|<>=+\-\*\/truefalse]*\z/

    begin
      !!eval(e)
    rescue StandardError, SyntaxError
      false
    end
  end

  def process_directive(line, result, filename)
    case line
    when /^#define\s+(\w+)\s+(.+)$/
      @defines[$1] = true
      @define_values[$1] = $2.strip

    when /^#define\s+(\w+)$/
      @defines[$1] = true
      @define_values[$1] = nil

    when /^#undef\s+(\w+)$/
      @defines.delete($1)
      @define_values.delete($1)

    when /^#include\s+"([^"]+)"$/
      path = $1
      base_dir = filename && !filename.empty? ? File.dirname(filename) : '.'
      candidate = File.join(base_dir, path)
      full_path = File.exist?(candidate) ? candidate : path
      raise "Preprocessor error in #{filename}: cannot find include file '#{path}'" unless File.exist?(full_path)
      result << process(File.read(full_path), full_path)

    when /^#error\s+(.+)$/
      raise "Preprocessor error in #{filename}: #{$1}"

    when /^#warning\s+(.+)$/
      puts "\e[33mWarning: #{$1}\e[0m"

    when /^#pragma\b/
      nil

    else
      nil
    end
  end

  def replace_macros(line)
    result = line
    @define_values.each do |name, value|
      next if value.nil?
      result = result.gsub(/\b#{Regexp.escape(name)}\b/, value.to_s)
    end
    result
  end

  def reg_info(name)
    REG_LOOKUP.fetch(name.downcase) { raise "Assembler error: unknown register '#{name}'" }
  end

  def reg_num64(name)
    SIZE_REGS[64].fetch(name.downcase) { raise "Assembler error: '#{name}' is not a valid base/index register" }
  end

  def reg_needs_rex8(name)
    size, idx = reg_info(name)
    size == 8 && idx.between?(4, 7)
  end

  def canonical_reg(name)
    _, idx = reg_info(name)
    SIZE_REGS[64].key(idx)
  end

  def parse_int(str)
    s = str.strip
    neg = s.start_with?('-')
    s = s[1..-1] if neg
    val = s.downcase.start_with?('0x') ? s.to_i(16) : s.to_i
    neg ? -val : val
  end

  def imm_bytes(val, size)
    case size
    when 8  then [val & 0xFF]
    when 16 then [val & 0xFFFF].pack('S<').bytes
    when 32 then [val & 0xFFFFFFFF].pack('L<').bytes
    when 64 then [val & 0xFFFFFFFFFFFFFFFF].pack('Q<').bytes
    end
  end

  def size_prefixes(size, ext = {}, force_rex: false)
    r = ext[:r] || 0
    x = ext[:x] || 0
    b = ext[:b] || 0
    bytes = []
    bytes << 0x66 if size == 16
    w = size == 64 ? 1 : 0
    rex = 0x40 | (w << 3) | (r << 2) | (x << 1) | b
    need_rex = w == 1 || r == 1 || x == 1 || b == 1 || force_rex
    bytes << rex if need_rex
    bytes
  end

  def parse_mem_operand(expr)
    base = nil
    index = nil
    scale = 1
    disp = 0
    s = expr.gsub(/\s+/, '')
    terms = s.scan(/[+\-]?[^+\-]+/)
    terms.each do |t|
      sign = 1
      body = t
      if body.start_with?('+')
        body = body[1..-1]
      elsif body.start_with?('-')
        sign = -1
        body = body[1..-1]
      end

      if body =~ /\A(#{REG64_ALT})(?:\*(\d+))?\z/i
        regname = $1
        sc = $2
        if sc
          raise "Assembler error: index register cannot be negated" if sign == -1
          index = regname
          scale = sc.to_i
        elsif base.nil? && sign == 1
          base = regname
        elsif index.nil?
          raise "Assembler error: implicit index register cannot be negated" if sign == -1
          index = regname
          scale = 1
        else
          raise "Assembler error: too many registers in memory operand '#{expr}'"
        end
      elsif body =~ /\A(#{NUM_RE})\z/
        disp += sign * parse_int(body)
      else
        raise "Assembler error: cannot parse memory operand term '#{t}' in '#{expr}'"
      end
    end
    { base: base, index: index, scale: scale, disp: disp }
  end

  def encode_mem_operand(reg_field, mem)
    base = mem[:base]
    index = mem[:index]
    scale = mem[:scale] || 1
    disp = mem[:disp] || 0

    x_ext = 0
    b_ext = 0
    idx_low = nil
    scale_bits = 0

    if index
      idx_num = reg_num64(index)
      idx_low = idx_num & 7
      x_ext = idx_num >= 8 ? 1 : 0
      raise "Assembler error: RSP/R12 cannot be used as SIB index register" if idx_low == 4
      scale_bits = { 1 => 0, 2 => 1, 4 => 2, 8 => 3 }.fetch(scale) do
        raise "Assembler error: invalid SIB scale #{scale} (must be 1, 2, 4 or 8)"
      end
    end

    base_low = nil
    if base
      base_num = reg_num64(base)
      base_low = base_num & 7
      b_ext = base_num >= 8 ? 1 : 0
    end

    force_disp8 = base && base_low == 5

    mod =
      if !base
        0b00
      elsif disp == 0 && !force_disp8
        0b00
      elsif disp.between?(-128, 127)
        0b01
      else
        0b10
      end

    disp_bytes =
      case mod
      when 0b00 then base ? [] : [disp & 0xFFFFFFFF].pack('L<').bytes
      when 0b01 then [disp & 0xFF].pack('C').bytes
      else [disp & 0xFFFFFFFF].pack('L<').bytes
      end

    needs_sib = index || !base || base_low == 4

    bytes = []
    if needs_sib
      bytes << ((mod << 6) | (reg_field << 3) | 0b100)
      sib_base = base ? base_low : 0b101
      sib_index = index ? idx_low : 0b100
      bytes << ((scale_bits << 6) | (sib_index << 3) | sib_base)
    else
      bytes << ((mod << 6) | (reg_field << 3) | base_low)
    end
    bytes.concat(disp_bytes)
    [bytes, x_ext, b_ext]
  end

  def encode_mov_reg_imm(reg, val, force64)
    size, idx = reg_info(reg)
    low = idx & 7
    ext = idx >= 8 ? 1 : 0
    prefixes = size_prefixes(size, { b: ext }, force_rex: reg_needs_rex8(reg))
    case size
    when 8  then prefixes + [0xB0 + low] + imm_bytes(val, 8)
    when 16 then prefixes + [0xB8 + low] + imm_bytes(val, 16)
    when 32 then prefixes + [0xB8 + low] + imm_bytes(val, 32)
    when 64
      if !force64 && val >= -0x80000000 && val <= 0x7fffffff
        prefixes + [0xC7, 0xC0 + low] + imm_bytes(val, 32)
      else
        prefixes + [0xB8 + low] + imm_bytes(val, 64)
      end
    end
  end

  def encode_mov_reg_reg(dst, src)
    dsize, didx = reg_info(dst)
    ssize, sidx = reg_info(src)
    raise "Assembler error: operand size mismatch in 'mov #{dst}, #{src}'" if dsize != ssize
    dlow = didx & 7; dext = didx >= 8 ? 1 : 0
    slow = sidx & 7; sext = sidx >= 8 ? 1 : 0
    prefixes = size_prefixes(dsize, { r: sext, b: dext }, force_rex: reg_needs_rex8(dst) || reg_needs_rex8(src))
    opcode = dsize == 8 ? 0x88 : 0x89
    prefixes + [opcode, 0xC0 + slow * 8 + dlow]
  end

  def encode_mov_reg_mem(dst, mem_expr)
    size, idx = reg_info(dst)
    mem = parse_mem_operand(mem_expr)
    low = idx & 7; dext = idx >= 8 ? 1 : 0
    mem_bytes, x_ext, b_ext = encode_mem_operand(low, mem)
    prefixes = size_prefixes(size, { r: dext, x: x_ext, b: b_ext }, force_rex: reg_needs_rex8(dst))
    opcode = size == 8 ? 0x8A : 0x8B
    prefixes + [opcode] + mem_bytes
  end

  def encode_mov_mem_reg(mem_expr, src)
    size, idx = reg_info(src)
    mem = parse_mem_operand(mem_expr)
    low = idx & 7; sext = idx >= 8 ? 1 : 0
    mem_bytes, x_ext, b_ext = encode_mem_operand(low, mem)
    prefixes = size_prefixes(size, { r: sext, x: x_ext, b: b_ext }, force_rex: reg_needs_rex8(src))
    opcode = size == 8 ? 0x88 : 0x89
    prefixes + [opcode] + mem_bytes
  end

  def encode_lea(dst, mem_expr)
    size, idx = reg_info(dst)
    raise "Assembler error: 'lea' requires a 16/32/64-bit destination register" if size == 8
    mem = parse_mem_operand(mem_expr)
    low = idx & 7; dext = idx >= 8 ? 1 : 0
    mem_bytes, x_ext, b_ext = encode_mem_operand(low, mem)
    prefixes = size_prefixes(size, { r: dext, x: x_ext, b: b_ext })
    prefixes + [0x8D] + mem_bytes
  end

  def encode_alu_reg_reg(mnem, dst, src)
    dsize, didx = reg_info(dst)
    ssize, sidx = reg_info(src)
    raise "Assembler error: operand size mismatch in '#{mnem} #{dst}, #{src}'" if dsize != ssize
    op_full = ALU_RR_OP[mnem]
    op = dsize == 8 ? op_full - 1 : op_full
    dlow = didx & 7; dext = didx >= 8 ? 1 : 0
    slow = sidx & 7; sext = sidx >= 8 ? 1 : 0
    prefixes = size_prefixes(dsize, { r: sext, b: dext }, force_rex: reg_needs_rex8(dst) || reg_needs_rex8(src))
    prefixes + [op, 0xC0 + slow * 8 + dlow]
  end

  def encode_alu_reg_imm(mnem, reg, val)
    size, idx = reg_info(reg)
    digit = ALU_IMM_DIGIT[mnem]
    low = idx & 7; ext = idx >= 8 ? 1 : 0
    prefixes = size_prefixes(size, { b: ext }, force_rex: reg_needs_rex8(reg))
    if size == 8
      prefixes + [0x80, 0xC0 + digit * 8 + low] + imm_bytes(val, 8)
    elsif val.between?(-128, 127)
      prefixes + [0x83, 0xC0 + digit * 8 + low] + imm_bytes(val, 8)
    else
      immsize = size == 16 ? 16 : 32
      prefixes + [0x81, 0xC0 + digit * 8 + low] + imm_bytes(val, immsize)
    end
  end

  def encode_test_reg_imm(reg, val)
    size, idx = reg_info(reg)
    low = idx & 7; ext = idx >= 8 ? 1 : 0
    prefixes = size_prefixes(size, { b: ext }, force_rex: reg_needs_rex8(reg))
    opcode = size == 8 ? 0xF6 : 0xF7
    immsize = size == 8 ? 8 : (size == 16 ? 16 : 32)
    prefixes + [opcode, 0xC0 + low] + imm_bytes(val, immsize)
  end

  def encode_incdec(mnem, reg)
    size, idx = reg_info(reg)
    low = idx & 7; ext = idx >= 8 ? 1 : 0
    prefixes = size_prefixes(size, { b: ext }, force_rex: reg_needs_rex8(reg))
    opcode = size == 8 ? 0xFE : 0xFF
    digit = mnem == 'inc' ? 0 : 1
    prefixes + [opcode, 0xC0 + digit * 8 + low]
  end

  def encode_negnot(mnem, reg)
    size, idx = reg_info(reg)
    low = idx & 7; ext = idx >= 8 ? 1 : 0
    prefixes = size_prefixes(size, { b: ext }, force_rex: reg_needs_rex8(reg))
    opcode = size == 8 ? 0xF6 : 0xF7
    digit = mnem == 'neg' ? 3 : 2
    prefixes + [opcode, 0xC0 + digit * 8 + low]
  end

  def encode_shift_imm(mnem, reg, cnt)
    size, idx = reg_info(reg)
    low = idx & 7; ext = idx >= 8 ? 1 : 0
    digit = SHIFT_DIGIT[mnem]
    prefixes = size_prefixes(size, { b: ext }, force_rex: reg_needs_rex8(reg))
    opcode = size == 8 ? 0xC0 : 0xC1
    prefixes + [opcode, 0xC0 + digit * 8 + low, cnt & 0xFF]
  end

  def encode_shift_cl(mnem, reg)
    size, idx = reg_info(reg)
    low = idx & 7; ext = idx >= 8 ? 1 : 0
    digit = SHIFT_DIGIT[mnem]
    prefixes = size_prefixes(size, { b: ext }, force_rex: reg_needs_rex8(reg))
    opcode = size == 8 ? 0xD2 : 0xD3
    prefixes + [opcode, 0xC0 + digit * 8 + low]
  end

  def encode_push(reg)
    size, idx = reg_info(reg)
    raise "Assembler error: cannot push a 32-bit register in long mode ('#{reg}')" if size == 32
    low = idx & 7; ext = idx >= 8 ? 1 : 0
    prefixes = []
    prefixes << 0x66 if size == 16
    prefixes << (0x40 | ext) if ext == 1
    prefixes + [0x50 + low]
  end

  def encode_pop(reg)
    size, idx = reg_info(reg)
    raise "Assembler error: cannot pop a 32-bit register in long mode ('#{reg}')" if size == 32
    low = idx & 7; ext = idx >= 8 ? 1 : 0
    prefixes = []
    prefixes << 0x66 if size == 16
    prefixes << (0x40 | ext) if ext == 1
    prefixes + [0x58 + low]
  end

  def label_rel(labels, name, next_offset)
    target = labels[name]
    raise "Assembler error: undefined label '#{name}'" if target.nil?
    target - next_offset
  end

  def clean_asm_line(raw_line)
    return "" if raw_line.nil? || raw_line.empty?
    parts = raw_line.split('//')
    return "" if parts.empty?
    parts2 = parts.first.split('#')
    return "" if parts2.empty?
    parts2.first.strip
  end

  def parse_data_values(str)
    vals = []
    str.scan(/"((?:[^"\\]|\\.)*)"|(#{NUM_RE})/) do |strval, numval|
      if strval
        strval.each_char { |c| vals << c.ord }
      elsif numval
        vals << parse_int(numval)
      end
    end
    vals
  end

  def written_register(line)
    case line
    when /^mov(?:abs)?\s+(#{REG_ALT_ALL})\s*,/i then canonical_reg($1)
    when /^lea\s+(#{REG_ALT_ALL})\s*,/i then canonical_reg($1)
    when /^(add|sub|and|or|xor)\s+(#{REG_ALT_ALL})\s*,/i then canonical_reg($2)
    when /^(inc|dec|neg|not|pop)\s+(#{REG_ALT_ALL})\b/i then canonical_reg($2)
    when /^(shl|shr|sar|rol|ror|rcl|rcr)\s+(#{REG_ALT_ALL})\s*,/i then canonical_reg($2)
    else nil
    end
  end

  def flag_affecting?(line)
    !!(line =~ /^(add|sub|and|or|xor|cmp|test|inc|dec|neg|shl|shr|sar|rol|ror|rcl|rcr)\b/i)
  end

  def collect_clobbers(cleaned_lines, declared)
    detected = {}
    flags_touched = false
    cleaned_lines.each do |l|
      next if l =~ LABEL_DEF_RE
      reg = written_register(l)
      detected[reg] = true if reg
      flags_touched = true if flag_affecting?(l)
    end
    detected_list = detected.keys.sort

    final_list =
      if declared
        declared_norm = declared.map { |r|
          if %w[memory flags cc fpsr].include?(r.to_s.downcase)
            r.to_s.downcase
          else
            canonical_reg(r)
          end
        }.uniq
        missing = detected_list - declared_norm
        unless missing.empty?
          raise "Assembler error: registers #{missing.join(', ')} are modified inside #asm block but not declared in clobbers(...). Declare them explicitly to avoid undefined behavior with the surrounding compiler's register allocation."
        end
        declared_norm
      else
        detected_list
      end

    final_list << 'flags' if flags_touched
    final_list
  end

  def assemble_block(raw_lines, declared_clobbers)
    cleaned = raw_lines.map { |l| clean_asm_line(l) }.reject(&:empty?)

    sizes = self.class.parallel_map(cleaned) do |l|
      if l =~ LABEL_DEF_RE
        0
      else
        assemble_line(l, 0, Hash.new(0)).size
      end
    end

    labels = {}
    offsets = []
    offset = 0
    cleaned.each_with_index do |l, i|
      if l =~ LABEL_DEF_RE
        labels[$1] = offset
        offsets << nil
      else
        offsets << offset
        offset += sizes[i]
      end
    end

    encoded = self.class.parallel_map(cleaned.each_with_index.to_a) do |(l, i)|
      if l =~ LABEL_DEF_RE
        []
      else
        assemble_line(l, offsets[i], labels)
      end
    end

    bytes = encoded.flatten(1)
    clobbers = collect_clobbers(cleaned, declared_clobbers)
    [bytes, clobbers]
  end

  def assemble_line(line, offset = 0, labels = {})
    return [] if line.empty?

    case line
    when /^syscall$/i    then [0x0F, 0x05]
    when /^ret$/i         then [0xC3]
    when /^leave$/i       then [0xC9]
    when /^cli$/i         then [0xFA]
    when /^sti$/i         then [0xFB]
    when /^hlt$/i         then [0xF4]
    when /^nop$/i         then [0x90]
    when /^pause$/i       then [0xF3, 0x90]
    when /^iretq$/i       then [0x48, 0xCF]
    when /^rdmsr$/i       then [0x0F, 0x32]
    when /^wrmsr$/i       then [0x0F, 0x30]
    when /^cpuid$/i       then [0x0F, 0xA2]
    when /^rdtsc$/i       then [0x0F, 0x31]
    when /^rdtscp$/i      then [0x0F, 0x01, 0xF9]
    when /^wbinvd$/i      then [0x0F, 0x09]
    when /^invd$/i        then [0x0F, 0x08]
    when /^clts$/i        then [0x0F, 0x06]
    when /^ud2$/i         then [0x0F, 0x0B]
    when /^clc$/i         then [0xF8]
    when /^stc$/i         then [0xF9]
    when /^cmc$/i         then [0xF5]
    when /^cld$/i         then [0xFC]
    when /^std$/i         then [0xFD]
    when /^lahf$/i        then [0x9F]
    when /^sahf$/i        then [0x9E]
    when /^cqo$/i         then [0x48, 0x99]
    when /^cdq$/i         then [0x99]
    when /^cwd$/i         then [0x66, 0x99]
    when /^cdqe$/i        then [0x48, 0x98]
    when /^cwde$/i        then [0x98]
    when /^cbw$/i         then [0x66, 0x98]
    when /^int1$/i        then [0xF1]
    when /^int3$/i, /^int\s+3$/i then [0xCC]

    when /^db\s+(.+)$/i then parse_data_values($1).flat_map { |v| [v & 0xFF] }
    when /^dw\s+(.+)$/i then parse_data_values($1).flat_map { |v| [v & 0xFFFF].pack('S<').bytes }
    when /^dd\s+(.+)$/i then parse_data_values($1).flat_map { |v| [v & 0xFFFFFFFF].pack('L<').bytes }
    when /^dq\s+(.+)$/i then parse_data_values($1).flat_map { |v| [v & 0xFFFFFFFFFFFFFFFF].pack('Q<').bytes }

    when /^in\s+al\s*,\s*dx$/i    then [0xEC]
    when /^out\s+dx\s*,\s*al$/i   then [0xEE]
    when /^in\s+ax\s*,\s*dx$/i    then [0x66, 0xED]
    when /^out\s+dx\s*,\s*ax$/i   then [0x66, 0xEF]
    when /^in\s+eax\s*,\s*dx$/i   then [0xED]
    when /^out\s+dx\s*,\s*eax$/i  then [0xEF]
    when /^in\s+al\s*,\s*(#{NUM_RE})$/i   then [0xE4, parse_int($1) & 0xFF]
    when /^out\s+(#{NUM_RE})\s*,\s*al$/i  then [0xE6, parse_int($1) & 0xFF]
    when /^in\s+eax\s*,\s*(#{NUM_RE})$/i  then [0xE5, parse_int($1) & 0xFF]
    when /^out\s+(#{NUM_RE})\s*,\s*eax$/i then [0xE7, parse_int($1) & 0xFF]

    when /^int\s+(#{NUM_RE})$/i
      [0xCD, parse_int($1) & 0xFF]

    when /^push\s+(#{REG_ALT_ALL})$/i then encode_push($1)
    when /^pop\s+(#{REG_ALT_ALL})$/i  then encode_pop($1)

    when /^call\s+(#{REG64_ALT})$/i
      low = reg_num64($1) & 7; ext = reg_num64($1) >= 8 ? 1 : 0
      (ext == 1 ? [0x41] : []) + [0xFF, 0xD0 + low]
    when /^jmp\s+(#{REG64_ALT})$/i
      low = reg_num64($1) & 7; ext = reg_num64($1) >= 8 ? 1 : 0
      (ext == 1 ? [0x41] : []) + [0xFF, 0xE0 + low]

    when /^call\s+(#{LABEL_RE})$/i
      rel = label_rel(labels, $1, offset + 5)
      [0xE8] + [rel & 0xFFFFFFFF].pack('L<').bytes

    when /^jmp\s+(#{LABEL_RE})$/i
      rel = label_rel(labels, $1, offset + 5)
      [0xE9] + [rel & 0xFFFFFFFF].pack('L<').bytes

    when /^(#{JCC_ALT})\s+(#{LABEL_RE})$/i
      op2 = JCC_OP[$1.downcase]
      rel = label_rel(labels, $2, offset + 6)
      [0x0F, op2] + [rel & 0xFFFFFFFF].pack('L<').bytes

    when /^mov(?:abs)?\s+(#{REG_ALT_ALL})\s*,\s*(#{NUM_RE})$/i
      encode_mov_reg_imm($1, parse_int($2), line =~ /^movabs\b/i ? true : false)

    when /^mov\s+(#{REG_ALT_ALL})\s*,\s*(#{REG_ALT_ALL})$/i
      encode_mov_reg_reg($1, $2)

    when /^mov\s+(#{REG_ALT_ALL})\s*,\s*\[([^\[\]]+)\]$/i
      encode_mov_reg_mem($1, $2)

    when /^mov\s+\[([^\[\]]+)\]\s*,\s*(#{REG_ALT_ALL})$/i
      encode_mov_mem_reg($1, $2)

    when /^lea\s+(#{REG_ALT_ALL})\s*,\s*\[([^\[\]]+)\]$/i
      encode_lea($1, $2)

    when /^(add|or|and|sub|xor|cmp|test)\s+(#{REG_ALT_ALL})\s*,\s*(#{REG_ALT_ALL})$/i
      encode_alu_reg_reg($1.downcase, $2, $3)

    when /^(add|or|and|sub|xor|cmp)\s+(#{REG_ALT_ALL})\s*,\s*(#{NUM_RE})$/i
      encode_alu_reg_imm($1.downcase, $2, parse_int($3))

    when /^test\s+(#{REG_ALT_ALL})\s*,\s*(#{NUM_RE})$/i
      encode_test_reg_imm($1, parse_int($2))

    when /^inc\s+(#{REG_ALT_ALL})$/i then encode_incdec('inc', $1)
    when /^dec\s+(#{REG_ALT_ALL})$/i then encode_incdec('dec', $1)
    when /^neg\s+(#{REG_ALT_ALL})$/i then encode_negnot('neg', $1)
    when /^not\s+(#{REG_ALT_ALL})$/i then encode_negnot('not', $1)

    when /^(rol|ror|rcl|rcr|shl|shr|sar)\s+(#{REG_ALT_ALL})\s*,\s*(\d+)$/i
      encode_shift_imm($1.downcase, $2, $3.to_i)
    when /^(rol|ror|rcl|rcr|shl|shr|sar)\s+(#{REG_ALT_ALL})\s*,\s*cl$/i
      encode_shift_cl($1.downcase, $2)

    when /^mov\s+cr(0|2|3|4)\s*,\s*(#{REG64_ALT})$/i
      crn = $1.to_i; low = reg_num64($2) & 7; ext = reg_num64($2) >= 8 ? 1 : 0
      (ext == 1 ? [0x40 | ext] : []) + [0x0F, 0x22, 0xC0 + crn * 8 + low]
    when /^mov\s+(#{REG64_ALT})\s*,\s*cr(0|2|3|4)$/i
      low = reg_num64($1) & 7; ext = reg_num64($1) >= 8 ? 1 : 0; crn = $2.to_i
      (ext == 1 ? [0x40 | ext] : []) + [0x0F, 0x20, 0xC0 + crn * 8 + low]

    when /^(sgdt|sidt|lgdt|lidt|smsw|lmsw|invlpg)\s+\[([^\[\]]+)\]$/i
      digit = SYS_MEM_DIGIT[$1.downcase]
      mem = parse_mem_operand($2)
      mem_bytes, x_ext, b_ext = encode_mem_operand(digit, mem)
      rex = 0x40 | (x_ext << 1) | b_ext
      prefix = (x_ext == 1 || b_ext == 1) ? [rex] : []
      prefix + [0x0F, 0x01] + mem_bytes

    when /^(lldt|ltr|verr|verw)\s+(#{REG64_ALT})$/i
      digit = SYS_REG_DIGIT[$1.downcase]
      low = reg_num64($2) & 7; ext = reg_num64($2) >= 8 ? 1 : 0
      (ext == 1 ? [0x40 | ext] : []) + [0x0F, 0x00, 0xC0 + digit * 8 + low]

    else
      []
    end
  end
end
