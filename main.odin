package main

import "core:bufio"
import "core:fmt"
import "core:os"
import "core:path/filepath"
import "core:strings"
import "core:time"

debug_tokenizer :: false
debug_parser_output :: false
debug_checker :: false
debug_emitter :: false
debug_equivalency_arrays :: false

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

done_command :: "done"

// - The `string` returned is the path to the executable
// - If the program is a metaprogram, it is set to ""
build :: proc(file_name: string) -> (string, bool) {
    fmt.printfln("Reading `%s`...", file_name)
    data, data_err := os.read_entire_file(file_name, context.allocator)
    if data_err != nil {
        fmt.eprintfln("Failed to read `%s`: %#v", file_name, data_err)
        return "", false
    }
    defer delete(data, context.allocator)

    file := CompilerFile{string(data), file_name}
    state := ParserState{make([dynamic]FunctionDefinition), TokenizerState{index = 0, file = file}}
    fmt.printfln("Parsing `%s`...", file.file_name)
    parser_output, ok := parse(&state)
    if !ok {
        fmt.eprintfln("\nFailed to parse `%s`", file.file_name)
        return "", false
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

    fmt.printfln("Checking `%s`...", file.file_name)
    checker_output := check(
        file,
        parser_output.imports,
        parser_output.globals,
        state.function_defs[:],
        parser_output.global_types_without_generics,
        parser_output.global_types_with_generics,
    )

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
        fmt.eprintfln("Erroneously checked `%s` with %s and %s", file.file_name, errors, warnings)
        return "", false
    } else {
        fmt.printfln("Successfully checked `%s` with %s and %s", file.file_name, errors, warnings)
    }

    fmt.printfln("Emitting C code for `%s`...", file.file_name)
    c := emit_c(
        checker_output.checked_funcs,
        checker_output.checked_global_types_without_generic,
        checker_output.generic_type_initialisations,
        checker_output.array_type_initialisations,
        checker_output.func_types,
        checker_output.entry_func_index,
        checker_output.entry_func_type == .BuildFunc ? "printf(\"" + done_command + "\" EOT_STR);" : "",
        checker_output.type_equivalancy_array,
    )

    if checker_output.entry_func_type == .BuildFunc {
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
        executable_path, executable_ok := write_and_compile_c(c, c_path)
        if !executable_ok {
            return "", false

        }

        run_metaprogram(absolute_file_dir, executable_path, parser_output, checker_output)
        return "", true
    } else {
        executable_path, executable_ok := write_and_compile_c(c, file_name)
        if !executable_ok {
            return "", false
        }
        return executable_path, true
    }
}

run_metaprogram :: proc(
    metaprogram_working_dir: string,
    metaprogram_path: string,
    parsed: ParserOutput,
    checked: CheckerOutput,
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
            arg := arg_raw[:len(arg_raw) - 1]
            fmt.printfln("Compiler received compiler.emit_js_code(%q) from metaprogram", arg)

            global, exists := parsed.globals[arg]
            if !exists {
                fmt.eprintfln("The global %q does not exist", arg)
                return false
            }

            value, is_value := global.value.(Value)
            if !is_value {
                fmt.eprintfln("The global %q is not a value. Expected a function value.", arg)
                return false
            }

            func_ref, is_func := value.value.(uint)
            if !is_func {
                fmt.eprintfln("The global %q is a value but not a function value", arg)
                return false
            }

            builder := emit_javascript(
                checked.checked_funcs,
                checked.checked_global_types_without_generic,
                checked.generic_type_initialisations,
                checked.array_type_initialisations,
                checked.func_types,
                checked.type_equivalancy_array,
            )
            strings.write_string(&builder, "const ")
            strings.write_string(&builder, arg)
            strings.write_string(&builder, "=func")
            strings.write_uint(&builder, func_ref)
            strings.write_byte(&builder, ';')
            strings.write_byte(&builder, EOT)
            str := strings.to_string(builder)
            defer delete(str)
            os.write_string(stdin_writer, str)
            fmt.printfln("Compiler responded to compiler.emit_js_code")
        case:
            fmt.eprintfln("Received unrecognized command %q from metaprogram", command)
            return false
        }
    }
}

print_help :: proc(exit_code: int) -> ! {
    fmt.println("- `build file_name` build a file")
    fmt.println("- `help` show this help message")
    os.exit(exit_code)
}

main :: proc() {
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
    case "build":
        if len(os.args) != 3 {
            fmt.eprintfln(
                "Expected 3 arguments for the build command, but got %d arguments",
                len(os.args),
            )
            print_help(1)
        }
        build_start := time.now()
        _, ok := build(os.args[2])
        fmt.printfln("Done in %f ms!", time.duration_milliseconds(time.since(build_start)))
        if !ok {
            os.exit(1)
        }
    case "help":
        print_help(0)
    case:
        fmt.eprintfln("Unexpected command `%s`", os.args[1])
        print_help(1)
    }
}

