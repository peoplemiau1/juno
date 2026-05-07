module LLVMBuiltinGenerator
  def gen_call(node)
    name = node[:name]
    tmp = next_tmp
    
    case name
    when "syscall"
      args = node[:args].map { |a| eval_expr(a) }
      num = args.shift
      args_str = args.map { |a| "i64 #{a}" }.join(", ")
      r = next_tmp
      @output << "  %#{r} = call i64 (i64, ...) @syscall(i64 #{num}, #{args_str})\n"
      return "%#{r}"
    when "str_len"
      arg = eval_expr(node[:args][0])
      r = next_tmp
      @output << "  %#{r} = call i64 @juno_strlen(i64 #{arg})\n"
      return "%#{r}"
    when "concat"
      a = eval_expr(node[:args][0])
      b = eval_expr(node[:args][1])
      r = next_tmp
      @output << "  %#{r} = call i64 @concat(i64 #{a}, i64 #{b})\n"
      return "%#{r}"
    when "substr"
      s = eval_expr(node[:args][0])
      start = eval_expr(node[:args][1])
      len = eval_expr(node[:args][2])
      r = next_tmp
      @output << "  %#{r} = call i64 @substr(i64 #{s}, i64 #{start}, i64 #{len})\n"
      return "%#{r}"
    when "time"
      r = next_tmp
      @output << "  %#{r} = call i64 @time(i64 0)\n"
      return "%#{r}"
    when "rand"
      r_int = next_tmp
      @output << "  %#{r_int} = call i32 @rand()\n"
      r = next_tmp
      @output << "  %#{r} = sext i32 %#{r_int} to i64\n"
      return "%#{r}"
    when "max", "min"
      a = eval_expr(node[:args][0])
      b = eval_expr(node[:args][1])
      cmp = next_tmp
      @output << "  %#{cmp} = icmp #{name == 'max' ? 'sgt' : 'slt'} i64 #{a}, #{b}\n"
      r = next_tmp
      @output << "  %#{r} = select i1 %#{cmp}, i64 #{a}, i64 #{b}\n"
      return "%#{r}"
    when "abs"
      arg = eval_expr(node[:args][0])
      neg = next_tmp
      @output << "  %#{neg} = sub i64 0, #{arg}\n"
      cmp = next_tmp
      @output << "  %#{cmp} = icmp slt i64 #{arg}, 0\n"
      r = next_tmp
      @output << "  %#{r} = select i1 %#{cmp}, i64 %#{neg}, i64 #{arg}\n"
      return "%#{r}"
    when "pow"
      base = eval_expr(node[:args][0])
      exp = eval_expr(node[:args][1])
      r = next_tmp
      @output << "  %#{r} = call i64 @juno_pow(i64 #{base}, i64 #{exp})\n"
      return "%#{r}"
    when "ord"
      arg = eval_expr(node[:args][0])
      tmp_ptr = next_tmp
      @output << "  %#{tmp_ptr} = inttoptr i64 #{arg} to i8*\n"
      tmp_val = next_tmp
      @output << "  %#{tmp_val} = load i8, i8* %#{tmp_ptr}\n"
      res = next_tmp
      @output << "  %#{res} = zext i8 %#{tmp_val} to i64\n"
      return "%#{res}"
    when "chr"
      arg = eval_expr(node[:args][0])
      buf = next_tmp
      @output << "  %#{buf} = call i64 @malloc(i64 2)\n"
      ptr0 = next_tmp
      @output << "  %#{ptr0} = inttoptr i64 %#{buf} to i8*\n"
      val_b = next_tmp
      @output << "  %#{val_b} = trunc i64 #{arg} to i8\n"
      @output << "  store i8 %#{val_b}, i8* %#{ptr0}\n"
      ptr1 = next_tmp
      @output << "  %#{ptr1} = getelementptr i8, i8* %#{ptr0}, i64 1\n"
      @output << "  store i8 0, i8* %#{ptr1}\n"
      return "%#{buf}"
    when "i8", "u8", "i16", "u16", "i32", "u32"
      arg = eval_expr(node[:args][0])
      bits = name[1..-1].to_i
      is_signed = name.start_with?("i")
      t1 = next_tmp
      @output << "  %#{t1} = trunc i64 #{arg} to i#{bits}\n"
      r = next_tmp
      ext = is_signed ? "sext" : "zext"
      @output << "  %#{r} = #{ext} i#{bits} %#{t1} to i64\n"
      return "%#{r}"
    when "ptr_add", "byte_add"
      ptr = eval_expr(node[:args][0])
      off = eval_expr(node[:args][1])
      r = next_tmp
      if name == "ptr_add"
        real_off = next_tmp
        @output << "  %#{real_off} = mul i64 #{off}, 8\n"
        @output << "  %#{r} = add i64 #{ptr}, %#{real_off}\n"
      else
        @output << "  %#{r} = add i64 #{ptr}, #{off}\n"
      end
      return "%#{r}"
    when "memcpy", "memset"
      args = node[:args].map { |a| eval_expr(a) }
      dst_p = next_tmp
      @output << "  %#{dst_p} = inttoptr i64 #{args[0]} to i8*\n"
      if name == "memcpy"
        src_p = next_tmp
        @output << "  %#{src_p} = inttoptr i64 #{args[1]} to i8*\n"
        @output << "  call void @llvm.memcpy.p0i8.p0i8.i64(i8* %#{dst_p}, i8* %#{src_p}, i64 #{args[2]}, i1 false)\n"
      else
        val_b = next_tmp
        @output << "  %#{val_b} = trunc i64 #{args[1]} to i8\n"
        @output << "  call void @llvm.memset.p0i8.i64(i8* %#{dst_p}, i8 %#{val_b}, i64 #{args[2]}, i1 false)\n"
      end
      return "0"
    when "malloc"
      arg = eval_expr(node[:args][0])
      r = next_tmp
      @output << "  %#{r} = call i64 @malloc(i64 #{arg})\n"
      return "%#{r}"
    when "realloc"
      ptr = eval_expr(node[:args][0])
      size = eval_expr(node[:args][1])
      tmp_ptr = next_tmp
      @output << "  %#{tmp_ptr} = inttoptr i64 #{ptr} to i8*\n"
      r = next_tmp
      @output << "  %#{r} = call i64 @realloc(i8* %#{tmp_ptr}, i64 #{size})\n"
      return "%#{r}"
    when "free"
      ptr = eval_expr(node[:args][0])
      tmp_ptr = next_tmp
      @output << "  %#{tmp_ptr} = inttoptr i64 #{ptr} to i8*\n"
      @output << "  call void @free(i8* %#{tmp_ptr})\n"
      return "0"
    when "write", "read"
      args = node[:args].map { |a| eval_expr(a) }
      tmp_ptr = next_tmp
      @output << "  %#{tmp_ptr} = inttoptr i64 #{args[1]} to i8*\n"
      tmp_fd = next_tmp
      @output << "  %#{tmp_fd} = trunc i64 #{args[0]} to i32\n"
      res = next_tmp
      @output << "  %#{res} = call i64 @#{name}(i32 %#{tmp_fd}, i8* %#{tmp_ptr}, i64 #{args[2]})\n"
      return "%#{res}"
    when "open"
      path = eval_expr(node[:args][0])
      flags = eval_expr(node[:args][1])
      mode = node[:args][2] ? eval_expr(node[:args][2]) : "0"
      tmp_path = next_tmp
      @output << "  %#{tmp_path} = inttoptr i64 #{path} to i8*\n"
      tmp_flags = next_tmp
      @output << "  %#{tmp_flags} = trunc i64 #{flags} to i32\n"
      tmp_mode = next_tmp
      @output << "  %#{tmp_mode} = trunc i64 #{mode} to i32\n"
      res = next_tmp
      @output << "  %#{res} = call i32 (i8*, i32, ...) @open(i8* %#{tmp_path}, i32 %#{tmp_flags}, i32 %#{tmp_mode})\n"
      ext = next_tmp
      @output << "  %#{ext} = sext i32 %#{res} to i64\n"
      return "%#{ext}"
    when "close"
      fd = eval_expr(node[:args][0])
      tmp_fd = next_tmp
      @output << "  %#{tmp_fd} = trunc i64 #{fd} to i32\n"
      @output << "  call i32 @close(i32 %#{tmp_fd})\n"
      return "0"
    when "spin_lock"
      ptr = eval_expr(node[:args][0])
      l_loop = next_label("spin_loop")
      l_exit = next_label("spin_exit")
      tmp_p = next_tmp
      @output << "  %#{tmp_p} = inttoptr i64 #{ptr} to i64*\n"
      @output << "  br label %#{l_loop}\n"
      @output << "#{l_loop}:\n"
      tmp_v = next_tmp
      @output << "  %#{tmp_v} = atomicrmw xchg i64* %#{tmp_p}, i64 1 acquire\n"
      tmp_c = next_tmp
      @output << "  %#{tmp_c} = icmp eq i64 %#{tmp_v}, 0\n"
      @output << "  br i1 %#{tmp_c}, label %#{l_exit}, label %#{l_loop}\n"
      @output << "#{l_exit}:\n"
      return "0"
    when "spin_unlock"
      ptr = eval_expr(node[:args][0])
      tmp_p = next_tmp
      @output << "  %#{tmp_p} = inttoptr i64 #{ptr} to i64*\n"
      @output << "  store atomic i64 0, i64* %#{tmp_p} release, align 8\n"
      return "0"
    when "store_i64", "store_ptr"
      p = eval_expr(node[:args][0])
      v = eval_expr(node[:args][1])
      tmp_p = next_tmp
      @output << "  %#{tmp_p} = inttoptr i64 #{p} to i64*\n"
      @output << "  store i64 #{v}, i64* %#{tmp_p}, align 8\n"
      return "0"
    when "load_i64", "load_ptr"
      p = eval_expr(node[:args][0])
      tmp_p = next_tmp
      @output << "  %#{tmp_p} = inttoptr i64 #{p} to i64*\n"
      r = next_tmp
      @output << "  %#{r} = load i64, i64* %#{tmp_p}, align 8\n"
      return "%#{r}"
    when "store_i8"
      p = eval_expr(node[:args][0])
      v = eval_expr(node[:args][1])
      tmp_p = next_tmp
      @output << "  %#{tmp_p} = inttoptr i64 #{p} to i8*\n"
      tmp_v = next_tmp
      @output << "  %#{tmp_v} = trunc i64 #{v} to i8\n"
      @output << "  store i8 %#{tmp_v}, i8* %#{tmp_p}, align 1\n"
      return "0"
    when "load_i8"
      p = eval_expr(node[:args][0])
      tmp_p = next_tmp
      @output << "  %#{tmp_p} = inttoptr i64 #{p} to i8*\n"
      tmp_v = next_tmp
      @output << "  %#{tmp_v} = load i8, i8* %#{tmp_p}, align 1\n"
      r = next_tmp
      @output << "  %#{r} = zext i8 %#{tmp_v} to i64\n"
      return "%#{r}"
    end

    # Method calls and custom functions
    func_name = name.gsub('.', '_')
    if name.include?('.')
      parts = name.split('.')
      receiver_name = parts[0]
      method_name = parts[1]
      receiver_type = node[:receiver_type] || find_variable_type(receiver_name)
      
      if receiver_type && !["int", "ptr"].include?(receiver_type)
        real_func_name = "#{receiver_type}_#{method_name}"
        receiver_val = eval_expr({type: :variable, name: receiver_name})
        args_list = "i64 #{receiver_val}"
        unless (node[:args] || []).empty?
          args_list << ", " << node[:args].map { |a| "i64 #{eval_expr(a)}" }.join(", ")
        end
        @output << "  %#{tmp} = call i64 @#{real_func_name}(#{args_list})\n"
        return "%#{tmp}"
      end
    end

    args = (node[:args] || []).map { |a| "i64 #{eval_expr(a)}" }.join(", ")
    @output << "  %#{tmp} = call i64 @#{func_name}(#{args})\n"
    "%#{tmp}"
  end

  def find_variable_type(name)
    @current_function[:body].each do |stmt|
      if stmt[:type] == :assignment && stmt[:name] == name
        return stmt[:var_type] || stmt[:inferred_type] || "int"
      end
    end
    "int"
  end
end
