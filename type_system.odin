package main

import "base:runtime"

Type :: OrderedHashSetSlotRef

string_type :: Type{max(u32)}
i64_type :: Type{max(u32) - 1}
i32_type :: Type{max(u32) - 2}
i16_type :: Type{max(u32) - 3}
i8_type :: Type{max(u32) - 4}
u64_type :: Type{max(u32) - 5}
u32_type :: Type{max(u32) - 6}
u16_type :: Type{max(u32) - 7}
u8_type :: Type{max(u32) - 8}
bool_type :: Type{max(u32) - 9}
invalid_type :: Type{max(u32) - 10}
unknown_type :: Type{max(u32) - 11}
type_type :: Type{max(u32) - 12}
max_index :: max(u32) - 13

dynamic_array_of_strings :: Type{0} // []String
string_to_nil_type :: Type{1} // (String)
string_string_to_nil_type :: Type{2} // (String, String)
string_to_string_type :: Type{3} // (String) -> String
comptime_u64_to_string_type :: Type{4} // #comptime ((U64) -> String)
no_args_to_nil_type :: Type{5} // ()
array_of_strings_to_nil_type :: Type{6} // ([]String)
i64_to_nil_type :: Type{7} // (I64)

GenericTypeValue :: struct {
    generic_type_index: u32, // an index into CheckerState.global_types_with_generics
    generic_arg:        Type,
    initialised_type:   Type, // Set to `unknown_type` when not initialised yet
}

TypeValue :: union {
    ArrayType,
    FuncType,
    GenericTypeValue,
    SumType(Type), // The type is always a struct

    // The extra data is the initialisation function
    Struct(Type, Type),
}

TypeSlot :: struct {
    aliases: ^[dynamic]string,
    value:   TypeValue,
}

Types :: OrderedHashSet(TypeSlot)

get_type :: proc(types: Types, t: Type) -> TypeValue {
    if t.index > max_index {
        return nil
    }
    slot := get_value(types, t)
    return slot.value
}

CreatedType :: struct {
    type:       Type,
    type_value: TypeValue,
    result:     Result,
}

create_type :: proc(
    types: ^Types,
    value: TypeValue,
    aliases: [dynamic]string = nil,
    loc := #caller_location,
) -> CreatedType {
    when debug_checker {
        print_call(loc, "create_type")
        debug("value: %v", value)
    }
    type, type_value, result := insert(
        types,
        hash_type_value(value),
        TypeSlot{new_clone(aliases), value},
        merge_type_slot,
        loc,
    )
    out := CreatedType{type, type_value.value, result}
    when debug_checker {
        debug("out: %v", out)
    }
    return out
}

hash_type_value :: proc(value: TypeValue) -> u32 {
    switch v in value {
    case ArrayType:
        return v.length ~ v.item_type.index
    case SumType(Type):
        return hash_sum_type(v)
    case Struct(Type, Type):
        return hash_struct_type(v)
    case FuncType:
        return hash_func_type(v)
    case GenericTypeValue:
        return v.generic_type_index ~ v.generic_arg.index
    }
    panic("Unreachable")
}

hash_struct_type :: proc(value: Struct(Type, Type)) -> u32 {
    result: u32
    for field, j in value.fields {
        for c in field.name.ident {
            result ~= u32(c) ~ u32(j)
        }
        result ~= field.type.index
    }
    return result
}

hash_sum_type :: proc(value: SumType(Type)) -> u32 {
    result: u32
    for variant in value.variants {
        for c in variant.name.ident {
            result ~= u32(c)
        }
        result ~= variant.payload.index
    }
    return result
}

hash_func_type :: proc(value: FuncType) -> u32 {
    result: u32
    for arg in value.args {
        result ~= arg.index
    }
    for ret in value.return_types {
        result ~= ret.index
    }
    return result ~ u32(value.type)
}

merge_type_slot :: proc(
    a: TypeSlot,
    b: TypeSlot,
    loc: runtime.Source_Code_Location,
) -> (
    bool,
    TypeSlot,
) {
    equal, merged := merge_type_value(a.value, b.value, loc)
    if equal {
        append_elems(a.aliases, ..b.aliases[:])
        return true, TypeSlot{a.aliases, merged}
    }
    return false, TypeSlot{}
}

merge_type_value :: proc(
    a: TypeValue,
    b: TypeValue,
    loc: runtime.Source_Code_Location,
) -> (
    bool,
    TypeValue,
) {
    #partial switch va in a {
    case ArrayType:
        vb, ok := b.(ArrayType)
        if !ok {
            return false, nil
        }
        return va.length == vb.length && va.item_type.index == vb.item_type.index, a
    case SumType(Type):
        vb, ok := b.(SumType(Type))
        if !ok {
            return false, nil
        }
        return merge_sum_types(va, vb, loc)
    case Struct(Type, Type):
        vb, ok := b.(Struct(Type, Type))
        if !ok {
            return false, nil
        }
        return merge_struct_types(va, vb, loc)
    case FuncType:
        vb, ok := b.(FuncType)
        if !ok {
            return false, nil
        }
        return func_types_are_equal(va, vb), a
    case GenericTypeValue:
        vb, ok := b.(GenericTypeValue)
        if !ok {
            return false, nil
        }
        if va.generic_type_index == vb.generic_type_index && va.generic_arg == vb.generic_arg {
            if va.initialised_type != unknown_type {
                assert(vb.initialised_type == unknown_type)
                return true, va
            }
            return true, vb
        }
    }
    return false, nil
}

merge_struct_types :: proc(
    a: Struct(Type, Type),
    b: Struct(Type, Type),
    loc: runtime.Source_Code_Location,
) -> (
    bool,
    Struct(Type, Type),
) {
    if len(a.fields) != len(b.fields) {
        return false, Struct(Type, Type){}
    }
    for a_field, i in a.fields {
        b_field := b.fields[i]
        if a_field.name.ident != b_field.name.ident {
            return false, Struct(Type, Type){}
        }
        if a_field.type != b_field.type {
            return false, Struct(Type, Type){}
        }
    }
    if a.extra_data != unknown_type {
        if b.extra_data != unknown_type {
            debug("file %s, line %d, column %d", loc.file_path, loc.line, loc.column)
            panic("Unreachable")
        }
        return true, a
    }
    return true, b
}

merge_sum_types :: proc(
    a: SumType(Type),
    b: SumType(Type),
    loc: runtime.Source_Code_Location,
) -> (
    bool,
    SumType(Type),
) {
    if len(a.variants) != len(b.variants) {
        return false, SumType(Type){}
    }
    for a_variant, i in a.variants {
        b_variant := b.variants[i]
        if a_variant.name.ident != b_variant.name.ident {
            return false, SumType(Type){}
        }
        if a_variant.payload != b_variant.payload {
            return false, SumType(Type){}
        }
    }
    return true, a
}

func_types_are_equal :: proc(a: FuncType, b: FuncType) -> bool {
    if len(a.args) != len(b.args) {
        return false
    }
    if len(a.return_types) != len(b.return_types) {
        return false
    }
    for arg, i in a.args {
        if arg.index != b.args[i].index {
            return false
        }
    }
    for ret, i in a.return_types {
        if ret.index != b.return_types[i].index {
            return false
        }
    }
    return a.type == b.type
}

