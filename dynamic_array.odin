package main

Dynamic :: struct(T: typeid) {
    length: int,
    data:   [^]T,
}

create_dynamic :: proc(a: ^Arena, $T: typeid, always_resizable := true) -> Dynamic(T) {
    return Dynamic(T){0, ([^]T)(alloc(a, struct {}, always_resizable))}
}

to_array :: proc(d: Dynamic($T)) -> []T {
    return d.data[:d.length]
}

fix_resizable_dynamic :: proc(d: Dynamic($T)) -> []T {
    fix_resizable(d.data)
    return to_array(d)
}

append_dynamic :: proc(d: ^Dynamic($T), elem: T) {
    d.length += 1
    realloc(d.data, d.length * size_of(T))
    d.data[d.length - 1] = elem
}

clear_dynamic :: proc(d: ^Dynamic($T)) {
    d.length = 0
    realloc(d.data, 0)
}

