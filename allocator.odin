package main

/*
import "core:mem/virtual"

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

