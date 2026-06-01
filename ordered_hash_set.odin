package main

// - Zero collision ordered hash set implementation
// - ALso has "merging", where 2 slightly different values in the has map can be
//   merged into one value with the same reference

// TODO: Benchmarks:
// - u64 hashes instead of u32 hashes
// - without the hash being cached in `OrderedHashSetValue`
// - different values for `ordered_hash_set_min_scale_factor`

import "core:mem"

ordered_hash_set_min_scale_factor :: 3 // len(OrderedHashSet.values) * min_scale_factoer <= len(OrderedHashSet.slots)
ordered_hash_set_size_with_one_elem :: 4 // math.next_power_of_two(ordered_hash_set_min_scale_factor)

OrderedHashSetSlotRef :: struct {
    index: u32, // An index into `OrderedHashSet.values`
}

OrderedHashSetValue :: struct(Value: typeid) {
    hash:  u32,
    value: Value,
}

OrderedHashSet :: struct(Value: typeid) {
    // In the case of collisions, the next slot is used
    // `len(slots)` is always a power of 2
    slots:  []OrderedHashSetSlotRef,
    values: [dynamic]OrderedHashSetValue(Value),
}

get_index :: proc(slots_len: $T, hash: T) -> T {
    return hash & (slots_len - 1)
}

get_value :: proc(ordered_hash_set: OrderedHashSet($Value), ref: OrderedHashSetSlotRef) -> Value {
    return ordered_hash_set.values[ref.index].value
}

resize :: proc(ordered_hash_set: ^OrderedHashSet($Value), new_slots_len: u32) {
    delete(ordered_hash_set.slots)
    ordered_hash_set.slots = make([]OrderedHashSetSlotRef, new_slots_len)
    mem.set(
        &ordered_hash_set.slots[0],
        max(u8),
        int(new_slots_len) * size_of(OrderedHashSetSlotRef),
    )
    for value, index in ordered_hash_set.values {
        slot_index := get_index(u32(len(ordered_hash_set.slots)), value.hash)

        for i in slot_index ..< new_slots_len {
            if ordered_hash_set.slots[index].index == max(u32) {
                ordered_hash_set.slots[index] = OrderedHashSetSlotRef{i}
                return
            }
        }

        for i in 0 ..< slot_index {
            if ordered_hash_set.slots[index].index == max(u32) {
                ordered_hash_set.slots[index] = OrderedHashSetSlotRef{i}
                return
            }
        }

        panic("Unreachable")
    }
}


insert :: proc(
    ordered_hash_set: ^OrderedHashSet($Value),
    hash: u32,
    value: Value,

    // The `bool` returned is whether the values can be merged
    // The `Value` returned is the merged value
    equal_merge_func: proc(_: Value, _: Value) -> (bool, Value),
) -> OrderedHashSetSlotRef {
    if len(ordered_hash_set.values) == 0 {
        append_elem(&ordered_hash_set.values, OrderedHashSetValue(Value){hash, value})
        resize(ordered_hash_set, ordered_hash_set_size_with_one_elem)
        return OrderedHashSetSlotRef{0}
    }

    i := get_index(len(ordered_hash_set.slots), int(hash))
    for {
        if ordered_hash_set.slots[i].index == max(u32) {
            out := OrderedHashSetSlotRef{u32(len(ordered_hash_set.values))}
            append_elem(&ordered_hash_set.values, OrderedHashSetValue(Value){hash, value})
            minimum_number_of_slots :=
                len(ordered_hash_set.values) * ordered_hash_set_min_scale_factor
            if minimum_number_of_slots > len(ordered_hash_set.slots) {
                new_size := len(ordered_hash_set.slots) << 1
                assert(new_size > minimum_number_of_slots)
                // for u32(minimum_number_of_slots) > new_size {
                // new_size <<= 1
                // }
                resize(ordered_hash_set, u32(new_size))
            } else {
                ordered_hash_set.slots[i] = out
            }
            return out
        }
        slot_value := ordered_hash_set.slots[i]
        is_equal, merged := equal_merge_func(
            value,
            ordered_hash_set.values[slot_value.index].value,
        )
        if is_equal {
            ordered_hash_set.values[slot_value.index].value = merged
            return slot_value
        }
        i = (i + 1) % len(ordered_hash_set.slots)
    }
}

