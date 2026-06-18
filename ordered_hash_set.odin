package main

// - Zero collision ordered hash set implementation
// - Also has "merging", where 2 slightly different values in the has map can be
//   merged into one value with the same reference

// TODO: Benchmarks:
// - u64 hashes instead of u32 hashes
// - without the hash being cached in `OrderedHashSetValue`
// - different values for `ordered_hash_set_min_scale_factor`

import "base:runtime"
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

resize :: proc(
    ordered_hash_set: ^OrderedHashSet($Value),
    new_slots_len: u32,
    loc := #caller_location,
) {
    when debug_ordered_hash_sets {
        print_call(loc, "resize")
        debug("new_slots_len: %d", new_slots_len)
    }
    delete(ordered_hash_set.slots)
    ordered_hash_set.slots = make([]OrderedHashSetSlotRef, new_slots_len)
    mem.set(
        &ordered_hash_set.slots[0],
        max(u8),
        int(new_slots_len) * size_of(OrderedHashSetSlotRef),
    )

    for value, index in ordered_hash_set.values {
        find_index_of_free_slot :: proc(
            slots: []OrderedHashSetSlotRef,
            start_slot_index: u32,
        ) -> u32 {
            for i in start_slot_index ..< u32(len(slots)) {
                if slots[i].index == max(u32) {
                    return i
                }
            }
            for i in 0 ..< start_slot_index {
                if slots[i].index == max(u32) {
                    return i
                }
            }
            panic("Unreachable")
        }

        start_slot_index := get_index(new_slots_len, value.hash)
        free_slot_index := find_index_of_free_slot(ordered_hash_set.slots, start_slot_index)

        when debug_ordered_hash_sets {
            debug("index: %d", index)
            debug("start_slot_index: %d", start_slot_index)
            debug("free_slot_index: %d", free_slot_index)
        }

        ordered_hash_set.slots[free_slot_index] = OrderedHashSetSlotRef{u32(index)}
    }
}

insert :: proc(
    ordered_hash_set: ^OrderedHashSet($Value),
    hash: u32,
    value: Value,

    // The `bool` returned is whether the values can be merged
    // The `Value` returned is the merged value
    equal_merge_func: proc(_: Value, _: Value, loc: runtime.Source_Code_Location) -> (bool, Value),
    can_insert: bool = true,
    loc := #caller_location,
) -> (
    OrderedHashSetSlotRef,
    Value,
) {
    when debug_ordered_hash_sets {
        print_call(loc, "insert")
        debug("hash: %d", hash)
        debug("value: %v", value)
    }
    if len(ordered_hash_set.values) == 0 {
        append_elem(&ordered_hash_set.values, OrderedHashSetValue(Value){hash, value})
        resize(ordered_hash_set, ordered_hash_set_size_with_one_elem)
        return OrderedHashSetSlotRef{0}, value
    }

    i := get_index(len(ordered_hash_set.slots), int(hash))
    for {
        if ordered_hash_set.slots[i].index == max(u32) {
            when debug_ordered_hash_sets {
                debug("found empty slot at index %d", i)
            }
            if !can_insert {
                panic("Could not find already existing hash set value to merge with")
            }
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
            return out, value
        }
        slot_value := ordered_hash_set.slots[i]
        is_equal, merged := equal_merge_func(
            value,
            ordered_hash_set.values[slot_value.index].value,
            loc,
        )
        when debug_ordered_hash_sets {
            debug("equal merge func called")
            debug("value: %v", value)
            debug("existing: %v", ordered_hash_set.values[slot_value.index].value)
            debug("is_equal: %b", is_equal)
            debug("merged: %v", merged)
        }
        if is_equal {
            ordered_hash_set.values[slot_value.index].value = merged
            return slot_value, merged
        }
        i = (i + 1) % len(ordered_hash_set.slots)
    }
}

