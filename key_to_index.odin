package main

// Zero collision "key to index" implementation

// TODO: Benchmarks:
// - u64 hashes instead of u32 hashes
// - without the hash being cached in `Key`
// - different values for `key_to_index_min_scale_factor`

import "core:mem"

key_to_index_min_scale_factor :: 3 // len(KeyToIndex.keys) * min_scale_factor <= len(KeyToIndex.slots)
key_to_index_size_with_one_elem :: 4 // math.next_power_of_two(key_to_index_min_scale_factor)

Index :: struct {
    index: u32, // An index into `KeyToIndex.keys`
}

SlotIndex :: struct {
    // An index into `KeyToIndex.slots`
    // Short-lived because the `KeyToIndex` slots may be reallocated
    index: int,
}

Key :: struct(T: typeid) {
    key:      T,
    key_hash: u32,
}

KeyToIndex :: struct(K: typeid) {
    // Always allocated using an `Arena`
    // In the case of collisions, the next slot is used
    // `len(slots)` is always a power of 2
    slots: []Index,
    keys:  []Key(K),
}

make_key_to_index :: proc(a: ^Arena, $T: typeid/KeyToIndex($K)) -> KeyToIndex(K) {
    return KeyToIndex(K) {
        arena_make(a, []Index, 0, resizable = true),
        arena_make(a, []Key(K), 0, resizable = true),
    }
}

fix_key_to_index :: proc(key_to_index: KeyToIndex($Key)) {
    fix_resizable_dynamic(key_to_index.slots)
    fix_resizable_dynamic(key_to_index.keys)
}

get_index :: proc(slots_len: $T, hash: T) -> T {
    return hash & (slots_len - 1)
}

/*
get_key :: proc(t: KeyToIndex($Key), ref: Index) -> Key {
    return t.keys[ref.index].key
}
*/

resize_key_to_index :: proc(
    key_to_index: ^KeyToIndex($Key),
    new_slots_len: u32,
    loc := #caller_location,
) {
    when debug_key_to_index {
        print_call(loc, "resize")
        debug("new_slots_len: %d", new_slots_len)
    }
    resize_dynamic(&key_to_index.slots, int(new_slots_len))
    mem.set(&key_to_index.slots[0], max(u8), int(new_slots_len) * size_of(Index))

    for _, index in key_to_index.keys {
        find_index_of_free_slot :: proc(slots: []Index, start_slot_index: u32) -> u32 {
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

        start_slot_index := get_index(new_slots_len, key_to_index.keys[index].key_hash)
        free_slot_index := find_index_of_free_slot(key_to_index.slots, start_slot_index)

        when debug_key_to_index {
            debug("index: %d", index)
            debug("start_slot_index: %d", start_slot_index)
            debug("free_slot_index: %d", free_slot_index)
        }

        key_to_index.slots[free_slot_index] = Index{u32(index)}
    }
}

KeyToIndexProcs :: struct(K: typeid) {
    hash_proc:  proc(_: K) -> u32,

    // The `bool` returned is whether the keys are equal
    equal_proc: proc(_: K, _: K) -> bool,
}

string_to_index_procs :: KeyToIndexProcs(string) {
    simple_hash_string,
    proc(a: string, b: string) -> bool {
        return a == b
    },
}

Result :: enum {
    Inserted,
    LookedUp,
}

Exists :: struct {
    index:      Index,
    slot_index: SlotIndex,
}

NoSlots :: struct {}

DoesNotExist :: union #no_nil {
    // The index of the slot that the key would go in
    SlotIndex,

    // Cannot know the `SlotIndex`, nor the `Index` because there are no slots
    NoSlots,
}

LookupResult :: union #no_nil {
    Exists,
    DoesNotExist,
}

_lookup :: proc(
    key_to_index: KeyToIndex($K),
    key: Key(K),
    equal_proc: proc(_: K, _: K) -> bool,
) -> union #no_nil {
        Index,
        SlotIndex,
    } {
    i := get_index(len(key_to_index.slots), int(key.key_hash))
    for {
        slot_value := key_to_index.slots[i]
        if slot_value.index == max(u32) {
            when debug_key_to_index {
                debug("found empty slot at index %d", i)
            }
            return SlotIndex{i}
        }
        existing_key := key_to_index.keys[slot_value.index].key
        is_equal := equal_proc(key.key, existing_key)
        when debug_key_to_index {
            debug("equal func called")
            debug("existing key: %v", existing_key)
            debug("is_equal: %b", is_equal)
        }
        if is_equal {
            return slot_value
        }
        i = (i + 1) % len(key_to_index.slots)
    }
}

does_not_exist :: Index{max(u32)}

lookup :: proc(
    key_to_index: KeyToIndex($K),
    key: K,
    procs: KeyToIndexProcs(K),
    loc := #caller_location,
) -> Index {
    when debug_key_to_index {
        print_call(loc, "lookup")
        debug("key: %v", key)
    }

    if len(key_to_index.keys) == 0 {
        return does_not_exist
    }
    assert(len(key_to_index.slots) > 0)
    full_key := Key(K){key, procs.hash_proc(key)}
    result, exists := _lookup(key_to_index, full_key, procs.equal_proc).(Index)
    if !exists {
        return does_not_exist
    }
    return result
}

lookup_or_insert :: proc(
    key_to_index: ^KeyToIndex($K),
    key: K,
    procs: KeyToIndexProcs(K),
    loc := #caller_location,
) -> (
    Index,
    Result,
) {
    when debug_key_to_index {
        print_call(loc, "lookup_or_insert")
        debug("key: %v", key)
    }
    full_key := Key(K){key, procs.hash_proc(key)}
    if len(key_to_index.keys) == 0 {
        append_dynamic(&key_to_index.keys, full_key)
        resize_key_to_index(key_to_index, key_to_index_size_with_one_elem)
        return Index{0}, .Inserted
    }
    switch result in _lookup(key_to_index^, full_key, procs.equal_proc) {
    case Index:
        return result, .LookedUp
    case SlotIndex:
        out := Index{u32(len(key_to_index.keys))}
        append_dynamic(&key_to_index.keys, full_key)
        minimum_number_of_slots := len(key_to_index.keys) * key_to_index_min_scale_factor
        if minimum_number_of_slots > len(key_to_index.slots) {
            new_size := len(key_to_index.slots) << 1
            assert(new_size > minimum_number_of_slots)
            // for u32(minimum_number_of_slots) > new_size {
            // new_size <<= 1
            // }
            resize_key_to_index(key_to_index, u32(new_size))
        } else {
            key_to_index.slots[result.index] = out
        }
        return out, .Inserted
    case:
        panic("Unreachable")
    }
}

