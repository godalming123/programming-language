package main

import "base:runtime"
import "core:fmt"
import "core:os"
import "core:path/filepath"
import "core:strings"

VariableRef :: struct {
    nesting_level: uint,
    index:         uint,
}

Scope :: struct {
    // The length of these arrays should be the same
    variable_types:   [dynamic]Type,
    variable_is_muts: [dynamic]bool,
}

ArrayType :: struct {
    length:    u32, // 0 means dynamic length
    item_type: Type,
}

FunctionType :: enum {
    Normal,
    // JsFunc,
    ComptimeFunc,
}

CheckerGlobalTypeWithoutGeneric :: struct {
    ast_node:   GlobalTypeWithoutGeneric,
    exact_type: Type,
}

CheckedGlobalRuntimeValue :: struct {
    type:         Type,
    inline_value: CheckedValue,
}

CheckedGlobalValue :: union {
    CheckedGlobalRuntimeValue,
    Import,
}

CheckerGlobalValue :: struct {
    ast_node: GlobalValue,
    value:    CheckedGlobalValue,
}

CheckerState :: struct {
    // The following fields do not change while checking
    files:                         []File,
    global_values:                 #soa[]CheckerGlobalValue,
    global_types_without_generics: #soa[]CheckerGlobalTypeWithoutGeneric,
    global_types_with_generics:    []GlobalTypeWithGeneric,

    // The following fields depend on the function currently being checked
    file:                          FileRef,
    func_type:                     FunctionType,
    return_types:                  []Type, // If the function does not return anything, then this is nil

    // The following fields depend on which variables are in scope
    scopes:                        [dynamic]Scope,
    variables_map:                 map[string]VariableRef,

    // The following fields change while checking
    types:                         Types,
    loop_index:                    uint,
    parent_loop_index:             uint, // Set to max(uint) when there is no parent loop
    diagnostics_info:              DiagnosticsInfo,
    // TODO: represent the order of the programmer controlled stack
}

CheckedFunction :: struct {
    type:      Type, // Always a function type
    variables: []Type,
    body:      []CheckedStatement,
}

StringLiteralValue :: distinct string
U8Value :: distinct u8
I64Value :: distinct i64
BooleanNotValue :: distinct ^CheckedValue
CheckedJoinedValues :: struct {
    join_method: UnitJoinMethod,
    val0:        ^CheckedValue,
    val1:        ^CheckedValue,
}
CheckedFunctionCall :: struct {
    function: ^CheckedValue,
    args:     []CheckedValue,
}
StructTypeInitFunc :: struct {
    type: Type,
}
SumTypeInitFunc :: struct {
    sum_type:      Type,
    variant_index: uint,
}
LengthOfArray :: struct {
    array: ^CheckedValue,
}
CheckedArrayAccess :: struct {
    // The code emitter might not emit code to sanity check the index
    array: ^CheckedValue,
    index: ^CheckedValue,
}
CheckedFieldAccess :: struct {
    value:       ^CheckedValue,
    field_index: uint,
}
BoolValue :: distinct bool
BuiltinFunction :: struct {
    index: u32,
}
StringsAreEqual :: struct {
    str0: ^CheckedValue,
    str1: ^CheckedValue,
}
NumberValue :: struct {
    value: BigInt,
}
ImportedFile :: struct {
    file_index: uint,
}
CompileTimeValue :: union {
    StringLiteralValue,
    NumberValue,
    BoolValue,
    Type,
    GlobalTypeWithGenericRef,
}
CheckedValue :: union {
    CompileTimeValue,
    ToString,
    VariableRef,
    BooleanNotValue,
    CheckedJoinedValues,
    CheckedFunctionCall,
    StructTypeInitFunc,
    SumTypeInitFunc,
    BuiltinFunction,
    CheckedArrayAccess,
    CheckedFieldAccess,
    // CheckedJsFunctionCall,
    LengthOfArray,
    StringsAreEqual,
    FuncDefinitionRef,
}

FuncType :: struct {
    args:         []Type,
    return_types: []Type,
    type:         FunctionType,
}

CharGroup :: enum {
    Underscore,
    LowerCase,
    UpperCase,
    Digit,
    Unknown,
}

get_character_group :: proc(c: byte) -> CharGroup {
    if 'a' <= c && c <= 'z' {
        return .LowerCase
    } else if c == '_' {
        return .Underscore
    } else if 'A' <= c && c <= 'Z' {
        return .UpperCase
    } else if '0' <= c && c <= '9' {
        return .Digit
    } else {
        return .Unknown
    }
}

expect_snake_case :: proc(s: ^CheckerState, expected: string, ident: IdentAndPos) {
    i: uint = 0
    state: enum {
        InUppercaseBlock,
        InLowercaseBlock,
        NotInBlock,
    } = .NotInBlock
    for i < len(ident.ident) {
        switch get_character_group(ident.ident[i]) {
        case .LowerCase:
            switch state {
            case .NotInBlock:
                state = .InLowercaseBlock
            case .InLowercaseBlock:
            case .InUppercaseBlock:
                warn(
                    s,
                    ident.pos + i,
                    "Expected %s to be `snake_case`, got `%s`\nUnexpected lowercase letter '%c' in an uppercase block of a snake case identifier\nExpected an underscore, a number, or an uppercase letter",
                    expected,
                    ident.ident,
                    ident.ident[i],
                )
                return
            }
        case .UpperCase:
            switch state {
            case .NotInBlock:
                state = .InUppercaseBlock
            case .InUppercaseBlock:
            case .InLowercaseBlock:
                warn(
                    s,
                    ident.pos + i,
                    "Expected %s to be `snake_case`, got `%s`\nUnexpected uppercase letter '%c' in a lowercase block of a snake case identifier\nExpected an underscore, a number, or a lowercase letter",
                    expected,
                    ident.ident,
                    ident.ident[i],
                )
                return
            }
        case .Digit:
        case .Underscore:
            state = .NotInBlock
        case .Unknown:
            warn(
                s,
                ident.pos + i,
                "Unexpected character '%c' in identifier `%s`",
                ident.ident[i],
                ident.ident,
            )
            return
        }
        i += 1
    }
    return
}

// The boolean returned is whether the identifier is camel case
expect_camel_case :: proc(s: ^CheckerState, expected: string, ident: IdentAndPos) {
    if get_character_group(ident.ident[0]) != .UpperCase {
        warn(
            s,
            ident.pos,
            "Expected %s to be `CamelCase`, got `%s`\nFirst character in a camel case identifier must be an uppercase letter\nGot '%c'",
            expected,
            ident.ident,
            ident.ident[0],
        )
        return
    }
    for c, i in ident.ident[1:] {
        switch get_character_group(u8(c)) {
        case .Underscore:
            warn(
                s,
                ident.pos + uint(i) + 1,
                "Expected %s to be `CamelCase`, got `%s`\nCannot have `_` in a camel case identifier",
                ident.ident,
                expected,
            )
            return
        case .LowerCase, .UpperCase, .Digit:
        case .Unknown:
            warn(
                s,
                ident.pos + uint(i) + 1,
                "Unexpected character '%c' in identifier `%s`",
                ident.ident[i],
                ident.ident,
            )
            return
        }
    }
    return
}

no_generic_arg :: map[string]Type{}

check_struct_type :: proc(
    s: ^CheckerState,
    type: Struct(Unit, struct {}),
    generic_args: map[string]Type,
) -> Type {
    field_types := make([]Type, len(type.fields))
    ok := true
    for field, i in type.fields {
        expect_snake_case(s, "the name of a struct field", field.name)
        field_types[i] = check_type(s, field.type, generic_args)
        if field_types[i] == invalid_type {
            ok = false
        }
    }
    if !ok {
        return invalid_type
    }

    fields: #soa[]StructField(Type) = soa_zip(type.fields.name[:len(type.fields)], field_types)
    created := create_type(&s.types, Struct(Type, Type){unknown_type, type.fields_map, fields})
    if created.type_value.(Struct(Type, Type)).extra_data != unknown_type {
        return created.type
    }

    return_types := make([]Type, 1)
    return_types[0] = created.type

    created2 := create_type(
        &s.types,
        Struct(Type, Type) {
            create_type(&s.types, FuncType{field_types, return_types, .Normal}).type,
            type.fields_map,
            fields,
        },
    )
    assert(created.type == created2.type)
    return created.type
}

check_function_type :: proc(
    s: ^CheckerState,
    inputs: []Unit,
    output: Unit, // if the function has no output, then `output` is `Unit{}`
    type: FunctionType,
    generic_args: map[string]Type,
) -> Type {
    ok := true

    args := make([]Type, len(inputs))
    for input, i in inputs {
        args[i] = check_type(s, input, generic_args)
        if args[i] == invalid_type {
            ok = false
        }
    }

    outputs: []Unit = ---
    if output.value == nil {
        outputs = nil
    } else if tuple, is_tuple := output.value.(Tuple); is_tuple {
        outputs = tuple.elements
    } else {
        outputs = make([]Unit, 1)
        outputs[0] = output
    }
    return_types := make([]Type, len(outputs))
    for output, i in outputs {
        return_types[i] = check_type(s, output, generic_args)
        if return_types[i] == invalid_type {
            ok = false
        }
    }

    if !ok {
        return invalid_type
    }

    return create_type(&s.types, FuncType{args, return_types, type}).type
}

// Returns nil if there are errors in the type
check_array_type :: proc(
    s: ^CheckerState,
    pos: uint,
    type: CallWithFrontedSquareBrackets,
    generic_args: map[string]Type,
) -> (
    ArrayType,
    bool,
) {
    length: u32 = 0
    if len(type.args) == 0 {
        length = 0
    } else if len(type.args) == 1 {
        body := make([dynamic]CheckedStatement)
        value := check_runtime_value(s, type.args[0], &body, i64_type)
        if value == nil {
            return ArrayType{}, false
        }
        compile_time_value, ok := value.(CompileTimeValue)
        if !ok {
            err(s, type.args[0].pos, "Expected a compile time value got a runtime value")
            return ArrayType{}, false
        }
        number := compile_time_value.(NumberValue)
        assert(len(body) == 0)
        length, ok = big_int_to_u32(number.value)
        if !ok {
            err(s, pos, "Expected an integer (n) where 0 < n <= max(u32)", type.args[0].pos)
            return ArrayType{}, false

        }
    } else {
        err(s, pos, "Expected either 0 or 1 unit inside `[]`, got %d units", len(type.args))
        return ArrayType{}, false
    }
    item_type := check_type(s, type.unit_being_called^, generic_args)
    if item_type == invalid_type {
        return ArrayType{}, false
    }
    return ArrayType{length, item_type}, true
}

