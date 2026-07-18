package main

// Requirements
// - You only call `resize` for resizable allocations
// - `dealloc` is called in the reverse order that `alloc` is called in
// See `arena_test` in `test.odin` for an example

import "base:runtime"
import "core:mem"
import "core:mem/virtual"

// For every `virtual.Memory_Block` the `.base` field points to an `ArenaBlockData`

Arena :: struct {
    last_allocation:      ^ArenaAllocation,
    last_block:           ^virtual.Memory_Block,
    last_resizable_block: ^virtual.Memory_Block,
}

ArenaBlockInfo :: struct {
    // The last block is stored in the virtual.Memory_Block
    last_resizable_block:     ^virtual.Memory_Block,
    last_allocation_in_block: ^ArenaAllocation,
    arena:                    ^Arena,
}

_ArenaAllocation :: struct {
    block:                    ^virtual.Memory_Block,
    prev_allocation_in_arena: ^ArenaAllocation,
    prev_allocation_in_block: ^ArenaAllocation,
}

when ODIN_DEBUG {
    ArenaAllocation :: struct {
        using a: _ArenaAllocation,
        loc:     runtime.Source_Code_Location,
    }
} else {
    ArenaAllocation :: _ArenaAllocation
}

get_block_info :: proc(block: ^virtual.Memory_Block) -> ^ArenaBlockInfo {
    return (^ArenaBlockInfo)(block.base)
}

create_block :: proc(a: ^Arena) {
    block, err := virtual.memory_block_alloc(0, virtual.DEFAULT_ARENA_STATIC_RESERVE_SIZE)
    if err != nil {
        panic("Failed to allocate memory block")
    }

    arena_block_raw, err2 := virtual.alloc_from_memory_block(
        block,
        size_of(ArenaBlockInfo),
        align_of(ArenaBlockInfo),
    )
    if err2 != nil {
        panic("Failed to allocate from memory block")
    }

    assert(raw_data(arena_block_raw) == block.base)

    arena_block := (^ArenaBlockInfo)(raw_data(arena_block_raw))

    arena_block.last_resizable_block = a.last_resizable_block
    arena_block.arena = a
    block.prev = a.last_block

    a.last_resizable_block = block
    a.last_block = block
}

alloc :: proc(
    a: ^Arena,
    size: uint,
    alignment: uint,
    resizable: bool,
    loc: runtime.Source_Code_Location,
) -> rawptr {
    if a.last_resizable_block == nil {
        create_block(a)
    }

    last_resizable_block_info := (^ArenaBlockInfo)(a.last_resizable_block.base)

    arena_allocation_raw, err := virtual.alloc_from_memory_block(
        a.last_resizable_block,
        size_of(ArenaAllocation),
        align_of(ArenaAllocation),
    )
    if err != nil {
        panic("Failed to allocate from memory block")
    }

    data, err2 := virtual.alloc_from_memory_block(a.last_resizable_block, size, alignment)
    if err2 != nil {
        panic("Failed to allocate from memory block")
    }

    arena_allocation := (^ArenaAllocation)(raw_data(arena_allocation_raw))
    arena_allocation.prev_allocation_in_block = last_resizable_block_info.last_allocation_in_block
    arena_allocation.prev_allocation_in_arena = a.last_allocation
    arena_allocation.block = a.last_resizable_block
    when ODIN_DEBUG {
        arena_allocation.loc = loc
    }

    last_resizable_block_info.last_allocation_in_block = arena_allocation
    a.last_allocation = arena_allocation

    if resizable {
        a.last_resizable_block = last_resizable_block_info.last_resizable_block
        last_resizable_block_info.last_resizable_block = nil
    }

    out := raw_data(data)

    info := get_info(out)
    assert(info.allocation == arena_allocation)
    assert(info.block == last_resizable_block_info)

    return out
}

arena_new :: proc(a: ^Arena, $T: typeid, resizable := false, loc := #caller_location) -> ^T {
    when debug_arena {
        print_call(loc, "arena_new")
    }
    allocated := alloc(a, size_of(T), align_of(T), resizable, loc)
    return (^T)(allocated)
}

arena_make :: proc(
    a: ^Arena,
    $T: typeid/[]$E,
    len: int,
    resizable := false,
    loc := #caller_location,
) -> T {
    when debug_arena {
        print_call(loc, "arena_make")
    }
    out: T = ---
    out_raw := (^runtime.Raw_Slice)(&out)
    out_raw.data = alloc(a, uint(size_of(E) * len), align_of(E), resizable, loc)
    out_raw.len = len
    return out
}

arena_make_multi :: proc(
    a: ^Arena,
    $T: typeid/Multi($E),
    len: int,
    resizable := false,
    loc := #caller_location,
) -> T {
    when debug_arena {
        print_call(loc, "arena_make_multi")
    }
    when ODIN_DEBUG {
        return T{arena_make(a, []E, len, resizable, loc)}
    } else {
        allocated := alloc(a, uint(size_of(E) * len), align_of(E), resizable, loc)
        return T{([^]E)(allocated)}
    }
}

