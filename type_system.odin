package main

import "base:runtime"

content_types :: []string{}

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
unknown_type :: Type{max(u32) - 11} // TODO: Ideally `unknown_type` would not be necersarry
type_type :: Type{max(u32) - 12}
any_type :: Type{max(u32) - 13}
imported_file_type :: Type{max(u32) - 14} // TODO: Create a struct type for the type of imported files rather than using `imported_file_type`
max_index :: max(u32) - 15

dynamic_array_of_strings :: Type{0} // []String
string_to_nil_type :: Type{1} // (String)
string_string_to_nil_type :: Type{2} // (String, String)
string_to_string_type :: Type{3} // (String) -> String
string_any_ordered_hashmap_type :: Type{4} // OrderedHashMap[String, Any]
no_args_to_nil_type :: Type{5} // () -> ()
array_of_strings_to_nil_type :: Type{6} // ([]String)
i64_to_nil_type :: Type{7} // (I64)
string_i64_to_string_type :: Type{8} // (String, I64) -> String
string_any_ordered_hashmap_and_string_to_string_type :: Type{9} // (OrderedHashMap[String, Any], String) -> String
string_to_bool_type :: Type{10} // (String) -> Bool
no_args_to_i64_type :: Type{11} // () -> I64
string_any_to_nil_type :: Type{12} // (String, Any) -> ()
string_to_any_type :: Type{13} // (String) -> Any

// {
//   contains: (String) -> Bool,
//   set: (String, Any) -> (),
//   get: (String) -> Any
// }
compiler_cache_type :: Type{14}

// {
//   emit_js_code: string_any_ordered_hashmap_and_string_to_string_type,
//   cache: compiler_cache_type,
// }
compiler_type :: Type{15}

compiler_to_i64_type :: Type{16} // (Compiler) -> I64

// {
//   url: String,
//   method: String,
// }
http_request_type :: Type{17}

// {body: String}
http_response_body_type :: Type{18}

// TODO: Add more response types:
// - Ico
// - Gif
// - Jpeg
// - Js
// - Json
// - Png
// - Svg
// - Url_Encoded
// - Xml
// - Zip
// - Wasm
//
// <
//   .Plain{body: String},
//   .Css{body: String},
//   .Html{body: String},
// >
http_response_type :: Type{19}

response_type_variant_index_to_content_type :: proc(variant_index: uint) -> string {
    switch variant_index {
    case 0:
        return "application/octet-stream"
    case 1:
        return "text/css"
    case 2:
        return "text/html"
    case:
        panic("Unreachable")
    }
}

// (HttpRequest) -> HttpResponse
http_request_handler_type :: Type{20}

// (HttpRequestHandler) -> ()
http_request_handler_to_nil_type :: Type{21}

// {
//   set_handler: (HttpRequestHandler) -> (),
//   listen_and_serve: () -> (),
//   port: I64,
// }
http_server_type :: Type{22}