// Returns `invalid_type` if there are errors in the type
check_type :: proc(
    s: ^CheckerState,
    type: Unit,
    generic_args: map[string]Type,
    loc := #caller_location,
) -> Type {
    when debug_checker {
        print_call(loc, "check_type")
    }
    body := make([dynamic]CheckedStatement)
    value := check_value(s, type, &body, type_type, generic_args)
    if value == nil {
        return invalid_type
    }
    assert(len(body) == 0)
    return value.(CompileTimeValue).(Type)
}

// A "runtime value" is any value which can be used at runtime
check_runtime_value :: proc(
    s: ^CheckerState,
    v: Unit,
    body: ^[dynamic]CheckedStatement,
    type: ExpectedType,
    loc := #caller_location,
) -> CheckedValue {
    when debug_checker {
        print_call(loc, "check_runtime_type")
    }
    out := check_value(s, v, body, type, no_generic_arg)
    comptime_value, is_comptime_value := out.(CompileTimeValue)
    #partial switch _ in comptime_value {
    case Type, GlobalTypeWithGenericRef, OrderedHashMapType:
        err(s, v.pos, "This value can only be used at compile time")
        return nil
    }
    return out
}

CheckedReturn :: struct {
    value: CheckedValue,
}

TwoValueOperation :: enum {
    IsEqual,
    LessThan,
    LessThanOrEqual,
}

CheckedIf :: struct {
    condition:  CheckedValue,
    if_block:   CheckedBlock,
    else_block: CheckedBlock,
}

// JsValue :: struct {
//     value: ^CheckedValue, // can be nil
//     str:   string,
// }

// CheckedJsFunctionCall :: struct {
//     function:  JsValue,
//     arguments: []CheckedValue,
// }
//
// CheckedJsAssignment :: struct {
//     destination: JsValue,
//     value:       CheckedValue,
// }

CheckedLoop :: struct {
    loop_index: uint,
    variables:  []Type,
    body:       []CheckedStatement,
    enter:      []CheckedStatement,
}

ContinueLoop :: struct {
    loop_index: uint,
}
BreakLoop :: struct {
    loop_index: uint,
}

CheckedBlock :: struct {
    variables: []Type,
    body:      []CheckedStatement,
}

MutationType :: enum {
    IncrementBy,
    DecrementBy,
    MultiplyBy,
    DivideBy,
    SetTo,
}

CheckedMutationDestination :: struct {
    variable: VariableRef, // the variable being mutated
    index:    CheckedValue, // if this is not nil, then `variable` is an array, and this is the index in that array which is being mutated
}

CheckedMutation :: struct {
    destination:   CheckedMutationDestination,
    mutation_type: MutationType,
    value:         CheckedValue, // The source
}

InlineArraySegment :: struct {
    array:        CheckedValue, // an array that should be copied into the `ArrayValue`
    array_length: CheckedValue,
}

SingleElemSegment :: struct {
    elem: CheckedValue, // a scalar value for an element in the `ArrayValue`
}

ArraySegment :: union {
    InlineArraySegment,
    SingleElemSegment,
}
// Cannot be a value and has to be a statement so that when something like
// `~my_array = append(my_array, 1)` is written, `check_value` creates a
// temporary variable that is used to allocate the expanded array, rather then
// setting `my_array` to a new allocation and then attempting to copy that
// uninitialised data onto itself.
CheckedArrayMutation :: struct {
    variable:      VariableRef, // the variable being mutated
    variable_type: ArrayType,
    segments:      []ArraySegment, // The source
}

ToStringFromType :: enum {
    BoolType,
    I64Type,
    I32Type,
    I16Type,
    I8Type,
    U64Type,
    U32Type,
    U16Type,
    U8Type,
}

ToString :: struct {
    from_type: ToStringFromType,
    value:     ^CheckedValue,
}

CheckedMatchBranch :: struct {
    block:     CheckedBlock,
    value_var: union {
        VariableRef,
    }, // May be nil
}

CheckedMatch :: struct {
    value:    VariableRef,
    branches: []CheckedMatchBranch, // The branch index is the variant index
}

CheckedStatement :: union {
    CheckedReturn,
    CheckedIf,
    CheckedLoop,
    ContinueLoop,
    BreakLoop,
    CheckedMutation,
    CheckedArrayMutation, // like `CheckedMutation`, except the value is an array
    CheckedFunctionCall,
    CheckedMatch,

    // TODO: Store where the statement is and tell the user where the statement is when it is reached
    UnreachableStatement,
}

// TODO: Rework this with a general Number type
type_is_numeric :: proc(s: ^CheckerState, type: Type) -> bool {
    switch type {
    case i64_type, i32_type, i16_type, i8_type, u64_type, u32_type, u16_type, u8_type:
        return true
    case:
        return false
    }
}

check_generic_type :: proc(
    s: ^CheckerState,
    pos: uint,
    generic_type_index: u32,
    generic_args: []Type,
    loc := #caller_location,
) -> Type {
    generic := s.global_types_with_generics[generic_type_index]
    if len(generic_args) != len(generic.generics) {
        argument_count_mismatch(s, pos, len(generic_args), len(generic.generics), generic.name)
        return invalid_type
    }

    created := create_type(
        &s.types,
        GenericTypeValue{generic_type_index, generic_args, unknown_type},
    )
    if created.result == .Merged {
        if created.type_value.(GenericTypeValue).initialised_type == invalid_type {
            return invalid_type
        }
        return created.type
    }

    old_file := s.file
    defer s.file = old_file
    s.file = generic.file
    generic_args_map := make(map[string]Type)
    for arg, i in generic.generics {
        assert(!(arg.ident in generic_args_map))
        generic_args_map[arg.ident] = generic_args[i]
    }
    initialised_type := check_type(s, generic.value, generic_args_map)
    created2 := create_type(
        &s.types,
        GenericTypeValue{generic_type_index, generic_args, initialised_type},
    )
    assert(created.type == created2.type)
    if initialised_type == invalid_type {
        return invalid_type
    }
    return created.type
}

initialise_global_type_without_generic :: proc(s: ^CheckerState, i: uint) -> Type {
    // TODO: Check for cycles
    type := s.global_types_without_generics[i]
    if type.exact_type != unknown_type {
        return type.exact_type
    }
    old_file := s.file
    s.file = type.ast_node.file
    checked_type := check_type(s, type.ast_node.value, no_generic_arg)
    s.global_types_without_generics[i].exact_type = checked_type
    s.file = old_file
    return checked_type
}

simplify_type :: proc(s: ^CheckerState, type: Type, loc := #caller_location) -> Type {
    when debug_checker {
        print_call(loc, "simplify_type")
        print_arg("type", type)
    }
    cur_type := type
    for {
        if generic, ok := get_type(s.types, cur_type).(GenericTypeValue); ok {
            cur_type = generic.initialised_type
        } else {
            return cur_type
        }
    }
}

// For `get_sum_type`, `get_struct_type`, and `get_func_type`, set pos to
// `max(uint)` to not report an error if it is not a sum/struct type

get_sum_type :: proc(
    s: ^CheckerState,
    pos: uint,
    type: Type,
    loc := #caller_location,
) -> (
    SumType(Type),
    Type,
    bool,
) {
    when debug_checker {
        print_call(loc, "get_sum_type")
        print_arg("pos", pos)
        print_arg("type", type)
    }
    simplified := simplify_type(s, type)
    sum_type, is_sum_type := get_type(s.types, simplified).(SumType(Type))
    if is_sum_type {
        when debug_checker {
            debug("returned SumType(Struct(Type)) is %#v", sum_type)
        }
        return sum_type, simplified, true
    }
    if pos != max(uint) {
        err(s, pos, "Expected a sum type, but got the type `%s`", type_to_string(s, type))
    }
    return SumType(Type){}, unknown_type, false
}

get_struct_type :: proc(s: ^CheckerState, pos: uint, type: Type) -> (Struct(Type, Type), bool) {
    simplified := simplify_type(s, type)
    struct_type, is_struct_type := get_type(s.types, simplified).(Struct(Type, Type))
    if is_struct_type {
        return struct_type, true
    }
    if pos != max(uint) {
        err(s, pos, "Expected a struct type, but got the type `%s`", type_to_string(s, type))
    }
    return Struct(Type, Type){}, false
}

// Always returns a function type
// Returns `invalid_type` on failure
get_func_type :: proc(s: ^CheckerState, pos: uint, value: ^CheckedValue, type: Type) -> Type {
    simplified := simplify_type(s, type)
    if simplified == type_type && value != nil {
        value_type := simplify_type(s, value.(CompileTimeValue).(Type))
        struct_type, is_struct := get_type(s.types, value_type).(Struct(Type, Type))
        if is_struct {
            value^ = StructTypeInitFunc{value_type}
            return struct_type.extra_data
        }
        err(
            s,
            pos,
            "The type `%s` cannot be converted to a function type",
            type_to_string(s, value_type),
        )
    } else if func_type, is_func := get_type(s.types, simplified).(FuncType); is_func {
        return simplified
    }
    if pos != max(uint) {
        err(s, pos, "Expected a func type, but got the type `%s`", type_to_string(s, type))
    }
    return invalid_type
}

type_is_subset :: proc(
    s: ^CheckerState,
    type: Type,
    superset: Type,
    loc := #caller_location,
) -> bool {
    when debug_checker {
        print_call(loc, "type_is_subset")
        debug("type: %v", get_type(s.types, type))
        debug("superset: %v", get_type(s.types, superset))
    }
    if type == superset {
        return true
    }
    if superset.index > max_index {
        return false
    }
    superset_type := get_type(s.types, superset)
    #partial switch superset_value in superset_type {
    case nil:
        panic("Unreachable")
    case:
        return false
    case SumType(Type):
        for variant in superset_value.variants {
            if variant.payload == type {
                return true
            }
        }
        return false
    case GenericTypeValue:
        return type_is_subset(s, type, superset_value.initialised_type)
    }
}

// For both `expect_type` and `expect_exact_type`
// - The boolean returned is whether the `got` type matches the `expected` type
// - TODO: Specify `extra_text` in all cases

