package main

import "core:fmt"
import "core:os"
import "core:path/filepath"
import "core:strings"
import "core:time"

debug_tokenizer :: false // You can use this to debug the parser
debug_parser_output :: false
debug_checker :: false
debug_emitter :: false
debug_ordered_hash_sets :: false
debug_interpreter :: false
debug_diagnostics :: false

// The `string` returned is the path to the executable
write_and_compile_c :: proc(c_code: []u8, path: string) -> (string, bool) {
    c_code_path := fmt.aprintf("%s.c", path)
    output_executable_path := fmt.aprintf("%s.bin", path)

    fmt.printfln("Writing C code to `%s`...", c_code_path)
    err := os.write_entire_file(c_code_path, c_code)
    if err != nil {
        fmt.eprintfln("Failed to write to `%s`: %#v", c_code_path, err)
        return "", false
    }

    fmt.printfln("Compiling the C code into an executable at `%s`...", output_executable_path)
    // TODO: Use `CC` environment variable by default, and fallback to `cc` command, than `gcc` command
    command := []string{"gcc", c_code_path, "-o", output_executable_path}
    state, _, _, err2 := os.process_exec(os.Process_Desc{command = command}, context.allocator)
    if err2 != nil {
        fmt.eprintln("Failed to invoke compilation command for `%s`: %#v", c_code_path, err2)
        return "", false
    }
    if state.exit_code != 0 {
        fmt.eprintfln(
            "Failed to compile `%s`:\nCommand ran: `%s`\nExit code: %d",
            c_code_path,
            strings.join(command, " "),
            state.exit_code,
        )
        return "", false
    }
    return output_executable_path, true
}

compile :: proc(func: FunctionRef, pipe: Pipe(^os.File)) -> (Checked, CheckedFuncRef, bool) {
    compile_start := time.now()
    defer {
        fmt.fprintfln(
            pipe.stdout,
            "Done compiling in %f ms!",
            time.duration_milliseconds(time.since(compile_start)),
        )
    }

    parsed, ok := parse_project(func.file_name, pipe.stderr)
    if !ok {
        return Checked{}, CheckedFuncRef{}, false
    }

    when debug_parser_output {
        debug("Printing function defs")
        debug_nesting += 1
        for function_def, i in state.function_defs {
            debug("Function def %d", i)
            debug_nesting += 1
            debug("%#v", function_def)
            debug_nesting -= 1
        }
        debug_nesting -= 1
    }

    fmt.fprintfln(pipe.stdout, "Checking...")
    checker_output := check(parsed, func.func_name, pipe.stderr)

    errors, warnings: string = ---, ---

    if checker_output.diagnostics_info.number_of_errors == 1 {
        errors = fmt.aprint("1 error")
    } else {
        errors = fmt.aprintf("%d errors", checker_output.diagnostics_info.number_of_errors)
    }
    defer delete_string(errors)

    if checker_output.diagnostics_info.number_of_warnings == 1 {
        warnings = fmt.aprint("1 warning")
    } else {
        warnings = fmt.aprintf("%d warnings", checker_output.diagnostics_info.number_of_warnings)
    }
    defer delete_string(warnings)

    if checker_output.diagnostics_info.number_of_errors > 0 {
        fmt.fprintfln(pipe.stderr, "Erroneously checked with %s and %s", errors, warnings)
        return Checked{}, CheckedFuncRef{}, false
    }

    fmt.fprintfln(pipe.stdout, "Successfully checked with %s and %s", errors, warnings)
    return checker_output.checked, checker_output.func_ref, true
}

