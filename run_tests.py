#!/usr/bin/env python3

import os
import sys
import glob
import subprocess
import concurrent.futures
from rich.console import Console
from rich.table import Table
from rich.progress import Progress, SpinnerColumn, BarColumn, TextColumn
from rich.live import Live
from rich.panel import Panel
from rich.align import Align

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
    "tests/test_simple_demo.juno",
    "tests/test_string.juno",
    "tests/test_swap.juno",
    "tests/test_two_int.juno",
    "tests/test_two_noopt.juno",
    "tests/test_all_features.juno",
    "tests/test_ptr_arith_and_str_plus.juno",
    "tests/test_file_io_wrappers.juno",
    "tests/test_syscall_extended.juno",
    "tests/test_sized_types_complex.juno",
    "tests/test_float_audit.juno",
    "tests/test_float_math.juno",
    "tests/test_new_features.juno",
    "tests/test_predictive_borrow.juno",
    "tests/test_autodrop.juno",
    "tests/test_safety_loopholes.juno",
    "tests/test_native_asm.juno",
]

FLAT_TESTS = [
    "tests/test_flat_binary.juno",
]

console = Console()

def get_output_path(test_file):
    base_name = os.path.basename(test_file).replace(".juno", "")
    return os.path.join("build", f"output_{base_name}")

def run_positive_test(test_file):
    if not os.path.exists(test_file):
        return "skip", "Not found"
    
    out_path = get_output_path(test_file)
    compile_cmd = ["./bin/juno", "-o", out_path, test_file]
    
    comp_res = subprocess.run(compile_cmd, capture_output=True)
    if comp_res.returncode != 0:
        return "fail", f"Compilation failed:\n{comp_res.stderr.decode().strip()}"
    
    try:
        os.chmod(out_path, 0o755)
        run_res = subprocess.run([f"./{out_path}"], capture_output=True)
        exit_code = run_res.returncode
    except Exception as e:
        return "fail", f"Execution error: {e}"
        
    if exit_code in [132, 134, 135, 136, 139]:
        sig = exit_code - 128
        return "fail", f"Crash (signal {sig}, exit {exit_code})"
        
    return "pass", f"Exit {exit_code}"

def run_flat_test(test_file):
    if not os.path.exists(test_file):
        return "skip", "Not found"
        
    out_path = get_output_path(test_file)
    compile_cmd = ["./bin/juno", "-t", "flat", "-o", out_path, test_file]
    
    comp_res = subprocess.run(compile_cmd, capture_output=True)
    if comp_res.returncode != 0:
        return "fail", "Compilation error"
        
    if not os.path.exists(out_path):
        return "fail", "Flat binary missing"
        
    try:
        with open(out_path, "rb") as f:
            header = f.read(4)
        if len(header) == 4 and header == b"\x7fELF":
            return "fail", "Not a flat binary (ELF detected)"
    except Exception as e:
        return "fail", f"Read error: {e}"
        
    return "pass", "Flat output valid"

def run_negative_test(test_file):
    if not os.path.exists(test_file):
        return "skip", "Not found"
        
    out_path = get_output_path(test_file)
    compile_cmd = ["./bin/juno", "-o", out_path, test_file]
    
    comp_res = subprocess.run(compile_cmd, capture_output=True)
    if comp_res.returncode != 0:
        return "pass", "Rejected as expected"
        
    try:
        os.chmod(out_path, 0o755)
        run_res = subprocess.run([f"./{out_path}"], capture_output=True)
        exit_code = run_res.returncode
    except Exception:
        return "pass", "Runtime error as expected"
        
    if exit_code != 0:
        return "pass", "Runtime error as expected"
        
    return "fail", "Unexpectedly compiled and passed"

def execute_test(category, test_file):
    if category == "positive":
        res, detail = run_positive_test(test_file)
    elif category == "flat":
        res, detail = run_flat_test(test_file)
    else:
        res, detail = run_negative_test(test_file)
    return res, detail

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
        
    passed = 0
    failed = 0
    skipped = 0
    failures = []

    header_panel = Panel(
        Align.center("[bold cyan]Juno Multi-Threaded Self-Tests Execution[/bold cyan]"),
        border_style="cyan"
    )
    console.print(header_panel)
    console.print()

    progress = Progress(
        SpinnerColumn(),
        TextColumn("[progress.description]{task.description}"),
        BarColumn(bar_width=40),
        TextColumn("[progress.percentage]{task.percentage:>3.0f}%"),
    )
    
    total_tasks = len(tasks)
    task_id = progress.add_task("[yellow]Processing tests...", total=total_tasks)
    
    table = Table(title="Test Matrix Summary", expand=True)
    table.add_column("Category", style="cyan")
    table.add_column("Passed", style="green", justify="right")
    table.add_column("Failed", style="red", justify="right")
    table.add_column("Skipped", style="blue", justify="right")
    table.add_column("Total", style="bold white", justify="right")
    
    with Live(progress, refresh_per_second=10) as live:
        with concurrent.futures.ThreadPoolExecutor(max_workers=os.cpu_count()) as executor:
            futures = {executor.submit(execute_test, cat, tf): (cat, tf) for cat, tf in tasks}
            for future in concurrent.futures.as_completed(futures):
                cat, tf = futures[future]
                res, detail = future.result()
                
                if res == "pass":
                    passed += 1
                elif res == "fail":
                    failed += 1
                    failures.append((tf, cat, detail))
                elif res == "skip":
                    skipped += 1
                    
                progress.update(task_id, advance=1)
    
    console.print()
    
    table.add_row("Positive Tests", str(passed), str(failed), str(skipped), str(total_tasks))
    console.print(table)
    console.print()
    
    if failures:
        fail_table = Table(title="Detailed Failure Report", expand=True, border_style="red")
        fail_table.add_column("Test File", style="yellow")
        fail_table.add_column("Category", style="magenta")
        fail_table.add_column("Error Detail", style="white")
        
        for f_file, f_cat, f_detail in failures:
            fail_table.add_row(f_file, f_cat, f_detail)
            
        console.print(fail_table)
        console.print()

    result_color = "red" if failed > 0 else "green"
    summary_panel = Panel(
        Align.center(
            f"[{result_color}]Status: {'FAILED' if failed > 0 else 'SUCCESS'}[/{result_color}]\n\n"
            f"[green]Passed: {passed}[/green]  •  [red]Failed: {failed}[/red]  •  [blue]Skipped: {skipped}[/blue]"
        ),
        border_style=result_color,
        title="Execution Summary",
        title_align="center"
    )
    console.print(summary_panel)
    
    if failed > 0:
        sys.exit(1)
    sys.exit(0)

if __name__ == "__main__":
    main()