expect_value_of_type :: proc(
    s: ^CheckerState,
    pos: uint,
    expected: ExpectedType,
    got_value: ^CheckedValue,
    got_type: Type,
    extra_text: string,
    loc := #caller_location,
) -> bool {
    when debug_checker {
        print_call(loc, "expect_type")
        print_arg("expected", expected)
        print_arg("got", got_type)
    }
    switch e in expected {
    case AnyType:
        e.store^ = got_type
        return true
    case Type:
        return expect_exact_type(s, pos, e, got_type, extra_text)
    case FunctionWithExpectedReturnTypes:
        func_type := get_func_type(s, pos, got_value, got_type)
        if func_type == invalid_type {
            return false
        }
        func_info := get_type(s.types, func_type).(FuncType)
        if len(func_info.return_types) != len(e.expected_return_types) {
            err(
                s,
                pos,
                "Expected a function with %d return types but got one with %d return types",
                len(e.expected_return_types),
                len(func_info.return_types),
            )
            return false
        }
        for return_type, i in func_info.return_types {
            if !expect_value_of_type(
                s,
                pos,
                e.expected_return_types[i],
                nil,
                return_type,
                extra_text,
            ) {
                return false
            }
        }
        e.args_store^ = func_info.args
        e.type_store^ = func_info.type
        return true
    }
    panic("unreachable")
}

expect_exact_type :: proc(
    s: ^CheckerState,
    pos: uint,
    expected: Type,
    got: Type,
    extra_text: string,
    loc := #caller_location,
) -> bool {
    when debug_checker {
        print_call(loc, "expect_exact_type")
    }
    if !type_is_subset(s, got, expected) {
        err(
            s,
            pos,
            "Expected the type `%s` but got the type `%s`%s",
            type_to_string(s, expected),
            type_to_string(s, got),
            extra_text,
        )
        return false
    }
    return true
}

get_variable_type :: proc(
    s: ^CheckerState,
    variable: VariableRef,
    loc := #caller_location,
) -> Type {
    when debug_checker {
        print_call(loc, "get variable type")
    }
    scope := s.scopes[variable.nesting_level]
    return scope.variable_types[variable.index]
}

type_to_string :: proc(s: ^CheckerState, t: Type, loc := #caller_location) -> string {
    when debug_checker {
        print_call(loc, "type_to_string")
    }
    builder := strings.builder_make()
    build_type_string(s, &builder, t)
    return strings.to_string(builder)
}

build_struct_string :: proc(s: ^CheckerState, b: ^strings.Builder, type: Struct(Type, Type)) {
    strings.write_byte(b, '{')
    first_field := true
    for field in type.fields {
        if !first_field {
            strings.write_string(b, ", ")
        }
        first_field = false
        strings.write_string(b, field.name.ident)
        strings.write_string(b, ": ")
        build_type_string(s, b, field.type)
    }
    strings.write_byte(b, '}')
}

build_type_string :: proc(
    s: ^CheckerState,
    b: ^strings.Builder,
    t: Type,
    loc := #caller_location,
) {
    when debug_checker {
        print_call(loc, "build type string")
    }
    // TODO: Format the string better
    switch t {
    case string_type:
        strings.write_string(b, "String")
    case i64_type:
        strings.write_string(b, "I64")
    case i32_type:
        strings.write_string(b, "I32")
    case i16_type:
        strings.write_string(b, "I16")
    case i8_type:
        strings.write_string(b, "I8")
    case u64_type:
        strings.write_string(b, "U64")
    case u32_type:
        strings.write_string(b, "U32")
    case u16_type:
        strings.write_string(b, "U16")
    case u8_type:
        strings.write_string(b, "U8")
    case bool_type:
        strings.write_string(b, "Bool")
    case type_type:
        strings.write_string(b, "Type")
    case invalid_type:
        strings.write_string(b, "invalid_type")
    case unknown_type:
        strings.write_string(b, "unknown_type")
    case:
        switch tv in get_type(s.types, t) {
        case Struct(Type, Type):
            build_struct_string(s, b, tv)
        case SumType(Type):
            strings.write_byte(b, '<')
            first_variant := true
            for variant in tv.variants {
                if !first_variant {
                    strings.write_string(b, ", ")
                }
                first_variant = false
                strings.write_string(b, variant.name.ident)
                build_struct_string(s, b, get_type(s.types, variant.payload).(Struct(Type, Type)))
            }
            strings.write_byte(b, '>')
        case GenericTypeValue:
            strings.write_string(b, s.global_types_with_generics[tv.generic_type_index].name)
            strings.write_byte(b, '[')
            first_arg := true
            for arg in tv.generic_args {
                if !first_arg {
                    strings.write_string(b, ", ")
                }
                build_type_string(s, b, arg)
                first_arg = false
            }
            strings.write_byte(b, ']')
        case FuncType:
            switch tv.type {
            case .Normal:
            // case .JsFunc:
            //     strings.write_string(b, "#js ")
            case .ComptimeFunc:
                strings.write_string(b, "#comptime ")
            }
            strings.write_byte(b, '(')
            for arg, index in tv.args {
                // TODO: Print the name and whether the arg is mutable
                build_type_string(s, b, arg)
                if index + 1 != len(tv.args) {
                    strings.write_string(b, ", ")
                }
            }
            strings.write_string(b, ")")
            switch len(tv.return_types) {
            case 0:
            case 1:
                strings.write_string(b, " -> ")
                build_type_string(s, b, tv.return_types[0])
            case:
                strings.write_string(b, " -> (")
                first_return_type := true
                for return_type in tv.return_types {
                    if first_return_type == false {
                        strings.write_string(b, ", ")
                    }
                    first_return_type = false
                    build_type_string(s, b, return_type)
                }
                strings.write_byte(b, ')')
            }
        case ArrayType:
            strings.write_byte(b, '[')
            if tv.length != 0 {
                strings.write_uint(b, uint(tv.length))
            }
            strings.write_byte(b, ']')
            build_type_string(s, b, tv.item_type)
        case nil:
            panic("Unreachable")
        }
    }
}

pop_scope :: proc(s: ^CheckerState, loc := #caller_location) {
    when debug_checker {
        print_call(loc, "pop_scope")
    }
    pop(&s.scopes)
    for var_name, var_ref in s.variables_map {
        if var_ref.nesting_level == len(s.scopes) {
            delete_key(&s.variables_map, var_name)
        } else {
            assert(var_ref.nesting_level < len(s.scopes))
        }
    }
}

get_array_type :: proc(
    s: ^CheckerState,
    pos: uint,
    description: string,
    type_unsimplified: Type,
) -> (
    ArrayType,
    bool,
) {
    type := simplify_type(s, type_unsimplified)
    if out, is_array := get_type(s.types, type).(ArrayType); is_array {
        return out, true
    }
    err(
        s,
        pos,
        "%s is of type `%s`\nExpected an array type",
        description,
        type_to_string(s, type_unsimplified),
    )
    return ArrayType{}, false
}

// The `CheckedValue` returned is the value of the destination array index
get_expected_value_type :: proc(
    s: ^CheckerState,
    var_name: IdentAndPos,
    var_type: Type,
    array_index: ^Unit,
    body: ^[dynamic]CheckedStatement,
) -> (
    Type,
    CheckedValue,
    bool,
) {
    if array_index == nil {
        return var_type, nil, true
    }
    warn(s, array_index.pos, "This array access is not bounds checked\nTODO: Bounds checks")
    desc := fmt.aprintf("The variable `%s`", var_name)
    defer delete(desc)
    array, ok := get_array_type(s, var_name.pos, desc, var_type)
    if !ok {
        return unknown_type, nil, false
    }
    expected_type: Type = i64_type
    index_value := check_runtime_value(s, array_index^, body, expected_type)
    if index_value == nil {
        return array.item_type, nil, false
    }
    return array.item_type, index_value, true
}

check_mutation :: proc(
    s: ^CheckerState,
    destination: VariableDest,
    mutation_type: MutationType,
    value_type: Type,
    value_pos: uint,
    body: ^[dynamic]CheckedStatement,
    loc := #caller_location,
) -> (
    CheckedMutationDestination,
    MutationType,
    bool,
) {
    when debug_checker {
        print_call(loc, "check_mutation")
    }
    switch destination.type {
    case .Mutated:
        var_ref, ok := s.variables_map[destination.name.ident]
        if !ok {
            err(
                s,
                destination.name.pos,
                "The variable `%s` is not defined",
                destination.name.ident,
            )
            return CheckedMutationDestination{}, .SetTo, false
        }
        if s.scopes[var_ref.nesting_level].variable_is_muts[var_ref.index] == false {
            err(
                s,
                destination.name.pos,
                "The variable `%s` is not mutable",
                destination.name.ident,
            )
            return CheckedMutationDestination{}, .SetTo, false
        }
        var_type := get_variable_type(s, var_ref)
        expected_value_type, index_value, dest_ok := get_expected_value_type(
            s,
            destination.name,
            var_type,
            destination.array_index,
            body,
        )
        if expected_value_type != unknown_type {
            if !expect_value_of_type(s, value_pos, expected_value_type, nil, value_type, "") {
                return CheckedMutationDestination{}, .SetTo, false
            }
        }
        if !dest_ok {
            return CheckedMutationDestination{}, .SetTo, false
        }
        if mutation_type != .SetTo {
            if !type_is_numeric(s, value_type) {
                err(
                    s,
                    value_pos,
                    "Cannot perform numeric mutation on non-numeric type `%s`",
                    type_to_string(s, value_type),
                )
                return CheckedMutationDestination{}, .SetTo, false
            }
        }
        return CheckedMutationDestination{var_ref, index_value}, mutation_type, true
    case .Constant, .Mutable:
        if mutation_type != .SetTo {
            err(s, destination.name.pos, "Expected variable assignment to be done with `=`")
            return CheckedMutationDestination{}, .SetTo, false
        }
        variable_is_mutable := destination.type == .Mutable
        variable, variable_ok := add_variable(s, value_type, variable_is_mutable, destination.name)
        if !variable_ok {
            return CheckedMutationDestination{}, .SetTo, false
        }
        return CheckedMutationDestination{variable, nil}, .SetTo, true
    case .ConstantAddedToPcs, .MutableAddedToPcs:
        err(s, destination.name.pos, "TODO: Figure out what to do with old code")
        return CheckedMutationDestination{}, .SetTo, false
    }
    panic("Unreachable")
}

