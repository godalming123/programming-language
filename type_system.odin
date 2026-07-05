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
any_type :: Type{max(u32) - 13}
imported_file_type :: Type{max(u32) - 14}
max_index :: max(u32) - 15

dynamic_array_of_strings :: Type{0} // []String
string_to_nil_type :: Type{1} // (String)
string_string_to_nil_type :: Type{2} // (String, String)
string_to_string_type :: Type{3} // (String) -> String
string_any_ordered_hashmap_type :: Type{4} // OrderedHashMap[String, Any]
no_args_to_nil_type :: Type{5} // ()
array_of_strings_to_nil_type :: Type{6} // ([]String)
i64_to_nil_type :: Type{7} // (I64)
string_i64_to_string_type :: Type{8} // (String, I64) -> String
string_any_ordered_hashmap_and_string_to_string_type :: Type{9} // (OrderedHashMap[String, Any], String) -> String
compiler_type :: Type{10} // {emit_js_code: (OrderedHashMap[String, Any], String) -> String}
no_args_to_i64_type :: Type{11} // () -> I64
compiler_to_i64_type :: Type{12} // (Compiler) -> I64

GenericTypeValue :: struct {
    global:           GlobalValueWithGenericRef,
    generic_args:     []Type,
    initialised_type: Type, // Set to `unknown_type` when not initialised yet
}

get_hash_of_array_of_types :: proc(arr: []Type) -> u32 {
    result: u32 = 0
    for value in arr {
        result ~= value.index
    }
    return result
}

TypeValue :: union {
    ArrayType,
    OrderedHashMapTypeWithStringKey,
    OrderedHashMapTypeWithI64Key,
    FuncType,
    GenericTypeValue,
    SumType(Type), // The type is always a struct

    // The extra data is the initialisation function
    Struct(Type, Type),
}

init_struct_type :: proc(
    types: ^Types,
    type: Type,
    fields: #soa[]StructField(Type),
    fields_map: map[string]uint,
) {
    // created := create_type(types, Struct(Type, Type){unknown_type, fields_map, fields})
    // if created.type_value.(Struct(Type, Type)).extra_data != unknown_type {
    // return created.type
    // }

    return_types := make([]Type, 1)
    return_types[0] = type

    created := create_type(
        types,
        Struct(Type, Type) {
            create_type(types, FuncType{fields.type[:len(fields)], return_types}).type,
            fields_map,
            fields,
        },
    )
    assert(created.type == type)
    // return created.type
}

create_types :: proc() -> Types {
    out: Types

    array_with_string_type := make([]Type, 1)
    array_with_string_type[0] = string_type

    array_with_2string_types := make([]Type, 2)
    array_with_2string_types[0] = string_type
    array_with_2string_types[1] = string_type

    array_with_i64_type := make([]Type, 1)
    array_with_i64_type[0] = i64_type

    array_with_u64_type := make([]Type, 1)
    array_with_u64_type[0] = u64_type

    array_with_string_any_ordered_hash_map_and_string := make([]Type, 2)
    array_with_string_any_ordered_hash_map_and_string[0] = string_any_ordered_hashmap_type
    array_with_string_any_ordered_hash_map_and_string[1] = string_type

    array_with_dynamic_array_of_strings := make([]Type, 1)
    array_with_dynamic_array_of_strings[0] = dynamic_array_of_strings

    array_with_string_i64_types := make([]Type, 2)
    array_with_string_i64_types[0] = string_type
    array_with_string_i64_types[1] = i64_type

    array_with_compiler_type := make([]Type, 1)
    array_with_compiler_type[0] = compiler_type

    assert(dynamic_array_of_strings == create_type(&out, ArrayType{0, string_type}).type)
    assert(string_to_nil_type == create_type(&out, FuncType{array_with_string_type, nil}).type)
    assert(
        string_string_to_nil_type ==
        create_type(&out, FuncType{array_with_2string_types, nil}).type,
    )
    assert(
        string_to_string_type ==
        create_type(&out, FuncType{array_with_string_type, array_with_string_type}).type,
    )
    assert(
        string_any_ordered_hashmap_type ==
        create_type(&out, OrderedHashMapTypeWithStringKey{any_type}).type,
    )
    assert(no_args_to_nil_type == create_type(&out, FuncType{nil, nil}).type)
    assert(
        array_of_strings_to_nil_type ==
        create_type(&out, FuncType{array_with_dynamic_array_of_strings, nil}).type,
    )
    assert(i64_to_nil_type == create_type(&out, FuncType{array_with_i64_type, nil}).type)
    assert(
        string_i64_to_string_type ==
        create_type(&out, FuncType{array_with_string_i64_types, array_with_string_type}).type,
    )
    assert(
        string_any_ordered_hashmap_and_string_to_string_type ==
        create_type(&out, FuncType{array_with_string_any_ordered_hash_map_and_string, array_with_string_type}).type,
    )

    compiler_fields := make(#soa[]StructField(Type), 1)
    compiler_fields[0] = StructField(Type) {
        IdentAndPos{"emit_js_code", unknown_pos},
        string_any_ordered_hashmap_and_string_to_string_type,
    }
    compiler_fields_map: map[string]uint
    compiler_fields_map["emit_js_code"] = 0
    assert(
        compiler_type ==
        create_type(&out, Struct(Type, Type){unknown_type, compiler_fields_map, compiler_fields}).type,
    )

    assert(no_args_to_i64_type == create_type(&out, FuncType{nil, array_with_i64_type}).type)
    assert(
        compiler_to_i64_type ==
        create_type(&out, FuncType{array_with_compiler_type, array_with_i64_type}).type,
    )

    init_struct_type(&out, compiler_type, compiler_fields, compiler_fields_map)

    return out
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
    case OrderedHashMapTypeWithStringKey:
        return v.value_type.index + 1
    case OrderedHashMapTypeWithI64Key:
        return v.value_type.index + 2
    case SumType(Type):
        return hash_sum_type(v)
    case Struct(Type, Type):
        return hash_struct_type(v)
    case FuncType:
        return hash_func_type(v)
    case GenericTypeValue:
        return v.global.index ~ get_hash_of_array_of_types(v.generic_args)
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
    return result
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
    switch va in a {
    case OrderedHashMapTypeWithStringKey:
        vb, ok := b.(OrderedHashMapTypeWithStringKey)
        if ok && va.value_type == vb.value_type {
            return true, a
        }
        return false, nil
    case OrderedHashMapTypeWithI64Key:
        vb, ok := b.(OrderedHashMapTypeWithI64Key)
        if ok && va.value_type == vb.value_type {
            return true, a
        }
        return false, nil
    case ArrayType:
        vb, ok := b.(ArrayType)
        if ok && va.length == vb.length && va.item_type.index == vb.item_type.index {
            return true, a
        }
        return false, nil
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
        if va.global.index != vb.global.index {
            return false, nil
        }
        if len(va.generic_args) != len(vb.generic_args) {
            return false, nil
        }
        for arg, i in va.generic_args {
            if arg.index != vb.generic_args[i].index {
                return false, nil
            }
        }
        if va.initialised_type != unknown_type {
            assert(vb.initialised_type == unknown_type)
            return true, va
        }
        return true, vb
    case:
        panic("Unreachable")
    }
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
    return true
}

