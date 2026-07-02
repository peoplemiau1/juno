#!/usr/bin/env python3
import os
import sys
import glob
import time
import subprocess
import concurrent.futures
import threading

GREEN = "\033[32m"
RED = "\033[31m"
YELLOW = "\033[33m"
BLUE = "\033[34m"
BOLD = "\033[1m"
RESET = "\033[0m"

print_lock = threading.Lock()

POSITIVE_TESTS = [
    "tests/big_suite.juno",
    "tests/test_simple_str.juno",
    "tests/test_math.juno",
    "tests/test_multiarg_fix.juno",
    "tests/test_else.juno",
    "tests/test_v1.juno",
    "tests/test_array.juno",
    "tests/test_call_order.juno",
    "tests/test_complex_oop.juno",
    "tests/test_debug.juno",
    "tests/test_deref_write.juno",
    "tests/test_exact.juno",
    "tests/test_full.juno",
    "tests/test_linux.juno",
    "tests/test_minimal_demo.juno",
    "tests/test_optimizer.juno",
    "tests/test_pointers.juno",
    "tests/test_ptr_arg.juno",
    "tests/test_ptr_debug.juno",
    "tests/test_ptr_debug2.juno",
    "tests/test_ptr_noopt.juno",
    "tests/test_ptr_parts.juno",
    "tests/test_ptr_read.juno",
    "tests/test_ptr_simple.juno",
    "tests/test_ptr_v2.juno",
    "tests/test_ptr_v3.juno",
    "tests/test_ptr_v4.juno",
    "tests/test_simple.juno",
    "tests/test_simple_demo.juno",
    "tests/test_string.juno",
    "tests/test_swap.juno",
    "tests/test_two_int.juno",
    "tests/test_two_noopt.juno",
    "tests/test_all_features.juno",
    "tests/test_ptr_arith_and_str_plus.juno",
    "tests/test_file_io_wrappers.juno",
    "tests/test_syscall_extended.juno",
    "tests/test_list_v2.juno",
    "tests/test_sized_types_complex.juno",
    "tests/test_selfhost_lexer_smoke.juno",
    "tests/test_selfhost_parser_smoke.juno",
    "tests/test_selfhost_codegen_smoke.juno",
    "tests/test_float_audit.juno",
    "tests/test_float_math.juno",
    "tests/test_new_features.juno",
    "tests/test_predictive_borrow.juno",
    "tests/test_autodrop.juno",
]

FLAT_TESTS = [
    "tests/test_flat_binary.juno",
]

def safe_print(message):
    with print_lock:
        print(message)

def get_output_path(test_file):
    base_name = os.path.basename(test_file).replace(".juno", "")
    return os.path.join("build", f"output_{base_name}")

def run_positive_test(test_file):
    if not os.path.exists(test_file):
        return ("skip", f"{BLUE}[SKIP]{RESET} {test_file} (not found)")
    
    out_path = get_output_path(test_file)
    compile_cmd = ["./bin/juno", "-o", out_path, test_file]
    
    comp_res = subprocess.run(compile_cmd, capture_output=True)
    if comp_res.returncode != 0:
        return ("fail", f"{RED}[FAIL]{RESET} {test_file} - compilation error\n{comp_res.stderr.decode()}")
    
    try:
        os.chmod(out_path, 0o755)
        run_res = subprocess.run([f"./{out_path}"], capture_output=True)
        exit_code = run_res.returncode
    except Exception as e:
        return ("fail", f"{RED}[FAIL]{RESET} {test_file} - execution failed: {e}")
        
    if exit_code in [132, 134, 135, 136, 139]:
        sig = exit_code - 128
        return ("fail", f"{RED}[FAIL]{RESET} {test_file} - CRASH (signal {sig}, exit {exit_code})")
        
    return ("pass", f"{GREEN}[OK]{RESET} {test_file} (exit {exit_code})")