// The boolean returned is whether the block checked successfully
check_block :: proc(
    s: ^CheckerState,
    block: []Statement,
    body: ^[dynamic]CheckedStatement,
    loc := #caller_location,
) -> (
    []Type,
    bool,
) {
    when debug_checker {
        print_call(loc, "check block")
    }
    assert(
        len(s.scopes[len(s.scopes) - 1].variable_types) ==
        len(s.scopes[len(s.scopes) - 1].variable_is_muts),
    )
    for stmt, stmt_index in block {
        switch value in stmt.value {

        case VariableManagement:
            value_type := unknown_type
            checked_value := check_runtime_value(s, value.value, body, AnyType{&value_type})
            if len(value.destination) != 1 {
                err(
                    s,
                    stmt.position,
                    "TODO: Handle variable management where len(value.destination) != 1",
                )
                return nil, false
            }
            if checked_value == nil {
                return nil, false
            }
            mutation_dest, mutation_type, mutation_ok := check_mutation(
                s,
                value.destination[0],
                value.mutation_type,
                value_type,
                value.value.pos,
                body,
            )
            if !mutation_ok {
                return nil, false
            }
            append_elem(body, CheckedMutation{mutation_dest, mutation_type, checked_value})

        case CallWithBrackets:
            call, call_ok := check_function_call(s, stmt.position, value, body, nil)
            if !call_ok {
                return nil, false
            }
            append_elem(body, call)

        case ConditionControlledLoop:
            append_elem(&s.scopes, Scope{})
            defer pop_scope(s)
            old_parent_loop_index := s.parent_loop_index
            defer s.parent_loop_index = old_parent_loop_index
            loop_index := s.loop_index
            s.parent_loop_index = loop_index
            s.loop_index += 1
            condition := check_runtime_value(s, value.condition, body, bool_type)

            loop_body_array := make([dynamic]CheckedStatement)
            exit_loop := make([]CheckedStatement, 1)
            exit_loop[0] = BreakLoop{loop_index}
            condition_check := CheckedIf{condition, CheckedBlock{}, CheckedBlock{nil, exit_loop}}
            if value.type == .WhileLoop {
                append_elem(&loop_body_array, condition_check)
            }

            loop_variables, loop_body_ok := check_block(s, value.body, &loop_body_array)
            if condition == nil || !loop_body_ok {
                return nil, false
            }

            if value.type == .DoWhileLoop {
                append_elem(&loop_body_array, condition_check)
            }

            append_elem(body, CheckedLoop{loop_index, loop_variables, loop_body_array[:], nil})

        case ForInLoop:
            append_elem(&s.scopes, Scope{})
            defer pop_scope(s)
            old_parent_loop_index := s.parent_loop_index
            defer s.parent_loop_index = old_parent_loop_index
            loop_index := s.loop_index
            s.parent_loop_index = loop_index
            s.loop_index += 1
            loop_body_array := make([dynamic]CheckedStatement)
            loop_enter: []CheckedStatement
            loop_end: []CheckedStatement
            switch iter in value.iterator {
            case Unit:
                type := unknown_type
                v := check_runtime_value(s, iter, body, AnyType{&type})
                if v == nil {
                    return nil, false
                }
                array, ok := get_array_type(s, iter.pos, "The value being iterated over", type)
                if !ok {
                    return nil, false
                }
                array_item_type: Type = array.item_type
                if value.variables[2].ident != "" {
                    err(
                        s,
                        stmt.position,
                        "You can only capture at most 2 variables from iterating over an array",
                    )
                    return nil, false
                }
                elem_ref, elem_ok := add_variable(s, array_item_type, false, value.variables[0])
                index_ref, index_ok := add_variable(s, i64_type, false, value.variables[1])
                if !elem_ok || !index_ok {
                    return nil, false
                }
                loop_enter = make([]CheckedStatement, 1)
                loop_enter[0] = CheckedMutation {
                    CheckedMutationDestination{index_ref, nil},
                    .SetTo,
                    CompileTimeValue(NumberValue{int_zero}),
                }
                if_block := make([]CheckedStatement, 1)
                if_block[0] = BreakLoop{loop_index}
                append_elem(
                    &loop_body_array,
                    CheckedIf {
                        create_joined_values(
                            .IsGreaterThanOrEqual,
                            index_ref,
                            length_of_array(array, v),
                        ),
                        CheckedBlock{nil, if_block},
                        CheckedBlock{},
                    },
                )
                append_elem(
                    &loop_body_array,
                    CheckedMutation {
                        CheckedMutationDestination{elem_ref, nil},
                        .SetTo,
                        CheckedArrayAccess{new_clone(v), new_clone(CheckedValue(index_ref))},
                    },
                )
                loop_end = make([]CheckedStatement, 1)
                loop_end[0] = CheckedMutation {
                    CheckedMutationDestination{index_ref, nil},
                    .IncrementBy,
                    CompileTimeValue(NumberValue{big_int_from_i64(1)}),
                }
            case NumericIterator:
                if value.variables[1].ident != "" || value.variables[2].ident != "" {
                    err(
                        s,
                        stmt.position,
                        "You can only capture at most one variable in a numeric iterator",
                    )
                    return nil, false
                }
                index_variable, var_ok := add_variable(
                    s,
                    i64_type, // TODO: Support types other than I64
                    false,
                    value.variables[0],
                )
                expected_type: Type = i64_type
                start := check_runtime_value(s, iter.start, &loop_body_array, expected_type)
                end := check_runtime_value(s, iter.end, &loop_body_array, expected_type)
                step: CheckedValue = ---
                if iter.step == nil {
                    step = CompileTimeValue(NumberValue{big_int_from_i64(1)})
                } else {
                    step = check_runtime_value(s, iter.step^, &loop_body_array, expected_type)
                }
                if !var_ok || start == nil || end == nil || step == nil {
                    return nil, false
                }
                loop_enter = make([]CheckedStatement, 1)
                loop_enter[0] = CheckedMutation {
                    CheckedMutationDestination{index_variable, nil},
                    .SetTo,
                    start,
                }
                if_block := make([]CheckedStatement, 1)
                if_block[0] = BreakLoop{loop_index}
                append_elem(
                    &loop_body_array,
                    CheckedIf {
                        create_joined_values(
                            iter.type == .IncludeEndValue ? .IsGreaterThan : .IsGreaterThanOrEqual,
                            index_variable,
                            end,
                        ),
                        CheckedBlock{nil, if_block},
                        CheckedBlock{},
                    },
                )
                loop_end = make([]CheckedStatement, 1)
                loop_end[0] = CheckedMutation {
                    CheckedMutationDestination{index_variable, nil},
                    .IncrementBy,
                    step,
                }
            }
            loop_variables, loop_body_ok := check_block(s, value.body, &loop_body_array)
            if !loop_body_ok {
                return nil, false
            }
            append_elems(&loop_body_array, ..loop_end)
            append_elem(
                body,
                CheckedLoop{loop_index, loop_variables, loop_body_array[:], loop_enter},
            )

        case IfElseStatement:
            expected_type: Type = bool_type
            condition := check_runtime_value(s, value.condition, body, expected_type)

            append_elem(&s.scopes, Scope{})
            if_block_array := make([dynamic]CheckedStatement)
            if_variables, if_block_ok := check_block(s, value.if_block, &if_block_array)
            if_block := CheckedBlock{if_variables, if_block_array[:]}
            pop_scope(s)

            append_elem(&s.scopes, Scope{})
            else_block_array := make([dynamic]CheckedStatement)
            else_variables, else_block_ok := check_block(s, value.else_block, &else_block_array)
            else_block := CheckedBlock{else_variables, else_block_array[:]}
            pop_scope(s)

            if condition == nil || !if_block_ok || !else_block_ok {
                return nil, false
            }
            append_elem(body, CheckedIf{condition, if_block, else_block})

        case ContinueStatement:
            if stmt_index + 1 != len(block) {
                err(s, stmt.position, "Continue statement must be last statement in block")
                return nil, false
            }
            if s.parent_loop_index == max(uint) {
                err(s, stmt.position, "Continue statement must go inside a loop")
                return nil, false
            }
            append_elem(body, ContinueLoop{s.parent_loop_index})

        case UnreachableStatement:
            if stmt_index + 1 != len(block) {
                err(s, stmt.position, "Unreachable statement must be last statement in block")
                return nil, false
            }
            append_elem(body, UnreachableStatement{})

        case ReturnStatement:
            if stmt_index + 1 != len(block) {
                err(s, stmt.position, "Return statement must be last statement in block")
                return nil, false
            }
            if len(value) != len(s.return_types) {
                err(
                    s,
                    stmt.position,
                    "Function returns %d values, but %d values given",
                    len(s.return_types),
                    len(value),
                )
                return nil, false
            }
            switch len(value) {
            case 0:
                append_elem(body, CheckedReturn{nil})
            case 1:
                v := check_runtime_value(s, value[0], body, s.return_types[0])
                if v == nil {
                    return nil, false
                }
                append_elem(body, CheckedReturn{v})
            case:
                err(
                    s,
                    stmt.position,
                    "Can only have <=1 value in return statement (TODO: add support for returning >1 values)",
                )
            }

        case YieldStatement:
            err(s, stmt.position, "TODO: Handle yield statement")
            return nil, false

        case MatchStatement:
            val_type := unknown_type
            val := check_runtime_value(s, value.value, body, AnyType{&val_type})
            if val == nil {
                return nil, false
            }

            val_sum_type, val_type_type, val_sum_type_ok := get_sum_type(
                s,
                value.value.pos,
                val_type,
            )
            if !val_sum_type_ok {
                return nil, false
            }

            variable_ref := add_unnamed_variable(s, val_type, false)
            append_elem(
                body,
                CheckedMutation{CheckedMutationDestination{variable_ref, nil}, .SetTo, val},
            )

            variant_has_branch := make([]bool, len(val_sum_type.variants))
            variant_branch_positions := make([]uint, len(val_sum_type.variants))

            branches := make([]CheckedMatchBranch, len(val_sum_type.variants))
            for branch in value.branches {
                append_elem(&s.scopes, Scope{})
                defer pop_scope(s)

                branch_type: Unit = ---
                variable_name: ^Unit = nil
                if joined, is_joined := branch.label.value.(JoinedUnits); is_joined {
                    if joined.join_method != .Colon {
                        err(
                            s,
                            branch.label.pos,
                            "Expected the join method to be `:`, got %v",
                            joined.join_method,
                        )
                        return nil, false
                    }
                    variable_name = joined.unit0
                    branch_type = joined.unit1^
                } else {
                    branch_type = branch.label
                }

                type_variable, is_variable := branch_type.value.(Ident)
                if !is_variable || len(type_variable) != 2 || type_variable[0].ident != "" {
                    err(
                        s,
                        branch_type.pos,
                        "Expected type variable without a generic type that starts with `.`",
                    )
                    return nil, false
                }

                variant_name := type_variable[1].ident
                variant_index, exists := val_sum_type.variants_map[variant_name]
                if !exists {
                    err(
                        s,
                        branch_type.pos,
                        "The sum type `%s` does not have the variant `.%s`",
                        type_to_string(s, val_type),
                        variant_name,
                    )
                    return nil, false
                }

                if variant_has_branch[variant_index] {
                    line, column := get_location(
                        s.files[s.file.index].file.code,
                        variant_branch_positions[variant_index],
                    )
                    err(
                        s,
                        branch_type.pos,
                        "The variant `.%s` already has a branch defined at line %d and column %d",
                        variant_name,
                        line,
                        column,
                    )
                    return nil, false
                }

                var: union {
                        VariableRef,
                    } = nil
                if variable_name != nil {
                    ident, is_ident := variable_name.value.(Ident)
                    if !is_ident || len(ident) != 1 {
                        err(s, variable_name.pos, "Expected an identifier without `.`")
                        return nil, false
                    }
                    var_ok: bool = ---
                    var, var_ok = add_variable(
                        s,
                        val_sum_type.variants[variant_index].payload,
                        false,
                        ident[0],
                    )
                    if !var_ok {
                        return nil, false
                    }
                }

                body := make([dynamic]CheckedStatement)
                variables, block_ok := check_block(s, branch.body, &body)
                if !block_ok {
                    return nil, false
                }

                branches[variant_index] = CheckedMatchBranch{CheckedBlock{variables, body[:]}, var}
                variant_has_branch[variant_index] = true
                variant_branch_positions[variant_index] = branch.label.pos
            }

            unhandled_variants := false
            for has_branch, i in variant_has_branch {
                if !has_branch {
                    err(
                        s,
                        stmt.position,
                        "Unhandled variant `.%s`",
                        val_sum_type.variants[i].name.ident,
                    )
                    unhandled_variants = true
                }
            }
            if unhandled_variants {
                return nil, false
            }
            append_elem(body, CheckedMatch{variable_ref, branches})

        }

        when debug_checker {
            debug("length of body is %d", len(body))
        }
    }
    return s.scopes[len(s.scopes) - 1].variable_types[:], true
}

