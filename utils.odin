package main

import "base:runtime"
import "core:fmt"
import "core:io"
import "core:os"
import "core:slice"
import "core:testing"

TestingTextExpecter :: struct {
    index:    uint,
    got_text: string,
    t:        ^testing.T,
}

expect_string :: proc(
    comparer: ^TestingTextExpecter,
    expected: string,
    loc1: runtime.Source_Code_Location,
    loc2 := #caller_location,
) {
    half_format :: "expect_string called from file %s at line %d column %d\n"
    format :: half_format + half_format
    start := comparer.index
    comparer.index += len(expected)
    if comparer.index >= len(comparer.got_text) {
        formatted := fmt.aprintf(
            format + "Expected text is longer than got text",
            loc1.file_path,
            loc1.line,
            loc1.column,
            loc2.file_path,
            loc2.line,
            loc2.column,
        )
        testing.fail_now(comparer.t, formatted)
    }
    got := comparer.got_text[start:comparer.index]
    if got != expected {
        formatted := fmt.aprintf(
            format + "\nMismatching expect_string: Got %q expected %q",
            loc1.file_path,
            loc1.line,
            loc1.column,
            loc2.file_path,
            loc2.line,
            loc2.column,
            got,
            expected,
        )
        testing.fail_now(comparer.t, formatted)
    }
}

/*
// Supported operations:
// - Iterate in order with the key and the value
// - Append to the end
// - Lookup based on the key

OrderedMapElement :: struct(Key: typeid, Value: typeid) {
    key: Key,
    value: Value,
}

OrderedMap :: struct(Key: typeid, Value: typeid) {
    elements: []OrderedMapElement(Key, Value),
    map: map[Key]uint,
}
*/

combine_u32 :: proc(a: u32, b: u32) -> (out: u64) {
    out = u64(a) << 32
    out += u64(b)
    return
}

seperate_u64 :: proc(combined: u64) -> (a: u32, b: u32) {
    a = u32(combined >> 32)
    b = u32(combined)
    return
}

up_line :: "\033[A"
erase_line :: "\033[2K"
to_beginning :: "\r"

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
    max_line_length :: 100
    line_padding := (4 * debug_nesting) + 4

    formatted := fmt.aprintf(format, ..args)
    defer delete_string(formatted)
    assert(formatted != "")

    for i in 0 ..< debug_nesting {
        fmt.print("│   ", flush = false)
    }
    fmt.print("├── ", flush = false)

    if line_padding >= max_line_length {
        fmt.println(formatted)
    } else {
        col := line_padding
        if len(formatted) > 1 {
            for char in formatted[0:len(formatted) - 1] {
                fmt.print(char, flush = false)
                if char == '\n' {
                    col = 0
                } else {
                    col += 1
                    if col >= max_line_length {
                        fmt.print("\n...", flush = false)
                        col = 3
                    } else {
                        continue
                    }
                }
                for _ in col ..< line_padding {
                    fmt.print(' ', flush = false)
                }
                col = line_padding
            }
        }
        fmt.printfln("%c", formatted[len(formatted) - 1])
    }

    when false {
        fmt.print("Press enter to continue")
        buf := make([]byte, 1)
        os.read(os.stdin, buf)
        delete(buf)
        fmt.print(up_line + erase_line)
    }
}

debug_exact_checked_type :: proc(s: ^CheckerState, type: ExactCheckedType) {
    debug("type is %#v", type)
    /*
    debug_nesting += 1
    #partial switch value in type {
    case GenericTypeRef:
        info, index := get_info(s.generic_types[:], value.generic_type_index)
        debug("simplified index is %d", index)
        debug("generic arg")
        debug_nesting += 1
        debug_exact_checked_type(s, info.generic_arg)
        debug_nesting -= 1
        debug("global type index is %d", info.global_type_index)
    // debug("type %v", info.type)
    }
    debug_nesting -= 1
    */
}

print_arg :: proc(arg_name: string, arg_value: any) {
    debug("arg `%s`: %v", arg_name, arg_value)
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
    debug("%s returned from", func_name)
    debug_nesting -= 1
}

