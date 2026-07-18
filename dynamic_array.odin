package main

import "base:runtime"

// Use bounds-checked multi pointers for debug builds
when ODIN_DEBUG {
    Multi :: struct(T: typeid) {
        d: []T,
    }
} else {
    Multi :: struct(T: typeid) {
        d: [^]T,
    }
}

array_to_multi :: proc(a: []$T, loc := #caller_location) -> Multi(T) {
    when debug_dynamic_array {
        print_call(loc, "array_to_multi")
    }
    when ODIN_DEBUG {
        return Multi(T){a}
    } else {
        return Multi(T){raw_data(a)}
    }
}

multi_to_array :: proc(a: Multi($T), length: int, loc := #caller_location) -> []T {
    when debug_dynamic_array {
        print_call(loc, "multi_to_array")
    }
    when ODIN_DEBUG {
        assert(len(a.d) == length)
        return a.d
    } else {
        return a.d[:length]
    }
}

fix_resizable_dynamic :: proc(d: []$T, loc := #caller_location) {
    when debug_dynamic_array {
        print_call(loc, "fix_resizable_dynamic")
    }
    fix_resizable(raw_data(d))
}

fix_resizable_multi :: proc(d: Multi($T), loc := #caller_location) {
    when debug_dynamic_array {
        print_call(loc, "fix_resizable_multi")
    }
    when ODIN_DEBUG {
        fix_resizable_dynamic(d.d)
    } else {
        fix_resizable(d.d)
    }
}

resize_dynamic :: proc(d: ^[]$T, new_length: int, loc := #caller_location) {
    when debug_dynamic_array {
        print_call(loc, "resize_dynamic")
    }
    raw := (^runtime.Raw_Slice)(d)
    raw.len = new_length
    resize(raw.data, new_length * size_of(T))
}

resize_multi :: proc(d: ^Multi($T), new_length: int, loc := #caller_location) {
    when debug_dynamic_array {
        print_call(loc, "resize_multi")
    }
    when ODIN_DEBUG {
        resize_dynamic(&d.d, new_length)
    } else {
        resize(d.d, new_length * size_of(T))
    }
}

append_dynamic :: proc(d: ^[]$T, elem: T, loc := #caller_location) {
    when debug_dynamic_array {
        print_call(loc, "append_dynamic")
    }
    resize_dynamic(d, len(d) + 1)
    d[len(d) - 1] = elem
}

append_dynamic_elems :: proc(d: ^[]$T, elems: ..T, loc := #caller_location) {
    when debug_dynamic_array {
        print_call(loc, "append_dynamic_elems")
    }
    old_len := len(d)
    resize_dynamic(d, len(d) + len(elems))
    for elem, i in elems {
        d[old_len + i] = elem
    }
}

append_multi_dynamic :: proc(d: ^Multi($T), old_length: int, elem: T, loc := #caller_location) {
    when debug_dynamic_array {
        print_call(loc, "append_multi_dynamic")
    }
    when ODIN_DEBUG {
        assert(old_length == len(d.d))
    }
    resize_multi(d, old_length + 1)
    d.d[old_length] = elem
}

clear_dynamic :: proc(d: ^[]$T, loc := #caller_location) {
    when debug_dynamic_array {
        print_call(loc, "clear_dynamic")
    }
    resize_dynamic(d, 0)
}

