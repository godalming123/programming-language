package main

import "base:runtime"
import "core:os"
import "core:path/filepath"
import "core:strings"

VariableRef :: struct {
    nesting_level: uint,
    index:         uint,
}

ScopeVariable :: struct {
    type:       Type,
    is_mutable: bool,
}

Scope :: struct {
    // The length of these arrays should be the same
    variables: #soa[dynamic]ScopeVariable,
}

ArrayType :: struct {
    length:    u32, // 0 means dynamic length
    item_type: Type,
}

OrderedHashMapTypeWithStringKey :: struct {
    value_type: Type,
}

OrderedHashMapTypeWithI64Key :: struct {
    value_type: Type,
}

FunctionType :: enum {
    Normal,
    // JsFunc,
    ComptimeFunc,
}

CheckerGlobalValueWithoutGeneric :: struct {
    ast_node: GlobalValueWithoutGeneric,
    v:        CheckedGlobalValue,
}

CheckerGlobalValue :: struct {
    ast_node: GlobalValueWithoutGeneric,
    value:    CheckerGlobalValueWithoutGeneric,
}

LabelRef :: struct {
    nesting_level: uint,
    loop_index:    uint,
}

GenericInitialisation :: struct {
    global: GlobalValueWithGenericRef,
    args:   []Type,
    v:      CheckedGlobalValue,
}

CheckedGlobalValue :: struct {
    type:  Type,
    value: CompileTimeValue,
}

generic_initialisation_equal_merge_func :: proc(
    v0: GenericInitialisation,
    v1: GenericInitialisation,
    loc: runtime.Source_Code_Location,
) -> (
    bool,
    GenericInitialisation,
) {
    if len(v0.args) != len(v1.args) {
        return false, GenericInitialisation{}
    }
    for arg, i in v0.args {
        if arg != v1.args[i] {
            return false, GenericInitialisation{}
        }
    }
    if v0.v.type != unknown_type {
        return true, v0
    } else {
        return true, v1
    }
}

CheckerState :: struct {
    // The following fields do not change while checking
    files:                         #soa[]File,
    global_values_without_generic: #soa[]CheckerGlobalValueWithoutGeneric,
    global_values_with_generics:   []GlobalValueWithGeneric,
    func_defs:                     []FunctionDefinition,
    stderr:                        ^os.File,

    // The following fields change while checking
    generic_initialisations:       OrderedHashSet(GenericInitialisation),
    checked_functions:             [dynamic]CheckedFunction,
    first_unchecked_function:      uint,
    types:                         Types,
    diagnostics_info:              DiagnosticsInfo,
    // checked_funcs:                 OrderedHashSet(CheckedFunction),
    func_type:                     FunctionType,
    return_types:                  []Type,
    loop_index:                    uint,
    parent_loop_index:             uint, // Set to max(uint) when there is no parent loop
    // TODO: represent the order of the programmer controlled stack

    // The following fields depend on which variables are in scope
    scopes:                        [dynamic]Scope,
    variables_map:                 map[string]VariableRef,
    labels_map:                    map[string]LabelRef,
}

CheckedFunction :: struct {
    type:         Type, // Always a function type
    definition:   FuncDefinitionRef,
    generic_args: map[string]Type,
    variables:    []Type,
    body:         []CheckedStatement,
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
OrderedHashMapInitFunc :: struct {
    type: Type,
}
SumTypeInitFunc :: struct {
    sum_type:      Type,
    variant_index: uint,
}
LengthOfArray :: struct {
    array: ^CheckedValue,
}
LengthOfOrderedHashMapWithStringKey :: struct {
    hash_map: ^CheckedValue,
}
LengthOfOrderedHashMapWithI64Key :: struct {
    hash_map: ^CheckedValue,
}
KeysOfOrderedHashMapWithStringKey :: struct {
    hash_map: ^CheckedValue,
}
KeysOfOrderedHashMapWithI64Key :: struct {
    hash_map: ^CheckedValue,
}
CheckedOrderedHashMapAccess :: struct {
    hash_map: ^CheckedValue,
    key:      ^CheckedValue,
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
// UninitialisedGlobalWithGenerics :: struct {
// global: GlobalValueWithGenericRef,
// generic_args: []Type,
// }
UninitialisedOrderedHashMapType :: struct {}
CompileTimeStructInitialisation :: struct {
    func: StructTypeInitFunc,
    args: []CompileTimeValue,
}
CompileTimeValue :: union {
    StringLiteralValue,
    NumberValue,
    BoolValue,
    Type,
    GlobalValueWithGenericRef, // For an uninitialised global value with generics
    UninitialisedOrderedHashMapType,
    Import,
    CheckedFuncRef,
    CompileTimeStructInitialisation,
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
    CheckedOrderedHashMapAccess,
    CheckedFieldAccess,
    // CheckedJsFunctionCall,
    LengthOfArray,
    OrderedHashMapInitFunc,
    LengthOfOrderedHashMapWithStringKey,
    LengthOfOrderedHashMapWithI64Key,
    KeysOfOrderedHashMapWithStringKey,
    KeysOfOrderedHashMapWithI64Key,
    StringsAreEqual,
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
                    Pos{ident.pos.index + i, ident.pos.file},
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
                    Pos{ident.pos.index + i, ident.pos.file},
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
                Pos{ident.pos.index + i, ident.pos.file},
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
                Pos{ident.pos.index + uint(i) + 1, ident.pos.file},
                "Expected %s to be `CamelCase`, got `%s`\nCannot have `_` in a camel case identifier",
                ident.ident,
                expected,
            )
            return
        case .LowerCase, .UpperCase, .Digit:
        case .Unknown:
            warn(
                s,
                Pos{ident.pos.index + uint(i) + 1, ident.pos.file},
                "Unexpected character '%c' in identifier `%s`",
                ident.ident[i],
                ident.ident,
            )
            return
        }
    }
    return
}

no_generic_args :: map[string]Type{}

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

// Returns `FuncType{}, false` on failure
check_function_type :: proc(
    s: ^CheckerState,
    inputs: []Unit,
    output: ^Unit, // if the function has no output, then `output` is `nil`
    type: FunctionType,
    generic_args: map[string]Type,
) -> (
    FuncType,
    bool,
) {
    ok := true

    args := make([]Type, len(inputs))
    for input, i in inputs {
        args[i] = check_type(s, input, generic_args)
        if args[i] == invalid_type {
            ok = false
        }
    }

    outputs: []Unit = ---
    if output == nil {
        outputs = nil
    } else if tuple, is_tuple := output.value.(Tuple); is_tuple {
        outputs = tuple.elements
    } else {
        outputs = make([]Unit, 1)
        outputs[0] = output^
    }
    return_types := make([]Type, len(outputs))
    for output, i in outputs {
        return_types[i] = check_type(s, output, generic_args)
        if return_types[i] == invalid_type {
            ok = false
        }
    }

    if !ok {
        return FuncType{}, false
    }

    return FuncType{args, return_types, type}, true
}