AllocationInfo :: struct {
    allocation: ^ArenaAllocation,
    block:      ^ArenaBlockInfo,
}

get_info :: proc(allocated: rawptr) -> AllocationInfo {
    assert(allocated != nil)
    allocation := &([^]ArenaAllocation)(allocated)[-1]
    return AllocationInfo{allocation, get_block_info(allocation.block)}
}

is_resizable_from_info :: proc(info: AllocationInfo) -> bool {
    return info.block.last_allocation_in_block == info.allocation
}

is_resiable_from_allocation :: proc(allocation: rawptr) -> bool {
    info := get_info(allocation)
    return is_resizable_from_info(info)
}

is_resizable :: proc {
    is_resizable_from_info,
    is_resiable_from_allocation,
}

resize :: proc(allocation: rawptr, new_size: int, loc := #caller_location) {
    when debug_arena {
        print_call(loc, "resize")
    }
    info := get_info(allocation)
    assert(is_resizable(info))
    // Dependent on https://github.com/odin-lang/Odin/pull/7049
    err := virtual.memory_block_resize(
        info.allocation.block,
        uint(mem.ptr_sub(([^]byte)(allocation), info.allocation.block.base) + new_size),
    )
    if err != nil {
        panic("Failed to resize memory block")
    }
}

fix_resizable :: proc(allocation: rawptr, loc := #caller_location) {
    when debug_arena {
        print_call(loc, "fix_resizable")
    }
    info := get_info(allocation)
    assert(is_resizable(info))
    assert(info.block.last_resizable_block == nil)
    info.block.last_resizable_block = info.block.arena.last_resizable_block
    info.block.arena.last_resizable_block = info.allocation.block
}

dealloc :: proc(allocation: rawptr, loc := #caller_location) {
    when debug_arena {
        print_call(loc, "dealloc")
    }
    info := get_info(allocation)
    assert(info.block.arena.last_allocation == info.allocation)
    info.allocation.block.used = uint(
        mem.ptr_sub(([^]byte)(info.allocation), info.allocation.block.base),
    )
    info.block.last_allocation_in_block = info.allocation.prev_allocation_in_block
    info.block.arena.last_allocation = info.allocation.prev_allocation_in_arena
}

delete_arena :: proc(a: ^Arena, expect_empty := true, loc := #caller_location) {
    when debug_arena {
        print_call(loc, "delete_arena")
    }
    if expect_empty {
        assert(a.last_allocation == nil)
    }

    resizable_blocks: map[^virtual.Memory_Block]struct{}
    defer delete(resizable_blocks) // TODO: Maybe we should use the arena for this allocation?
    resizable_block := a.last_resizable_block
    for resizable_block != nil {
        when debug_arena {
            debug("Found resizable block at ^virtual.MemoryBlock %p", resizable_block)
        }
        resizable_blocks[resizable_block] = struct{}{}
        resizable_block = get_block_info(resizable_block).last_resizable_block
    }

    block := a.last_block
    for block != nil {
        block_info := get_block_info(block)
        assert(block_info.arena == a)

        if expect_empty {
            assert(block_info.last_allocation_in_block == nil)
        }

        // Expect that `fix_resizable` has been called for all resizable elements which were allocated on the arena
        if block not_in resizable_blocks {
            when ODIN_DEBUG {
                panicf(
                    "There was a resizable allocation allocated at %v for which `fix_resizable` was not called",
                    block_info.last_allocation_in_block.loc,
                )
            } else {
                panic("There was a resizable allocation for which `fix_resizable` was not called")
            }
        }

        prev_block := block.prev
        virtual.memory_block_dealloc(block)
        block = prev_block
    }
}

/*

allocator := Allocator{}

AllocatorScope :: struct {
    last_scope: ^AllocatorScope,
    kind:       enum {
        GeneralScope,
        DynamicArrayScope,
    },
}

Allocator :: struct {
    block:     ^virtual.Memory_Block,
    top_scope: ^AllocatorScope,
}

Dynamic :: struct(T: typeid) {
    
}

init_allocator :: proc() {
    err: virtual.Allocator_Error = ---
    allocator.block, err = virtual.memory_block_alloc(0, virtual.DEFAULT_ARENA_STATIC_RESERVE_SIZE)
    if err != nil {
        panic("Failed to allocate memory block")
    }
}

allocate :: proc($T: typeid) -> ^T {
    data, err := virtual.alloc_from_memory_block(allocator.block, size_of(T), align_of(T))
    if err != nil {
        panic("Failed to allocate from memory block")
    }
    return (^T)(raw_data(data))
}

create_scope :: proc() {
    scope := allocate(AllocatorScope)
    scope.last_scope = allocator.top_scope
    scope.kind = .GeneralScope
    allocator.top_scope = scope
}

fini_allocator :: proc() {
    virtual.memory_block_dealloc(allocator.block)
}

*/

