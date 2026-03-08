package main

import "core:fmt"
import "core:mem"
import "core:os/os2"
import "core:path/filepath"
import "core:strings"
import "core:time"

debug_tokenizer :: false
debug_checker :: false
debug_emitter :: true
debug_equivalency_arrays :: false

// The `string` returned is the path to the executable
write_and_compile_c :: proc(c_code: []u8, path: string) -> (string, bool) {
    c_code_path := fmt.aprintf("%s.c", path)
    output_executable_path := fmt.aprintf("%s.bin", path)

    fmt.printfln("Writing C code to `%s`...", c_code_path)
    err := os2.write_entire_file(c_code_path, c_code)
    if err != nil {
        fmt.eprintfln("Failed to write to `%s`: %#v", c_code_path, err)
        return "", false
    }

    fmt.printfln("Compiling the C code into an executable at `%s`...", output_executable_path)
    // TODO: Use `CC` environment variable by default, and fallback to `cc` command, than `gcc` command
    command := []string{"gcc", c_code_path, "-o", output_executable_path}
    state, stdout, stderr, err2 := os2.process_exec(
        os2.Process_Desc{command = command},
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
    data, err := os2.read_entire_file(file_name, context.allocator)
    if err != nil {
        fmt.eprintfln("Failed to read `%s`: %#v", file_name, err)
        return "", false
    }
    defer delete(data, context.allocator)

    file := CompilerFile{string(data), file_name}
    state := ParserState{make([dynamic]FunctionDefinition), TokenizerState{index = 0, file = file}}
    fmt.printfln("Parsing `%s`...", file.file_name)
    imports, globals, global_types, ok := parse(&state)
    if !ok {
        fmt.eprintfln("\nFailed to parse `%s`", file.file_name)
        return "", false
    }
    // fmt.printfln("%#v", state.function_defs[:])
    // fmt.printfln("%#v", global_types)
    // print_ast(imports, globals)

    fmt.printfln("Checking `%s`...", file.file_name)
    checker_output := check(file, imports, globals, state.function_defs[:], global_types)
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
        checker_output.checked_global_types,
        checker_output.generic_types,
        checker_output.array_types,
        checker_output.entry_func_index,
    )

    if checker_output.entry_func_type == .BuildFunc {
        tmp, err := os2.temp_directory(context.allocator)
        if err != nil {
            fmt.eprintfln("Failed to get temporary directory: %#v", file_name, err)
            return "", false
        }

        absolute_file_name, ok := filepath.abs(file_name)
        if !ok {
            fmt.eprintfln("Failed to convert `%s` to an absolute path", file_name)
            return "", false
        }

        dir_in_tmp := filepath.join([]string{tmp, filepath.dir(absolute_file_name)})
        if !os2.exists(dir_in_tmp) {
            err = os2.make_directory_all(dir_in_tmp)
            if err != nil {
                fmt.eprintfln("Failed to create directory `%s`: %#v", dir_in_tmp, err)
                return "", false
            }
        }

        fmt.println("TODO: Handle when the entry func is a build func")
        return write_and_compile_c(c, filepath.join([]string{tmp, absolute_file_name}))
    } else {
        return write_and_compile_c(c, file_name)
    }
}

print_help :: proc(exit_code: int) -> ! {
    fmt.println("- `build file_name` build a file")
    fmt.println("- `help` show this help message")
    os2.exit(exit_code)
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

    if len(os2.args) < 2 {
        fmt.eprintfln("Expected at least one argument for the command to run")
        print_help(1)
    }
    switch os2.args[1] {
    case "build":
        if len(os2.args) != 3 {
            fmt.eprintfln(
                "Expected 3 arguments for the build command, but got %d arguments",
                len(os2.args),
            )
            print_help(1)
        }
        build_start := time.now()
        _, ok := build(os2.args[2])
        fmt.printfln("Done in %f ms!", time.duration_milliseconds(time.since(build_start)))
        if !ok {
            os2.exit(1)
        }
    case "help":
        print_help(0)
    case:
        fmt.eprintfln("Unexpected command `%s`", os2.args[1])
        print_help(1)
    }
}