// Returns nil if there are errors in the type
check_array_type :: proc(
    s: ^CheckerState,
    pos: Pos,
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
        value := check_runtime_value(s, type.args[0], &body, i64_type, generic_args)
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
        if !ok || length == 0 {
            err(s, type.args[0].pos, "Expected an integer, n, where 0 < n <= max(u32)")
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
    value := check_value(s, type, CheckValueArgs{&body, type_type, generic_args, nil})
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
    generic_args: map[string]Type,
    loc := #caller_location,
) -> CheckedValue {
    when debug_checker {
        print_call(loc, "check_runtime_value")
    }
    out := check_value(s, v, CheckValueArgs{body, type, generic_args, nil})
    if comptime_value, is_comptime_value := out.(CompileTimeValue); is_comptime_value {
        #partial switch _ in comptime_value {
        case Type, GlobalValueWithGenericRef, UninitialisedOrderedHashMapType, Import:
            err(s, v.pos, "This value can only be used at compile time")
            return nil
        }
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
    loop_index:    uint,
    variables:     []Type,
    enter:         []CheckedStatement,
    continue_code: []CheckedStatement,
    body:          []CheckedStatement,
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

CheckedMutation :: struct {
    destination: CheckedValue,
    value:       CheckedValue, // The source
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

non_compiletime_global_err :: "This value is not a compile time known constant\nAll global values must be compile time known constants"

check_comptime_func_call :: proc(
    s: ^CheckerState,
    pos: Pos,
    global: GlobalValueWithGenericRef,
    generic_args: []Type,
    type: ExpectedType,
    loc := #caller_location,
) -> CheckedValue {
    // return CompileTimeValue(UninitialisedGlobalWithGenerics{global,generic_args})
    generic := &s.global_values_with_generics[global.index]
    if len(generic_args) != len(generic.generics) {
        argument_count_mismatch(s, pos, len(generic_args), len(generic.generics), generic.name)
        return invalid_type
    }

    hash := global.index ~ get_hash_of_array_of_types(generic_args)
    ref, value, _ := ordered_hash_set_insert(
        &s.generic_initialisations,
        hash,
        GenericInitialisation{global, generic_args, CheckedGlobalValue{unknown_type, nil}},
        generic_initialisation_equal_merge_func,
    )
    if value.v.type != unknown_type {
        return finish_checking_value(s, pos, type, value.v.value, value.v.type, "")
    }

    generic_args_map := make(map[string]Type)
    for arg, i in generic.generics {
        assert(!(arg.ident in generic_args_map))
        generic_args_map[arg.ident] = generic_args[i]
    }

    body: [dynamic]CheckedStatement
    value_type := unknown_type
    checked_value := check_value(
        s,
        generic.value,
        CheckValueArgs {
            &body,
            AnyType{&value_type},
            generic_args_map,
            GenericTypeValue{global, generic_args, unknown_type},
        },
    )
    if checked_value == nil {
        return nil
    }
    comptime_value, ok := checked_value.(CompileTimeValue)
    if !ok {
        err(s, generic.value.pos, non_compiletime_global_err)
        return nil
    }
    assert(len(body) == 0)

    s.generic_initialisations.values[ref.index].value.v = CheckedGlobalValue {
        value_type,
        comptime_value,
    }

    out := finish_checking_value(s, pos, type, checked_value, value_type, "")

    if value_type == type_type {
        type_value := comptime_value.(Type)
        initialised_type := check_value(
            s,
            generic.value,
            CheckValueArgs{&body, AnyType{&value_type}, generic_args_map, nil},
        )
        if initialised_type == nil {
            return out
        }
        s.types.values[type_value.index].value.value = GenericTypeValue {
            global,
            generic_args,
            initialised_type.(CompileTimeValue).(Type),
        }
    }

    return out
    /*

    s.generic_initialisations.values[ref.index].value.v = CheckedGlobalValue {
        checked_value_type,
        comptime_value,
    }

    if expect_value_of_type(s, pos, type, &checked_value, checked_value_type, "") {
        return checked_value
    }
    return nil
    */
    /*

    generic_args_map := make(map[string]Type)
    for arg, i in generic.generics {
        assert(!(arg.ident in generic_args_map))
        generic_args_map[arg.ident] = generic_args[i]
    }
    */
}

/*
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

initialise_global_type_without_generic :: proc(
    s: ^CheckerState,
    i: uint,
    loc := #caller_location,
) -> Type {
    when true {
        print_call(loc, "initialise_global_type_without_generic")
    }
    // TODO: Check for cycles
    type := s.global_values_without_generic[i]
    if type.v.type == type_type {
        return type.v.value.(Type)
    }
    if type.v.type != unknown_type {
        err(s, type.ast_node.unit.pos, "TODO: FIX") // TODO FIX
    }
    checked_type := check_type(s, type.ast_node.unit, no_generic_args)
    s.global_values_without_generic[i].v.value = CompileTimeValue(checked_type)
    return checked_type
}
*/

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
    pos: Pos,
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
    if pos != unknown_pos {
        err(s, pos, "Expected a sum type, but got the type `%s`", type_to_string(s, type))
    }
    return SumType(Type){}, unknown_type, false
}

get_struct_type :: proc(s: ^CheckerState, pos: Pos, type: Type) -> (Struct(Type, Type), bool) {
    simplified := simplify_type(s, type)
    struct_type, is_struct_type := get_type(s.types, simplified).(Struct(Type, Type))
    if is_struct_type {
        return struct_type, true
    }
    if pos != unknown_pos {
        err(s, pos, "Expected a struct type, but got the type `%s`", type_to_string(s, type))
    }
    return Struct(Type, Type){}, false
}

// Always returns a function type
// Returns `invalid_type` on failure
get_func_type :: proc(s: ^CheckerState, pos: Pos, value: ^CheckedValue, type: Type) -> Type {
    simplified := simplify_type(s, type)
    if simplified == type_type && value != nil {
        value_type_unsimplified := value.(CompileTimeValue).(Type)
        value_type := simplify_type(s, value_type_unsimplified)
        #partial switch type in get_type(s.types, value_type) {
        case Struct(Type, Type):
            value^ = StructTypeInitFunc{value_type}
            return type.extra_data
        // TODO: CLEANUP
        case OrderedHashMapTypeWithI64Key:
            value^ = OrderedHashMapInitFunc{value_type}
            return_types := make([]Type, 1)
            return_types[0] = value_type_unsimplified
            return create_type(&s.types, FuncType{nil, return_types, .Normal}).type
        case OrderedHashMapTypeWithStringKey:
            value^ = OrderedHashMapInitFunc{value_type}
            return_types := make([]Type, 1)
            return_types[0] = value_type_unsimplified
            return create_type(&s.types, FuncType{nil, return_types, .Normal}).type
        }
        err(
            s,
            pos,
            "The type `%s` cannot be converted to a function type",
            type_to_string(s, value_type_unsimplified),
        )
    } else if _, is_func := get_type(s.types, simplified).(FuncType); is_func {
        return simplified
    }
    if pos != unknown_pos {
        if simplified == unknown_type && value != nil {
            // TODO: Also have this better error message for other functions:
            // - `get_struct_type`
            // - `get_sum_type`
            // - `expect_value_of_type`
            // - `expect_exact_type`
            global_value_with_generic_ref, ok := value.(CompileTimeValue).(GlobalValueWithGenericRef)
            if ok {
                global_value_with_generic :=
                    s.global_values_with_generics[global_value_with_generic_ref.index]
                initialisation := strings.builder_make()
                defer strings.builder_destroy(&initialisation)
                strings.write_string(&initialisation, global_value_with_generic.name)
                strings.write_byte(&initialisation, '[')
                first_arg := true
                for generic in global_value_with_generic.generics {
                    if first_arg == false {
                        strings.write_byte(&initialisation, ',')
                    }
                    strings.write_string(&initialisation, generic.ident)
                    first_arg = false
                }
                strings.write_byte(&initialisation, ']')
                err(
                    s,
                    pos,
                    "Expected a func type, but got an uninitialised global value with generics\nHint: Try initialising the global value with something like `%s`",
                    strings.to_string(initialisation),
                )
                return invalid_type
            }
        }
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
    if superset == any_type {
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

finish_checking_value :: proc(
    s: ^CheckerState,
    pos: Pos,
    type: ExpectedType,
    got_value: CheckedValue,
    got_type: Type,
    extra_text: string,
    loc := #caller_location,
) -> CheckedValue {
    when debug_checker {
        print_call(loc, "finish_checking_value")
    }
    got_value_mut := got_value
    if expect_value_of_type(s, pos, type, &got_value_mut, got_type, extra_text) {
        return got_value_mut
    }
    return nil
    /*
    switch value in hint {
    case ExpectedType:
    case ValueWithGenericHint:
        global_value := &s.generic_initialisations.values[value.initialisations_ref.index].value.v
        assert(global_value.type == unknown_type)
        assert(global_value.value == nil)
        global_value^ = CheckedGlobalValue{got_type, nil}
        comptime_value, ok := got_value.(CompileTimeValue)
        if !ok {
            err(s, pos, non_compiletime_global_err)
            return nil
        }
        global_value^ = CheckedGlobalValue{got_type, comptime_value}
        return nil
    case GlobalValueWithoutGenericRef:
        panic("TODO")
    case:
        panic("Unreachable")
    case nil:
        panic("Unreachable")
    }
    */
}

// For both `expect_value_of_type` and `expect_exact_type`
// - The boolean returned is whether the `got` type matches the `expected` type
// - TODO: Specify `extra_text` in all cases

expect_value_of_type :: proc(
    s: ^CheckerState,
    pos: Pos,
    expected: ExpectedType,
    got_value: ^CheckedValue,
    got_type: Type,
    extra_text: string,
    loc := #caller_location,
) -> bool {
    when debug_checker {
        print_call(loc, "expect_value_of_type")
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
    pos: Pos,
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
    return s.scopes[variable.nesting_level].variables[variable.index].type
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
    case invalid_type:
        strings.write_string(b, "invalid_type")
    case unknown_type:
        strings.write_string(b, "unknown_type")
    case imported_file_type:
        strings.write_string(b, "ImportedFile")
    case type_type:
        strings.write_string(b, "Type")
    case any_type:
        strings.write_string(b, "Any")
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
            strings.write_string(b, s.global_values_with_generics[tv.global.index].name)
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
            strings.write_string(b, ") -> ")
            if len(tv.return_types) == 1 {
                build_type_string(s, b, tv.return_types[0])
            } else {
                strings.write_byte(b, '(')
                first_return_type := true
                for return_type in tv.return_types {
                    if first_return_type == false {
                        strings.write_string(b, ", ")
                    }
                    build_type_string(s, b, return_type)
                    first_return_type = false
                }
                strings.write_byte(b, ')')
            }
        case OrderedHashMapTypeWithI64Key:
            strings.write_string(b, "OrderedHashMap[I64, ")
            build_type_string(s, b, tv.value_type)
            strings.write_string(b, "]")
        case OrderedHashMapTypeWithStringKey:
            strings.write_string(b, "OrderedHashMap[String, ")
            build_type_string(s, b, tv.value_type)
            strings.write_string(b, "]")
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
    for label_name, label_ref in s.labels_map {
        if label_ref.nesting_level == len(s.scopes) {
            delete_key(&s.labels_map, label_name)
        } else {
            assert(label_ref.nesting_level < len(s.scopes))
        }
    }
}

get_array_type :: proc(
    s: ^CheckerState,
    pos: Pos,
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

// The `Type` returned is the expected type of the source value
// The `CheckedValue` returned is the value of the destination
check_mutation_destination :: proc(
    s: ^CheckerState,
    var_name: IdentAndPos,
    var_ref: VariableRef,
    key: ^Unit,
    body: ^[dynamic]CheckedStatement,
    generic_args: map[string]Type,
) -> (
    Type,
    CheckedValue,
) {
    var_type := get_variable_type(s, var_ref)
    if key == nil {
        return var_type, var_ref
    }
    #partial switch var_type_value in get_type(s.types, simplify_type(s, var_type)) {
    case ArrayType:
        warn(s, key.pos, "This array access is not bounds checked\nTODO: Bounds checks")
        index_value := check_runtime_value(s, key^, body, i64_type, generic_args)
        if index_value == nil {
            return var_type_value.item_type, nil
        }
        index_variable: CheckedValue = add_unnamed_variable(s, i64_type, false)
        append_elem(body, CheckedMutation{index_variable, index_value})
        return var_type_value.item_type, CheckedArrayAccess{new_clone(CheckedValue(var_ref)), new_clone(index_variable)}

    case OrderedHashMapTypeWithI64Key:
        panic("TODO")

    case OrderedHashMapTypeWithStringKey:
        key_value := check_runtime_value(s, key^, body, string_type, generic_args)
        if key_value == nil {
            return var_type_value.value_type, nil
        }
        key_variable: CheckedValue = add_unnamed_variable(s, string_type, false)
        append_elem(body, CheckedMutation{key_variable, key_value})
        return var_type_value.value_type, CheckedOrderedHashMapAccess{new_clone(CheckedValue(var_ref)), new_clone(key_variable)}

    }
    err(s, key.pos, "Cannot use a key with the type `%s`", type_to_string(s, var_type))
    return invalid_type, nil
}

check_mutation :: proc(
    s: ^CheckerState,
    destination: VariableDest,
    mutation_type: MutationType,
    value: CheckedValue,
    value_type: Type,
    value_pos: Pos,
    body: ^[dynamic]CheckedStatement,
    generic_args: map[string]Type,
    loc := #caller_location,
) -> (
    CheckedMutation,
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
            return CheckedMutation{}, false
        }
        if s.scopes[var_ref.nesting_level].variables[var_ref.index].is_mutable == false {
            err(
                s,
                destination.name.pos,
                "The variable `%s` is not mutable",
                destination.name.ident,
            )
            return CheckedMutation{}, false
        }
        expected_value_type, destination_value := check_mutation_destination(
            s,
            destination.name,
            var_ref,
            destination.key,
            body,
            generic_args,
        )
        if expected_value_type != unknown_type {
            if !expect_value_of_type(s, value_pos, expected_value_type, nil, value_type, "") {
                return CheckedMutation{}, false
            }
        }
        if destination_value == nil {
            return CheckedMutation{}, false
        }
        val := value
        if mutation_type != .SetTo {
            if !type_is_numeric(s, value_type) {
                err(
                    s,
                    value_pos,
                    "Cannot perform numeric mutation on non-numeric type `%s`",
                    type_to_string(s, value_type),
                )
                return CheckedMutation{}, false
            }
            join_method: UnitJoinMethod = ---
            switch mutation_type {
            case .IncrementBy:
                join_method = .Addition
            case .DecrementBy:
                join_method = .Subtraction
            case .MultiplyBy:
                join_method = .Multiplication
            case .DivideBy:
                join_method = .Division
            case .SetTo:
                panic("Unreachable")
            }
            val = CheckedJoinedValues{join_method, new_clone(destination_value), new_clone(value)}
        }
        return CheckedMutation{destination_value, val}, true
    case .Constant, .Mutable:
        if mutation_type != .SetTo {
            err(s, destination.name.pos, "Expected variable assignment to be done with `=`")
            return CheckedMutation{}, false
        }
        variable_is_mutable := destination.type == .Mutable
        variable, variable_ok := add_variable(s, value_type, variable_is_mutable, destination.name)
        if !variable_ok {
            return CheckedMutation{}, false
        }
        return CheckedMutation{variable, value}, true
    case .ConstantAddedToPcs, .MutableAddedToPcs:
        err(s, destination.name.pos, "TODO: Figure out what to do with old code")
        return CheckedMutation{}, false
    }
    panic("Unreachable")
}

// The boolean returned is whether the block checked successfully
check_block :: proc(
    s: ^CheckerState,
    block: []Statement,
    body: ^[dynamic]CheckedStatement,
    generic_args: map[string]Type,
    loc := #caller_location,
) -> (
    []Type,
    bool,
) {
    when debug_checker {
        print_call(loc, "check_block")
    }
    for stmt, stmt_index in block {
        switch value in stmt.value {

        case VariableManagement:
            value_type := unknown_type
            checked_value := check_runtime_value(
                s,
                value.value,
                body,
                AnyType{&value_type},
                generic_args,
            )
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
            mutation, mutation_ok := check_mutation(
                s,
                value.destination[0],
                value.mutation_type,
                checked_value,
                value_type,
                value.value.pos,
                body,
                generic_args,
            )
            if !mutation_ok {
                return nil, false
            }
            append_elem(body, mutation)

        case CallWithBrackets:
            call := check_function_call(s, stmt.position, value, body, nil, generic_args)
            if call == nil {
                return nil, false
            }
            // Call cannot be a `CompileTimeValue` because `expected_return_types` is set to `nil`
            append_elem(body, call.(CheckedFunctionCall))

        case ConditionControlledLoop:
            append_elem(&s.scopes, Scope{})
            defer pop_scope(s)
            old_parent_loop_index := s.parent_loop_index
            defer s.parent_loop_index = old_parent_loop_index
            loop_index := s.loop_index
            s.parent_loop_index = loop_index
            s.loop_index += 1
            condition := check_runtime_value(s, value.condition, body, bool_type, generic_args)

            loop_body_array := make([dynamic]CheckedStatement)
            exit_loop := make([]CheckedStatement, 1)
            exit_loop[0] = BreakLoop{loop_index}
            condition_check := CheckedIf{condition, CheckedBlock{}, CheckedBlock{nil, exit_loop}}
            if value.type == .WhileLoop {
                append_elem(&loop_body_array, condition_check)
            }

            loop_variables, loop_body_ok := check_block(
                s,
                value.body,
                &loop_body_array,
                generic_args,
            )
            if condition == nil || !loop_body_ok {
                return nil, false
            }

            if value.type == .DoWhileLoop {
                append_elem(&loop_body_array, condition_check)
            }

            append_elem(
                body,
                CheckedLoop{loop_index, loop_variables, nil, nil, loop_body_array[:]},
            )

        case ForInLoop:
            append_elem(&s.scopes, Scope{})
            defer pop_scope(s)
            old_parent_loop_index := s.parent_loop_index
            defer s.parent_loop_index = old_parent_loop_index
            loop_index := s.loop_index
            if value.label.ident != "" {
                if value.label.ident in s.labels_map {
                    err(s, value.label.pos, "The label `%s` is already defined", value.label.ident)
                    return nil, false
                }
                s.labels_map[value.label.ident] = LabelRef{len(s.scopes) - 1, loop_index}
            }
            s.parent_loop_index = loop_index
            s.loop_index += 1
            loop_body_array := make([dynamic]CheckedStatement)
            outer: switch iter in value.iterator {
            case Unit:
                type := unknown_type
                v := check_runtime_value(s, iter, body, AnyType{&type}, generic_args)
                if v == nil {
                    return nil, false
                }
                #partial switch t in get_type(s.types, simplify_type(s, type)) {
                case ArrayType:
                    array_item_type := t.item_type
                    if value.variables[2].ident != "" {
                        err(
                            s,
                            stmt.position,
                            "You can only capture at most 2 variables from iterating over an array",
                        )
                        return nil, false
                    }
                    elem_ref, elem_ok := add_variable(
                        s,
                        array_item_type,
                        false,
                        value.variables[0],
                    )
                    index_ref, index_ok := add_variable(s, i64_type, false, value.variables[1])
                    if !elem_ok || !index_ok {
                        return nil, false
                    }
                    loop_variables, loop_body_ok := check_block(
                        s,
                        value.body,
                        &loop_body_array,
                        generic_args,
                    )
                    if !loop_body_ok {
                        return nil, false
                    }
                    append_elem(
                        body,
                        iterate_array(
                            loop_index,
                            index_ref,
                            elem_ref,
                            &Dynamic(CheckedStatement){loop_body_array, 0},
                            loop_variables,
                            v,
                            t,
                        ),
                    )
                    break outer
                case OrderedHashMapTypeWithStringKey:
                    key, key_ok := add_variable(s, string_type, false, value.variables[0])
                    value_var, value_var_ok := add_variable(
                        s,
                        t.value_type,
                        false,
                        value.variables[1],
                    )
                    index, index_ok := add_variable(s, i64_type, false, value.variables[2])
                    if !key_ok || !value_var_ok || !index_ok {
                        return nil, false
                    }
                    loop_variables, loop_body_ok := check_block(
                        s,
                        value.body,
                        &loop_body_array,
                        generic_args,
                    )
                    if !loop_body_ok {
                        return nil, false
                    }
                    append_elem(
                        body,
                        iterate_ordered_hash_map(
                            loop_index,
                            v,
                            index,
                            key,
                            value_var,
                            &Dynamic(CheckedStatement){loop_body_array, 0},
                            loop_variables,
                        ),
                    )
                    break outer
                }
                err(
                    s,
                    iter.pos,
                    "Expected an array or an `OrderedHashMap`, got the type `%s`",
                    type_to_string(s, type),
                )

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
                start := check_runtime_value(
                    s,
                    iter.start,
                    &loop_body_array,
                    expected_type,
                    generic_args,
                )
                end := check_runtime_value(
                    s,
                    iter.end,
                    &loop_body_array,
                    expected_type,
                    generic_args,
                )
                step: CheckedValue = ---
                if iter.step == nil {
                    step = CompileTimeValue(NumberValue{big_int_from_i64(1)})
                } else {
                    step = check_runtime_value(
                        s,
                        iter.step^,
                        &loop_body_array,
                        expected_type,
                        generic_args,
                    )
                }
                if !var_ok || start == nil || end == nil || step == nil {
                    return nil, false
                }
                loop_variables, loop_body_ok := check_block(
                    s,
                    value.body,
                    &loop_body_array,
                    generic_args,
                )
                if !loop_body_ok {
                    return nil, false
                }
                append_elem(
                    body,
                    iterate_start_end_step(
                        loop_index,
                        index_variable,
                        iter.type,
                        start,
                        end,
                        step,
                        &Dynamic(CheckedStatement){loop_body_array, 0},
                        loop_variables,
                    ),
                )
            }

        case IfElseStatement:
            expected_type: Type = bool_type
            condition := check_runtime_value(s, value.condition, body, expected_type, generic_args)

            append_elem(&s.scopes, Scope{})
            if_block_array := make([dynamic]CheckedStatement)
            if_variables, if_block_ok := check_block(
                s,
                value.if_block,
                &if_block_array,
                generic_args,
            )
            if_block := CheckedBlock{if_variables, if_block_array[:]}
            pop_scope(s)

            append_elem(&s.scopes, Scope{})
            else_block_array := make([dynamic]CheckedStatement)
            else_variables, else_block_ok := check_block(
                s,
                value.else_block,
                &else_block_array,
                generic_args,
            )
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
            if value.label.ident == "" {
                append_elem(body, ContinueLoop{s.parent_loop_index})
            } else {
                loop_ref, ok := s.labels_map[value.label.ident]
                if !ok {
                    err(
                        s,
                        value.label.pos,
                        "There is no parent loop labelled with `%s`",
                        value.label.ident,
                    )
                    return nil, false
                }
                append_elem(body, ContinueLoop{loop_ref.loop_index})
            }

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
                v := check_runtime_value(s, value[0], body, s.return_types[0], generic_args)
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
            val := check_runtime_value(s, value.value, body, AnyType{&val_type}, generic_args)
            if val == nil {
                return nil, false
            }

            val_sum_type, _, val_sum_type_ok := get_sum_type(s, value.value.pos, val_type)
            if !val_sum_type_ok {
                return nil, false
            }

            variable_ref := add_unnamed_variable(s, val_type, false)
            append_elem(body, CheckedMutation{variable_ref, val})

            variant_has_branch := make([]bool, len(val_sum_type.variants))
            variant_branch_positions := make([]Pos, len(val_sum_type.variants))

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
                if !is_variable ||
                   len(type_variable.segments) != 2 ||
                   type_variable.segments[0].ident != "" {
                    err(
                        s,
                        branch_type.pos,
                        "Expected type variable without a generic type that starts with `.`",
                    )
                    return nil, false
                }

                variant_name := type_variable.segments[1].ident
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
                    l := get_location(
                        s.files.file[:len(s.files)],
                        variant_branch_positions[variant_index],
                    )
                    err(
                        s,
                        branch_type.pos,
                        "The variant `.%s` already has a branch defined at %s",
                        variant_name,
                        l,
                    )
                    return nil, false
                }

                var: union {
                        VariableRef,
                    } = nil
                if variable_name != nil {
                    ident, is_ident := variable_name.value.(Ident)
                    if !is_ident || len(ident.segments) != 1 {
                        err(s, variable_name.pos, "Expected an identifier without `.`")
                        return nil, false
                    }
                    var_ok: bool = ---
                    var, var_ok = add_variable(
                        s,
                        val_sum_type.variants[variant_index].payload,
                        false,
                        ident.segments[0],
                    )
                    if !var_ok {
                        return nil, false
                    }
                }

                body := make([dynamic]CheckedStatement)
                variables, block_ok := check_block(s, branch.body, &body, generic_args)
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
    variables := s.scopes[len(s.scopes) - 1].variables
    return variables.type[:len(variables)], true
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
    parsed_global, global_exists := file.globals[ref.segments[index].ident]
    if !global_exists {
        err(
            s,
            ref.segments[index].pos,
            "The variable `%s` is not defined in the file `%s`",
            ref.segments[index].ident,
            file.file.file_path,
        )
        return nil, invalid_type, 0
    }
    if parsed_global.has_generics {
        return CompileTimeValue(GlobalValueWithGenericRef{parsed_global.index}),
            unknown_type,
            index + 1
    } else {
        global_value := check_global_value_without_generic(
            s,
            GlobalValueWithoutGenericRef{uint(parsed_global.index)},
        )
        if global_value.type == invalid_type {
            assert(global_value.value != nil)
            return nil, invalid_type, 0
        }
        // if global_value.type == imported_file_type && index + 1 < len(ref.segments) {
        // return check_namespaced_var_ref(s, global_value.value.(Import).file, ref, index + 1)
        // }
        return global_value.value, global_value.type, index + 1
        // switch value in global.value {
        // case:
        //     panic("Unreachable")
        // case nil:
        //     err(
        //         s,
        //         ref[index].pos,
        //         "Either this global has not been defined yet, there was an error checking this global, or this type of global is not yet supported (TODO)",
        //     )
        //     return nil, invalid_type, 0
        // case CheckerGlobalValueWithoutGeneric:
        //     return value.inline_value, value.type, index + 1
        // case Import:
        //     if index + 1 >= len(ref) {
        //         err(s, ref[index].pos, import_use_err)
        //         return nil, invalid_type, 0
        //     }
        //     return check_namespaced_var_ref(s, value.file, ref, index + 1)
        // }
        // initialised := initialise_global_type_without_generic(s, global_value.index)
        // if initialised == invalid_type {
        //     return nil, invalid_type, 0
        // }
        // return CompileTimeValue(initialised), type_type, index + 1
        /*
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
        */
    }
}

// Returns `nil, invalid_type, 0` if there was an error in the ref start
check_var_ref_start :: proc(
    s: ^CheckerState,
    pos: Pos,
    ref: Ident,
    generic_args: map[string]Type,
) -> (
    CheckedValue,
    Type,
    int,
) {
    if ref.segments[0].ident != "" && ref.segments[0].ident in generic_args {
        return CompileTimeValue(generic_args[ref.segments[0].ident]), type_type, 1
    }
    if builtin_func, builtin_func_type := get_builtin_func_from_name(ref.segments[0].ident);
       builtin_func != .invalid_builtin {
        return builtin_func, builtin_func_type, 1
    }
    if builtin_type := get_builtin_type_from_name(ref.segments[0].ident);
       builtin_type != unknown_type {
        return CompileTimeValue(builtin_type), type_type, 1
    }
    if ref.segments[0].ident == "OrderedHashMap" {
        return CompileTimeValue(UninitialisedOrderedHashMapType{}), unknown_type, 1
    }
    if ref.segments[0].ident == "compiler" {
        compiler_funcs :: "`compiler.emit_js_code`"
        if len(ref.segments) == 1 {
            err(s, pos, "Expected " + compiler_funcs + " got just `compiler`")
            return nil, invalid_type, 0
        }
        switch ref.segments[1].ident {
        case "emit_js_code":
            return .emit_js_code, comptime_string_any_ordered_hashmap_and_string_to_string_type, 2
        case:
            err(s, pos, "Expected " + compiler_funcs + " got `compiler.%s`", ref.segments[1].ident)
            return nil, invalid_type, 0
        }
    }
    if var_ref, ok := s.variables_map[ref.segments[0].ident]; ok {
        return var_ref, get_variable_type(s, var_ref), 1
    }
    return check_namespaced_var_ref(s, pos.file, ref, 0)
}

check_var_ref :: proc(
    s: ^CheckerState,
    ref: Ident,
    pos: Pos,
    a: CheckValueArgs,
    loc := #caller_location,
) -> CheckedValue {
    when debug_checker {
        print_call(loc, "check_var_ref")
        print_arg("ref", ref)
        print_arg("a", a)
    }
    if len(ref.segments) == 2 && ref.segments[0].ident == "" {
        expected_return_type: Type = ---
        switch expected in a.type {
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

        variant_index, exists := sum_type.variants_map[ref.segments[1].ident]
        if !exists {
            err(
                s,
                pos,
                "The sum type `%s` does not have a variant called `%s`",
                type_to_string(s, expected_return_type),
                ref.segments[1].ident,
            )
            return nil
        }
        func_ref :=
            get_type(s.types, sum_type.variants[variant_index].payload).(Struct(Type, Type)).extra_data
        // TODO: Use `StructTypeInitFunc` instead of `SumTypeInitFunc` if `type` is the struct type rather than the sum type
        return finish_checking_value(
            s,
            pos,
            a.type,
            SumTypeInitFunc{type_type, variant_index},
            func_ref,
            "",
        )
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

    out, out_type, start_i := check_var_ref_start(s, pos, ref, a.generic_args)
    if out == nil {
        return nil
    }
    for i := start_i; i < len(ref.segments); i += 1 {
        extra_segment := ref.segments[i]
        if extra_segment.ident == "len" {
            #partial switch type in get_type(s.types, simplify_type(s, out_type)) {
            case ArrayType:
                out_type = i64_type
                out = length_of_array(type, out)
                continue
            case OrderedHashMapTypeWithI64Key:
                out_type = i64_type
                out = LengthOfOrderedHashMapWithI64Key{new_clone(out)}
                continue
            case OrderedHashMapTypeWithStringKey:
                out_type = i64_type
                out = LengthOfOrderedHashMapWithStringKey{new_clone(out)}
                continue
            }
            err(
                s,
                extra_segment.pos,
                "The value before `.len` is of type %s\nExpected an array type of an OrderedHashSet type",
                type_to_string(s, out_type),
            )
            return nil
        } else if extra_segment.ident == "to_str" {
            converted := to_str(s, extra_segment.pos, out, out_type)
            if converted == nil {
                return nil
            }
            out_type = string_type
            out = converted
            continue
        } else if out_type == imported_file_type {
            out, out_type, i = check_namespaced_var_ref(
                s,
                out.(CompileTimeValue).(Import).file,
                ref,
                i,
            )
            continue
        }
        struct_type, ok := get_struct_type(s, ref.segments[i].pos, out_type)
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
        out = create_field_access(out, field_index)
    }
    return finish_checking_value(s, pos, a.type, out, out_type, "")
}

check_array_initialisation :: proc(
    s: ^CheckerState,
    pos: Pos,
    array_type_node: CallWithFrontedSquareBrackets,
    array_type_pos: Pos,
    args: []Unit,
    a: CheckValueArgs,
    loc := #caller_location,
) -> CheckedValue {
    when debug_checker {
        print_call(loc, "check_array_initialisation")
    }
    array_type_value, ok := check_array_type(s, array_type_pos, array_type_node, a.generic_args)
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
        value := check_runtime_value(s, arg, a.body, array_type_value.item_type, a.generic_args)
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
    append_elem(a.body, CheckedArrayMutation{array_ref, array_type_value, array_segments})
    return finish_checking_value(s, array_type_pos, a.type, array_ref, array_type, "")
}

// Returns `nil` on failure
check_function_call :: proc(
    s: ^CheckerState,
    pos: Pos,
    call: CallWithBrackets,
    body: ^[dynamic]CheckedStatement,
    expected_return_types: []ExpectedType,
    generic_args: map[string]Type,
    loc := #caller_location,
) -> union {
        CheckedFunctionCall,
        CompileTimeValue,
    } {
    when debug_checker {
        print_call(loc, "check_function_call")
    }

    func_args: []Type = ---
    func_type: FunctionType = ---
    when debug_checker {
        func_args = nil // So that `func_args` can be printed by `debug_arg` without causing a segfault
    }
    expected_type := FunctionWithExpectedReturnTypes{&func_args, &func_type, expected_return_types}
    value := check_runtime_value(s, call.unit_being_called^, body, expected_type, generic_args)
    if value == nil {
        return nil
    }

    if s.func_type == .Normal && func_type == .ComptimeFunc {
        err(s, pos, function_err)
        return nil
    }

    if len(call.args) != len(func_args) {
        argument_count_mismatch(s, pos, len(call.args), len(func_args), "TODO")
        return nil
    }

    checked_args := make([]CheckedValue, len(call.args))
    for arg, i in call.args {
        arg_value := check_runtime_value(s, arg, body, Type(func_args[i]), generic_args)
        if arg_value == nil {
            return nil
        }
        checked_args[i] = arg_value
    }

    return create_checked_func_call(value, checked_args)
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
    a: CheckValueArgs,
) -> CheckedValue {
    if len(markers) == 0 {
        return check_value(s, v, a)
    }
    switch markers[0].ident {
    case "load":
        value := check_value_with_markers(
            s,
            v,
            markers[1:],
            CheckValueArgs{a.body, string_type, a.generic_args, nil},
        )
        if value == nil {
            return nil
        }
        comptime_value, is_comptime := value.(CompileTimeValue)
        if !is_comptime {
            err(s, v.pos, "Expected a compile time known value")
            return nil
        }

        file := s.files[v.pos.file.index].file
        joined, join_err := filepath.join(
            []string{file.dir_path, string(comptime_value.(StringLiteralValue))},
            context.allocator,
        )
        if join_err != nil {
            err(s, v.pos, "Failed to join strings: %v", join_err)
            return nil
        }
        data, data_err := os.read_entire_file(joined, context.allocator)
        if data_err != nil {
            err(s, markers[0].pos, "Failed to read `%s`: %#v\n", joined, data_err)
            return nil
        }
        return finish_checking_value(
            s,
            markers[0].pos,
            a.type,
            CompileTimeValue(StringLiteralValue(data)),
            string_type,
            "",
        )
    case "debug_ast":
        debug_unit(nil, v)
    case:
        warn(s, markers[0].pos, "TODO: Handle the `%s` marker", markers[0].ident)
    }

    return check_value_with_markers(s, v, markers[1:], a)
}

// For `check_value` and `check_joined_unit_value`:
// - Returns `nil` if there are errors in the value
// - The `body` arg may be appended to with statements that should be executed
//   before the value is accessed

check_joined_unit_value :: proc(
    s: ^CheckerState,
    pos: Pos,
    value: JoinedUnits,
    a: CheckValueArgs,
) -> CheckedValue {
    // TODO: In lots of this code, `check_runtime_value` is used when the
    // operations should be performable on values that can only be used at
    // compile time, like a value of the type `type_type`
    array_err :: "Expected an array type\nGot the type `%s`"
    switch value.join_method {

    case .Colon:
        err(s, pos, "Cannot use `:` to join values")
        return nil

    case .In:
        val0_type := unknown_type
        val0 := check_runtime_value(s, value.unit0^, a.body, AnyType{&val0_type}, a.generic_args)
        val1_type := unknown_type
        val1 := check_runtime_value(s, value.unit1^, a.body, AnyType{&val1_type}, a.generic_args)
        if val0 == nil || val1 == nil {
            return nil
        }
        val0_expected_type := invalid_type
        #partial switch t in get_type(s.types, simplify_type(s, val1_type)) {
        case OrderedHashMapTypeWithI64Key:
            val0_expected_type = i64_type
        case OrderedHashMapTypeWithStringKey:
            val0_expected_type = string_type
        }
        if val0_expected_type == invalid_type {
            err(
                s,
                value.unit1.pos,
                "Expected an ordered hash map type\nGot the type %s",
                type_to_string(s, val1_type),
            )
            return nil
        }
        if !expect_exact_type(s, value.unit0.pos, val0_expected_type, val0_type, "") {
            return nil
        }
        out: CheckedValue = CheckedJoinedValues{.In, new_clone(val0), new_clone(val1)}
        return finish_checking_value(s, value.unit0.pos, a.type, out, bool_type, "")

    case .Arrow:
        if a.early_exit_if_value_is_type != nil {
            return finish_checking_early_return_type(s, pos, a)
        }
        tuple, is_tuple := value.unit0.value.(Tuple)
        if !is_tuple {
            err(
                s,
                value.unit1.pos,
                "While checking function type: The unit before the `->` should be a tuple (for example `(String, U64)`)",
            )
            return CompileTimeValue(invalid_type)
        }
        assert(value.unit1 != nil)
        t, ok := check_function_type(s, tuple.elements, value.unit1, .Normal, a.generic_args)
        if !ok {
            return nil
        }
        out: CheckedValue = CompileTimeValue(create_type(&s.types, t).type)
        return finish_checking_value(s, pos, a.type, out, type_type, "")
    case .BooleanAnd, .BooleanOr:
        val0 := check_value(
            s,
            value.unit0^,
            CheckValueArgs{a.body, bool_type, a.generic_args, nil},
        )
        val1 := check_value(
            s,
            value.unit1^,
            CheckValueArgs{a.body, bool_type, a.generic_args, nil},
        )
        if val0 == nil || val1 == nil {
            return nil
        }
        return finish_checking_value(
            s,
            pos,
            a.type,
            create_joined_values(value.join_method, val0, val1),
            bool_type,
            "",
        )
    case .IsEqual, .IsNotEqual:
        t := invalid_type
        val0 := check_runtime_value(s, value.unit0^, a.body, AnyType{&t}, a.generic_args)
        if val0 == nil {
            return nil
        }
        val1 := check_runtime_value(s, value.unit1^, a.body, t, a.generic_args)
        if val1 == nil {
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
        return finish_checking_value(
            s,
            pos,
            a.type,
            create_joined_values(value.join_method, val0, val1),
            bool_type,
            "",
        )

    case .Append:
        t: Type = unknown_type
        val0 := check_runtime_value(s, value.unit0^, a.body, AnyType{&t}, a.generic_args)
        if val0 == nil {
            return nil
        }
        length, item_type := check_array(s, value.unit0.pos, val0, t, array_err)
        if length == nil {
            return nil
        }
        val1 := check_runtime_value(s, value.unit1^, a.body, Type(item_type), a.generic_args)
        if val1 == nil {
            return nil
        }
        return_type1 := ArrayType{0, item_type}
        return_type0 := create_type(&s.types, return_type1).type // TODO: Maybe `::` should be able to output fixed size arrays
        segments := make([]ArraySegment, 2)
        segments[0] = InlineArraySegment{val0, length}
        segments[1] = SingleElemSegment{val1}
        array_ref := add_unnamed_variable(s, return_type0, false)
        append_elem(a.body, CheckedArrayMutation{array_ref, return_type1, segments})
        return finish_checking_value(s, pos, a.type, array_ref, return_type0, "")

    case .StringConcat:
        val0 := check_runtime_value(s, value.unit0^, a.body, string_type, a.generic_args)
        val1 := check_runtime_value(s, value.unit1^, a.body, string_type, a.generic_args)
        if val0 == nil || val1 == nil {
            return nil
        }
        return finish_checking_value(
            s,
            pos,
            a.type,
            create_joined_values(.StringConcat, val0, val1),
            string_type,
            "",
        )
    case .Concat:
        type0: Type = ---
        type1: Type = ---
        val0 := check_runtime_value(s, value.unit0^, a.body, AnyType{&type0}, a.generic_args)
        val1 := check_runtime_value(s, value.unit1^, a.body, AnyType{&type1}, a.generic_args)
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
        segments := make([]ArraySegment, 2)
        segments[0] = InlineArraySegment{val0, length0}
        segments[1] = InlineArraySegment{val1, length1}
        array_ref := add_unnamed_variable(s, return_type, false)
        append_elem(a.body, CheckedArrayMutation{array_ref, return_type1, segments})
        return finish_checking_value(s, pos, a.type, array_ref, return_type, "")
    case .IsGreaterThan, .IsGreaterThanOrEqual, .IsLessThan, .IsLessThanOrEqual:
        // TODO: Do not assume number types
        val0 := check_runtime_value(s, value.unit0^, a.body, i64_type, a.generic_args)
        val1 := check_runtime_value(s, value.unit1^, a.body, i64_type, a.generic_args)
        if val0 == nil || val1 == nil {
            return nil
        }
        return finish_checking_value(
            s,
            pos,
            a.type,
            create_joined_values(value.join_method, val0, val1),
            bool_type,
            "",
        )
    case .Multiplication, .Subtraction, .Division, .Addition, .Modulo:
        // TODO: Do not assume number types
        val0 := check_runtime_value(s, value.unit0^, a.body, i64_type, a.generic_args)
        val1 := check_runtime_value(s, value.unit1^, a.body, i64_type, a.generic_args)
        if val0 == nil || val1 == nil {
            return nil
        }
        return finish_checking_value(
            s,
            pos,
            a.type,
            create_joined_values(value.join_method, val0, val1),
            i64_type,
            "",
        )
    case:
        panic("Unreachable")
    }

}

import_use_err :: "Cannot use an import as a runtime value"

/*
ValueWithGenericHint :: struct {
    ref:                 GlobalValueWithGenericRef,
    initialisations_ref: OrderedHashSetSlotRef,
    args:                []Type,
}

ValueHint :: union {
    ExpectedType,

    // Used if the value is a global value
    // If `ValueHint` is one of these variants, then the type of the `GlobalValue` is set by `check_value`
    ValueWithGenericHint,
    GlobalValueWithoutGenericRef,
}

// The `bool` returned is whether `check_value` should return early
start_checking_type :: proc(
    s: ^CheckerState,
    pos: Pos,
    hint: ValueHint,
    generic_args: map[string]Type,
) -> (
    CheckedValue,
    bool,
) {
    switch value in hint {
    case ExpectedType:
        if expect_value_of_type(s, pos, value, nil, type_type, "") {
            return nil, false
        }
        return nil, true
    case ValueWithGenericHint:
        global_value := &s.generic_initialisations.values[value.initialisations_ref.index].value.v
        assert(global_value.type == unknown_type)
        assert(global_value.value == nil)
        global_value^ = CheckedGlobalValue{type_type, nil}
        created := create_type(&s.types, GenericTypeValue{value.ref, value.args, unknown_type})
        if created.result == .Merged {
            if created.type_value.(GenericTypeValue).initialised_type == invalid_type {
                return invalid_type, true
            }
            return created.type, true
        }
        initialised_type := check_type(
            s,
            s.global_values_with_generics[value.ref.index].value,
            generic_args,
        )
        created2 := create_type(
            &s.types,
            GenericTypeValue{value.ref, value.args, initialised_type},
        )
        assert(created.type == created2.type)
        if initialised_type == invalid_type {
            return invalid_type, true
        }
        return created.type, true
    case GlobalValueWithoutGenericRef:
        panic("TODO")
    case:
        panic("Unreachable")
    }
}
*/

CheckValueArgs :: struct {
    // Used if the value is a runtime value
    body:                        ^[dynamic]CheckedStatement,

    // TODO: Update the compiler so all type information flows from source to
    // destination and remove this field and
    type:                        ExpectedType,

    // Used if the value is defined inside a generic global value definition
    generic_args:                map[string]Type,

    // Used to prevent infinite cycles
    // Normally set to `nil`
    // If the value is a type and `early_exit_if_value_is_type != nil`, the
    // check value function returns
    // `finish_checking_early_return_type(s, v.pos, a)`
    early_exit_if_value_is_type: TypeValue,
}

finish_checking_early_return_type :: proc(
    s: ^CheckerState,
    pos: Pos,
    a: CheckValueArgs,
) -> CheckedValue {
    out := CompileTimeValue(create_type(&s.types, a.early_exit_if_value_is_type).type)
    return finish_checking_value(s, pos, a.type, out, type_type, "")
}

check_value :: proc(
    s: ^CheckerState,
    v: Unit,
    a: CheckValueArgs,
    loc := #caller_location,
) -> CheckedValue {
    when debug_checker {
        print_call(loc, "check_value")
        print_arg("v", v)
    }
    switch value in v.value {
    case:
        err(s, v.pos, "Internal error: got nil value in check_value")
        return nil

    case Struct(Unit, struct {}):
        if a.early_exit_if_value_is_type != nil {
            return finish_checking_early_return_type(s, v.pos, a)
        }
        return finish_checking_value(
            s,
            v.pos,
            a.type,
            CompileTimeValue(check_struct_type(s, value, a.generic_args)),
            type_type,
            "",
        )

    case CallWithFrontedSquareBrackets:
        if a.early_exit_if_value_is_type != nil {
            return finish_checking_early_return_type(s, v.pos, a)
        }
        array, ok := check_array_type(s, v.pos, value, a.generic_args)
        if !ok {
            return nil
        }
        return CompileTimeValue(create_type(&s.types, array).type)

    case SumType(Struct(Unit, struct {})):
        if a.early_exit_if_value_is_type != nil {
            return finish_checking_early_return_type(s, v.pos, a)
        }
        variants: #soa[]SumTypeVariant(Type) = soa_zip(
            value.variants.name[:len(value.variants)],
            make([]Type, len(value.variants)),
        )
        ok := true
        for variant, i in value.variants {
            expect_camel_case(s, "the name of a sum type variant", variant.name)
            variants[i].payload = check_struct_type(s, variant.payload, a.generic_args)
            if variants[i].payload == invalid_type {
                ok = false
            }
        }
        if !ok {
            return nil
        }
        return finish_checking_value(
            s,
            v.pos,
            a.type,
            CompileTimeValue(
                create_type(&s.types, SumType(Type){value.variants_map, variants}).type,
            ),
            type_type,
            "",
        )
    case Import:
        err(s, v.pos, import_use_err)
        return nil

    case MarkedUnit:
        return check_value_with_markers(s, value.value^, value.markers, a)

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
        return check_value(s, value.elements[0], a)

    case CallWithSquareBrackets:
        being_called_type := invalid_type
        being_called_value := check_value(
            s,
            value.unit_being_called^,
            CheckValueArgs{a.body, AnyType{&being_called_type}, a.generic_args, nil},
        )
        if being_called_value == nil {
            return nil
        }
        being_called_type = simplify_type(s, being_called_type)
        if being_called_type == unknown_type {
            checked_args := make([]Type, len(value.args))
            ok := true
            for arg, i in value.args {
                checked_args[i] = check_type(s, arg, a.generic_args)
                if checked_args[i] == invalid_type {
                    ok = false
                }
            }
            if !ok {
                return nil
            }
            #partial switch comptime_value in being_called_value.(CompileTimeValue) {
            case GlobalValueWithGenericRef:
                return check_comptime_func_call(s, v.pos, comptime_value, checked_args, a.type)
            case UninitialisedOrderedHashMapType:
                if len(checked_args) != 2 {
                    argument_count_mismatch(s, v.pos, len(checked_args), 2, "OrderedHashMap")
                    return nil
                }
                key := simplify_type(s, checked_args[0])
                type_value: TypeValue
                if key == string_type {
                    type_value = OrderedHashMapTypeWithStringKey{checked_args[1]}
                } else if key == i64_type {
                    type_value = OrderedHashMapTypeWithI64Key{checked_args[1]}
                } else {
                    err(
                        s,
                        v.pos,
                        "The key of an `OrderedHashMap` must be a `String` or an `I64`\nGot the key `%s`\nTODO: Support `OrderedHashMap`s with keys other than `String`s and `I64`s",
                        type_to_string(s, checked_args[0]),
                    )
                    return nil
                }
                out: CheckedValue = CompileTimeValue(create_type(&s.types, type_value).type)
                return finish_checking_value(s, v.pos, a.type, out, type_type, "")
            }
            panic("Unreachable")
        }
        if len(value.args) != 1 {
            err(
                s,
                v.pos,
                "Indexed accesses into an array or ordered hash map must pass one value into the square brackets\nGot %d values",
                len(value.args),
            )
            return nil
        }
        #partial switch t in get_type(s.types, being_called_type) {
        case ArrayType:
            warn(s, v.pos, "This array access is not bounds checked\nTODO: Bounds checks")
            index_value := check_runtime_value(s, value.args[0], a.body, i64_type, a.generic_args)
            if index_value == nil {
                return nil
            }
            //if t.length == 0 {
            //    err(
            //        s,
            //        value.array.pos,
            //        "TODO: Implement element access for dynamically sized arrays",
            //    )
            //    return nil, false
            //}
            return finish_checking_value(
                s,
                v.pos,
                a.type,
                CheckedArrayAccess{new_clone(being_called_value), new_clone(index_value)},
                t.item_type,
                "",
            )
        case OrderedHashMapTypeWithI64Key:
            panic("TODO")
        case OrderedHashMapTypeWithStringKey:
            key_value := check_runtime_value(s, value.args[0], a.body, string_type, a.generic_args)
            if key_value == nil {
                return nil
            }
            return finish_checking_value(
                s,
                v.pos,
                a.type,
                CheckedOrderedHashMapAccess{new_clone(being_called_value), new_clone(key_value)},
                t.value_type,
                "",
            )}
        err(
            s,
            value.unit_being_called.pos,
            "The value is of type `%s`\nExpected an array type or an `OrderedHashMap` type",
            type_to_string(s, being_called_type),
        )
        return nil

    case Bool:
        return finish_checking_value(
            s,
            v.pos,
            a.type,
            CompileTimeValue(BoolValue(value)),
            bool_type,
            "",
        )
    case FuncDefinitionRef:
        out_func_ref, out_type, _ := check_anonymous_func_head(s, value, a.generic_args)
        return finish_checking_value(s, v.pos, a.type, out_func_ref, out_type, "")
    case CallWithBrackets:
        if array_type, is_array := value.unit_being_called.value.(CallWithFrontedSquareBrackets);
           is_array {
            return check_array_initialisation(
                s,
                v.pos,
                array_type,
                value.unit_being_called.pos,
                value.args,
                CheckValueArgs{a.body, a.type, a.generic_args, nil},
            )
        }
        expected_return_types := make([]ExpectedType, 1)
        expected_return_types[0] = a.type
        call := check_function_call(s, v.pos, value, a.body, expected_return_types, a.generic_args)
        delete(expected_return_types)
        switch c in call {
        case nil:
            return nil
        case CompileTimeValue:
            return c
        case CheckedFunctionCall:
            return c
        case:
            panic("Unreachable")
        }

    case JoinedUnits:
        return check_joined_unit_value(s, v.pos, value, a)

    case Ident:
        return check_var_ref(s, value, v.pos, a)

    case Number:
        // TODO: Check that min(i64) <= number <= max(i64)
        // TODO: Do not assume number type
        out := CompileTimeValue(
            NumberValue{BigInt{value.is_negated, big_uint_from_string(value.absolute_digits)}},
        )
        return finish_checking_value(s, v.pos, a.type, out, i64_type, "")
    case String:
        out := CompileTimeValue(StringLiteralValue(strings.join(([]string)(value), "")))
        return finish_checking_value(s, v.pos, a.type, out, string_type, "")
    case Char:
        // TODO: Do not assume number type
        out := CompileTimeValue(NumberValue{BigInt{false, big_uint_from_u64(u64(value))}})
        return finish_checking_value(s, v.pos, a.type, out, u8_type, "")
    }
}

// Returns `CheckedFuncRef{max(uint)}, invalid_type` on failure
check_anonymous_func_head :: proc(
    s: ^CheckerState,
    ref: FuncDefinitionRef,
    generic_args: map[string]Type,
) -> (
    CheckedFuncRef,
    Type,
    FuncType,
) {
    func := s.func_defs[ref.index]

    func_type: FunctionType
    if len(func.markers) == 0 {
        func_type = .Normal
    } else if len(func.markers) > 1 {
        err(s, func.markers[1].pos, "TODO: Handle function definitions with more than one marker")
        return CheckedFuncRef{max(uint)}, invalid_type, FuncType{}
    } else if func.markers[0].ident == "comptime" {
        func_type = .ComptimeFunc
    } else {
        err(
            s,
            func.markers[0].pos,
            "Expected marker to be `#comptime`\nGot `#%s`",
            func.markers[0].ident,
        )
        return CheckedFuncRef{max(uint)}, invalid_type, FuncType{}
    }
    checked_func_type, ok := check_function_type(
        s,
        func.inputs.value_type[:len(func.inputs)],
        func.output,
        func_type,
        generic_args,
    )
    if !ok {
        return CheckedFuncRef{max(uint)}, invalid_type, FuncType{}
    }
    type := create_type(&s.types, checked_func_type).type
    checked_ref := CheckedFuncRef{len(s.checked_functions)}
    append(&s.checked_functions, CheckedFunction{type, ref, generic_args, nil, nil})
    return checked_ref, type, checked_func_type
}

// Returns `false` on failure
check_anonymous_func_body :: proc(s: ^CheckerState, ref: CheckedFuncRef) -> bool {
    checked_func := s.checked_functions[ref.index]
    generic_args := checked_func.generic_args
    func := s.func_defs[checked_func.definition.index]
    func_type := get_type(s.types, checked_func.type).(FuncType)

    s.func_type = func_type.type
    s.return_types = make([]Type, len(func_type.return_types))
    s.loop_index = 0
    s.parent_loop_index = max(uint)
    assert(len(s.scopes) == 0)
    assert(len(s.variables_map) == 0)
    assert(len(s.labels_map) == 0)
    for return_type, i in func_type.return_types {
        s.return_types[i] = return_type
    }
    append(&s.scopes, Scope{})
    defer pop_scope(s)
    ok := true
    for arg_type, i in func_type.args {
        arg := func.inputs[i]
        _, var_ok := add_variable(s, arg_type, arg.arg_type == .Mutable, arg.name)
        if !var_ok {
            ok = false
        }
    }
    if !ok {
        return false
    }
    append(&s.scopes, Scope{})
    defer pop_scope(s)
    // TODO: Check that the function always returns if it has a return type
    body := make([dynamic]CheckedStatement)
    variables, block_ok := check_block(s, func.body, &body, generic_args)
    if !block_ok {
        return false
    }
    s.checked_functions[ref.index].variables = variables
    s.checked_functions[ref.index].body = body[:]
    return true
}

// Returns `CheckedGlobalValue{invalid_type, nil}` on failure
check_global_value_without_generic :: proc(
    s: ^CheckerState,
    ref: GlobalValueWithoutGenericRef,
) -> (
    out: CheckedGlobalValue,
) {
    global := &s.global_values_without_generic[ref.index]
    if global.v.type != unknown_type {
        out = global.v
        return
    }
    defer global.v = out
    value := global.ast_node
    //if func_ref, is_func := value.unit.value.(FuncDefinitionRef); is_func {
    //    // func := s.func_defs[func_ref.index]
    //    ref, type, func_type := check_anonymous_func_head(s, func_ref, no_generic_args)
    //    s.global_values_without_generic[i].type = type
    //    if ref.index == max(uint) {
    //        return false
    //    }
    //    s.global_values_without_generic[i].value = ref
    //    return check_anonymous_func_body(s, func, func_type, ref, no_generic_args)
    //}
    if import_value, is_import := value.unit.value.(Import); is_import {
        out = CheckedGlobalValue{imported_file_type, import_value}
        return
    }
    body: [dynamic]CheckedStatement = nil
    early_exit_if_value_is_type: TypeValue = nil // TODO: Do not use nil to prevent infinite cycles with global types without generics
    type: Type = unknown_type
    checked_value := check_value(
        s,
        value.unit,
        CheckValueArgs{&body, AnyType{&type}, no_generic_args, early_exit_if_value_is_type},
    )
    when debug_checker {
        debug(
            "Checked global with name `%s` and type `%v`",
            global.ast_node.name,
            type_to_string(s, type),
        )
    }
    if checked_value == nil {
        out = CheckedGlobalValue{invalid_type, nil}
        return
    }
    comptime_value, ok := checked_value.(CompileTimeValue)
    if !ok {
        err(s, value.unit.pos, non_compiletime_global_err)
        out = CheckedGlobalValue{invalid_type, nil}
        return
    }
    assert(len(body) == 0)
    out = CheckedGlobalValue{type, comptime_value}
    return
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
    pos: Pos,
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
    usage_pos: Pos,
    file_to_search: FileRef,
    name: string,
    extra_text: string,
) -> (
    CheckedFuncRef,
    Pos,
    bool,
) {
    parsed_global, exists := s.files[file_to_search.index].globals[name]
    if !exists {
        err(s, usage_pos, "The global `%s` is not defined%s", name, extra_text)
        return CheckedFuncRef{}, unknown_pos, false
    }
    pos := usage_pos == unknown_pos ? Pos{parsed_global.pos, file_to_search} : usage_pos
    if parsed_global.has_generics {
        err(
            s,
            pos,
            "The global `%s` has generic\nExpected it to not have generics%s",
            name,
            extra_text,
        )
        return CheckedFuncRef{}, unknown_pos, false
    }
    global := s.global_values_without_generic[parsed_global.index]
    func_ref, is_func := global.v.value.(CheckedFuncRef)
    if !is_func {
        err(
            s,
            pos,
            "The global value `%s` is not a function and so cannot be called%s",
            name,
            extra_text,
        )
        return CheckedFuncRef{}, unknown_pos, false
    }
    return func_ref, Pos{parsed_global.pos, file_to_search}, true
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
    func_ref:         CheckedFuncRef,
}

Checked :: struct {
    checked_funcs: []CheckedFunction,
    types:         Types,
}

check :: proc(parsed: ParsedProject, func_name: string, stderr: ^os.File) -> CheckerOutput {
    state := CheckerState {
        stderr                        = stderr,
        files                         = parsed.files,
        global_values_without_generic = soa_zip(
            parsed.global_values_without_generic,
            make([]CheckedGlobalValue, len(parsed.global_values_without_generic)),
        ),
        global_values_with_generics   = parsed.global_values_with_generics,
        func_defs                     = parsed.function_defs,
    }

    for _, i in state.global_values_without_generic {
        state.global_values_without_generic[i].v.type = unknown_type
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

    array_with_string_any_ordered_hash_map_and_string := make([]Type, 2)
    array_with_string_any_ordered_hash_map_and_string[0] = string_any_ordered_hashmap_type
    array_with_string_any_ordered_hash_map_and_string[1] = string_type

    array_with_dynamic_array_of_strings := make([]Type, 1)
    array_with_dynamic_array_of_strings[0] = dynamic_array_of_strings

    array_with_string_i64_types := make([]Type, 2)
    array_with_string_i64_types[0] = string_type
    array_with_string_i64_types[1] = i64_type

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
        string_any_ordered_hashmap_type ==
        create_type(&state.types, OrderedHashMapTypeWithStringKey{any_type}).type,
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
    assert(
        string_i64_to_string_type ==
        create_type(&state.types, FuncType{array_with_string_i64_types, array_with_string_type, .Normal}).type,
    )
    assert(
        comptime_string_any_ordered_hashmap_and_string_to_string_type ==
        create_type(&state.types, FuncType{array_with_string_any_ordered_hash_map_and_string, array_with_string_type, .ComptimeFunc}).type,
    )

    for _, i in parsed.global_values_without_generic {
        check_global_value_without_generic(&state, GlobalValueWithoutGenericRef{uint(i)})
    }

    for state.first_unchecked_function < len(state.checked_functions) {
        // TODO: Do not pass `nil` in
        check_anonymous_func_body(&state, CheckedFuncRef{state.first_unchecked_function})
        state.first_unchecked_function += 1
    }

    for type in state.global_values_with_generics {
        // state.file = type.file
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

    // for _, i in state.global_values_without_generic {
    // initialise_global_type_without_generic(&state, uint(i))
    // }

    if state.diagnostics_info.number_of_errors > 0 {
        return CheckerOutput{diagnostics_info = state.diagnostics_info}
    }

    for file, i in parsed.files {
        // state.file = FileRef{uint(i)}
        // TODO: Iterating over globals as a map is a big source of the
        // non-deterministic error ordering in this compiler
        for global_name, global in file.globals {
            if is_builtin(global_name) {
                err(&state, Pos{global.pos, FileRef{uint(i)}}, builtins_err, global_name)
                continue
            }
            // TODO: Check that the name is the correct case
            /*
            switch value in global.value {
            case GlobalValueWithoutGenericRef:
                expect_snake_case(&state, "variable names", IdentAndPos{global_name, global.pos})
                global_val := state.global_values_without_generics[value.index]
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
            case GlobalValueWithGenericRef, GlobalValueWithoutGenericRef:
                expect_camel_case(&state, "type names", IdentAndPos{global_name, global.pos})
            }
            */
        }
    }

    if state.diagnostics_info.number_of_errors > 0 {
        return CheckerOutput{diagnostics_info = state.diagnostics_info}
    }

    func_ref, _, func_ok := get_global_function(
        &state,
        unknown_pos,
        FileRef{0},
        func_name,
        "TODO: Write hint",
    )
    if !func_ok {
        return CheckerOutput{diagnostics_info = state.diagnostics_info}
    }
    checked := Checked{state.checked_functions[:], state.types}
    // TODO: Check the arguments and return types of the func
    return CheckerOutput{checked, state.diagnostics_info, func_ref}

    /*
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

    entry_func_ref: CheckedFuncRef = ---
    entry_func_type: EntryFuncType = ---
    if build_props, build_exists := parsed.files[0].globals["build"]; build_exists {
        if build_props.has_generics {
            err(
                &state,
                Pos{build_props.pos, FileRef{0}},
                "`build` is has generics\nExpected it to be a function without generics%s",
                hint,
            )
            return CheckerOutput{diagnostics_info = state.diagnostics_info}
        }
        build_value := state.global_values_without_generic[build_props.index]
        build_ref, build_is_func := build_value.v.value.(CheckedFuncRef)
        if !build_is_func {
            err(
                &state,
                Pos{build_props.pos, FileRef{0}},
                "`build` is a value other than a function\nExpected it to be a function%s",
                hint,
            )
            return CheckerOutput{diagnostics_info = state.diagnostics_info}
        }
        build_info := get_type(state.types, build_value.v.type).(FuncType)
        if build_info.type != .ComptimeFunc {
            err(
                &state,
                Pos{build_props.pos, FileRef{0}},
                "`build` is not marked with `#comptime`\nExpected it to be marked with `#comptime`%s",
                hint,
            )
            return CheckerOutput{diagnostics_info = state.diagnostics_info}
        }
        entry_func_ref = build_ref
        entry_func_type = .BuildFunc
    } else {
        main_ref, main_pos, main_ok := get_global_function(
            &state,
            unknown_pos,
            FileRef{0},
            "main",
            hint,
        )
        if !main_ok {
            return CheckerOutput{diagnostics_info = state.diagnostics_info}
        }
        main_info := get_type(state.types, state.checked_functions[main_ref.index].type).(FuncType)
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
    checked := Checked{state.checked_functions[:], state.types}
    return CheckerOutput{checked, state.diagnostics_info, entry_func_ref, entry_func_type}
    */
}

