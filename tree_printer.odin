package main

/*
import "core:fmt"
import "core:strings"

// TODO: Merge with tree printing code in `utils.odin`

TreePrinterState :: struct {
    depth: uint,
}

@(deferred_in_out = reduce_depth)
list_item :: proc(state: ^TreePrinterState, format: string, args: ..any) {
    indentation := strings.repeat("  ", int(state.depth))
    fmt.print(indentation, flush = false)
    delete_string(indentation)
    fmt.print("- ", flush = false)
    fmt.printfln(format, ..args)
    state.depth += 1
}

reduce_depth :: proc(state: ^TreePrinterState, _: string, _: ..any) {
    state.depth -= 1
}
*/

