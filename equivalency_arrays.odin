package main

// - Implements a data structure where:
//   - Elements can be added in `O(n) = 1` time (no equivalency checking)
//   - 2 elements can be marked as the same in `O(n) = 1` time
//   - You can iterate through all of the unique elements in `O(n) = n` time
//     where n is the number of elements
// - This data structure is used to store array types and generic type
//   instantiations, and then to mark that 2 of these are the same type later
//   on in the checking process

EquivalencyArrayElem :: union(T: typeid) {
    uint, // A reference to an earlier value in the array
    T,
}

// Returns the element and the simplified index
get_info :: proc(
    equivalency_array: $Array/[]EquivalencyArrayElem($Elem),
    index: uint,
    loc := #caller_location,
) -> (
    Elem,
    uint,
) {
    when debug_equivalency_arrays {
        print_call(loc, "get info")
        print_arg("index", index)
    }
    i := index
    for {
        switch value in equivalency_array[i] {
        case uint:
            i = value
        case Elem:
            return value, i
        case:
            panic("Unreachable")
        }
    }
}

mark_elements_equal :: proc(
    equivalency_array: $Array/[]EquivalencyArrayElem($Elem),
    index0: uint,
    index1: uint,
) {
    assert(index0 != index1)
    larger_index := max(index0, index1)
    smaller_index := min(index0, index1)

    // If the larger index is already a reference, then making the larger index
    // a reference to the smaller index losses equility information
    _, is_reference := equivalency_array[larger_index].(uint)
    assert(!is_reference)

    equivalency_array[larger_index] = smaller_index
}

