package main

import "core:fmt"
import "core:mem"
import "core:os/os2"

debug_tokenizer :: false
debug_checker :: false // TODO: Improve the debugging logs when this in turned on

print_help :: proc(exit_code: int) -> ! {
    fmt.println("- `build file_name` build a file")
    fmt.println("- `help` show this help message")
    os2.exit(exit_code)
}

build :: proc(file_name: string) -> bool {
    fmt.printfln("Reading `%s`...", file_name)
    data, err := os2.read_entire_file(file_name, context.allocator)
    if err != nil {
        fmt.eprintfln("Failed to read %s: %#v", file_name, err)
        return false
    }
    defer delete(data, context.allocator)

    file := CompilerFile{string(data), file_name}
    state := ParserState{make([dynamic]FunctionDefinition), TokenizerState{index = 0, file = file}}
    fmt.printfln("Parsing `%s`...", file.file_name)
    imports, globals, global_types, ok := parse(&state)
    if !ok {
        fmt.eprintfln("\nFailed to parse `%s`", file.file_name)
        return false
    }
    // fmt.printf("%#v", globals)
    // print_ast(imports, globals)

    fmt.printfln("Checking `%s`...", file.file_name)
    checked, array_types, main_func_index, checked_ok := check(
        file,
        imports,
        globals,
        state.function_defs[:],
        global_types,
    )
    if !checked_ok {
        fmt.eprintfln("\nFailed to check `%s`", file.file_name)
        return false
    }

    fmt.println("Emitting c code...")
    c := emit_c(checked, array_types, main_func_index)

    out_name := fmt.aprintf("%s.c", file_name)
    fmt.printfln("Writing to `%s`...", out_name)
    err = os2.write_entire_file(out_name, c)
    if err != nil {
        fmt.eprintfln("Failed to write %s: %#v", out_name, err)
        return false
    }

    fmt.println("Done!")
    return true
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
        ok := build(os2.args[2])
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

