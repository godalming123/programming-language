package main

Type :: OrderedHashSetSlotRef

GenericTypeValue :: struct {
    generic_type_index: u32, // an index into CheckerState.global_types_with_generics
    generic_arg:        Type,
    is_initialised:     bool,
    initialised_type:   u32, // an index into type_equivalancy_array
}

TypeValue :: union {
    ArrayType(Type),
    SumType(Type, struct {}),
    FuncType(Type),
    GenericTypeValue,
}

Types :: OrderedHashSet(TypeValue)

create_type :: proc(types: ^Types, value: TypeValue) -> Type {
    return insert(types, hash_type_value(value), value, merge_type_value)
}

hash_type_value :: proc(value: TypeValue) -> u32 {
    switch v in value {
    case ArrayType(Type):
        return v.length ~ v.item_type.index
    case SumType(Type, struct {}):
        return hash_sum_type(v)
    case FuncType(Type):
        return hash_func_type(v)
    case GenericTypeValue:
        return v.generic_type_index ~ v.generic_arg.index
    }
    panic("Unreachable")
}

hash_sum_type :: proc(value: SumType(Type, struct {})) -> u32 {
    result: u32
    for key in value.variants_map {
        for c in key {
            result ~= u32(c)
        }
    }
    for variant in value.variants {
        for field, j in variant.payload.fields {
            for c in field.name.ident {
                result ~= u32(c) ~ u32(j)
            }
        }
    }
    return result
}

hash_func_type :: proc(value: FuncType(Type)) -> u32 {
    result: u32
    for arg in value.args {
        result ~= arg.index
    }
    for ret in value.return_types {
        result ~= ret.index
    }
    return result ~ u32(value.type)
}

merge_type_value :: proc(a: TypeValue, b: TypeValue) -> (bool, TypeValue) {
    #partial switch va in a {
    case ArrayType(Type):
        vb, ok := b.(ArrayType(Type))
        if !ok {
            return false, a
        }
        return va.length == vb.length && va.item_type.index == vb.item_type.index, a
    case SumType(Type, struct {}):
        vb, ok := b.(SumType(Type, struct {}))
        if !ok {
            return false, a
        }
        return sum_types_are_equal(va, vb), a
    case FuncType(Type):
        vb, ok := b.(FuncType(Type))
        if !ok {
            return false, a
        }
        return func_types_are_equal(va, vb), a
    case GenericTypeValue:
        vb, ok := b.(GenericTypeValue)
        if !ok {
            return false, a
        }
        if va.generic_type_index == vb.generic_type_index && va.generic_arg == vb.generic_arg {
            if va.is_initialised {
                assert(!vb.is_initialised)
                return true, va
            }
            return true, vb
        }
    }
    return false, a
}

sum_types_are_equal :: proc(a: SumType(Type, struct {}), b: SumType(Type, struct {})) -> bool {
    if len(a.variants) != len(b.variants) {
        return false
    }
    for key in a.variants_map {
        _, in_b := b.variants_map[key]
        if !in_b {
            return false
        }
    }
    for variant, i in a.variants {
        b_variant := b.variants[i]
        if variant.name.ident != b_variant.name.ident {
            return false
        }
        if len(variant.payload.fields) != len(b_variant.payload.fields) {
            return false
        }
    }
    return true
}

func_types_are_equal :: proc(a: FuncType(Type), b: FuncType(Type)) -> bool {
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