// Returns nil if there was an error
check_array_index :: proc(
    s: ^CheckerState,
    pos: uint,
    args: []Unit,
    body: ^[dynamic]CheckedStatement,
) -> CheckedValue {
    warn(s, pos, "This array access is not bounds checked\nTODO: Bounds checks")
    if len(args) != 1 {
        err(
            s,
            pos,
            "Indexed accesses into an array must pass one value into the square brackets\nGot %d values",
            len(args),
        )
        return nil
    }
    // TODO: Support multi elem array access
    expected_type: Type = i64_type // TODO: Do not assume number type
    return check_runtime_value(s, args[0], body, expected_type)
}

value_err1 :: "Compiler cannot generate a `.` function without knowing the return type of the function"

check_namespaced_var_ref :: proc(
    s: ^CheckerState,
    namespace: FileRef,
    ref: Ident,
    index: int,
) -> (
    CheckedValue,
    Type,
    int,
) {
    file := s.files[namespace.index]
    global, global_exists := file.globals[ref[index].ident]
    if !global_exists {
        err(
            s,
            ref[index].pos,
            "The variable `%s` is not defined in the file `%s`",
            ref[index].ident,
            file.file.file_path,
        )
        return nil, invalid_type, 0
    }
    switch global_value in global.value {
    case:
        panic("Unreachable")
    case nil:
        panic("Unreachable")
    case GlobalValueRef:
        switch value in s.global_values[global_value.index].value {
        case:
            panic("Unreachable")
        case nil:
            err(
                s,
                ref[index].pos,
                "Either this global has not been defined yet, there was an error checking this global, or this type of global is not yet supported (TODO)",
            )
            return nil, invalid_type, 0
        case CheckedGlobalRuntimeValue:
            return value.inline_value, value.type, index + 1
        case Import:
            if index + 1 >= len(ref) {
                err(s, ref[index].pos, import_use_err)
                return nil, invalid_type, 0
            }
            return check_namespaced_var_ref(s, value.file, ref, index + 1)
        }
    case GlobalTypeWithGenericRef:
        return CompileTimeValue(global_value), unknown_type, index + 1
    case GlobalTypeWithoutGenericRef:
        initialised := initialise_global_type_without_generic(s, global_value.index)
        if initialised == invalid_type {
            return nil, invalid_type, 0
        }
        return CompileTimeValue(initialised), type_type, index + 1
    }
}

check_var_ref :: proc(
    s: ^CheckerState,
    ref: Ident,
    pos: uint,
    type: ExpectedType,
    body: ^[dynamic]CheckedStatement,
    generic_args: map[string]Type,
    loc := #caller_location,
) -> CheckedValue {
    when debug_checker {
        print_call(loc, "check_var_ref")
        print_arg("ref", ref)
        print_arg("type", type)
    }
    if len(ref) == 2 && ref[0].ident == "" {
        expected_return_type: Type = ---
        switch expected in type {
        case AnyType:
            err(s, pos, value_err1)
            return nil
        case Type:
            err(s, pos, "TODO: Generate `.` functions better")
            return nil
        case FunctionWithExpectedReturnTypes:
            if len(expected.expected_return_types) != 1 {
                err(
                    s,
                    pos,
                    "Compiler cannot generate a `.` function which generates %d return types",
                    len(expected.expected_return_types),
                )
                return nil
            }
            switch expected_return in expected.expected_return_types[0] {
            case AnyType, FunctionWithExpectedReturnTypes:
                err(s, pos, value_err1)
            case Type:
                expected_return_type = expected_return
            }
        }

        sum_type, type_type, sum_type_ok := get_sum_type(s, pos, expected_return_type)
        if !sum_type_ok {
            return nil
        }

        variant_index, exists := sum_type.variants_map[ref[1].ident]
        if !exists {
            err(
                s,
                pos,
                "The sum type `%s` does not have a variant called `%s`",
                type_to_string(s, expected_return_type),
                ref[1].ident,
            )
            return nil
        }
        func_ref :=
            get_type(s.types, sum_type.variants[variant_index].payload).(Struct(Type, Type)).extra_data
        if expect_value_of_type(s, pos, type, nil, func_ref, "") {
            // TODO: Use `StructTypeInitFunc` instead of `SumTypeInitFunc` if `type` is the struct type rather than the sum type
            return SumTypeInitFunc{type_type, variant_index}
        }
        return nil
        /*
        if len(variant.fields) != len(call.args) {
            argument_count_mismatch(
                s,
                pos,
                len(call.args),
                len(variant.fields),
                ..function_segments.ident[:len(function_segments)],
            )
            return nil
        }

        checked_args := make([]CheckedValue, len(call.args))
        args_ok := true
        for arg, i in call.args {
            expected_type := variant.fields[i].type
            when debug_checker {
                debug("expected_type is %#v", expected_type)
            }
            checked_args[i] = check_value(s, arg, body, &expected_type)
            if checked_args[i] == nil {
                args_ok = false
            }
        }
        if !args_ok {
            return nil
        }
        dest := add_unnamed_variable(s, type^, false)
        append_elem(body, CheckedSumTypeInitialisation{dest, type^, variant_index, checked_args})
        return dest
        */
    }

    out: CheckedValue = ---
    out_type: Type = ---
    start_i := 1

    if ref[0].ident != "" && ref[0].ident in generic_args {
        out = CompileTimeValue(generic_args[ref[0].ident])
        out_type = type_type
    } else if builtin_func_index, builtin_func_type := get_builtin_func_from_name(ref[0].ident);
       builtin_func_index != max(u32) {
        out = BuiltinFunction{builtin_func_index}
        out_type = builtin_func_type
    } else if builtin_type := get_builtin_type_from_name(ref[0].ident);
       builtin_type != unknown_type {
        out = CompileTimeValue(builtin_type)
        out_type = type_type
    } else if var_ref, ok := s.variables_map[ref[0].ident]; ok {
        out_type = get_variable_type(s, var_ref)
        out = var_ref
    } else if ref[0].ident == "compiler" {
        compiler_funcs :: "`compiler.emit_js_code`"
        if len(ref) == 1 {
            err(s, pos, "Expected " + compiler_funcs + " got just `compiler`")
            return nil
        }
        start_i = 2
        switch ref[1].ident {
        case "emit_js_code":
            out_type = comptime_u64_to_string_type
            out = BuiltinFunction{builtin_emit_js_code}
        case:
            err(s, pos, "Expected " + compiler_funcs + " got `compiler.%s`", ref[1].ident)
            return nil
        }
    } else {
        out, out_type, start_i = check_namespaced_var_ref(s, s.file, ref, 0)
        if out == nil {
            return nil
        }
    }
    for i := start_i; i < len(ref); i += 1 {
        extra_segment := ref[i]
        if extra_segment.ident == "len" {
            array, ok := get_array_type(s, extra_segment.pos, "The value before `.len`", out_type)
            if !ok {
                return nil
            }
            out_type = i64_type
            out = length_of_array(array, out)
            continue
        } else if extra_segment.ident == "to_str" {
            converted := to_str(s, extra_segment.pos, out, out_type)
            if converted == nil {
                return nil
            }
            out_type = string_type
            out = converted
            continue
        } else if extra_segment.ident == "function_id" {
            func_ref, is_func := out.(FuncDefinitionRef)
            if !is_func {
                err(
                    s,
                    extra_segment.pos,
                    "Can only use `.function_id` for compile-time known functions",
                )
                return nil
            }

            out_type = u64_type
            out = CompileTimeValue(NumberValue{big_int_from_i64(i64(func_ref.index))})
            continue
        }
        struct_type, ok := get_struct_type(s, ref[i].pos, out_type)
        if !ok {
            return nil
        }
        field_index, field_exists := struct_type.fields_map[extra_segment.ident]
        if !field_exists {
            err(
                s,
                extra_segment.pos,
                "The field `%s` does not exist on the struct type `%s`",
                extra_segment.ident,
                type_to_string(s, out_type),
            )
            return nil
        }
        out_type = struct_type.fields[field_index].type
        out = CheckedFieldAccess{new_clone(out), field_index}
    }
    if expect_value_of_type(s, pos, type, &out, out_type, "") {return out}
    return nil
}