def run_flat_test(test_file):
    if not os.path.exists(test_file):
        return ("skip", f"{BLUE}[SKIP]{RESET} {test_file} (not found)")
        
    out_path = get_output_path(test_file)
    compile_cmd = ["./bin/juno", "-t", "flat", "-o", out_path, test_file]
    
    comp_res = subprocess.run(compile_cmd, capture_output=True)
    if comp_res.returncode != 0:
        return ("fail", f"{RED}[FAIL]{RESET} {test_file} - compilation error")
        
    if not os.path.exists(out_path):
        return ("fail", f"{RED}[FAIL]{RESET} {test_file} - flat binary missing")
        
    try:
        with open(out_path, "rb") as f:
            header = f.read(4)
        if len(header) == 4 and header == b"\x7fELF":
            return ("fail", f"{RED}[FAIL]{RESET} {test_file} - not flat output")
    except Exception as e:
        return ("fail", f"{RED}[FAIL]{RESET} {test_file} - error reading output: {e}")
        
    return ("pass", f"{GREEN}[OK]{RESET} {test_file}")

def run_negative_test(test_file):
    if not os.path.exists(test_file):
        return ("skip", f"{BLUE}[SKIP]{RESET} {test_file} (not found)")
        
    out_path = get_output_path(test_file)
    compile_cmd = ["./bin/juno", "-o", out_path, test_file]
    
    comp_res = subprocess.run(compile_cmd, capture_output=True)
    if comp_res.returncode != 0:
        return ("pass", f"{GREEN}[OK FAIL]{RESET} {test_file} (compile error as expected)")
        
    try:
        os.chmod(out_path, 0o755)
        run_res = subprocess.run([f"./{out_path}"], capture_output=True)
        exit_code = run_res.returncode
    except Exception:
        return ("pass", f"{GREEN}[OK FAIL]{RESET} {test_file} (runtime error as expected)")
        
    if exit_code != 0:
        return ("pass", f"{GREEN}[OK FAIL]{RESET} {test_file} (runtime error as expected)")
        
    return ("fail", f"{RED}[UNEXPECTED PASS]{RESET} {test_file}")

def execute_test(category, test_file):
    if category == "positive":
        res, msg = run_positive_test(test_file)
    elif category == "flat":
        res, msg = run_flat_test(test_file)
    else:
        res, msg = run_negative_test(test_file)
    safe_print(msg)
    return res

def main():
    os.makedirs("build", exist_ok=True)
    
    all_files = glob.glob("tests/test_*.juno")
    known_tests = set(POSITIVE_TESTS + FLAT_TESTS)
    negative_tests = [f for f in all_files if f not in known_tests]
    
    tasks = []
    for tf in POSITIVE_TESTS:
        tasks.append(("positive", tf))
    for tf in FLAT_TESTS:
        tasks.append(("flat", tf))
    for tf in negative_tests:
        tasks.append(("negative", tf))
        
    print(f"{BOLD}========================================{RESET}")
    print(f"{BOLD}Running Juno Self-Tests in Parallel{RESET}")
    print(f"{BOLD}========================================{RESET}\n")
    
    passed = 0
    failed = 0
    skipped = 0
    
    with concurrent.futures.ThreadPoolExecutor(max_workers=os.cpu_count()) as executor:
        futures = {executor.submit(execute_test, cat, tf): (cat, tf) for cat, tf in tasks}
        for future in concurrent.futures.as_completed(futures):
            res = future.result()
            if res == "pass":
                passed += 1
            elif res == "fail":
                failed += 1
            elif res == "skip":
                skipped += 1
                
    print(f"\n{BOLD}========================================{RESET}")
    print(f"{BOLD}Results: {GREEN}{passed} passed{RESET}, {RED}{failed} failed{RESET}, {BLUE}{skipped} skipped{RESET}")
    print(f"{BOLD}========================================{RESET}")
    
    if failed > 0:
        sys.exit(1)
    sys.exit(0)

if __name__ == "__main__":
    main()
