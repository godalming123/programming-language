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
    variable_types:   [dynamic]ExactCheckedType,
    variable_is_muts: [dynamic]bool,
}

ArrayType :: struct(T: typeid) {
    length:    u32, // 0 means dynamic length
    item_type: T,
}

FunctionType :: enum {
    Normal,
    // JsFunc,
    ComptimeFunc,
}

SumVariant :: struct(T: typeid) {
    sum_type:      T,
    variant_index: uint,
}

GenericType :: struct(T: typeid) {
    generic_type_index: u32, // an index into CheckerState.global_types_with_generics
    generic_arg:        T,
}

ExactFuncType :: FuncType(ExactCheckedType)

// a is an index into checked_global_types_with_generics and b is an index into
// type_equivalancy_array
GenericTypeInitialisationsStore :: map[u64]ExactCheckedType

// a is the length of the array and b is an index into type_equivalancy_array
ArrayTypeInitialisationsStore :: map[u64]struct{}

CheckerGlobalTypeWithoutGeneric :: struct {
    ast_node:      GlobalTypeWithoutGeneric,
    exact_type:    ExactCheckedType,
    function_type: FuncTypeRef,
}

CheckerGlobalTypeWithGeneric :: struct {
    ast_node:     GlobalTypeWithGeneric,
    generic_type: GenericCheckedType,
}

CheckedGlobalRuntimeValue :: struct {
    type:         ExactCheckedType,
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
    global_types_with_generics:    #soa[]CheckerGlobalTypeWithGeneric,

    // The following fields depend on the function currently being checked
    file:                          FileRef,
    func_type:                     FunctionType,
    return_types:                  []ExactCheckedType, // If the function does not return anything, then this is nil

    // The following fields depend on which variables are in scope
    scopes:                        [dynamic]Scope,
    variables_map:                 map[string]VariableRef,

    // The following fields change while checking
    // TODO: Use some sort of hash map to store the types in a program so that
    // you can figure out if a new type is the same as any type which has already
    // been used in the program in O(1) time.
    generic_being_initialised:     GenericType(u32), // TODO: Does this need to be an array?
    type_equivalancy_array:        [dynamic]EquivalencyArrayElem(ExactCheckedType),
    generic_type_initialisations:  GenericTypeInitialisationsStore,
    array_type_initialisations:    ArrayTypeInitialisationsStore,
    func_types:                    [dynamic]EquivalencyArrayElem(ExactFuncType), // The first len(CheckerState.funcs) are associated with that function
    loop_index:                    uint,
    diagnostics_info:              DiagnosticsInfo,
    // TODO: represent the order of the programmer controlled stack
}

