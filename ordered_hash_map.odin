package main

// Zero collision ordered hash map implementation

// TODO: Benchmarks:
// - u64 hashes instead of u32 hashes
// - without the hash being cached in `OrderedHashSetValue`
// - different values for `ordered_hash_set_min_scale_factor`

import "base:runtime"
import "core:mem"

ordered_hash_set_min_scale_factor :: 3 // len(OrderedHashSet.values) * min_scale_factor <= len(OrderedHashSet.slots)
ordered_hash_set_size_with_one_elem :: 4 // math.next_power_of_two(ordered_hash_set_min_scale_factor)

OrderedHashMapSlotRef :: struct {
    index: u32, // An index into `OrderedHashMap.values`
}

OrderedHashMapValue :: struct(Key: typeid, Value: typeid) {
    key:      Key,
    key_hash: u32,
    value:    Value,
}

OrderedHashMap :: struct(Key: typeid, Value: typeid) {
    // In the case of collisions, the next slot is used
    // `len(slots)` is always a power of 2
    slots:  []OrderedHashMapSlotRef,
    values: [dynamic]OrderedHashMapValue(Key, Value),
}

get_hash_map_index :: proc(slots_len: $T, hash: T) -> T {
    return hash & (slots_len - 1)
}

get_value :: proc(t: OrderedHashMap($Key, $Value), ref: OrderedHashMapSlotRef) -> (Key, Value) {
    slot := t.values[ref.index]
    return slot.key, slot.value
}

resize :: proc(
    ordered_hash_map: ^OrderedHashMap($Key, $Value),
    new_slots_len: u32,
    loc := #caller_location,
) {
    when debug_ordered_hash_maps {
        print_call(loc, "resize")
        debug("new_slots_len: %d", new_slots_len)
    }
    delete(ordered_hash_map.slots)
    ordered_hash_map.slots = make([]OrderedHashMapSlotRef, new_slots_len)
    mem.set(
        &ordered_hash_map.slots[0],
        max(u8),
        int(new_slots_len) * size_of(OrderedHashMapSlotRef),
    )

    for value, index in ordered_hash_map.values {
        find_index_of_free_slot :: proc(
            slots: []OrderedHashMapSlotRef,
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

        start_slot_index := get_hash_map_index(new_slots_len, value.key_hash)
        free_slot_index := find_index_of_free_slot(ordered_hash_map.slots, start_slot_index)

        when debug_ordered_hash_maps {
            debug("index: %d", index)
            debug("start_slot_index: %d", start_slot_index)
            debug("free_slot_index: %d", free_slot_index)
        }

        ordered_hash_map.slots[free_slot_index] = OrderedHashMapSlotRef{u32(index)}
    }
}

Result :: enum {
    Inserted,
    Merged,
}

ordered_hash_map_insert :: proc(
    ordered_hash_map: ^OrderedHashMap($Key, $Value),
    key: Key,
    key_hash: u32,
    default_value: Value,

    // The `bool` returned is whether the keys are equal
    equal_func: proc(_: Key, _: Key, loc: runtime.Source_Code_Location) -> bool,
    loc := #caller_location,
) -> (
    OrderedHashMapSlotRef,
    Value,
    Result,
) {
    when debug_ordered_hash_maps {
        print_call(loc, "insert")
        debug("key: %v", key)
        debug("key_hash: %d", key_hash)
        debug("default_value: %v", default_value)
    }
    if len(ordered_hash_map.values) == 0 {
        append_elem(
            &ordered_hash_map.values,
            OrderedHashMapValue(Key, Value){key, key_hash, default_value},
        )
        resize(ordered_hash_map, ordered_hash_set_size_with_one_elem)
        return OrderedHashMapSlotRef{0}, ordered_hash_map.values[0].value, .Inserted
    }

    i := get_hash_map_index(len(ordered_hash_map.slots), int(key_hash))
    for {
        if ordered_hash_map.slots[i].index == max(u32) {
            when debug_ordered_hash_maps {
                debug("found empty slot at index %d", i)
            }
            out := OrderedHashMapSlotRef{u32(len(ordered_hash_map.values))}
            append_elem(
                &ordered_hash_map.values,
                OrderedHashMapValue(Key, Value){key, key_hash, default_value},
            )
            minimum_number_of_slots :=
                len(ordered_hash_map.values) * ordered_hash_set_min_scale_factor
            if minimum_number_of_slots > len(ordered_hash_map.slots) {
                new_size := len(ordered_hash_map.slots) << 1
                assert(new_size > minimum_number_of_slots)
                // for u32(minimum_number_of_slots) > new_size {
                // new_size <<= 1
                // }
                resize(ordered_hash_map, u32(new_size))
            } else {
                ordered_hash_map.slots[i] = out
            }
            return out, ordered_hash_map.values[len(ordered_hash_map.values) - 1].value, .Inserted
        }
        slot_value := ordered_hash_map.slots[i]
        is_equal := equal_func(key, ordered_hash_map.values[slot_value.index].key, loc)
        when debug_ordered_hash_maps {
            debug("equal func called")
            debug("existing key: %v", ordered_hash_map.values[slot_value.index].key)
            debug("is_equal: %b", is_equal)
        }
        if is_equal {
            return slot_value, ordered_hash_map.values[slot_value.index].value, .Merged
        }
        i = (i + 1) % len(ordered_hash_map.slots)
    }
}

