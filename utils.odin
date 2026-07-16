package main

import "base:runtime"
import "core:fmt"
import "core:io"
import "core:math/rand"
import "core:os"
import "core:strings"
import "core:testing"

panicf :: proc(format: string, args: ..any) -> ! {
    panic(fmt.aprintf(format, ..args))
}

// FNV-1a 32-bit
simple_hash :: proc(data: []byte) -> u32 {
    h: u32 = 0x811c_9dc5 // FNV 32-bit offset basis
    for b in data {
        h = (h ~ u32(b)) * 0x0100_0193 // FNV 32-bit prime
    }
    return h
}

simple_hash_string :: proc(data: string) -> u32 {
    return simple_hash(transmute([]byte)data)
}

file_mock :: proc() -> (^os.File, ^strings.Builder) {
    builder := new_clone(strings.builder_make())
    stream_proc: os.File_Stream_Proc : proc(
        stream_data: rawptr,
        mode: os.File_Stream_Mode,
        p: []byte,
        offset: i64,
        whence: io.Seek_From,
        _: runtime.Allocator,
    ) -> (
        i64,
        os.Error,
    ) {
        assert(mode == .Write)
        assert(offset == 0)
        assert(whence == io.Seek_From(0))
        file := cast(^os.File)stream_data
        builder := cast(^strings.Builder)file.stream.data
        strings.write_bytes(builder, p)
        return i64(len(p)), nil
    }
    return new_clone(os.File{nil, os.File_Stream{stream_proc, builder}}), builder
}

pipe_mock :: proc() -> (Pipe(^os.File), Pipe(^strings.Builder)) {
    stdout_writer, stdout_builder := file_mock()
    stderr_writer, stderr_builder := file_mock()
    writers := Pipe(^os.File){stdout_writer, stderr_writer}
    builders := Pipe(^strings.Builder){stdout_builder, stderr_builder}
    return writers, builders
}

get_output :: proc(p: Pipe(^strings.Builder)) -> Pipe(string) {
    return Pipe(string){strings.to_string(p.stdout^), strings.to_string(p.stderr^)}
}

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

ansi_clear :: "\033[1;1H\033[2J"

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

build_error_info :: proc(
    first_location: runtime.Source_Code_Location,
    other_locations: []runtime.Source_Code_Location,
) -> strings.Builder {
    add_code_location :: proc(b: ^strings.Builder, loc: runtime.Source_Code_Location) {
        strings.write_string(b, "expect_string called from file ")
        strings.write_string(b, loc.file_path)
        strings.write_string(b, " at line ")
        strings.write_int(b, int(loc.line))
        strings.write_string(b, " column ")
        strings.write_int(b, int(loc.column))
        strings.write_byte(b, '\n')
    }
    builder := strings.builder_make()
    add_code_location(&builder, first_location)
    for other_location in other_locations {
        add_code_location(&builder, other_location)
    }
    return builder
}

expect_string :: proc(
    comparer: ^TestingTextExpecter,
    expected: string,
    first_location := #caller_location,
    other_locations: ..runtime.Source_Code_Location,
) {
    start := comparer.index
    comparer.index += len(expected)
    if comparer.index > len(comparer.got_text) {
        builder := build_error_info(first_location, other_locations)
        strings.write_string(&builder, "Expected text is longer than got text")
        testing.fail_now(comparer.t, strings.to_string(builder))
    }
    got := comparer.got_text[start:comparer.index]
    if got != expected {
        builder := build_error_info(first_location, other_locations)
        strings.write_string(&builder, "Mismatching expect_string: Got ")
        strings.write_quoted_string(&builder, got)
        strings.write_string(&builder, " expected ")
        strings.write_quoted_string(&builder, expected)
        testing.fail_now(comparer.t, strings.to_string(builder))
    }
}

