package main

import "core:fmt"
import "core:mem"
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
    state, stdout, stderr, err2 := os.process_exec(
        os.Process_Desc{command = command},
        context.allocator,
    )
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

// The `string` returned is the path to the executable
build :: proc(file_name: string) -> (string, bool) {
    fmt.printfln("Reading `%s`...", file_name)
    data, err := os.read_entire_file(file_name, context.allocator)
    if err != nil {
        fmt.eprintfln("Failed to read `%s`: %#v", file_name, err)
        return "", false
    }
    defer delete(data, context.allocator)

    file := CompilerFile{string(data), file_name}
    state := ParserState{make([dynamic]FunctionDefinition), TokenizerState{index = 0, file = file}}
    fmt.printfln("Parsing `%s`...", file.file_name)
    parser_output := parse(&state)
    if !parser_output.ok {
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
    if checker_output.diagnostics_info.number_of_errors > 0 {
        fmt.eprintfln(
            "Erroneously checked `%s` with %d errors and %d warnings",
            file.file_name,
            checker_output.diagnostics_info.number_of_errors,
            checker_output.diagnostics_info.number_of_warnings,
        )
        return "", false
    } else {
        fmt.eprintfln(
            "Successfully checked `%s` with %d errors and %d warnings",
            file.file_name,
            checker_output.diagnostics_info.number_of_errors,
            checker_output.diagnostics_info.number_of_warnings,
        )
    }

    fmt.printfln("Emitting C code for `%s`...", file.file_name)
    c := emit_c(
        checker_output.checked_funcs,
        checker_output.checked_global_types_without_generic,
        checker_output.generic_type_initialisations,
        checker_output.array_type_initialisations,
        checker_output.func_types,
        checker_output.entry_func_index,
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

        dir_in_tmp, err3 := filepath.join(
            []string{tmp, filepath.dir(absolute_file_name)},
            context.allocator,
        )
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

        fmt.println("TODO: Handle when the entry func is a build func")
        c_path, err4 := filepath.join([]string{tmp, absolute_file_name}, context.allocator)
        if err4 != nil {
            fmt.eprintfln("Failed to join filepath: %v", err4)
            return "", false
        }
        return write_and_compile_c(c, c_path)
    } else {
        return write_and_compile_c(c, file_name)
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