check_array_initialisation :: proc(
    s: ^CheckerState,
    pos: uint,
    array_type_node: CallWithFrontedSquareBrackets,
    array_type_pos: uint,
    args: []Unit,
    body: ^[dynamic]CheckedStatement,
    expected_return_type: ExpectedType,
    loc := #caller_location,
) -> CheckedValue {
    when debug_checker {
        print_call(loc, "check_array_initialisation")
    }
    array_type_value, ok := check_array_type(s, array_type_pos, array_type_node, no_generic_arg)
    if !ok {
        return nil
    }
    array_type := create_type(&s.types, array_type_value).type
    if array_type_value.length != 0 && len(args) != int(array_type_value.length) {
        err(
            s,
            pos,
            "Type initialisation provides %d values\nType expects %d values",
            len(args),
            array_type_value.length,
        )
        return nil
    }
    array_segments := make([]ArraySegment, len(args))
    for arg, i in args {
        value := check_runtime_value(s, arg, body, array_type_value.item_type)
        if value == nil {
            ok = false
        } else {
            array_segments[i] = SingleElemSegment{value}
        }
    }
    if !ok {
        return nil
    }
    array_ref := add_unnamed_variable(s, array_type, false)
    append_elem(body, CheckedArrayMutation{array_ref, array_type_value, array_segments})
    if !expect_value_of_type(s, array_type_pos, expected_return_type, nil, array_type, "") {
        return nil
    }
    return array_ref
}

check_function_call :: proc(
    s: ^CheckerState,
    pos: uint,
    call: CallWithBrackets,
    body: ^[dynamic]CheckedStatement,
    expected_return_types: []ExpectedType,
    loc := #caller_location,
) -> (
    CheckedFunctionCall,
    bool,
) {
    when debug_checker {
        print_call(loc, "check_function_call")
    }

    func_args: []Type = ---
    func_type: FunctionType = ---
    when debug_checker {
        func_args = nil // So that `func_args` can be printed by `debug_arg` without causing a segfault
    }
    expected_type := FunctionWithExpectedReturnTypes{&func_args, &func_type, expected_return_types}
    value := check_runtime_value(s, call.unit_being_called^, body, expected_type)
    if value == nil {
        return CheckedFunctionCall{}, false
    }

    if s.func_type == .Normal && func_type == .ComptimeFunc {
        err(s, pos, function_err)
        return CheckedFunctionCall{}, false
    }

    if len(call.args) != len(func_args) {
        argument_count_mismatch(s, pos, len(call.args), len(func_args), "TODO")
        return CheckedFunctionCall{}, false
    }

    checked_args := make([]CheckedValue, len(call.args))
    for arg, i in call.args {
        arg_value := check_runtime_value(s, arg, body, Type(func_args[i]))
        if arg_value == nil {
            return CheckedFunctionCall{}, false
        }
        checked_args[i] = arg_value
    }

    return CheckedFunctionCall{new_clone(value), checked_args}, true
}

AnyType :: struct {
    store: ^Type,
}

FunctionWithExpectedReturnTypes :: struct {
    args_store:            ^[]Type,
    type_store:            ^FunctionType,
    expected_return_types: []ExpectedType,
}

ExpectedType :: union {
    AnyType,
    Type,
    FunctionWithExpectedReturnTypes,
}

check_value_with_markers :: proc(
    s: ^CheckerState,
    v: Unit,
    markers: []IdentAndPos,
    body: ^[dynamic]CheckedStatement,
    type: ExpectedType,
    generic_args: map[string]Type,
) -> CheckedValue {
    if len(markers) == 0 {
        return check_value(s, v, body, type, generic_args)
    }
    switch markers[0].ident {
    case "load":
        value := check_value_with_markers(s, v, markers[1:], body, string_type, generic_args)
        if value == nil {
            return nil
        }
        comptime_value, is_comptime := value.(CompileTimeValue)
        if !is_comptime {
            err(s, v.pos, "Expected a compile time known value")
            return nil
        }

        file := s.files[s.file.index].file
        joined, join_err := filepath.join(
            []string{file.dir_path, string(comptime_value.(StringLiteralValue))},
            context.allocator,
        )
        data, data_err := os.read_entire_file(joined, context.allocator)
        if data_err != nil {
            err(s, markers[0].pos, "Failed to read `%s`: %#v\n", joined, data_err)
            return nil
        }
        if !expect_value_of_type(s, markers[0].pos, type, nil, string_type, "") {
            return nil
        }
        return CompileTimeValue(StringLiteralValue(data))
    case "debug_ast":
        debug_unit(nil, v)
    case:
        warn(s, markers[0].pos, "TODO: Handle the `%s` marker", markers[0].ident)
    }

    return check_value_with_markers(s, v, markers[1:], body, type, generic_args)
}

// For `check_value` and `check_joined_unit_value`:
// - Returns `nil` if there are errors in the value
// - The `body` arg may be appended to with statements that should be executed
//   before the value is accessed

check_joined_unit_value :: proc(
    s: ^CheckerState,
    pos: uint,
    value: JoinedUnits,
    body: ^[dynamic]CheckedStatement,
    type: ExpectedType,
    generic_args: map[string]Type, // Used if the value is a type
) -> CheckedValue {
    // TODO: In lots of this code, `check_runtime_value` is used when the
    // operations should be performable on values that can only be used at
    // compile time, like a value of the type `type_type`
    array_err :: "Expected an array type\nGot the type `%s`"
    switch value.join_method {

    case .Colon:
        err(s, pos, "Cannot use `:` to join values")
        return nil

    case .Arrow:
        tuple, is_tuple := value.unit0.value.(Tuple)
        if !is_tuple {
            err(
                s,
                value.unit1.pos,
                "While checking function type: The unit before the `->` should be a tuple (for example `(String, U64)`)",
            )
            return CompileTimeValue(invalid_type)
        }
        out: CheckedValue = CompileTimeValue(
            check_function_type(s, tuple.elements, value.unit1^, .Normal, generic_args),
        )
        if expect_value_of_type(s, pos, type, &out, type_type, "") {
            return out
        }
        return nil

    case .BooleanAnd, .BooleanOr:
        val0 := check_value(s, value.unit0^, body, bool_type, no_generic_arg)
        val1 := check_value(s, value.unit1^, body, bool_type, no_generic_arg)
        if val0 == nil || val1 == nil {
            return nil
        }
        if expect_value_of_type(s, pos, type, nil, bool_type, "") {
            return create_joined_values(value.join_method, val0, val1)
        }
        return nil

    case .IsEqual, .IsNotEqual:
        t := invalid_type
        val0 := check_runtime_value(s, value.unit0^, body, AnyType{&t})
        if val0 == nil {
            return nil
        }
        val1 := check_runtime_value(s, value.unit1^, body, t)
        if val1 == nil {
            return nil
        }
        if !expect_value_of_type(s, pos, type, nil, bool_type, "") {
            return nil
        }
        t_simplified := simplify_type(s, t)
        if t_simplified == string_type {
            str_comp: CheckedValue = StringsAreEqual{new_clone(val0), new_clone(val1)}
            if value.join_method == .IsNotEqual {
                return create_not(str_comp)
            }
            return str_comp
        }
        return create_joined_values(value.join_method, val0, val1)

    case .Append:
        t: Type = unknown_type
        val0 := check_runtime_value(s, value.unit0^, body, AnyType{&t})
        if val0 == nil {
            return nil
        }
        length, item_type := check_array(s, value.unit0.pos, val0, t, array_err)
        if length == nil {
            return nil
        }
        val1 := check_runtime_value(s, value.unit1^, body, Type(item_type))
        if val1 == nil {
            return nil
        }
        return_type1 := ArrayType{0, item_type}
        return_type0 := create_type(&s.types, return_type1).type // TODO: Maybe `::` should be able to output fixed size arrays
        if expect_value_of_type(s, pos, type, nil, return_type0, "") {
            segments := make([]ArraySegment, 2)
            segments[0] = InlineArraySegment{val0, length}
            segments[1] = SingleElemSegment{val1}
            array_ref := add_unnamed_variable(s, return_type0, false)
            append_elem(body, CheckedArrayMutation{array_ref, return_type1, segments})
            return array_ref
        }
        return nil

    case .StringConcat:
        val0 := check_runtime_value(s, value.unit0^, body, string_type)
        val1 := check_runtime_value(s, value.unit1^, body, string_type)
        if val0 == nil || val1 == nil {
            return nil
        }
        if expect_value_of_type(s, pos, type, nil, string_type, "") {
            return create_joined_values(.StringConcat, val0, val1)
        }
        return nil

    case .Concat:
        type0: Type = ---
        type1: Type = ---
        val0 := check_runtime_value(s, value.unit0^, body, AnyType{&type0})
        val1 := check_runtime_value(s, value.unit1^, body, AnyType{&type1})
        if val0 == nil || val1 == nil {
            return nil
        }
        length0, item_type0 := check_array(s, value.unit0.pos, val0, type0, array_err)
        length1, item_type1 := check_array(s, value.unit1.pos, val1, type1, array_err)
        if length0 == nil || length1 == nil {
            return nil
        }
        if item_type0 != item_type1 {
            err(
                s,
                pos,
                "Array item type mismatch:\nItem type on left is %s\nItem type on right is %s",
                type_to_string(s, item_type0),
                type_to_string(s, item_type1),
            )
            return nil
        }
        return_type1 := ArrayType{0, item_type0}
        return_type := create_type(&s.types, return_type1).type // TODO: Maybe `++` should be able to output fixed size arrays
        if expect_value_of_type(s, pos, type, nil, return_type, "") {
            segments := make([]ArraySegment, 2)
            segments[0] = InlineArraySegment{val0, length0}
            segments[1] = InlineArraySegment{val1, length1}
            array_ref := add_unnamed_variable(s, return_type, false)
            append_elem(body, CheckedArrayMutation{array_ref, return_type1, segments})
            return array_ref
        }
        return nil

    case .IsGreaterThan, .IsGreaterThanOrEqual, .IsLessThan, .IsLessThanOrEqual:
        // TODO: Do not assume number types
        val0 := check_runtime_value(s, value.unit0^, body, i64_type)
        val1 := check_runtime_value(s, value.unit1^, body, i64_type)
        if val0 == nil || val1 == nil {
            return nil
        }
        if expect_value_of_type(s, pos, type, nil, bool_type, "") {
            return create_joined_values(value.join_method, val0, val1)
        }
        return nil

    case .Multiplication, .Subtraction, .Division, .Addition, .Modulo:
        // TODO: Do not assume number types
        val0 := check_runtime_value(s, value.unit0^, body, i64_type)
        val1 := check_runtime_value(s, value.unit1^, body, i64_type)
        if val0 == nil || val1 == nil {
            return nil
        }
        if expect_value_of_type(s, pos, type, nil, i64_type, "") {
            return create_joined_values(value.join_method, val0, val1)
        }
        return nil

    case:
        panic("Unreachable")
    }

}

