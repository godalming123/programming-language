package main

import "core:slice"

join :: proc(slice0: $TypeDefinition/[]$Elem, slice1: ..Elem) -> []Elem {
    dyn := slice.clone_to_dynamic(slice0)
    append_elems(&dyn, ..slice1)
    return dyn[:]
}