// The `string` returned is the path to the executable
// Returns `"", false` on failure
build_c :: proc(func: FunctionRef, pipe: Pipe(^os.File)) -> (string, bool) {
    checked, func_ref, ok := compile(func, pipe)
    if !ok {
        return "", false
    }

    fmt.printfln("Emitting C code...")
    c := emit_c(checked, func_ref)

    executable_path, ok2 := write_and_compile_c(c, func.file_name)
    if !ok2 {
        return "", false
    }
    return executable_path, true

    /*
    if checker_output.entry_func_type == .BuildFunc {
        if interpret_file {
            fmt.eprintln("Cannot use `interpret` with files that use a custom `build` func")
            return "", false
        }
        fmt.printfln("Interpreting metaprogram...")
        result := interpret(checker_output.checked, builtin_handler, checker_output.entry_func_ref)
        return "", result.(i64) == 0 ? true : false
        /*
        // OLD(METAPROGRAM_IN_C)
        tmp, err := os.temp_directory(context.allocator)
        if err != nil {
            fmt.eprintfln("Failed to get temporary directory: %#v", file_name, err)
            return "", false
        }

        absolute_file_name, err2 := filepath.abs(file_name, context.allocator)
        if err2 != nil {
            fmt.eprintfln("Failed to convert `%s` to an absolute path: %v", file_name, err2)
            return "", false
        }
        absolute_file_dir := filepath.dir(absolute_file_name)

        dir_in_tmp, err3 := filepath.join([]string{tmp, absolute_file_dir}, context.allocator)
        if err3 != nil {
            fmt.eprintfln("Failed to join filepath: %v", err3)
            return "", false
        }
        if !os.exists(dir_in_tmp) {
            err = os.make_directory_all(dir_in_tmp)
            if err != nil {
                fmt.eprintfln("Failed to create directory `%s`: %#v", dir_in_tmp, err)
                return "", false
            }
        }

        c_path, err4 := filepath.join([]string{tmp, absolute_file_name}, context.allocator)
        if err4 != nil {
            fmt.eprintfln("Failed to join filepath: %v", err4)
            return "", false
        }
        executable_path, ok := write_and_compile_c(c, c_path)
        if !ok {
            return "", false
        }

        run_metaprogram(absolute_file_dir, executable_path, checker_output.checked)
        return "", true
        */
    } else if interpret_file {
        fmt.printfln(
            "Finished building in %f ms!",
            time.duration_milliseconds(time.since(build_start)),
        )
        fmt.printfln("Interpreting...")
        result := interpret(checker_output.checked, builtin_handler, checker_output.entry_func_ref)
        return "", result.(i64) == 0 ? true : false
    } else {
    }
    */
}

run :: proc(func: FunctionRef, compiler: Pipe(^os.File), program: Pipe(^os.File)) -> i64 {
    checked, func_ref, ok := compile(func, compiler)
    if !ok {
        return 1
    }
    absolute_file_name, err := filepath.abs(func.file_name, context.allocator)
    if err != nil {
        fmt.fprintfln(compiler.stderr, "Failed make path absolute: %#v", err)
        return 1
    }
    defer delete(absolute_file_name)

    absolute_file_dir := filepath.dir(absolute_file_name)
    builtin_handler := BuiltinHandler {
        &DefaultBuiltinHandlerData{absolute_file_dir, program},
        default_builtin_handler_procedure,
    }
    result := interpret(checked, builtin_handler, func_ref)
    return result.(i64)
}

/*
// OLD(METAPROGRAM_IN_C)
run_metaprogram :: proc(
    metaprogram_working_dir: string,
    metaprogram_path: string,
    checked: Checked,
) -> bool {
    stdin_reader, stdin_writer, err := os.pipe()
    if err != nil {
        fmt.eprintln("Failed to create pipe: %#v", err)
        return false
    }
    defer os.close(stdin_reader)
    defer os.close(stdin_writer)

    stdout_pipe, err2 := create_buffered_pipe()
    if err2 != nil {
        fmt.eprintln("Failed to create buffered pipe: %#v", err2)
        return false
    }
    defer close_buffered_pipe(stdout_pipe)

    fmt.printfln("Starting metaprogram at `%s`...", metaprogram_path)
    // TODO: Check the exit code of the process
    _, err3 := os.process_start(
        os.Process_Desc {
            working_dir = metaprogram_working_dir,
            command = []string{metaprogram_path},
            stdin = stdin_reader,
            stdout = stdout_pipe.writer,
            stderr = os.stderr,
        },
    )
    if err3 != nil {
        fmt.eprintln("Failed to start %s: %#v", metaprogram_path, err3)
        return false
    }

    for {
        command_raw, err4 := bufio.reader_read_string(stdout_pipe.bufio_reader, EOT)
        if err4 != nil {
            assert(command_raw == "")
            fmt.eprintln("Failed to read string: %#v", err4)
            return false
        }
        defer delete(command_raw)
        assert(command_raw[len(command_raw) - 1] == EOT)
        command := command_raw[:len(command_raw) - 1]

        switch command {
        case done_command:
            return true
        case "compiler.emit_js_code":
            arg_raw, err5 := bufio.reader_read_string(stdout_pipe.bufio_reader, EOT)
            if err5 != nil {
                assert(arg_raw == "")
                fmt.eprintln("Failed to read string: %#v", err5)
                return false
            }
            defer delete(arg_raw)
            assert(arg_raw[len(arg_raw) - 1] == EOT)
            arg, ok := strconv.parse_uint(arg_raw[:len(arg_raw) - 1])
            assert(ok)
            fmt.printfln("Compiler received compiler.emit_js_code(%d) from metaprogram", arg)

            builder := emit_javascript(checked)
            defer strings.builder_destroy(&builder)

            strings.write_byte(&builder, EOT)
            os.write_string(stdin_writer, strings.to_string(builder))

            fmt.printfln("Compiler responded to compiler.emit_js_code")
        case:
            fmt.eprintfln("Received unrecognized command %q from metaprogram", command)
            return false
        }
    }
}
*/