CheckedFunction :: struct {
    type:      FuncTypeRef,
    variables: []ExactCheckedType,
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
TypeInitFunc :: struct {
    type: ExactCheckedType,
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
}
CheckedValue :: union {
    CompileTimeValue,
    ToString,
    VariableRef,
    BooleanNotValue,
    CheckedJoinedValues,
    CheckedFunctionCall,
    TypeInitFunc,
    BuiltinFunction,
    CheckedArrayAccess,
    CheckedFieldAccess,
    // CheckedJsFunctionCall,
    LengthOfArray,
    StringsAreEqual,
    FuncDefinitionRef,
}

StringType :: struct {}
I64Type :: struct {}
I32Type :: struct {}
I16Type :: struct {}
I8Type :: struct {}
U64Type :: struct {}
U32Type :: struct {}
U16Type :: struct {}
U8Type :: struct {}
BoolType :: struct {}
TypeOfGenericArg :: struct {}
FuncTypeRef :: struct {
    index: uint, // An index into `CheckerState.func_types`
}
FuncType :: struct(T: typeid) {
    args:         []T,
    return_types: []T,
    type:         FunctionType,
}

GenericCheckedType :: union {
    // Same
    StringType,
    I64Type,
    I32Type,
    I16Type,
    I8Type,
    U64Type,
    U32Type,
    U16Type,
    U8Type,
    BoolType,
    GlobalTypeWithoutGenericRef,

    // Different args to generic
    SumVariant(^GenericCheckedType),
    SumType(GenericCheckedType, struct {}),
    Struct(GenericCheckedType),
    ArrayType(^GenericCheckedType),
    GenericType(^GenericCheckedType),

    // Inline type values
    FuncType(GenericCheckedType),

    // Extra types
    TypeOfGenericArg,
}

ExactCheckedType :: union {
    // Same
    StringType,
    I64Type,
    I32Type,
    I16Type,
    I8Type,
    U64Type,
    U32Type,
    U16Type,
    U8Type,
    BoolType,
    GlobalTypeWithoutGenericRef,

    // Different args to generic
    SumVariant(^ExactCheckedType),
    SumType(ExactCheckedType, FuncTypeRef),
    Struct(ExactCheckedType),
    // The `u32` is an index into `CheckerState.type_equivalancy_array
    ArrayType(u32),
    GenericType(u32),

    // References
    FuncTypeRef,
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

// TODO: Maybe a few functions should be polymorphic so they can produce `ExactCheckedType` or `GenericCheckedType`:
// - `check_struct_type`
// - `check_function_type`
// - `check_type`
// - `handle_named_type`

check_struct_type :: proc(
    s: ^CheckerState,
    type: Struct(Unit),
    generic_arg_name: string,
) -> (
    Struct(GenericCheckedType),
    bool,
) {
    fields := make(#soa[]StructField(GenericCheckedType), len(type.fields))
    ok := true
    for field, i in type.fields {
        expect_snake_case(s, "the name of a struct field", field.name)
        field_type := check_type(s, field.type, generic_arg_name)
        if field_type == nil {
            ok = false
        } else {
            fields[i] = StructField(GenericCheckedType){field.name, field_type}
        }
    }
    if !ok {
        return Struct(GenericCheckedType){}, false
    }
    return Struct(GenericCheckedType){type.fields_map, fields}, true
}

check_function_type :: proc(
    s: ^CheckerState,
    inputs: []Unit,
    output: Unit, // if the function has no output, then `output` is `Unit{}`
    type: FunctionType,
    generic_arg_name: string,
) -> (
    FuncType(GenericCheckedType),
    bool,
) {
    ok := true

    args := make([]GenericCheckedType, len(inputs))
    for input, i in inputs {
        args[i] = check_type(s, input, generic_arg_name)
        if args[i] == nil {
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
    return_types := make([]GenericCheckedType, len(outputs))
    for output, i in outputs {
        return_types[i] = check_type(s, output, generic_arg_name)
        if return_types[i] == nil {
            ok = false
        }
    }

    if !ok {
        return FuncType(GenericCheckedType){}, false
    }

    return FuncType(GenericCheckedType){args, return_types, type}, true
}

// Returns nil if there are errors in the type
check_array_type :: proc(
    s: ^CheckerState,
    pos: uint,
    type: CallWithFrontedSquareBrackets,
    generic_arg_name: string,
) -> GenericCheckedType {
    length: u32 = 0
    if len(type.args) == 0 {
        length = 0
    } else if len(type.args) == 1 {
        body := make([dynamic]CheckedStatement)
        value := check_value(s, type.args[0], &body, ExactCheckedType(I64Type{}))
        if value == nil {
            return nil
        }
        compile_time_value, ok := value.(CompileTimeValue)
        if !ok {
            err(s, type.args[0].pos, "Expected a compile time value got a runtime value")
            return nil
        }
        number := compile_time_value.(NumberValue)
        assert(len(body) == 0)
        length, ok = big_int_to_u32(number.value)
        if !ok {
            err(s, pos, "Expected an integer (n) where 0 < n <= max(u32)", type.args[0].pos)
            return nil
        }
    } else {
        err(s, pos, "Expected either 0 or 1 unit inside `[]`, got %d units", len(type.args))
        return nil
    }
    item_type := check_type(s, type.unit_being_called^, generic_arg_name)
    if item_type == nil {
        return nil
    }
    return ArrayType(^GenericCheckedType){length, new_clone(item_type)}
}

// Returns nil if there are errors in the type
check_type :: proc(
    s: ^CheckerState,
    type: Unit,
    generic_arg_name: string,
    loc := #caller_location,
) -> GenericCheckedType {
    err_context :: "While checking type: "
    when debug_checker {
        print_call(loc, "check_type")
        print_arg("generic_arg_name", generic_arg_name)
    }
    switch t in type.value {
    // case DynamicType:
    //     err(s, type.pos, "TODO: Support checking dynamic type")
    //     return nil
    case Import:
        err(s, type.pos, err_context + "Cannot use an import as a type")
        return nil
    case FuncDefinitionRef:
        err(s, type.pos, err_context + "Cannot use a function definition as a type")
        return nil
    case CallWithBrackets:
        err(s, type.pos, err_context + "Cannot use a call with brackets as a type")
        return nil
    case Number:
        err(s, type.pos, err_context + "Cannot use a number value as a type")
        return nil
    case String:
        err(s, type.pos, err_context + "Cannot use a string value as a type")
        return nil
    case Char:
        err(s, type.pos, err_context + "Cannot use a char value as a type")
        return nil
    case Bool:
        err(s, type.pos, err_context + "Cannot use a bool value as a type")
        return nil
    case MarkedUnit:
        err(s, type.pos, err_context + "Cannot use a marker as a type")
        return nil
    case Struct(Unit):
        checked_struct, ok := check_struct_type(s, t, generic_arg_name)
        if !ok {
            return nil
        }
        return checked_struct
    case SumType(Unit, struct {}):
        variants := make_soa(#soa[]SumTypeVariant(GenericCheckedType, struct {}), len(t.variants))
        ok := true
        for variant, i in t.variants {
            expect_camel_case(s, "the name of a sum type variant", variant.name)
            checked_variant, variant_ok := check_struct_type(s, variant.payload, generic_arg_name)
            if variant_ok {
                variants[i] = SumTypeVariant(GenericCheckedType, struct {}) {
                    variant.name,
                    checked_variant,
                    struct{}{},
                }
            } else {
                ok = false
            }
        }
        if !ok {
            return nil
        }
        return SumType(GenericCheckedType, struct {}){t.variants_map, variants}
    case Tuple:
        func, ok := check_function_type(s, t.elements, Unit{}, .Normal, generic_arg_name)
        if !ok {
            return nil
        }
        return func
    case JoinedUnits:
        if t.join_method != .Arrow {
            err(s, type.pos, "While checking type: Joined units must be joined with `->`")
            return nil
        }
        tuple, is_tuple := t.unit0.value.(Tuple)
        if !is_tuple {
            err(
                s,
                t.unit1.pos,
                "While checking function type: The unit before the `->` should be a tuple (for example `(String, U64)`)",
            )
            return nil
        }
        func, ok := check_function_type(s, tuple.elements, t.unit1^, .Normal, generic_arg_name)
        if !ok {
            return nil
        }
        return func
    case Ident:
        return handle_named_type(s, type.pos, t, nil, generic_arg_name)
    case CallWithSquareBrackets:
        ident, is_ident := t.unit_being_called.value.(Ident)
        if !is_ident {
            err(
                s,
                t.unit_being_called.pos,
                err_context +
                "The unit being called in a call with square brackets must be an identifier",
            )
            return nil
        }
        return handle_named_type(s, type.pos, ident, t.args, generic_arg_name)
    case CallWithFrontedSquareBrackets:
        return check_array_type(s, type.pos, t, generic_arg_name)
    case:
        panic("Unreachable")
    }
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
    variables:  []ExactCheckedType,
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
    variables: []ExactCheckedType,
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
    variable_type: ArrayType(u32),
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
    // CheckedJsFunctionCall,
    // CheckedJsAssignment,
}

// TODO: Rework this with a general Number type
type_is_numeric :: proc(type: ExactCheckedType) -> bool {
    switch _ in type {
    case I64Type, I32Type, I16Type, I8Type, U64Type, U32Type, U16Type, U8Type:
        return true
    case StringType,
         BoolType,
         ArrayType(u32),
         FuncTypeRef,
         GenericType(u32),
         GlobalTypeWithoutGenericRef,
         SumType(ExactCheckedType, FuncTypeRef),
         Struct(ExactCheckedType),
         SumVariant(^ExactCheckedType):
        return false
    case nil:
        panic("Unreachable")
    case:
        panic("Unreachable")
    }
}

create_generic_struct_type :: proc(
    s: ^CheckerState,
    elem: Struct(GenericCheckedType),
    generic_arg: ExactCheckedType,
) -> Struct(ExactCheckedType) {
    field_types := make([]ExactCheckedType, len(elem.fields))
    for field, i in elem.fields {
        field_types[i] = create_generic_type_elem(s, field.type, generic_arg)
    }
    return Struct(ExactCheckedType) {
        elem.fields_map,
        soa_zip(elem.fields.name[0:len(elem.fields)], field_types),
    }
}

create_array_type :: proc(s: ^CheckerState, length: u32, item_type: u32) -> ArrayType(u32) {
    s.array_type_initialisations[combine_u32(length, item_type)] = struct{}{}
    return ArrayType(u32){length, item_type}
}

create_generic_type :: proc(
    s: ^CheckerState,
    generic_type_index: u32,
    generic_arg: u32,
    loc := #caller_location,
) -> GenericType(u32) {
    when debug_checker {
        print_call(loc, "create_generic_type")
        print_arg("generic_type_index", generic_type_index)
        print_arg("generic_arg", generic_arg)
        debug("s.generic_being_initialised is %v", s.generic_being_initialised)
    }
    mut_generic_arg := generic_arg
    if s.generic_being_initialised.generic_type_index == generic_type_index {
        if type_is_equal2(s, s.generic_being_initialised.generic_arg, generic_arg, true) {
            when debug_checker {
                debug(
                    "s.generic_being_initialised is the same as GenericType(u32){{generic_type_index, generic_arg}}",
                )
            }
            if s.generic_being_initialised.generic_arg < mut_generic_arg {
                mut_generic_arg = s.generic_being_initialised.generic_arg
            }
        }
    }
    key := combine_u32(generic_type_index, mut_generic_arg)
    _, exists := s.generic_type_initialisations[key]
    if !exists {
        s.generic_type_initialisations[key] = nil
    }
    when debug_checker {
        debug("exists is %t", exists)
        debug("mut_generic_arg is %d", mut_generic_arg)
    }
    return GenericType(u32){generic_type_index, mut_generic_arg}
}

// This function should always be used to handle appending to the equivalancy
// array so that the type system is easier to debug
append_to_type_equivalancy_array :: proc(
    s: ^CheckerState,
    type: ExactCheckedType,
    loc := #caller_location,
) -> u32 {
    ref := u32(len(s.type_equivalancy_array))
    when debug_checker {
        print_call(loc, "append_to_type_equivalancy_array")
        print_arg("type", type)
        debug("ref is %d", ref)
    }
    append_elem(&s.type_equivalancy_array, type)
    return ref
}

create_generic_array_type :: proc(
    s: ^CheckerState,
    elem: ArrayType(^GenericCheckedType),
    generic_arg: ExactCheckedType,
    loc := #caller_location,
) -> (
    ArrayType(u32),
    ExactCheckedType,
) {
    when debug_checker {
        print_call(loc, "create_generic_array_type")
        print_arg("elem", elem)
        print_arg("generic_arg", generic_arg)
    }
    item_type := create_generic_type_elem(s, elem.item_type^, generic_arg)
    item_ref := append_to_type_equivalancy_array(s, item_type)
    array_type := create_array_type(s, elem.length, item_ref)
    when debug_checker {
        debug("returned ArrayType(u32) is %#v", array_type)
        debug("returned ExactCheckedType is %#v", item_type)
    }
    return array_type, item_type
}

make_func_type_exact :: proc(
    s: ^CheckerState,
    elem: FuncType(GenericCheckedType),
    generic_arg: ExactCheckedType,
    loc := #caller_location,
) -> FuncType(ExactCheckedType) {
    when debug_checker {
        print_call(loc, "make_func_type_exact")
    }
    exact_args := make([]ExactCheckedType, len(elem.args))
    for arg, i in elem.args {
        exact_args[i] = create_generic_type_elem(s, arg, generic_arg)
    }
    exact_return_types := make([]ExactCheckedType, len(elem.return_types))
    for return_type, i in elem.return_types {
        exact_return_types[i] = create_generic_type_elem(s, return_type, generic_arg)
    }
    return FuncType(ExactCheckedType){exact_args, exact_return_types, elem.type}
}

create_generic_func_type :: proc(
    s: ^CheckerState,
    elem: FuncType(GenericCheckedType),
    generic_arg: ExactCheckedType,
) -> FuncTypeRef {
    ref := FuncTypeRef{len(s.func_types)}
    append_elem(&s.func_types, make_func_type_exact(s, elem, generic_arg))
    return ref
}

get_generic :: proc(s: ^CheckerState, generic: GenericType(u32)) -> (ExactCheckedType, u64) {
    combined := combine_u32(generic.generic_type_index, generic.generic_arg)
    if s.generic_type_initialisations[combined] != nil {
        return s.generic_type_initialisations[combined], combined
    }
    _, generic_arg := get_info(s.type_equivalancy_array[:], uint(generic.generic_arg))
    if generic_arg == uint(generic.generic_arg) {
        return nil, combined
    }
    key := combine_u32(generic.generic_type_index, u32(generic_arg))
    initialised, _ := s.generic_type_initialisations[key]
    return initialised, key
}

initialise_generic :: proc(
    s: ^CheckerState,
    generic_type_index: u32,
    generic_arg: u32,
    combined: u64,
    loc := #caller_location,
) -> ExactCheckedType {
    when debug_checker {
        print_call(loc, "initialise_generic")
        print_arg("generic_type_index", generic_type_index)
        print_arg("generic_arg", generic_arg)
    }
    if s.generic_type_initialisations[combined] != nil {
        return s.generic_type_initialisations[combined]
    }
    arg, generic_arg_uint := get_info(s.type_equivalancy_array[:], uint(generic_arg))
    key: u64 = ---
    if generic_arg_uint == uint(generic_arg) {
        key = combined
    } else {
        key = combine_u32(generic_type_index, u32(generic_arg_uint))
        out, exists := s.generic_type_initialisations[key]
        if exists && out != nil {
            return out
        }
    }
    assert(s.generic_being_initialised.generic_type_index == max(u32))
    assert(s.generic_being_initialised.generic_arg == max(u32))
    s.generic_being_initialised = GenericType(u32){generic_type_index, u32(generic_arg_uint)}
    out := create_generic_type_elem(
        s,
        s.global_types_with_generics[generic_type_index].generic_type,
        arg,
    )
    s.generic_being_initialised = GenericType(u32){max(u32), max(u32)}
    s.generic_type_initialisations[key] = out
    return out
}

create_generic_type_elem :: proc(
    s: ^CheckerState,
    elem: GenericCheckedType,
    generic_arg: ExactCheckedType,
    loc := #caller_location,
) -> ExactCheckedType {
    when debug_checker {
        print_call(loc, "create_generic_type_elem")
        print_arg("elem", elem)
    }
    switch e in elem {
    case:
        panic(fmt.aprintf("Unreachable (elem is %v)", elem))
    case FuncType(GenericCheckedType):
        return create_generic_func_type(s, e, generic_arg)
    case SumVariant(^GenericCheckedType):
        panic("TODO: Handle sum variant")
    case SumType(GenericCheckedType, struct {}):
        variant_payloads := make([]Struct(ExactCheckedType), len(e.variants))
        variant_funcs := make([]FuncTypeRef, len(e.variants))
        sum_type: ExactCheckedType = SumType(ExactCheckedType, FuncTypeRef) {
            e.variants_map,
            soa_zip(e.variants.name[0:len(e.variants)], variant_payloads, variant_funcs),
        }
        for variant, i in e.variants {
            variant_payloads[i] = create_generic_struct_type(s, variant.payload, generic_arg)
            variant_funcs[i] = FuncTypeRef{len(s.func_types)}
            args := make([]ExactCheckedType, len(variant_payloads[i].fields))
            for field, j in variant_payloads[i].fields {
                args[j] = field.type
            }
            return_types := make([]ExactCheckedType, 1)
            return_types[0] = sum_type
            append_elem(&s.func_types, ExactFuncType{args, return_types, .Normal})
        }
        return sum_type
    case Struct(GenericCheckedType):
        return create_generic_struct_type(s, e, generic_arg)
    case StringType:
        return StringType{}
    case I64Type:
        return I64Type{}
    case I32Type:
        return I32Type{}
    case I16Type:
        return I16Type{}
    case I8Type:
        return I8Type{}
    case U64Type:
        return U64Type{}
    case U32Type:
        return U32Type{}
    case U16Type:
        return U16Type{}
    case U8Type:
        return U8Type{}
    case BoolType:
        return BoolType{}
    case GenericType(^GenericCheckedType):
        // TODO
        // append_elem(&s.global_types_with_generics_initialisations[e.generic_type_index], arg_ref)
        arg := create_generic_type_elem(s, e.generic_arg^, generic_arg)
        arg_ref := append_to_type_equivalancy_array(s, arg)
        // array := s.global_types_with_generics_initialisations[e.generic_type_index]
        // assert(array[len(array) - 1] == arg_ref)
        // pop(&s.global_types_with_generics_initialisations[e.generic_type_index])
        out := create_generic_type(s, e.generic_type_index, arg_ref)
        return out
    case GlobalTypeWithoutGenericRef:
        return e
    case ArrayType(^GenericCheckedType):
        out, _ := create_generic_array_type(s, e, generic_arg)
        return out
    case TypeOfGenericArg:
        return generic_arg
    }
}

/*
get_sum_type_for_generic_checked_type :: proc(
    s: ^CheckerState,
    pos: uint,
    type: Type,
) -> (
    SumType(Type),
    bool,
) {
}

get_sum_type_for_exact_checked_type :: proc(
    s: ^CheckerState,
    pos: uint,
    type: ExactCheckedType,
) -> (
    map[string]uint,
    union {
        #soa[]SumTypeVariant(ExactCheckedType),
        #soa[]SumTypeVariant(Type),
    },
) {
    #partial switch t in type {
    case nil:
        panic("Unreachable")
    case GenericTypeRef:
        info, _ := get_info(s.generic_types[:], t.generic_type_index)
        global := s.global_types_with_generics[info.global_type_index]
        return get_sum_variants_for_generic_checked_type(s, pos, global.value)
    case GlobalTypeWithoutGenericRef:
        return get_sum_variants_for_exact_checked_type(
            s,
            pos,
            s.checked_global_types_without_generics[t.index],
        )
    case SumVariant(^ExactCheckedType):
        variants_map, variants := get_sum_type_for_exact_checked_type(s, pos, t.sum_type^)
        switch variants_value in variants {
        case #soa[]SumTypeVariant(ExactCheckedType):
            return get_sum_type_for_exact_checked_type(
                s,
                pos,
                variants_value[t.variant_index].payload,
            )
        case #soa[]SumTypeVariant(Type):
            return get_sum_type_for_generic_checked_type(
                s,
                pos,
                variants_value[t.variant_index].payload,
            )
        case nil:
            return nil, nil
        }
    }
}

get_struct_type_for_exact_checked_type :: proc(
    s: ^CheckerState,
    pos: uint,
    type: ExactCheckedType,
) -> (
    map[string]uint,
    union {
        #soa[]StructField(ExactCheckedType),
        #soa[]StructField(Type),
    },
) {

}
create_generic_type :: proc(
    s: ^CheckerState,
    global_type_index: uint,
    generic_arg: ExactCheckedType,
    loc := #caller_location,
) -> GenericTypeRef {
    when debug_checker {
        print_call(loc, "create_generic_type")
        print_arg("global_type_index", global_type_index)
        print_arg("generic_arg", generic_arg)
    }
    generic_type :=
        s.checked_global_types_with_generics[global_type_index] == nil ? nil : create_generic_type_elem(s, s.checked_global_types_with_generics[global_type_index], generic_arg)
    assert(generic_arg != nil)
    append_elem(&s.generic_types, ExactGenericType{generic_type, global_type_index, generic_arg})
    return GenericTypeRef{len(s.generic_types) - 1}
}
*/

simplify_type :: proc(
    s: ^CheckerState,
    pos: uint,
    type: ExactCheckedType,
    loc := #caller_location,
) -> (
    ExactCheckedType,
    bool,
) {
    when debug_checker {
        print_call(loc, "simplify_type")
        print_arg("type", type)
    }
    cur_type := type
    for {
        #partial switch t in cur_type {
        case nil:
            panic("Unreachable")
        case GenericType(u32):
            cur_type = initialise_generic(
                s,
                t.generic_type_index,
                t.generic_arg,
                combine_u32(t.generic_type_index, u32(t.generic_arg)),
            )
        case GlobalTypeWithoutGenericRef:
            cur_type = s.global_types_without_generics[t.index].exact_type
        case SumVariant(^ExactCheckedType):
            sum_type, ok := get_sum_type(s, pos, t.sum_type^)
            if !ok {
                return nil, false
            }
            cur_type = sum_type.variants[t.variant_index].payload
        case:
            return cur_type, true
        }
    }
}

// For `get_sum_type`, `get_struct_type`, and `get_func_type`, set pos to
// `max(uint)` to not report an error if it is not a sum/struct type

get_sum_type :: proc(
    s: ^CheckerState,
    pos: uint,
    type: ExactCheckedType,
    loc := #caller_location,
) -> (
    SumType(ExactCheckedType, FuncTypeRef),
    bool,
) {
    when debug_checker {
        print_call(loc, "get_sum_type")
        print_arg("pos", pos)
        print_arg("type", type)
    }
    simplified, ok := simplify_type(s, pos, type)
    if !ok {
        return SumType(ExactCheckedType, FuncTypeRef){}, false
    }
    sum_type, is_sum_type := simplified.(SumType(ExactCheckedType, FuncTypeRef))
    if !is_sum_type {
        if pos != max(uint) {
            err(s, pos, "Expected a sum type, but got the type `%s`", type_to_string(s, type))
        }
        return SumType(ExactCheckedType, FuncTypeRef){}, false
    }
    when debug_checker {
        debug("returned SumType(ExactCheckedType) is %#v", sum_type)
    }
    return sum_type, true
}

get_struct_type :: proc(
    s: ^CheckerState,
    pos: uint,
    type: ExactCheckedType,
) -> (
    Struct(ExactCheckedType),
    bool,
) {
    simplified, ok := simplify_type(s, pos, type)
    if !ok {
        return Struct(ExactCheckedType){}, false
    }
    struct_type, is_struct_type := simplified.(Struct(ExactCheckedType))
    if !is_struct_type {
        if pos != max(uint) {
            err(s, pos, "Expected a struct type, but got the type `%s`", type_to_string(s, type))
        }
        return Struct(ExactCheckedType){}, false
    }
    return struct_type, true
}

get_func_type :: proc(s: ^CheckerState, pos: uint, type: ExactCheckedType) -> (FuncTypeRef, bool) {
    simplified, ok := simplify_type(s, pos, type)
    if !ok {
        return FuncTypeRef{}, false
    }
    func_type, is_func := simplified.(FuncTypeRef)
    if !is_func {
        if pos != max(uint) {
            err(s, pos, "Expected a func type, but got the type `%s`", type_to_string(s, type))
        }
        return FuncTypeRef{}, false
    }
    return func_type, true
}

struct_is_equal :: proc(
    s: ^CheckerState,
    type0: Struct(ExactCheckedType),
    type1: Struct(ExactCheckedType),
    fully_equilize_types: bool,
) -> bool {
    if len(type0.fields) != len(type1.fields) {
        return false
    }
    for field, i in type0.fields {
        if type_is_equal(s, field.type, type1.fields[i].type, fully_equilize_types) == false {
            return false
        }
    }
    return true
}

type_is_equal2 :: proc(
    s: ^CheckerState,
    type0: u32,
    type1: u32,
    fully_equilize_types: bool,
    loc := #caller_location,
) -> bool {
    when debug_checker {
        print_call(loc, "type_is_equal2")
    }
    t0, t0_ref := get_info(s.type_equivalancy_array[:], uint(type0))
    t1, t1_ref := get_info(s.type_equivalancy_array[:], uint(type1))
    if t0_ref == t1_ref {
        return true
    }
    equal := type_is_equal(s, t0, t1, fully_equilize_types)
    if !equal {
        return false
    }
    _, t0_ref2 := get_info(s.type_equivalancy_array[:], t0_ref)
    _, t1_ref2 := get_info(s.type_equivalancy_array[:], t1_ref)
    mark_elements_equal(s.type_equivalancy_array[:], t0_ref2, t1_ref2)
    return true
}

type_is_equal :: proc(
    s: ^CheckerState,
    type0: ExactCheckedType,
    type1: ExactCheckedType,
    fully_equilize_types: bool,
    loc := #caller_location,
) -> bool {
    when debug_checker {
        print_call(loc, "type_is_equal")
        print_arg("type0", type0)
        print_arg("type1", type1)
    }

    sum_variant0, is_sum_variant0 := type0.(SumVariant(^ExactCheckedType))
    sum_variant1, is_sum_variant1 := type1.(SumVariant(^ExactCheckedType))
    if is_sum_variant0 && is_sum_variant1 {
        if sum_variant0.variant_index != sum_variant1.variant_index {
            return false
        }
        return type_is_equal(
            s,
            sum_variant0.sum_type^,
            sum_variant1.sum_type^,
            fully_equilize_types,
        )
    } else if is_sum_variant0 {
        sum_type0, ok := get_sum_type(s, max(uint), sum_variant0.sum_type^)
        assert(ok)
        new_type0 := sum_type0.variants[sum_variant0.variant_index].payload
        return type_is_equal(s, new_type0, type1, fully_equilize_types)
    } else if is_sum_variant1 {
        sum_type1, ok := get_sum_type(s, max(uint), sum_variant1.sum_type^)
        assert(ok)
        new_type1 := sum_type1.variants[sum_variant1.variant_index].payload
        return type_is_equal(s, type0, new_type1, fully_equilize_types)
    }

    switch &t0 in type0 {
    case:
        panic("Unreachable")
    case nil:
        panic("Unreachable")
    case FuncTypeRef:
        t1, is_func_type_ref := type1.(FuncTypeRef)
        if !is_func_type_ref {
            return false
        }
        t0_type, t0_ref := get_info(s.func_types[:], t0.index)
        t1_type, t1_ref := get_info(s.func_types[:], t1.index)
        if t0_ref == t1_ref {
            return true
        }

        // Check function type
        if t0_type.type != t1_type.type {
            return false
        }

        // Check return types
        if len(t0_type.return_types) != len(t1_type.return_types) {
            return false
        }
        for t0_return_type, i in t0_type.return_types {
            if !type_is_equal(s, t0_return_type, t1_type.return_types[i], fully_equilize_types) {
                return false
            }
        }

        // Check args
        if len(t0_type.args) != len(t1_type.args) {
            return false
        }
        for t0_arg, i in t0_type.args {
            if !type_is_equal(s, t0_arg, t1_type.args[i], fully_equilize_types) {
                return false
            }
        }

        // The function types are equal
        mark_elements_equal(s.func_types[:], t0_ref, t1_ref)
        return true
    case Struct(ExactCheckedType):
        t1, is_struct := get_struct_type(s, max(uint), type1)
        if !is_struct {
            return false
        }
        return struct_is_equal(s, t0, t1, fully_equilize_types)
    case SumType(ExactCheckedType, FuncTypeRef):
        t1, is_sum := get_sum_type(s, max(uint), type1)
        if !is_sum {
            return false
        }
        if len(t0.variants) != len(t1.variants) {
            return false
        }
        for variant, i in t0.variants {
            if struct_is_equal(s, variant.payload, t1.variants[i].payload, fully_equilize_types) ==
               false {
                return false
            }
        }
        return true
    case SumVariant(^ExactCheckedType):
        panic("unreachable")
    case StringType:
        _, is_string := type1.(StringType)
        return is_string
    case I64Type:
        _, is_i64 := type1.(I64Type)
        return is_i64
    case I32Type:
        _, is_i32 := type1.(I32Type)
        return is_i32
    case I16Type:
        _, is_i16 := type1.(I16Type)
        return is_i16
    case I8Type:
        _, is_i8 := type1.(I8Type)
        return is_i8
    case U64Type:
        _, is_u64 := type1.(U64Type)
        return is_u64
    case U32Type:
        _, is_u32 := type1.(U32Type)
        return is_u32
    case U16Type:
        _, is_u16 := type1.(U16Type)
        return is_u16
    case U8Type:
        _, is_u8 := type1.(U8Type)
        return is_u8
    // case JsObjectType:
    //     _, is_js_object := type1.(JsObjectType)
    //     return is_js_object
    case BoolType:
        _, is_bool := type1.(BoolType)
        return is_bool
    case GlobalTypeWithoutGenericRef:
        t1, is_type_ref := type1.(GlobalTypeWithoutGenericRef)
        if !is_type_ref {
            return false
        }
        return t0 == t1
    case GenericType(u32):
        t1, is_generic_type_ref := type1.(GenericType(u32))
        if !is_generic_type_ref {
            return false
        }
        if t0.generic_type_index != t1.generic_type_index {
            return false
        }
        generic0, key0 := get_generic(s, t0)
        generic1, key1 := get_generic(s, t1)
        if fully_equilize_types && generic0 != nil && generic1 != nil {
            // Compare initialised types rather than generic args so that nested initialised types become equated properly
            return type_is_equal(s, generic0, generic1, false)
        } else {
            equal := type_is_equal2(s, t0.generic_arg, t1.generic_arg, fully_equilize_types)
            if equal {
                if generic0 != nil && generic1 == nil {
                    s.generic_type_initialisations[key1] = generic0
                } else if generic1 != nil && generic0 == nil {
                    s.generic_type_initialisations[key0] = generic1
                }
            }
            return equal
        }
    case ArrayType(u32):
        t1, is_array := type1.(ArrayType(u32))
        if !is_array {
            return false
        }

        // TODO: Maybe fixed size arrays should coerce into dynamic size arrays
        return(
            t0.length == t1.length &&
            type_is_equal2(s, t0.item_type, t1.item_type, fully_equilize_types) \
        )
    }
}

// For both `expect_type` and `expect_exact_type`
// - The boolean returned is whether the `got` type matches the `expected` type
// - TODO: Specify `extra_text` in all cases

expect_type :: proc(
    s: ^CheckerState,
    pos: uint,
    expected: ExpectedType,
    got: ExactCheckedType,
    extra_text: string,
    loc := #caller_location,
) -> bool {
    when debug_checker {
        print_call(loc, "expect_type")
        print_arg("expected", expected)
        print_arg("got", got)
    }
    switch e in expected {
    case AnyType:
        e.store^ = got
        return true
    case ExactCheckedType:
        return expect_exact_type(s, pos, e, got, extra_text)
    case FunctionWithExpectedReturnTypes:
        func_ref, is_func := get_func_type(s, pos, got)
        if !is_func {
            err(s, pos, "Expected a function")
            return false
        }
        func_info, _ := get_info(s.func_types[:], func_ref.index)
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
            if !expect_type(s, pos, e.expected_return_types[i], return_type, extra_text) {
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
    expected: ExactCheckedType,
    got: ExactCheckedType,
    extra_text: string,
    loc := #caller_location,
) -> bool {
    when debug_checker {
        print_call(loc, "expect_exact_type")
    }
    if !type_is_equal(s, got, expected, true) {
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
) -> ExactCheckedType {
    when debug_checker {
        print_call(loc, "get variable type")
    }
    scope := s.scopes[variable.nesting_level]
    return scope.variable_types[variable.index]
}

type_to_string :: proc(s: ^CheckerState, t: ExactCheckedType, loc := #caller_location) -> string {
    when debug_checker {
        print_call(loc, "type to string")
    }
    builder := strings.builder_make()
    build_type_string(s, &builder, t)
    return strings.to_string(builder)
}

build_struct_string :: proc(
    s: ^CheckerState,
    b: ^strings.Builder,
    type: Struct(ExactCheckedType),
) {
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
    t: ExactCheckedType,
    loc := #caller_location,
) {
    when debug_checker {
        print_call(loc, "build type string")
    }
    // TODO: Format the string better
    switch type in t {
    case nil:
        panic("Unreachable")
    case SumType(ExactCheckedType, FuncTypeRef):
        strings.write_byte(b, '<')
        first_variant := true
        for variant in type.variants {
            if !first_variant {
                strings.write_string(b, ", ")
            }
            first_variant = false
            strings.write_string(b, variant.name.ident)
            build_struct_string(s, b, variant.payload)
        }
        strings.write_byte(b, '>')
    case Struct(ExactCheckedType):
        build_struct_string(s, b, type)
    case GlobalTypeWithoutGenericRef:
        strings.write_string(b, s.global_types_without_generics[type.index].ast_node.name)
    case GenericType(u32):
        generic_arg, _ := get_info(s.type_equivalancy_array[:], uint(type.generic_arg))
        strings.write_string(
            b,
            s.global_types_with_generics[type.generic_type_index].ast_node.name,
        )
        strings.write_byte(b, '[')
        build_type_string(s, b, generic_arg)
        strings.write_byte(b, ']')
    case SumVariant(^ExactCheckedType):
        sum_type, ok := get_sum_type(s, max(uint), type.sum_type^)
        assert(ok)
        build_type_string(s, b, type.sum_type^)
        strings.write_byte(b, '.')
        strings.write_string(b, sum_type.variants[type.variant_index].name.ident)
    case FuncTypeRef:
        func, _ := get_info(s.func_types[:], type.index)
        switch func.type {
        case .Normal:
        // case .JsFunc:
        //     strings.write_string(b, "#js ")
        case .ComptimeFunc:
            strings.write_string(b, "#comptime ")
        }
        strings.write_byte(b, '(')
        for arg, index in func.args {
            // TODO: Print the name and whether the arg is mutable
            build_type_string(s, b, arg)
            if index + 1 != len(func.args) {
                strings.write_string(b, ", ")
            }
        }
        strings.write_string(b, ")")
        switch len(func.return_types) {
        case 0:
        case 1:
            strings.write_string(b, " -> ")
            build_type_string(s, b, func.return_types[0])
        case:
            strings.write_string(b, " -> (")
            first_return_type := true
            for return_type in func.return_types {
                if first_return_type == false {
                    strings.write_string(b, ", ")
                }
                first_return_type = false
                build_type_string(s, b, return_type)
            }
            strings.write_byte(b, ')')
        }
    // case JsObjectType:
    //     strings.write_string(b, "js.Object")
    case StringType:
        strings.write_string(b, "String")
    case I64Type:
        strings.write_string(b, "I64")
    case I32Type:
        strings.write_string(b, "I32")
    case I16Type:
        strings.write_string(b, "I16")
    case I8Type:
        strings.write_string(b, "I8")
    case U64Type:
        strings.write_string(b, "U64")
    case U32Type:
        strings.write_string(b, "U32")
    case U16Type:
        strings.write_string(b, "U16")
    case U8Type:
        strings.write_string(b, "U8")
    case BoolType:
        strings.write_string(b, "Bool")
    case ArrayType(u32):
        strings.write_byte(b, '[')
        if type.length != 0 {
            strings.write_uint(b, uint(type.length))
        }
        strings.write_byte(b, ']')
        item_type, _ := get_info(s.type_equivalancy_array[:], uint(type.item_type))
        build_type_string(s, b, item_type)
    }
}

pop_scope :: proc(s: ^CheckerState, loc := #caller_location) {
    when debug_checker {
        print_call(loc, "pop_scope")
    }
    for var_type in s.scopes[len(s.scopes) - 1].variable_types {
        assert(var_type != nil)
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

// The `CheckedValue` returned is the value of the destination array index
get_expected_value_type :: proc(
    s: ^CheckerState,
    var_name: IdentAndPos,
    var_type: ExactCheckedType,
    array_index: ^Unit,
    body: ^[dynamic]CheckedStatement,
) -> (
    ExactCheckedType,
    CheckedValue,
    bool,
) {
    if array_index == nil {
        return var_type, nil, true
    }
    warn(s, array_index.pos, "This array access is not bounds checked\nTODO: Bounds checks")
    array_ref, is_array := var_type.(ArrayType(u32))
    if !is_array {
        err(
            s,
            var_name.pos,
            "The variable `%s` is of type `%s`\nExpected an array",
            var_name.ident,
            type_to_string(s, var_type),
        )
        return nil, nil, false
    }
    array_item_type, _ := get_info(s.type_equivalancy_array[:], uint(array_ref.item_type))
    expected_type: ExactCheckedType = I64Type{}
    index_value := check_value(s, array_index^, body, expected_type)
    if index_value == nil {
        return array_item_type, nil, false
    }
    return array_item_type, index_value, true
}

check_mutation :: proc(
    s: ^CheckerState,
    destination: VariableDest,
    mutation_type: MutationType,
    value_type: ExactCheckedType,
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
    assert(value_type != nil)
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
        if expected_value_type != nil {
            if !expect_type(s, value_pos, expected_value_type, value_type, "") {
                return CheckedMutationDestination{}, .SetTo, false
            }
        }
        if !dest_ok {
            return CheckedMutationDestination{}, .SetTo, false
        }
        if mutation_type != .SetTo {
            if !type_is_numeric(value_type) {
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
    []ExactCheckedType,
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
            value_type: ExactCheckedType = nil
            checked_value := check_value(s, value.value, body, AnyType{&value_type})
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
            loop_index := s.loop_index
            s.loop_index += 1
            condition := check_value(s, value.condition, body, ExactCheckedType(BoolType{}))

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
            loop_index := s.loop_index
            s.loop_index += 1
            loop_body_array := make([dynamic]CheckedStatement)
            loop_enter: []CheckedStatement
            loop_end: []CheckedStatement
            switch iter in value.iterator {
            case Unit:
                type: ExactCheckedType = nil
                v := check_value(s, iter, body, AnyType{&type})
                if v == nil {
                    return nil, false
                }
                array, is_array := type.(ArrayType(u32))
                if !is_array {
                    err(
                        s,
                        iter.pos,
                        "Can only iterate over an array\nGot a value of type `%s`",
                        type_to_string(s, type),
                    )
                    return nil, false
                }
                array_item_type, _ := get_info(s.type_equivalancy_array[:], uint(array.item_type))
                if value.variables[2].ident != "" {
                    err(
                        s,
                        stmt.position,
                        "You can only capture at most 2 variables from iterating over an array",
                    )
                    return nil, false
                }
                elem_ref, elem_ok := add_variable(s, array_item_type, false, value.variables[0])
                index_ref, index_ok := add_variable(s, I64Type{}, false, value.variables[1])
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
                    I64Type{}, // TODO: Support types other than I64
                    false,
                    value.variables[0],
                )
                expected_type: ExactCheckedType = I64Type{}
                start := check_value(s, iter.start, &loop_body_array, expected_type)
                end := check_value(s, iter.end, &loop_body_array, expected_type)
                step: CheckedValue = ---
                if iter.step == nil {
                    step = CompileTimeValue(NumberValue{big_int_from_i64(1)})
                } else {
                    step = check_value(s, iter.step^, &loop_body_array, expected_type)
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
            expected_type: ExactCheckedType = BoolType{}
            condition := check_value(s, value.condition, body, expected_type)

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
                v := check_value(s, value[0], body, s.return_types[0])
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
            val_type: ExactCheckedType = nil
            val := check_value(s, value.value, body, AnyType{&val_type})
            if val == nil {
                return nil, false
            }

            val_sum_type, val_sum_type_ok := get_sum_type(s, value.value.pos, val_type)
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
                        panic("TODO")
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
                        SumVariant(^ExactCheckedType){new_clone(val_type), variant_index},
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
    expected_type: ExactCheckedType = I64Type{} // TODO: Do not assume number type
    return check_value(s, args[0], body, expected_type)
}

value_err1 :: "Compiler cannot generate a `.` function without knowing the return type of the function"

check_namespaced_var_ref :: proc(
    s: ^CheckerState,
    namespace: FileRef,
    ref: Ident,
    index: int,
) -> (
    CheckedValue,
    ExactCheckedType,
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
        return nil, nil, 0
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
            return nil, nil, 0
        case CheckedGlobalRuntimeValue:
            return value.inline_value, value.type, index + 1
        case Import:
            if index + 1 >= len(ref) {
                err(s, ref[index].pos, import_use_err)
                return nil, nil, 0
            }
            return check_namespaced_var_ref(s, value.file, ref, index + 1)
        }
    case GlobalTypeWithGenericRef:
        err(s, ref[index].pos, "No generic type argument passed to generic type")
        return nil, nil, 0
    case GlobalTypeWithoutGenericRef:
        func_type := s.global_types_without_generics[global_value.index].function_type
        if func_type.index == max(uint) {
            err(
                s,
                ref[index].pos,
                "The global type `%s` cannot be initialised like this",
                ref[index].ident,
            )
            return nil, nil, 0
        }
        return TypeInitFunc{global_value}, func_type, index + 1
    }
}

check_var_ref :: proc(
    s: ^CheckerState,
    ref: Ident,
    pos: uint,
    type: ExpectedType,
    body: ^[dynamic]CheckedStatement,
    loc := #caller_location,
) -> CheckedValue {
    when debug_checker {
        print_call(loc, "check_var_ref")
        print_arg("ref", ref)
        print_arg("type", type)
    }
    if len(ref) == 2 && ref[0].ident == "" {
        expected_return_type: ExactCheckedType = ---
        switch expected in type {
        case AnyType:
            err(s, pos, value_err1)
            return nil
        case ExactCheckedType:
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
            case ExactCheckedType:
                expected_return_type = expected_return
            }
        }

        sum_type, sum_type_ok := get_sum_type(s, pos, expected_return_type)
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
        func_ref := sum_type.variants[variant_index].extra_data
        if expect_type(s, pos, type, func_ref, "") {
            return TypeInitFunc {
                SumVariant(^ExactCheckedType){new_clone(expected_return_type), variant_index},
            }
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
    out_type: ExactCheckedType = ---
    start_i := 1

    if builtin_func_index, builtin_func_type := get_builtin_func_from_name(s, ref[0].ident);
       builtin_func_index != max(u32) {
        out = BuiltinFunction{builtin_func_index}
        out_type = builtin_func_type
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
            array, is_array := out_type.(ArrayType(u32))
            if !is_array {
                err(
                    s,
                    extra_segment.pos,
                    "Expected an array before `.len`, but got the type `%s`",
                    type_to_string(s, out_type),
                )
                return nil
            }
            out_type = I64Type{}
            out = length_of_array(array, out)
            continue
        } else if extra_segment.ident == "to_str" {
            converted := to_str(s, extra_segment.pos, out, out_type)
            if converted == nil {
                return nil
            }
            out_type = StringType{}
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

            out_type = U64Type{}
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
    return expect_type(s, pos, type, out_type, "") ? out : nil
}

check_array_initialisation :: proc(
    s: ^CheckerState,
    pos: uint,
    array_type: CallWithFrontedSquareBrackets,
    array_type_pos: uint,
    args: []Unit,
    body: ^[dynamic]CheckedStatement,
    expected_return_type: ExpectedType,
    loc := #caller_location,
) -> CheckedValue {
    when debug_checker {
        print_call(loc, "check_array_initialisation")
    }
    initialised_type := check_array_type(s, array_type_pos, array_type, "")
    if initialised_type == nil {
        return nil
    }
    generic_array_type := initialised_type.(ArrayType(^GenericCheckedType))
    if generic_array_type.length != 0 && len(args) != int(generic_array_type.length) {
        err(
            s,
            pos,
            "Type initialisation provides %d values\nType expects %d values",
            len(args),
            generic_array_type.length,
        )
        return nil
    }
    exact_array_type, array_item_type := create_generic_array_type(s, generic_array_type, nil)
    array_segments := make([]ArraySegment, len(args))
    ok := true
    for arg, i in args {
        value := check_value(s, arg, body, array_item_type)
        if value == nil {
            ok = false
        } else {
            array_segments[i] = SingleElemSegment{value}
        }
    }
    if !ok {
        return nil
    }
    array_ref := add_unnamed_variable(s, exact_array_type, false)
    append_elem(body, CheckedArrayMutation{array_ref, exact_array_type, array_segments})
    if !expect_type(s, array_type_pos, expected_return_type, exact_array_type, "") {
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

    func_args: []ExactCheckedType = ---
    func_type: FunctionType = ---
    when debug_checker {
        func_args = nil // So that `func_args` can be printed by `debug_arg` without causing a segfault
    }
    expected_type := FunctionWithExpectedReturnTypes{&func_args, &func_type, expected_return_types}
    value := check_value(s, call.unit_being_called^, body, expected_type)
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
        arg_value := check_value(s, arg, body, func_args[i])
        if arg_value == nil {
            return CheckedFunctionCall{}, false
        }
        checked_args[i] = arg_value
    }

    return CheckedFunctionCall{new_clone(value), checked_args}, true
}

AnyType :: struct {
    store: ^ExactCheckedType,
}

FunctionWithExpectedReturnTypes :: struct {
    args_store:            ^[]ExactCheckedType,
    type_store:            ^FunctionType,
    expected_return_types: []ExpectedType,
}

ExpectedType :: union {
    AnyType,
    ExactCheckedType,
    FunctionWithExpectedReturnTypes,
}

check_value_with_markers :: proc(
    s: ^CheckerState,
    v: Unit,
    markers: []IdentAndPos,
    body: ^[dynamic]CheckedStatement,
    type: ExpectedType,
) -> CheckedValue {
    if len(markers) == 0 {
        return check_value(s, v, body, type)
    }
    switch markers[0].ident {
    case "load":
        value := check_value_with_markers(s, v, markers[1:], body, ExactCheckedType(StringType{}))
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
        if !expect_type(s, markers[0].pos, type, StringType{}, "") {
            return nil
        }
        return CompileTimeValue(StringLiteralValue(data))
    case "debug_ast":
        debug_unit(nil, v)
    case:
        warn(s, markers[0].pos, "TODO: Handle the `%s` marker", markers[0].ident)
    }

    return check_value_with_markers(s, v, markers[1:], body, type)
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
) -> CheckedValue {
    array_err :: "Expected an array type\nGot the type `%s`"
    switch value.join_method {

    case .Colon:
        err(s, pos, "Cannot use `:` to join values")
        return nil

    case .Arrow:
        err(s, pos, "Cannot use `->` to join values")
        return nil

    case .BooleanAnd, .BooleanOr:
        val0 := check_value(s, value.unit0^, body, ExactCheckedType(BoolType{}))
        val1 := check_value(s, value.unit1^, body, ExactCheckedType(BoolType{}))
        if val0 == nil || val1 == nil {
            return nil
        }
        if expect_type(s, pos, type, BoolType{}, "") {
            return create_joined_values(value.join_method, val0, val1)
        }
        return nil

    case .IsEqual, .IsNotEqual:
        t: ExactCheckedType = nil
        val0 := check_value(s, value.unit0^, body, AnyType{&t})
        if val0 == nil {
            return nil
        }
        val1 := check_value(s, value.unit1^, body, t)
        if val1 == nil {
            return nil
        }
        if !expect_type(s, pos, type, ExactCheckedType(BoolType{}), "") {
            return nil
        }
        if _, is_string := t.(StringType); is_string {
            str_comp: CheckedValue = StringsAreEqual{new_clone(val0), new_clone(val1)}
            if value.join_method == .IsNotEqual {
                return create_not(str_comp)
            }
            return str_comp
        }
        return create_joined_values(value.join_method, val0, val1)

    case .Append:
        t: ExactCheckedType = nil
        val0 := check_value(s, value.unit0^, body, AnyType{&t})
        if val0 == nil {
            return nil
        }
        length, item_type_ref, item_type := check_array(s, value.unit0.pos, val0, t, array_err)
        if length == nil {
            return nil
        }
        val1 := check_value(s, value.unit1^, body, item_type)
        if val1 == nil {
            return nil
        }
        return_type := ArrayType(u32){0, item_type_ref} // TODO: Maybe `::` should be able to output fixed size arrays
        s.array_type_initialisations[combine_u32(return_type.length, return_type.item_type)] =
            struct{}{}
        if expect_type(s, pos, type, return_type, "") {
            segments := make([]ArraySegment, 2)
            segments[0] = InlineArraySegment{val0, length}
            segments[1] = SingleElemSegment{val1}
            array_ref := add_unnamed_variable(s, return_type, false)
            append_elem(body, CheckedArrayMutation{array_ref, return_type, segments})
            return array_ref
        }
        return nil

    case .StringConcat:
        val0 := check_value(s, value.unit0^, body, ExactCheckedType(StringType{}))
        val1 := check_value(s, value.unit1^, body, ExactCheckedType(StringType{}))
        if val0 == nil || val1 == nil {
            return nil
        }
        if expect_type(s, pos, type, ExactCheckedType(StringType{}), "") {
            return create_joined_values(.StringConcat, val0, val1)
        }
        return nil

    case .Concat:
        type0: ExactCheckedType = ---
        type1: ExactCheckedType = ---
        val0 := check_value(s, value.unit0^, body, AnyType{&type0})
        val1 := check_value(s, value.unit1^, body, AnyType{&type1})
        if val0 == nil || val1 == nil {
            return nil
        }
        length0, item_type0_ref, item_type0 := check_array(
            s,
            value.unit0.pos,
            val0,
            type0,
            array_err,
        )
        length1, item_type1_ref, item_type1 := check_array(
            s,
            value.unit1.pos,
            val1,
            type1,
            array_err,
        )
        if length0 == nil || length1 == nil {
            return nil
        }
        if item_type0_ref != item_type1_ref {
            if type_is_equal(s, item_type0, item_type1, true) {
                mark_elements_equal(
                    s.type_equivalancy_array[:],
                    uint(item_type0_ref),
                    uint(item_type1_ref),
                )
            } else {
                err(
                    s,
                    pos,
                    "Array item type mismatch:\nItem type on left is %s\nItem type on right is %s",
                    type_to_string(s, item_type0),
                    type_to_string(s, item_type1),
                )
                return nil
            }
        }
        return_type := ArrayType(u32){0, item_type0_ref} // TODO: Maybe `++` should be able to output fixed size arrays
        s.array_type_initialisations[combine_u32(return_type.length, return_type.item_type)] =
            struct{}{}
        if expect_type(s, pos, type, return_type, "") {
            segments := make([]ArraySegment, 2)
            segments[0] = InlineArraySegment{val0, length0}
            segments[1] = InlineArraySegment{val1, length1}
            array_ref := add_unnamed_variable(s, return_type, false)
            append_elem(body, CheckedArrayMutation{array_ref, return_type, segments})
            return array_ref
        }
        return nil

    case .IsGreaterThan, .IsGreaterThanOrEqual, .IsLessThan, .IsLessThanOrEqual:
        // TODO: Do not assume number types
        val0 := check_value(s, value.unit0^, body, ExactCheckedType(I64Type{}))
        val1 := check_value(s, value.unit1^, body, ExactCheckedType(I64Type{}))
        if val0 == nil || val1 == nil {
            return nil
        }
        if expect_type(s, pos, type, ExactCheckedType(BoolType{}), "") {
            return create_joined_values(value.join_method, val0, val1)
        }
        return nil

    case .Multiplication, .Subtraction, .Division, .Addition, .Modulo:
        // TODO: Do not assume number types
        val0 := check_value(s, value.unit0^, body, ExactCheckedType(I64Type{}))
        val1 := check_value(s, value.unit1^, body, ExactCheckedType(I64Type{}))
        if val0 == nil || val1 == nil {
            return nil
        }
        if expect_type(s, pos, type, ExactCheckedType(I64Type{}), "") {
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
    body: ^[dynamic]CheckedStatement,
    type: ExpectedType,
    loc := #caller_location,
) -> CheckedValue {
    when debug_checker {
        print_call(loc, "check_value")
    }
    switch value in v.value {
    case:
        err(s, v.pos, "Internal error: got nil value in check_value")
        return nil

    case Struct(Unit):
        err(s, v.pos, "Cannot use a struct type as a value")
        return nil
    case CallWithFrontedSquareBrackets:
        err(s, v.pos, "Cannot use a call with fronted square brackets as a value")
        return nil
    case SumType(Unit, struct {}):
        err(s, v.pos, "Cannot use a sum type as a value")
        return nil

    case Import:
        err(s, v.pos, import_use_err)
        return nil

    case MarkedUnit:
        return check_value_with_markers(s, value.value^, value.markers, body, type)

    case Tuple:
        if len(value.elements) != 1 {
            err(
                s,
                v.pos,
                "Only tuples with one element are supported\nThis tuple has %d elements",
                len(value.elements),
            )
            return false
        }
        return check_value(s, value.elements[0], body, type)

    case CallWithSquareBrackets:
        array_type: ExactCheckedType = nil
        array_value := check_value(s, value.unit_being_called^, body, AnyType{&array_type})
        index_value := check_array_index(s, v.pos, value.args, body)
        if array_value == nil {
            return nil
        }
        array_ref, is_array := array_type.(ArrayType(u32))
        if !is_array {
            err(
                s,
                value.unit_being_called.pos,
                "Expected an array, but got the type `%s`",
                type_to_string(s, array_type),
            )
            return nil
        }
        array_item_type, _ := get_info(s.type_equivalancy_array[:], uint(array_ref.item_type))
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
        if expect_type(s, v.pos, type, array_item_type, "") {
            return CheckedArrayAccess{new_clone(array_value), new_clone(index_value)}
        }
        return nil

    case Bool:
        if !expect_type(s, v.pos, type, BoolType{}, "") {
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
        return check_joined_unit_value(s, v.pos, value, body, type)

    case Ident:
        return check_var_ref(s, value, v.pos, type, body)

    case Number:
        // TODO: Check that min(i64) <= number <= max(i64)
        // TODO: Do not assume number type
        if !expect_type(s, v.pos, type, I64Type{}, "") {
            return nil
        }
        return CompileTimeValue(
            NumberValue{BigInt{value.is_negated, big_uint_from_string(value.absolute_digits)}},
        )

    case String:
        if expect_type(s, v.pos, type, StringType{}, "") {
            return CompileTimeValue(StringLiteralValue(strings.join(([]string)(value), "")))
        }
        return nil

    case Char:
        // TODO: Do not assume number type
        if !expect_type(s, v.pos, type, U8Type{}, "") {
            return nil
        }
        return CompileTimeValue(NumberValue{BigInt{false, big_uint_from_u64(u64(value))}})

    }
}

// The bool returned is whether the function checked successfully
check_function :: proc(
    s: ^CheckerState,
    func: FunctionDefinition,
    type: FuncTypeRef,
    loc := #caller_location,
) -> (
    CheckedFunction,
    bool,
) {
    when debug_checker {
        print_call(loc, "check_function")
    }
    f_props, simplified_index := get_info(s.func_types[:], type.index)
    s.func_type = f_props.type
    s.return_types = f_props.return_types
    s.loop_index = 0
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
    return CheckedFunction{FuncTypeRef{simplified_index}, variables, body[:]}, true
}

length_of_array :: proc(type: ArrayType(u32), value: CheckedValue) -> CheckedValue {
    if type.length != 0 {
        return CompileTimeValue(NumberValue{big_int_from_i64(i64(type.length))})
    }
    return LengthOfArray{new_clone(value)}
}

// Returns `nil, max(u32), nil` if there was an error
// The `CheckedValue` returned is the length of the array
// The `u32` returned is the simplified unique type reference
// The `ExactCheckedType` returned is the item type of the array
check_array :: proc(
    s: ^CheckerState,
    pos: uint,
    value: CheckedValue,
    value_type: ExactCheckedType,

    // The error message for if the value is not an array
    // Must have one `%s` in it for the actual type of the value
    err_msg: string,
) -> (
    CheckedValue,
    u32,
    ExactCheckedType,
) {
    array, is_array := value_type.(ArrayType(u32))
    if !is_array {
        err(s, pos, err_msg, type_to_string(s, value_type))
        return nil, max(u32), nil
    }
    item_type, item_type_index := get_info(s.type_equivalancy_array[:], uint(array.item_type))
    if array.length != 0 {
        return CompileTimeValue(NumberValue{big_int_from_i64(i64(array.length))}),
            u32(item_type_index),
            item_type
    }
    return length_of_array(array, value), u32(item_type_index), item_type
}

get_global_function :: proc(
    s: ^CheckerState,
    pos: uint,
    name: string,
    extra_text: string,
) -> (
    FuncDefinitionRef,
    bool,
) {
    global_props, exists := s.files[s.file.index].globals[name]
    if !exists {
        err(s, pos, "The global `%s` is not defined%s", name, extra_text)
        return FuncDefinitionRef{}, false
    }
    value_ref, is_value := global_props.value.(GlobalValueRef)
    if !is_value {
        err(
            s,
            pos,
            "The global `%s` is a type\nExpected it to be a function so it can be called%s",
            name,
            extra_text,
        )
        return FuncDefinitionRef{}, false
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
        return FuncDefinitionRef{}, false
    }
    return func_ref, true
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
    checked_funcs:                        []CheckedFunction,
    checked_global_types_without_generic: []ExactCheckedType,
    generic_type_initialisations:         GenericTypeInitialisationsStore,
    array_type_initialisations:           ArrayTypeInitialisationsStore,
    func_types:                           []EquivalencyArrayElem(ExactFuncType),
    type_equivalancy_array:               []EquivalencyArrayElem(ExactCheckedType),
}

// Function types
string_to_nil_type :: FuncTypeRef{0} // (String)
string_string_to_nil_type :: FuncTypeRef{1} // (String, String)
string_to_string_type :: FuncTypeRef{2} // (String) -> String
comptime_u64_to_string_type :: FuncTypeRef{3} // #comptime ((U64) -> String)
no_args_to_nil_type :: FuncTypeRef{4} // ()
array_of_strings_to_nil_type :: FuncTypeRef{5} // ([]String)
i64_to_nil_type :: FuncTypeRef{6} // (I64)

check :: proc(parsed: ParsedProject) -> CheckerOutput {
    state := CheckerState {
            files                         = parsed.files,
            generic_being_initialised     = GenericType(u32){max(u32), max(u32)},
            global_values                 = soa_zip(
                parsed.global_values,
                make([]CheckedGlobalValue, len(parsed.global_values)),
            ),
            global_types_without_generics = soa_zip(
                parsed.global_types_without_generics,
                make([]ExactCheckedType, len(parsed.global_types_without_generics)),
                make([]FuncTypeRef, len(parsed.global_types_without_generics)),
            ),
            global_types_with_generics    = soa_zip(
                parsed.global_types_with_generics,
                make([]GenericCheckedType, len(parsed.global_types_with_generics)),
            ),
            func_types                    = make([dynamic]EquivalencyArrayElem(ExactFuncType), 7),
        }

    array_with_string_type := make([]ExactCheckedType, 1)
    array_with_string_type[0] = StringType{}

    array_with_2string_types := make([]ExactCheckedType, 2)
    array_with_2string_types[0] = StringType{}
    array_with_2string_types[1] = StringType{}

    array_with_i64_type := make([]ExactCheckedType, 1)
    array_with_i64_type[0] = I64Type{}

    array_with_u64_type := make([]ExactCheckedType, 1)
    array_with_u64_type[0] = U64Type{}

    array_with_dynamic_array_of_strings := make([]ExactCheckedType, 1)
    array_with_dynamic_array_of_strings[0] = create_array_type(
        &state,
        0,
        u32(len(state.type_equivalancy_array)),
    )
    append_elem(&state.type_equivalancy_array, ExactCheckedType(StringType{}))

    state.func_types[string_to_nil_type.index] = ExactFuncType {
        array_with_string_type,
        nil,
        .Normal,
    }
    state.func_types[string_string_to_nil_type.index] = ExactFuncType {
        array_with_2string_types,
        nil,
        .Normal,
    }
    state.func_types[string_to_string_type.index] = ExactFuncType {
        array_with_string_type,
        array_with_string_type,
        .Normal,
    }
    state.func_types[comptime_u64_to_string_type.index] = ExactFuncType {
        array_with_u64_type,
        array_with_string_type,
        .ComptimeFunc,
    }
    state.func_types[no_args_to_nil_type.index] = ExactFuncType{nil, nil, .Normal}
    state.func_types[array_of_strings_to_nil_type.index] = ExactFuncType {
        array_with_dynamic_array_of_strings,
        nil,
        .Normal,
    }
    state.func_types[i64_to_nil_type.index] = ExactFuncType{array_with_i64_type, nil, .Normal}

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
            checked_func_type, _ := check_function_type(
                &state,
                func.inputs.value_type[:len(func.inputs)],
                func.output^,
                func_type,
                "",
            )
            state.global_values[i].value = CheckedGlobalRuntimeValue {
                FuncTypeRef{len(state.func_types)},
                func_ref,
            }
            append_elem(&state.func_types, make_func_type_exact(&state, checked_func_type, nil))
        } else if import_value, is_import := value.unit.value.(Import); is_import {
            state.global_values[i].value = import_value
        } else {
            body: [dynamic]CheckedStatement = nil
            type: ExactCheckedType = nil
            checked_value := check_value(&state, value.unit, &body, AnyType{&type})
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
        state.file = type.ast_node.file
        if is_builtin(type.ast_node.generic.ident) {
            err(&state, type.ast_node.generic.pos, builtins_err, type.ast_node.generic.ident)
        } else {
            expect_camel_case(&state, "generic names", type.ast_node.generic)
            state.global_types_with_generics[i].generic_type = check_type(
                &state,
                type.ast_node.value,
                type.ast_node.generic.ident,
            )
        }
    }

    for type, i in state.global_types_without_generics {
        state.file = type.ast_node.file
        checked_type := check_type(&state, type.ast_node.value, "")
        generic_elem := create_generic_type_elem(&state, checked_type, nil)
        state.global_types_without_generics[i].exact_type = generic_elem
        struct_type, is_struct := generic_elem.(Struct(ExactCheckedType))
        if is_struct {
            args := make([]ExactCheckedType, len(struct_type.fields))
            for field, j in struct_type.fields {
                args[j] = field.type
            }
            return_types := make([]ExactCheckedType, 1)
            return_types[0] = GlobalTypeWithoutGenericRef{uint(i)}
            state.global_types_without_generics[i].function_type = FuncTypeRef {
                uint(len(state.func_types)),
            }
            append_elem(&state.func_types, ExactFuncType{args, return_types, .Normal})
        } else {
            state.global_types_without_generics[i].function_type = FuncTypeRef{max(uint)}
        }
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
                    global_val.value.(CheckedGlobalRuntimeValue).type.(FuncTypeRef),
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

    // Initialise generic types
    when debug_checker {
        debug("Initialising uninitialised generic types")
        debug_nesting += 1
    }
    for key in state.generic_type_initialisations {
        generic_type_index, generic_arg := seperate_u64(key)
        initialise_generic(&state, generic_type_index, generic_arg, key)
    }
    when debug_checker {
        debug_nesting -= 1
    }

    when debug_checker {
        debug("Printing type equivalancy array elements")
        debug_nesting += 1
        for value, index in state.type_equivalancy_array {
            debug("Type equivalancy array element")
            debug_nesting += 1
            debug("Index is %d", index)
            debug("Value is %#v", value)
            debug_nesting -= 1
        }
        debug_nesting -= 1

        debug("Printing func type equivalancy array elements")
        debug_nesting += 1
        for func, index in state.func_types {
            debug("Func equivalancy array element at index %d", index)
            debug_nesting += 1
            debug("%#v", func)
            debug_nesting -= 1
        }
        debug_nesting -= 1
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
        build_info, _ := get_info(
            state.func_types[:],
            checked_functions[build_ref.index].type.index,
        )
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
        main_ref, main_ok := get_global_function(&state, max(uint), "main", hint)
        if !main_ok {
            return CheckerOutput{diagnostics_info = state.diagnostics_info}
        }
        main_info, _ := get_info(state.func_types[:], checked_functions[main_ref.index].type.index)
        if main_info.type != .Normal {
            err(
                &state,
                build_props.pos,
                "`main` has a marker\nExpected `main` to not have a marker",
            )
            return CheckerOutput{diagnostics_info = state.diagnostics_info}
        }
        entry_func_ref = main_ref
        entry_func_type = .MainFunc
    }
    if state.diagnostics_info.number_of_errors > 0 {
        return CheckerOutput{diagnostics_info = state.diagnostics_info}
    }
    checked := Checked {
        checked_functions,
        state.global_types_without_generics.exact_type[:len(state.global_types_without_generics)],
        state.generic_type_initialisations,
        state.array_type_initialisations,
        state.func_types[:],
        state.type_equivalancy_array[:],
    }
    return CheckerOutput{checked, state.diagnostics_info, entry_func_ref, entry_func_type}
}

