package main

import "core:fmt"
import "core:slice"

join :: proc(slice0: $TypeDefinition/[]$Elem, slice1: ..Elem) -> []Elem {
    dyn := slice.clone_to_dynamic(slice0)
    append_elems(&dyn, ..slice1)
    return dyn[:]
}

// NOTE: Must be in this order (as the compiler relies upon it)
Loc :: struct {
    file_path:    string,
    line, column: i32,
    procedure:    string,
}

print_call :: proc(loc: Loc, func_name: string) {
    fmt.printfln(
        "%s called from file %s at line %d column %d",
        func_name,
        loc.file_path,
        loc.line,
        loc.column,
    )
}