expect_digits :: proc(
    e: ^TestingTextExpecter,
    first_location := #caller_location,
    other_locations: ..runtime.Source_Code_Location,
) {
    if e.index >= len(e.got_text) {
        builder := build_error_info(first_location, other_locations)
        strings.write_string(&builder, "Expected text is longer than got text")
        testing.fail_now(e.t, strings.to_string(builder))
    }

    if !is_digit_char(e.got_text[e.index]) {
        builder := build_error_info(first_location, other_locations)
        fmt.sbprintf(&builder, "Expected a digit, but got the character '%c'", e.got_text[e.index])
        testing.fail_now(e.t, strings.to_string(builder))
    }

    e.index += 1

    for e.index < len(e.got_text) && is_digit_char(e.got_text[e.index]) {
        e.index += 1
    }
}

expect_done_message :: proc(
    e: ^TestingTextExpecter,
    first_location := #caller_location,
    other_locations: ..runtime.Source_Code_Location,
) {
    expect_string(e, "Done in ")
    expect_digits(e)
    expect_string(e, ".")
    expect_digits(e)
    expect_string(e, " ms!\n")
}

expect_finished :: proc(e: ^TestingTextExpecter) {
    if e.index < len(e.got_text) {
        testing.fail_now(e.t, fmt.aprintf("Got additional code %q", e.got_text[e.index:]))
    } else {
        testing.expect(e.t, e.index == len(e.got_text))
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
*/

/*
append2 :: proc(
    a_array: ^[dynamic]$A,
    b_array: ^[^]$B,
    a_elem: A,
    b_elem: B,
) -> runtime.Allocator_Error {
    a_raw := (^runtime.Raw_Dynamic_Array)(a_array)

    if a_raw.len + 1 > a_raw.cap {
        if a_raw.allocator.procedure == nil {
            a_raw.allocator = context.allocator
            assert(a_raw.allocator.procedure != nil)
        }

        new_cap := 2 * a_raw.cap + runtime.DEFAULT_DYNAMIC_ARRAY_CAPACITY

        a_raw_data, err := runtime.mem_resize(
            a_raw.data,
            a_raw.cap * size_of(A),
            new_cap * size_of(A),
            align_of(A),
            a_raw.allocator,
        )
        if err != nil {
            return err
        }
        a_raw.data = raw_data(a_raw_data)

        b_raw_data, err2 := runtime.mem_resize(
            b_array^,
            a_raw.cap * size_of(B),
            new_cap * size_of(B),
            align_of(B),
            a_raw.allocator,
        )
        if err2 != nil {
            return err2
        }
        b_array^ = ([^]B)(raw_data(b_raw_data))

        a_raw.cap = new_cap
    }

    ([^]A)(a_raw.data)[a_raw.len] = a_elem
    b_array[a_raw.len] = b_elem
    a_raw.len += 1

    return nil
}
*/

// Like a dynamic array, except can also be inserted into in average O(1) time
DoubleDynamic :: struct(T: typeid) {
    elems:       [dynamic]T,
    start_index: int,
}

dynamic_grow_front :: proc(array: ^DoubleDynamic($T), grow_by: int) {
    old_start_index := array.start_index
    array.start_index += grow_by

    old_elems := array.elems
    array.elems = make([dynamic]T, cap(array.elems) + grow_by)

    copy_slice(array.elems[array.start_index:], old_elems[old_start_index:])
    delete(old_elems)
}

dynamic_insert :: proc(array: ^DoubleDynamic($T), elems: ..T) {
    if array.start_index < len(elems) {
        dynamic_grow_front(array, max(len(array.elems), len(elems)))
    }
    array.start_index -= len(elems)
    copy(array.elems[array.start_index:], elems)
}

dynamic_append_elem :: proc(array: ^DoubleDynamic($T), elem: T) {
    append_elem(&array.elems, elem)
}

dynamic_to_fixed :: proc(array: DoubleDynamic($T)) -> []T {
    return array.elems[array.start_index:]
}

insert :: proc {
    dynamic_insert,
}

up_line :: "\033[A"
erase_line :: "\033[2K"
to_beginning :: "\r"

/*
join :: proc(slice0: $TypeDefinition/[]$Elem, slice1: ..Elem) -> []Elem {
    dyn := slice.clone_to_dynamic(slice0)
    append_elems(&dyn, ..slice1)
    return dyn[:]
}

OutputBuilder :: struct {
    file:   ^os.File,
    b:      strings.Builder,
    footer: string,
}

write :: proc(output_builder: ^OutputBuilder) {
    strings.write_string(&output_builder.b, footer)
    fmt.fprint(output_builder.file, strings.to_string(output_builder.b))
    strings.builder_destroy(&output_builder.b)
}
*/

DiagnosticType :: enum {
    Error,
    Warning,
}

DiagnosticReporter :: struct {
    files:     Multi(CompilerFile),
    io:        Pipe(^os.File),
    number_of: [DiagnosticType]uint,
}

// Set the position to `unknown_pos` to not have a position for the error message
diagnostic :: proc(
    r: ^DiagnosticReporter,
    position: Pos,
    message_fmt: string,
    message_args: ..any,
    type: DiagnosticType = .Error,
    loc := #caller_location,
) {
    when debug_diagnostics {
        print_call(loc, "diagnostic")
    }

    message := strings.builder_make()
    defer strings.builder_destroy(&message)

    if r.number_of[.Error] + r.number_of[.Warning] == 0 {
        strings.write_byte(&message, '\n')
    }

    r.number_of[type] += 1

    // TODO: use bold text for header
    switch type {
    case .Error:
        strings.write_string(&message, "Error")
    case .Warning:
        strings.write_string(&message, "Warning")
    case:
        panic("Unreachable")
    }
    strings.write_string(&message, " compiling")
    if position != unknown_pos {
        fmt.sbprintf(&message, " %v", position)
    }
    strings.write_byte(&message, '\n')

    fmt.sbprintf(&message, message_fmt, ..message_args)
    strings.write_string(&message, "\n\n")

    fmt.fprint(type == .Error ? r.io.stderr : r.io.stdout, strings.to_string(message))
}

/*
err :: proc(
    s: ^CheckerState,
    position: Pos,
    message_fmt: string,
    message_args: ..any,
    loc := #caller_location,
) {
    diagnostic_before :=
        s.diagnostics_info.number_of_errors + s.diagnostics_info.number_of_warnings > 0
    s.diagnostics_info.number_of_errors += 1
    diagnostic(
        s.stderr,
        s.files.file[:len(s.files)],
        position,
        message_fmt,
        ..message_args,
        type = .Error,
        newline_before = !diagnostic_before,
        newline_after = true,
        loc = loc,
    )
}

warn :: proc(
    s: ^CheckerState,
    position: Pos,
    message_fmt: string,
    message_args: ..any,
    loc := #caller_location,
) {
    diagnostic_before :=
        s.diagnostics_info.number_of_errors + s.diagnostics_info.number_of_warnings > 0
    s.diagnostics_info.number_of_warnings += 1
    diagnostic(
        s.stderr,
        s.files.file[:len(s.files)],
        position,
        message_fmt,
        ..message_args,
        type = "Warning",
        newline_before = !diagnostic_before,
        newline_after = true,
        loc = loc,
    )
}
*/

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

/*
debug_exact_checked_type :: proc(s: ^CheckerState, type: Type) {
    debug("type is %#v", type)
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
}
*/

print_arg :: proc(arg_name: string, arg_value: any) {
    debug("arg `%s`: %v", arg_name, arg_value)
}

@(deferred_in_out = print_call_finished)
print_call :: proc(loc: runtime.Source_Code_Location, func_name: string) {
    debug("%s called from %v", func_name, loc)
    debug_nesting += 1
}

print_call_finished :: proc(_: runtime.Source_Code_Location, func_name: string) {
    debug("%s returned from", func_name)
    debug_nesting -= 1
}

