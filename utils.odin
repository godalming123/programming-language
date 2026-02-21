package main

import "base:runtime"
import "core:fmt"
import "core:slice"

join :: proc(slice0: $TypeDefinition/[]$Elem, slice1: ..Elem) -> []Elem {
    dyn := slice.clone_to_dynamic(slice0)
    append_elems(&dyn, ..slice1)
    return dyn[:]
}

// Set the position to max(uint) to not have a position for the error message
diagnostic :: proc(
    file: CompilerFile,
    position: uint,
    message_fmt: string,
    message_args: ..any,
    type: string = "Error",
    newline_before: bool = true,
    newline_after: bool = false,
) {
    if newline_before {
        fmt.println("")
    }
    message := fmt.aprintf(message_fmt, ..message_args)
    defer delete(message)
    if position == max(uint) {
        fmt.eprintf("%s compiling `%s`:\n%s\n", type, file.file_name, message)
    } else {
        line, column := get_location(file.code, position)
        fmt.eprintf(
            "%s compiling `%s`:\nLine %d column %d:\n%s\n",
            type,
            file.file_name,
            line,
            column,
            message,
        )
    }
    if newline_after {
        fmt.println("")
    }
}

err :: proc(s: ^CheckerState, position: uint, message_fmt: string, message_args: ..any) {
    diagnostic_before :=
        s.diagnostics_info.number_of_errors + s.diagnostics_info.number_of_warnings > 0
    s.diagnostics_info.number_of_errors += 1
    diagnostic(
        s.file,
        position,
        message_fmt,
        ..message_args,
        type = "Error",
        newline_before = !diagnostic_before,
        newline_after = true,
    )
}

warn :: proc(s: ^CheckerState, position: uint, message_fmt: string, message_args: ..any) {
    diagnostic_before :=
        s.diagnostics_info.number_of_errors + s.diagnostics_info.number_of_warnings > 0
    s.diagnostics_info.number_of_warnings += 1
    diagnostic(
        s.file,
        position,
        message_fmt,
        ..message_args,
        type = "Warning",
        newline_before = !diagnostic_before,
        newline_after = true,
    )
}

debug_nesting := 0

debug :: proc(format: string, args: ..any) {
    for i in 0 ..< debug_nesting {
        fmt.printf("│   ", flush = false)
    }
    fmt.printf("├── ", flush = false)
    fmt.printfln(format, ..args)
}

debug_and_reduce_nesting :: proc(format: string, args: ..any) {
    for i in 0 ..< debug_nesting {
        fmt.printf("│   ", flush = false)
    }
    fmt.printf("╰── ", flush = false)
    fmt.printfln(format, ..args)
    debug_nesting -= 1
}

@(deferred_in_out = print_call_finished)
print_call :: proc(loc: runtime.Source_Code_Location, func_name: string) {
    debug(
        "%s called from file %s at line %d column %d",
        func_name,
        loc.file_path,
        loc.line,
        loc.column,
    )
    debug_nesting += 1
}

print_call_finished :: proc(_: runtime.Source_Code_Location, func_name: string) {
    debug_and_reduce_nesting("%s returned from", func_name)
}