default_file_name :: "./main.code" // TODO: Choose proper file extension
default_func_name :: "main"

print_help :: proc(exit_code: int) -> ! {
    fmt.println(
        "- `build_c file_name func_name` transpile a file into C and then build the C code into an executable",
    )
    fmt.println(
        "- `run file_name func_name` compile a file and interpret a function within that file",
    )
    fmt.println("- `help` show this help message")
    fmt.println("- For commands that take the arguments `file_name func_name`:")
    fmt.println(
        "  - If only one argument is specified, and the argument contains only alphanumerics and underscores, the compiler assumes it is the `func_name`",
    )
    fmt.println("  - Otherwise, the compiler assumes that the first argument is the `file_name`")
    fmt.println(
        "  - If the `file_name` is not specified, it defaults to `" + default_file_name + "`",
    )
    fmt.println(
        "  - If the `func_name` is not specified, it defaults to `" + default_func_name + "`",
    )
    os.exit(exit_code)
}

FunctionRef :: struct {
    file_name: string,
    func_name: string,
}

get_function_ref :: proc(args_after_command: []string) -> FunctionRef {
    switch len(args_after_command) {
    case 0:
        return FunctionRef{default_file_name, default_func_name}
    case 1:
        for char in args_after_command[0] {
            if !is_alphanumeric_char_rune(char) {
                return FunctionRef{args_after_command[0], default_func_name}
            }
        }
        return FunctionRef{default_file_name, args_after_command[0]}
    case 2:
        return FunctionRef{args_after_command[0], args_after_command[1]}
    case:
        fmt.eprintln(
            "Expected at most 2 arguments after the name of the command to specify the file name and the func name, got %d arguments",
            len(args_after_command),
        )
        print_help(1)
    }
}

main :: proc() {
    std_pipe := Pipe(^os.File){os.stdout, os.stderr}

    when ODIN_DEBUG {
        track: mem.Tracking_Allocator
        mem.tracking_allocator_init(&track, context.allocator)
        context.allocator = mem.tracking_allocator(&track)

        defer {
            if len(track.allocation_map) > 0 {
                fmt.eprintf("=== %v allocations not freed: ===\n", len(track.allocation_map))
                for _, entry in track.allocation_map {
                    fmt.eprintf("- %v bytes @ %v\n", entry.size, entry.location)
                }
            }
            mem.tracking_allocator_destroy(&track)
        }
    }

    if len(os.args) < 2 {
        fmt.eprintfln("Expected at least one argument for the command to run")
        print_help(1)
    }
    switch os.args[1] {
    case "build_c":
        ref := get_function_ref(os.args[2:])
        _, ok := build_c(ref, std_pipe)
        if !ok {
            os.exit(1)
        }
    case "run":
        ref := get_function_ref(os.args[2:])
        os.exit(int(run(ref, std_pipe, std_pipe)))
    case "help":
        print_help(0)
    case:
        fmt.eprintfln("Unexpected command `%s`", os.args[1])
        print_help(1)
    }
}