import_use_err :: "Cannot use an import as a runtime value"

check_value :: proc(
    s: ^CheckerState,
    v: Unit,
    body: ^[dynamic]CheckedStatement, // Used if the value is a runtime value
    type: ExpectedType,
    generic_args: map[string]Type, // Used if the value is a type
    loc := #caller_location,
) -> CheckedValue {
    when debug_checker {
        print_call(loc, "check_value")
    }
    switch value in v.value {
    case:
        err(s, v.pos, "Internal error: got nil value in check_value")
        return nil

    case Struct(Unit, struct {}):
        out: CheckedValue = CompileTimeValue(check_struct_type(s, value, generic_args))
        if expect_value_of_type(s, v.pos, type, &out, type_type, "") {
            return out
        }
        return nil
    case CallWithFrontedSquareBrackets:
        array, ok := check_array_type(s, v.pos, value, generic_args)
        if !ok {
            return nil
        }
        if expect_value_of_type(s, v.pos, type, nil, type_type, "") {
            return CompileTimeValue(create_type(&s.types, array).type)
        }
        return nil
    case SumType(Struct(Unit, struct {})):
        variants: #soa[]SumTypeVariant(Type) = soa_zip(
            value.variants.name[:len(value.variants)],
            make([]Type, len(value.variants)),
        )
        ok := true
        for variant, i in value.variants {
            expect_camel_case(s, "the name of a sum type variant", variant.name)
            variants[i].payload = check_struct_type(s, variant.payload, generic_args)
            if variants[i].payload == invalid_type {
                ok = false
            }
        }
        if !ok {
            return nil
        }
        out: CheckedValue = CompileTimeValue(
            create_type(&s.types, SumType(Type){value.variants_map, variants}).type,
        )
        if expect_value_of_type(s, v.pos, type, &out, type_type, "") {
            return out
        }
        return nil

    case Import:
        err(s, v.pos, import_use_err)
        return nil

    case MarkedUnit:
        return check_value_with_markers(s, value.value^, value.markers, body, type, generic_args)

    case Tuple:
        if len(value.elements) != 1 {
            err(
                s,
                v.pos,
                "Only tuples with one element are supported\nThis tuple has %d elements",
                len(value.elements),
            )
            return nil
        }
        return check_runtime_value(s, value.elements[0], body, type)

    case CallWithSquareBrackets:
        // TODO
        being_called_type := invalid_type
        being_called_value := check_value(
            s,
            value.unit_being_called^,
            body,
            AnyType{&being_called_type},
            generic_args,
        )
        if being_called_type == unknown_type {
            generic_type_ref := being_called_value.(CompileTimeValue).(GlobalTypeWithGenericRef)
            checked_args := make([]Type, len(value.args))
            ok := true
            for arg, i in value.args {
                checked_args[i] = check_type(s, arg, generic_args)
                if checked_args[i] == invalid_type {
                    ok = false
                }
            }
            if !ok {
                return nil
            }
            out_as_type := check_generic_type(s, v.pos, generic_type_ref.index, checked_args)
            if out_as_type == invalid_type {
                return nil
            }
            out: CheckedValue = CompileTimeValue(out_as_type)
            if expect_value_of_type(s, v.pos, type, &out, type_type, "") {
                return out
            }
            return nil
        }
        index_value := check_array_index(s, v.pos, value.args, body)
        if being_called_value == nil {
            return nil
        }
        array_type, ok := get_array_type(
            s,
            value.unit_being_called.pos,
            "The value",
            being_called_type,
        )
        if !ok {
            return nil
        }
        //array := get_array_type(s.array_types[:], &array_ref)
        //if array.length == 0 {
        //    err(
        //        s,
        //        value.array.pos,
        //        "TODO: Implement element access for dynamically sized arrays",
        //        type_to_string(s, array_type),
        //    )
        //    return nil, false
        //}
        if index_value == nil {
            return nil
        }
        if expect_value_of_type(s, v.pos, type, nil, array_type.item_type, "") {
            return CheckedArrayAccess{new_clone(being_called_value), new_clone(index_value)}
        }
        return nil

    case Bool:
        if !expect_value_of_type(s, v.pos, type, nil, bool_type, "") {
            return nil
        }
        return CompileTimeValue(BoolValue(value))

    case FuncDefinitionRef:
        // if s.func_type != .JsFunc {
        //     err(
        //         s,
        //         v.pos,
        //         "TODO: Handle inline functions in functions that aren't marked with `#js`",
        //     )
        //     return nil, false
        // }
        // if s.funcs_props[value].func_type != s.func_type {
        //     err(
        //         s,
        //         v.pos,
        //         "TODO: Handle inline function where the inline function type is different to the external function type",
        //     )
        //     return nil, false
        // }
        // func, func_ok := check_function(s, value)
        // if !func_ok {
        //     return nil, false
        // }
        // return func, true
        err(s, v.pos, "TODO: Handle function definition")
        return nil

    case CallWithBrackets:
        if array_type, is_array := value.unit_being_called.value.(CallWithFrontedSquareBrackets);
           is_array {
            return check_array_initialisation(
                s,
                v.pos,
                array_type,
                value.unit_being_called.pos,
                value.args,
                body,
                type,
            )
        }
        expected_return_types := make([]ExpectedType, 1)
        expected_return_types[0] = type
        call, call_ok := check_function_call(s, v.pos, value, body, expected_return_types)
        delete(expected_return_types)
        if !call_ok {
            return nil
        }
        return call

    case JoinedUnits:
        return check_joined_unit_value(s, v.pos, value, body, type, generic_args)

    case Ident:
        return check_var_ref(s, value, v.pos, type, body, generic_args)

    case Number:
        // TODO: Check that min(i64) <= number <= max(i64)
        // TODO: Do not assume number type
        if !expect_value_of_type(s, v.pos, type, nil, i64_type, "") {
            return nil
        }
        return CompileTimeValue(
            NumberValue{BigInt{value.is_negated, big_uint_from_string(value.absolute_digits)}},
        )

    case String:
        if expect_value_of_type(s, v.pos, type, nil, string_type, "") {
            return CompileTimeValue(StringLiteralValue(strings.join(([]string)(value), "")))
        }
        return nil

    case Char:
        // TODO: Do not assume number type
        if !expect_value_of_type(s, v.pos, type, nil, u8_type, "") {
            return nil
        }
        return CompileTimeValue(NumberValue{BigInt{false, big_uint_from_u64(u64(value))}})

    }
}

// The bool returned is whether the function checked successfully
check_function :: proc(
    s: ^CheckerState,
    func: FunctionDefinition,
    type: Type,
    loc := #caller_location,
) -> (
    CheckedFunction,
    bool,
) {
    when debug_checker {
        print_call(loc, "check_function")
    }
    f_props, is_func := get_type(s.types, type).(FuncType)
    assert(is_func)
    s.func_type = f_props.type
    s.return_types = make([]Type, len(f_props.return_types))
    for return_type, i in f_props.return_types {
        s.return_types[i] = return_type
    }
    s.loop_index = 0
    s.parent_loop_index = max(uint)
    append_elem(&s.scopes, Scope{})
    defer {
        pop_scope(s)
        assert(len(s.scopes) == 0)
        assert(len(s.variables_map) == 0)
    }
    ok := true
    for type, i in f_props.args {
        arg := func.inputs[i]
        _, var_ok := add_variable(s, type, arg.arg_type == .Mutable, arg.name)
        if !var_ok {
            ok = false
        }
    }
    if !ok {
        return CheckedFunction{}, false
    }
    append(&s.scopes, Scope{})
    defer pop_scope(s)
    // TODO: Check that the function always returns if it has a return type
    body := make([dynamic]CheckedStatement)
    variables, block_ok := check_block(s, func.body, &body)
    if !block_ok {
        return CheckedFunction{}, false
    }
    return CheckedFunction{type, variables, body[:]}, true
}

length_of_array :: proc(type: ArrayType, value: CheckedValue) -> CheckedValue {
    if type.length != 0 {
        return CompileTimeValue(NumberValue{big_int_from_i64(i64(type.length))})
    }
    return LengthOfArray{new_clone(value)}
}

// Returns `nil, Type{}` if there was an error
// The `CheckedValue` returned is the length of the array
// The `Type` returned is the array's item_type
check_array :: proc(
    s: ^CheckerState,
    pos: uint,
    value: CheckedValue,
    value_type: Type,

    // The error message for if the value is not an array
    // Must have one `%s` in it for the actual type of the value
    err_msg: string,
) -> (
    CheckedValue,
    Type,
) {
    array, ok := get_array_type(s, pos, "This value", value_type)
    if !ok {
        // err(s, pos, err_msg, type_to_string(s, value_type))
        return nil, Type{}
    }
    if array.length != 0 {
        return CompileTimeValue(NumberValue{big_int_from_i64(i64(array.length))}), array.item_type
    }
    return length_of_array(array, value), array.item_type
}

