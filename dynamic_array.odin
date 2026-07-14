package main

import "base:runtime"

fix_resizable_dynamic :: proc(d: []$T) {
    fix_resizable(raw_data(d))
}

resize_dynamic :: proc(d: ^[]$T, new_length: int) {
    raw := (^runtime.Raw_Slice)(d)
    raw.len = new_length
    resize(raw.data, new_length * size_of(T))
}

append_dynamic :: proc(d: ^[]$T, elem: T) {
    resize_dynamic(d, len(d) + 1)
    d[len(d) - 1] = elem
}

append_multi_dynamic :: proc(d: [^]$T, old_length: int, elem: T) {
    resize(d, (old_length + 1) * size_of(T))
    d[old_length] = elem
}

clear_dynamic :: proc(d: ^[]$T) {
    resize_dynamic(d, 0)
}