// () -> HttpServer
no_args_to_http_server_type :: Type{23}

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

    array_with_string_any_type := make([]Type, 2)
    array_with_string_any_type[0] = string_type
    array_with_string_any_type[1] = any_type

    array_with_bool_type := make([]Type, 1)
    array_with_bool_type[0] = bool_type

    array_with_any_type := make([]Type, 1)
    array_with_any_type[0] = any_type

    array_with_http_request := make([]Type, 1)
    array_with_http_request[0] = http_request_type

    array_with_http_response := make([]Type, 1)
    array_with_http_response[0] = http_response_type

    array_with_http_request_handler := make([]Type, 1)
    array_with_http_request_handler[0] = http_request_handler_type

    array_with_http_server := make([]Type, 1)
    array_with_http_server[0] = http_server_type

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
    assert(
        string_to_bool_type ==
        create_type(&out, FuncType{array_with_string_type, array_with_bool_type}).type,
    )
    assert(no_args_to_i64_type == create_type(&out, FuncType{nil, array_with_i64_type}).type)
    assert(
        string_any_to_nil_type ==
        create_type(&out, FuncType{array_with_string_any_type, nil}).type,
    )
    assert(
        string_to_any_type ==
        create_type(&out, FuncType{array_with_string_type, array_with_any_type}).type,
    )

    compiler_cache_fields := make(#soa[]StructField(Type), 3)
    compiler_cache_fields[0] = StructField(Type) {
        IdentAndPos{"contains", unknown_pos},
        string_to_bool_type,
    }
    compiler_cache_fields[1] = StructField(Type) {
        IdentAndPos{"set", unknown_pos},
        string_any_to_nil_type,
    }
    compiler_cache_fields[2] = StructField(Type) {
        IdentAndPos{"get", unknown_pos},
        string_to_any_type,
    }
    compiler_cache_fields_map: map[string]uint
    compiler_cache_fields_map["contains"] = 0
    compiler_cache_fields_map["set"] = 1
    compiler_cache_fields_map["get"] = 2
    assert(
        compiler_cache_type ==
        create_type(&out, Struct(Type, Type){unknown_type, compiler_cache_fields_map, compiler_cache_fields}).type,
    )

    compiler_fields := make(#soa[]StructField(Type), 2)
    compiler_fields[0] = StructField(Type) {
        IdentAndPos{"emit_js_code", unknown_pos},
        string_any_ordered_hashmap_and_string_to_string_type,
    }
    compiler_fields[1] = StructField(Type){IdentAndPos{"cache", unknown_pos}, compiler_cache_type}
    compiler_fields_map: map[string]uint
    compiler_fields_map["emit_js_code"] = 0
    compiler_fields_map["cache"] = 1
    assert(
        compiler_type ==
        create_type(&out, Struct(Type, Type){unknown_type, compiler_fields_map, compiler_fields}).type,
    )

    assert(
        compiler_to_i64_type ==
        create_type(&out, FuncType{array_with_compiler_type, array_with_i64_type}).type,
    )

    http_request_type_fields := make(#soa[]StructField(Type), 2)
    http_request_type_fields[0] = StructField(Type){IdentAndPos{"url", unknown_pos}, string_type}
    http_request_type_fields[1] = StructField(Type) {
        IdentAndPos{"method", unknown_pos},
        string_type,
    }
    http_request_type_fields_map: map[string]uint
    http_request_type_fields_map["url"] = 0
    http_request_type_fields_map["method"] = 1
    assert(
        http_request_type ==
        create_type(&out, Struct(Type, Type){unknown_type, http_request_type_fields_map, http_request_type_fields}).type,
    )

    http_response_body_fields := make(#soa[]StructField(Type), 1)
    http_response_body_fields[0] = StructField(Type){IdentAndPos{"body", unknown_pos}, string_type}
    http_response_body_fields_map: map[string]uint
    http_response_body_fields_map["body"] = 0
    assert(
        http_response_body_type ==
        create_type(&out, Struct(Type, Type){unknown_type, http_response_body_fields_map, http_response_body_fields}).type,
    )

    http_response_type_variants := make(#soa[]SumTypeVariant(Type), 3)
    http_response_type_variants[0] = SumTypeVariant(Type) {
        IdentAndPos{"Plain", unknown_pos},
        http_response_body_type,
    }
    http_response_type_variants[1] = SumTypeVariant(Type) {
        IdentAndPos{"Css", unknown_pos},
        http_response_body_type,
    }
    http_response_type_variants[2] = SumTypeVariant(Type) {
        IdentAndPos{"Html", unknown_pos},
        http_response_body_type,
    }
    http_response_type_variants_map: map[string]uint
    http_response_type_variants_map["Plain"] = 0
    http_response_type_variants_map["Css"] = 1
    http_response_type_variants_map["Html"] = 2
    assert(
        http_response_type ==
        create_type(&out, SumType(Type){http_response_type_variants_map, http_response_type_variants}).type,
    )

    assert(
        http_request_handler_type ==
        create_type(&out, FuncType{array_with_http_request, array_with_http_response}).type,
    )

    assert(
        http_request_handler_to_nil_type ==
        create_type(&out, FuncType{array_with_http_request_handler, nil}).type,
    )

    http_server_fields := make(#soa[]StructField(Type), 3)
    http_server_fields[0] = StructField(Type) {
        IdentAndPos{"set_handler", unknown_pos},
        http_request_handler_to_nil_type,
    }
    http_server_fields[1] = StructField(Type) {
        IdentAndPos{"listen_and_serve", unknown_pos},
        no_args_to_nil_type,
    }
    http_server_fields[2] = StructField(Type){IdentAndPos{"port", unknown_pos}, i64_type}
    http_server_fields_map: map[string]uint
    http_server_fields_map["set_handler"] = 0
    http_server_fields_map["listen_and_serve"] = 1
    http_server_fields_map["port"] = 2
    assert(
        http_server_type ==
        create_type(&out, Struct(Type, Type){unknown_type, http_server_fields_map, http_server_fields}).type,
    )

    assert(
        no_args_to_http_server_type ==
        create_type(&out, FuncType{nil, array_with_http_server}).type,
    )

    init_struct_type(&out, compiler_type, compiler_fields, compiler_fields_map)
    init_struct_type(&out, compiler_cache_type, compiler_cache_fields, compiler_cache_fields_map)
    init_struct_type(
        &out,
        http_request_type,
        http_request_type_fields,
        http_request_type_fields_map,
    )
    init_struct_type(
        &out,
        http_response_body_type,
        http_response_body_fields,
        http_response_body_fields_map,
    )
    init_struct_type(&out, http_server_type, http_server_fields, http_server_fields_map)

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