get_global_function :: proc(
    s: ^CheckerState,
    usage_pos: uint,
    name: string,
    extra_text: string,
) -> (
    FuncDefinitionRef,
    uint,
    bool,
) {
    global_props, exists := s.files[s.file.index].globals[name]
    if !exists {
        err(s, usage_pos, "The global `%s` is not defined%s", name, extra_text)
        return FuncDefinitionRef{}, max(uint), false
    }
    pos := usage_pos == max(uint) ? global_props.pos : usage_pos
    value_ref, is_value := global_props.value.(GlobalValueRef)
    if !is_value {
        err(
            s,
            pos,
            "The global `%s` is a type\nExpected it to be a function so it can be called%s",
            name,
            extra_text,
        )
        return FuncDefinitionRef{}, max(uint), false
    }
    func_ref, is_func := s.global_values[value_ref.index].ast_node.unit.value.(FuncDefinitionRef)
    if !is_func {
        err(
            s,
            pos,
            "TODO: The global value `%s` is not a function and so cannot be called%s",
            name,
            extra_text,
        )
        return FuncDefinitionRef{}, max(uint), false
    }
    return func_ref, global_props.pos, true
}

EntryFuncType :: enum {
    BuildFunc,
    MainFunc,
}

DiagnosticsInfo :: struct {
    number_of_errors:   uint,
    number_of_warnings: uint,
}

CheckerOutput :: struct {
    checked:          Checked,
    diagnostics_info: DiagnosticsInfo,
    entry_func_ref:   FuncDefinitionRef,
    entry_func_type:  EntryFuncType,
}

Checked :: struct {
    checked_funcs: []CheckedFunction,
    types:         Types,
}

check :: proc(parsed: ParsedProject) -> CheckerOutput {
    state := CheckerState {
        files                         = parsed.files,
        global_values                 = soa_zip(
            parsed.global_values,
            make([]CheckedGlobalValue, len(parsed.global_values)),
        ),
        global_types_without_generics = soa_zip(
            parsed.global_types_without_generics,
            make([]Type, len(parsed.global_types_without_generics)),
        ),
        global_types_with_generics    = parsed.global_types_with_generics,
    }

    for _, i in state.global_types_without_generics {
        state.global_types_without_generics[i].exact_type = unknown_type
    }

    array_with_string_type := make([]Type, 1)
    array_with_string_type[0] = string_type

    array_with_2string_types := make([]Type, 2)
    array_with_2string_types[0] = string_type
    array_with_2string_types[1] = string_type

    array_with_i64_type := make([]Type, 1)
    array_with_i64_type[0] = i64_type

    array_with_u64_type := make([]Type, 1)
    array_with_u64_type[0] = u64_type

    array_with_dynamic_array_of_strings := make([]Type, 1)
    array_with_dynamic_array_of_strings[0] = dynamic_array_of_strings

    assert(dynamic_array_of_strings == create_type(&state.types, ArrayType{0, string_type}).type)
    assert(
        string_to_nil_type ==
        create_type(&state.types, FuncType{array_with_string_type, nil, .Normal}).type,
    )
    assert(
        string_string_to_nil_type ==
        create_type(&state.types, FuncType{array_with_2string_types, nil, .Normal}).type,
    )
    assert(
        string_to_string_type ==
        create_type(&state.types, FuncType{array_with_string_type, array_with_string_type, .Normal}).type,
    )
    assert(
        comptime_u64_to_string_type ==
        create_type(&state.types, FuncType{array_with_u64_type, array_with_string_type, .ComptimeFunc}).type,
    )
    assert(no_args_to_nil_type == create_type(&state.types, FuncType{nil, nil, .Normal}).type)
    assert(
        array_of_strings_to_nil_type ==
        create_type(&state.types, FuncType{array_with_dynamic_array_of_strings, nil, .Normal}).type,
    )
    assert(
        i64_to_nil_type ==
        create_type(&state.types, FuncType{array_with_i64_type, nil, .Normal}).type,
    )

    for value, i in parsed.global_values {
        state.file = value.file
        if func_ref, is_func := value.unit.value.(FuncDefinitionRef); is_func {
            func := parsed.function_defs[func_ref.index]
            func_type: FunctionType
            if len(func.markers) == 0 {
                func_type = .Normal
            } else if len(func.markers) > 1 {
                err(
                    &state,
                    func.markers[1].pos,
                    "TODO: Handle function definitions with more than one marker",
                )
                continue
            } else if func.markers[0].ident == "comptime" {
                func_type = .ComptimeFunc
            } else {
                err(
                    &state,
                    func.markers[0].pos,
                    "Expected marker to be `#comptime`\nGot `#%s`",
                    func.markers[0].ident,
                )
                continue
            }
            checked_func_type := check_function_type(
                &state,
                func.inputs.value_type[:len(func.inputs)],
                func.output^,
                func_type,
                no_generic_arg,
            )
            if checked_func_type == invalid_type {
                continue
            }
            state.global_values[i].value = CheckedGlobalRuntimeValue{checked_func_type, func_ref}
        } else if import_value, is_import := value.unit.value.(Import); is_import {
            state.global_values[i].value = import_value
        } else {
            body: [dynamic]CheckedStatement = nil
            type: Type = unknown_type
            checked_value := check_runtime_value(&state, value.unit, &body, AnyType{&type})
            if checked_value == nil {
                continue
            }
            comptime_value, ok := checked_value.(CompileTimeValue)
            if !ok {
                err(
                    &state,
                    value.unit.pos,
                    "All global values must be compile time known constants",
                )
                continue
            }
            assert(len(body) == 0)
            state.global_values[i].value = CheckedGlobalRuntimeValue{type, checked_value}
        }
    }

    for type, i in state.global_types_with_generics {
        state.file = type.file
        for arg in type.generics {
            expect_camel_case(&state, "generic names", arg)
            if is_builtin(arg.ident) {
                err(&state, arg.pos, builtins_err, arg.ident)
            }
        }
        // TODO: Check that unused generics are valid
        // state.global_types_with_generics[i].generic_type = check_type(
        // &state,
        // type.ast_node.value,
        // type.ast_node.generic.ident,
        // )
    }

    for _, i in state.global_types_without_generics {
        initialise_global_type_without_generic(&state, uint(i))
    }

    if state.diagnostics_info.number_of_errors > 0 {
        return CheckerOutput{diagnostics_info = state.diagnostics_info}
    }

    checked_functions := make([]CheckedFunction, len(parsed.function_defs))

    for file, i in parsed.files {
        state.file = FileRef{uint(i)}
        // TODO: Iterating over globals as a map is a big source of the
        // non-deterministic error ordering in this compiler
        for global_name, global in file.globals {
            if is_builtin(global_name) {
                err(&state, global.pos, builtins_err, global_name)
                continue
            }
            switch value in global.value {
            case GlobalValueRef:
                expect_snake_case(&state, "variable names", IdentAndPos{global_name, global.pos})
                global_val := state.global_values[value.index]
                func_ref, is_func := global_val.ast_node.unit.value.(FuncDefinitionRef)
                if !is_func {
                    continue
                }
                checked_func, func_ok := check_function(
                    &state,
                    parsed.function_defs[func_ref.index],
                    global_val.value.(CheckedGlobalRuntimeValue).type,
                )
                if func_ok {
                    checked_functions[func_ref.index] = checked_func
                }
            case GlobalTypeWithGenericRef, GlobalTypeWithoutGenericRef:
                expect_camel_case(&state, "type names", IdentAndPos{global_name, global.pos})
            }
        }
    }

    if state.diagnostics_info.number_of_errors > 0 {
        return CheckerOutput{diagnostics_info = state.diagnostics_info}
    }

    // TODO: Check the arguments and return types of the `build` or `main` functions
    hint ::
        "\n\nHint: If you define a `build` function, the compiler will run that " +
        "function at compile time to build the program, for example:\n\n" +
        "```\n" +
        "build = #comptime || {\n" +
        "    code = compiler.emit_c_code(this_can_have_any_name)\n" +
        "    write_file(\"code.c\", code)\n" +
        "}\n" +
        "this_can_have_any_name = || -> I64 {\n    println(\"Hello world\")\n    return 0\n}\n" +
        "```\n\nIf no `build` function is defined, then you must specify a " +
        "`main` function, and the compiler will just emit C code to run that " +
        "`main` function, for example:\n\n" +
        "```\n" +
        "main = || -> I64 {\n    println(\"Hello world\")\n    return 0\n}\n" +
        "```\n\n" +
        "TODO: Add link to docs"

    entry_func_ref: FuncDefinitionRef = ---
    entry_func_type: EntryFuncType = ---
    state.file = FileRef{0}
    if build_props, build_exists := parsed.files[0].globals["build"]; build_exists {
        build_value, build_is_value := build_props.value.(GlobalValueRef)
        if !build_is_value {
            err(&state, build_props.pos, "`build` is a type\nExpected it to be a function%s", hint)
            return CheckerOutput{diagnostics_info = state.diagnostics_info}
        }
        build_ref, build_is_func := state.global_values[build_value.index].ast_node.unit.value.(FuncDefinitionRef)
        if !build_is_func {
            err(
                &state,
                build_props.pos,
                "`build` is a value other than a function\nExpected it to be a function%s",
                hint,
            )
            return CheckerOutput{diagnostics_info = state.diagnostics_info}
        }
        build_info := get_type(state.types, checked_functions[build_ref.index].type).(FuncType)
        if build_info.type != .ComptimeFunc {
            err(
                &state,
                build_props.pos,
                "`build` is not marked with `#comptime`\nExpected it to be marked with `#comptime`%s",
                hint,
            )
            return CheckerOutput{diagnostics_info = state.diagnostics_info}
        }
        entry_func_ref = build_ref
        entry_func_type = .BuildFunc
    } else {
        main_ref, main_pos, main_ok := get_global_function(&state, max(uint), "main", hint)
        if !main_ok {
            return CheckerOutput{diagnostics_info = state.diagnostics_info}
        }
        main_info := get_type(state.types, checked_functions[main_ref.index].type).(FuncType)
        if main_info.type != .Normal {
            err(&state, main_pos, "`main` has a marker\nExpected `main` to not have a marker")
            return CheckerOutput{diagnostics_info = state.diagnostics_info}
        }
        entry_func_ref = main_ref
        entry_func_type = .MainFunc
    }
    if state.diagnostics_info.number_of_errors > 0 {
        return CheckerOutput{diagnostics_info = state.diagnostics_info}
    }
    checked := Checked{checked_functions, state.types}
    return CheckerOutput{checked, state.diagnostics_info, entry_func_ref, entry_func_type}
}

