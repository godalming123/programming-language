package main

import "base:runtime"
import "core:fmt"
import "core:math/rand"
import "core:os"
import "core:slice"
import "core:testing"

random_string :: proc(max_length: int, gen := context.random_generator) -> string {
    context.random_generator = gen
    length := rand.int_max(max_length / 4)
    out := make([]byte, length * 4)
    for i in 0 ..< length {
        char_group := rand.uint32()
        out[i * 4] = byte(char_group)
        out[i * 4 + 1] = byte(char_group >> 8)
        out[i * 4 + 2] = byte(char_group >> 16)
        out[i * 4 + 3] = byte(char_group >> 32)
    }
    return string(out)
}

/*
// OLD(METAPROGRAM_IN_C)
EOT :: '\x04'

BufferedPipe :: struct {
    writer:        ^os.File,
    file_reader:   ^os.File,
    stream_reader: io.Stream,
    bufio_reader:  ^bufio.Reader,
}

create_buffered_pipe :: proc() -> (BufferedPipe, os.Error) {
    file_reader, writer, err := os.pipe()
    if err != nil {
        return BufferedPipe{}, err
    }
    out := BufferedPipe{writer, file_reader, os.to_stream(file_reader), new(bufio.Reader)}
    bufio.reader_init(out.bufio_reader, out.stream_reader)
    return out, nil
}

close_buffered_pipe :: proc(pipe: BufferedPipe) {
    bufio.reader_destroy(pipe.bufio_reader)
    free(pipe.bufio_reader)
    io.close(pipe.stream_reader)
    os.close(pipe.writer)
    os.close(pipe.file_reader)
}

// read_message :: proc(pipe: BufferedPipe) -> (string, bool) {
//     msg, err := bufio.reader_read_string(pipe.bufio_reader, EOT)
//     if err != nil {
//         assert(msg == "")
//         fmt.eprintln("Failed to read string: %#v", err)
//         return "", false
//     }
// }
*/

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

separate_u64 :: proc(combined: u64) -> (a: u32, b: u32) {
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
    loc := #caller_location,
) {
    when debug_tokenizer || debug_checker {
        print_call(loc, "diagnostic")
    }
    if newline_before {
        fmt.println("")
    }
    message := fmt.aprintf(message_fmt, ..message_args)
    defer delete(message)
    if position == max(uint) {
        fmt.eprintf("%s compiling `%s`:\n%s\n", type, file.file_path, message)
    } else {
        line, column := get_location(file.code, position)
        fmt.eprintf(
            "%s compiling `%s`:\nLine %d column %d:\n%s\n",
            type,
            file.file_path,
            line,
            column,
            message,
        )
    }
    if newline_after {
        fmt.println("")
    }
}

err :: proc(
    s: ^CheckerState,
    position: uint,
    message_fmt: string,
    message_args: ..any,
    loc := #caller_location,
) {
    diagnostic_before :=
        s.diagnostics_info.number_of_errors + s.diagnostics_info.number_of_warnings > 0
    s.diagnostics_info.number_of_errors += 1
    diagnostic(
        s.files[s.file.index].file,
        position,
        message_fmt,
        ..message_args,
        type = "Error",
        newline_before = !diagnostic_before,
        newline_after = true,
        loc = loc,
    )
}

warn :: proc(
    s: ^CheckerState,
    position: uint,
    message_fmt: string,
    message_args: ..any,
    loc := #caller_location,
) {
    diagnostic_before :=
        s.diagnostics_info.number_of_errors + s.diagnostics_info.number_of_warnings > 0
    s.diagnostics_info.number_of_warnings += 1
    diagnostic(
        s.files[s.file.index].file,
        position,
        message_fmt,
        ..message_args,
        type = "Warning",
        newline_before = !diagnostic_before,
        newline_after = true,
        loc = loc,
    )
}

debug_nesting := 0

// Print flushing is necessary even when we know that a flushing print call is
// going to happen because flush does not work properly
// See https://github.com/odin-lang/Odin/issues/6656
flush_needed :: true

debug :: proc(format: string, args: ..any, loc := #caller_location) {
    max_line_length :: 100
    line_padding := (4 * debug_nesting) + 4

    formatted := fmt.aprintf(format, ..args)
    defer delete_string(formatted)
    assert(formatted != "")

    for _ in 0 ..< debug_nesting {
        fmt.print("│   ", flush = flush_needed)
    }
    fmt.print("├── ", flush = flush_needed)

    if line_padding >= max_line_length {
        fmt.println(formatted)
    } else {
        col := line_padding
        if len(formatted) > 1 {
            for char in formatted[0:len(formatted) - 1] {
                fmt.print(char, flush = flush_needed)
                if char == '\n' {
                    col = 0
                } else {
                    col += 1
                    if col >= max_line_length {
                        fmt.print("\n...", flush = flush_needed)
                        col = 3
                    } else {
                        continue
                    }
                }
                for _ in col ..< line_padding {
                    fmt.print(' ', flush = flush_needed)
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

debug_exact_checked_type :: proc(s: ^CheckerState, type: Type) {
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

