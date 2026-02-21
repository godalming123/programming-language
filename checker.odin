package main

import "base:intrinsics"
import "core:fmt"
import "core:strconv"
import "core:strings"

VariableRef :: struct {
    nesting_level: uint,
    index:         uint,
}

Scope :: struct {
    // The length of these arrays should be the same
    variable_types:   [dynamic]CheckedType,
    variable_is_muts: [dynamic]bool,
}

ArrayType :: struct {
    length:    uint, // 0 means dynamic length
    item_type: CheckedType,
}

FunctionType :: enum {
    Normal,
    // JsFunc,
    ComptimeFunc,
}

ArrayRef :: distinct uint // An index into `CheckerState.array_types`

CheckerState :: struct {
    // The following fields do not change while checking
    file:             CompilerFile,
    globals:          map[string]ParsedGlobal,
    funcs:            []FunctionDefinition,
    global_types:     []TypeValue,
    funcs_props:      []CheckedFunctionProps,

    // The following fields depend on the function currently being checked
    func_type:        FunctionType,
    return_type:      CheckedType,

    // The following fields depend on which variables are in scope
    scopes:           [dynamic]Scope,
    variables_map:    map[string]VariableRef,

    // The following field changes while checking
    // TODO: Use some sort of hash map to store the types in a program so that
    // you can figure out if a new type is the same as any type which has already
    // been used in the program in O(1) time.
    array_types:      [dynamic]union {
        ArrayType,
        ArrayRef,
    },
    loop_index:       uint,
    diagnostics_info: DiagnosticsInfo,
    // TODO: represent the order of the programmer controlled stack
}

CheckedFunction :: struct {
    inputs:    []CheckedType,
    output:    CheckedType,
    variables: []CheckedType,
    body:      []CheckedStatement,
}

StringLiteralValue :: distinct string
U8Value :: distinct u8
I64Value :: distinct i64
BooleanNotValue :: distinct ^CheckedValue
CheckedJoinedValues :: struct {
    join_method: ValueJoinMethod,
    val0:        ^CheckedValue,
    val1:        ^CheckedValue,
}
CheckedFunctionCall :: struct {
    index: uint,
    args:  []CheckedValue,
}
LengthOfArray :: struct {
    array: ^CheckedValue,
}
CheckedArrayAccess :: struct {
    // The code emitter might not emit code to sanity check the index
    array: ^CheckedValue,
    index: ^CheckedValue,
}
BoolValue :: distinct bool
CheckedValue :: union {
    StringLiteralValue,
    U8Value,
    I64Value,
    VariableRef,
    BooleanNotValue,
    CheckedJoinedValues,
    CheckedFunctionCall,
    BoolValue,
    CheckedArrayAccess,
    // CheckedJsFunctionCall,
    LengthOfArray,
    uint, // an index into the function definitions
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
// JsObjectType :: struct {}
FuncType :: struct {
    args:   []CheckedArg,
    output: ^CheckedType,
    type:   FunctionType,
}
CheckedType :: union {
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
    ArrayRef,
    // Type,
    // JsObjectType,
    FuncType,
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
                    "Expect %s to be `snake_case`\nUnexpected lowercase letter '%c' in an uppercase block of a snake case identifier\nExpected an underscore, a number, or an uppercase letter",
                    expected,
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
                    "Expect %s to be `snake_case`\nUnexpected uppercase letter '%c' in a lowercase block of a snake case identifier\nExpected an underscore, a number, or a lowercase letter",
                    expected,
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
            "Expect %s to be `CamelCase`\nFirst character in camel case ident must be an uppercase letter\nGot '%c'",
            expected,
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
                "Expect %s to be `CamelCase`\nCannot have `_` in a camel case identifier",
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

// Returns nil if there are errors in the type
check_type :: proc(s: ^CheckerState, type: Type) -> CheckedType {
    switch t in type.type {
    case DynamicType:
        err(s, type.pos, "TODO: Support checking dynamic type")
        return nil
    case Struct:
        err(s, type.pos, "TODO: Support checking struct type")
        return nil
    case Function:
        err(s, type.pos, "TODO: Support checking function type")
        return nil
    case TypeVariable:
        if t.generic_type != nil {
            err(s, type.pos, "TODO: Handle generic type")
            return nil
        }
        return handle_named_type(s, type.pos, t.identifier)
    case Array:
        item_type := check_type(s, t.item_type^)
        if item_type == nil {
            return nil
        }
        append_elem(&s.array_types, ArrayType{t.length, item_type})
        return ArrayRef(len(s.array_types) - 1)
    case SumType:
        err(s, type.pos, "TODO: Support checking sum type")
        return nil
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

CheckedPrint :: distinct CheckedValue // Always a string

CheckedWriteFile :: struct {
    file_name:     CheckedValue,
    file_contents: CheckedValue,
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
    variables:  []CheckedType,
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
    variables: []CheckedType,
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

StringInterpolation :: struct {
    variable: VariableRef, // the variable being mutated
    format:   string,
    values:   []CheckedValue,
}

CheckedStatement :: union {
    StringInterpolation,
    CheckedReturn,
    CheckedIf,
    CheckedWriteFile,
    CheckedLoop,
    CheckedPrint,
    ContinueLoop,
    BreakLoop,
    CheckedMutation,
    CheckedArrayMutation, // like `CheckedMutation`, except the value is an array
    CheckedFunctionCall,
    // CheckedJsFunctionCall,
    // CheckedJsAssignment,
}

type_is_numeric :: proc(type: CheckedType) -> bool {
    switch _ in type {
    case I64Type, I32Type, I16Type, I8Type, U64Type, U32Type, U16Type, U8Type:
        return true
    case StringType, BoolType, ArrayRef, FuncType:
        return false
    }
    panic("Unreachable")
}

// Returns whether the ref was simplified
simplify_array_ref :: proc(array_types: []union {
        ArrayType,
        ArrayRef,
    }, ref: ^ArrayRef) -> bool {
    new_ref, is_ref := array_types[ref^].(ArrayRef)
    if is_ref {
        ref^ = new_ref
        return true
    }
    return false
}

get_array_type :: proc(array_types: []union {
        ArrayType,
        ArrayRef,
    }, reference: ^ArrayRef) -> ArrayType {
    for simplify_array_ref(array_types, reference) {}
    return array_types[reference^].(ArrayType)
}

type_is_equal :: proc(s: ^CheckerState, type0: CheckedType, type1: CheckedType) -> bool {
    switch &t0 in type0 {
    case:
        panic("Unreachable")
    case FuncType:
        fmt.println("TODO: Check type equivalency for functions")
        return false
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
    case ArrayRef:
        t1, is_array := type1.(ArrayRef)
        if !is_array {
            return false
        }
        for {
            if t0 == t1 {
                return true
            } else if t0 > t1 {
                if !simplify_array_ref(s.array_types[:], &t0) {
                    break
                }
            } else {
                if !simplify_array_ref(s.array_types[:], &t1) {
                    break
                }
            }
        }
        t0_type := get_array_type(s.array_types[:], &t0)
        t1_type := get_array_type(s.array_types[:], &t1)
        if t0_type.length != t1_type.length {
            return false // TODO: Maybe fixed size arrays should coerce into dynamic size arrays
        }
        equal := type_is_equal(s, t0_type.item_type, t1_type.item_type)
        if equal {
            larger_array := max(t0, t1)
            smaller_array := min(t0, t1)
            s.array_types[larger_array] = ArrayRef(smaller_array)
        }
        return equal
    }
}

// The boolean returned is whether the `got` type matches the `expected` type
expect_type :: proc(
    s: ^CheckerState,
    pos: uint,
    expected: CheckedType,
    got: CheckedType,
    extra_text: string, // TODO: Specify `extra_text` in all cases
) -> bool {
    if !type_is_equal(s, got, expected) {
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

get_type :: proc(s: ^CheckerState, value: CheckedValue) -> CheckedType {
    switch v in value {
    case uint:
        props := s.funcs_props[v]
        return FuncType{props.args, new_clone(props.return_type), props.func_type}
    case CheckedArrayAccess:
        array_ref := get_type(s, v.array^).(ArrayRef)
        array_type := get_array_type(s.array_types[:], &array_ref)
        return array_type.item_type
    case BoolValue:
        return BoolType{}
    case CheckedFunctionCall:
        return s.funcs_props[v.index].return_type
    case StringLiteralValue:
        return StringType{}
    case U8Value:
        return U8Type{}
    case I64Value:
        return I64Type{}
    case VariableRef:
        scope := s.scopes[v.nesting_level]
        return scope.variable_types[v.index]
    case BooleanNotValue:
        return BoolType{}
    case CheckedJoinedValues:
        switch v.join_method {
        case .BooleanAnd,
             .BooleanOr,
             .IsEqual,
             .IsNotEqual,
             .IsGreaterThan,
             .IsGreaterThanOrEqual,
             .IsLessThan,
             .IsLessThanOrEqual:
            return BoolType{}
        case .Division, .Multiplication, .Subtraction, .Addition, .Modulo:
            return I64Type{} // TODO: do not assume type
        }
    // case CheckedJsFunctionCall:
    //     return JsObjectType{}
    case LengthOfArray:
        return I64Type{} // TODO: do not assume type
    }
    panic("Unreachable")
}

type_to_string :: proc(s: ^CheckerState, t: CheckedType) -> string {
    builder := strings.builder_make()
    build_type_string(s, &builder, t)
    return strings.to_string(builder)
}

build_type_string :: proc(s: ^CheckerState, b: ^strings.Builder, t: CheckedType) {
    switch &type in t {
    case FuncType:
        switch type.type {
        case .Normal:
        // case .JsFunc:
        //     strings.write_string(b, "#js ")
        case .ComptimeFunc:
            strings.write_string(b, "#comptime ")
        }
        strings.write_byte(b, '(')
        for arg, index in type.args {
            // TODO: Print the name and whether the arg is mutable
            build_type_string(s, b, arg.type)
            if index + 1 != len(type.args) {
                strings.write_string(b, ", ")
            }
        }
        strings.write_string(b, ") -> ")
        build_type_string(s, b, type.output^)
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
    case ArrayRef:
        array_type := get_array_type(s.array_types[:], &type)
        strings.write_byte(b, '[')
        if array_type.length != 0 {
            strings.write_uint(b, array_type.length)
        }
        strings.write_byte(b, ']')
        build_type_string(s, b, array_type.item_type)
    }
}

check_function_call :: proc(
    s: ^CheckerState,
    pos: uint,
    call: FunctionCall,
    body: ^[dynamic]CheckedStatement,
    loc := #caller_location,
) -> (
    CheckedValue,
    bool,
) {
    when debug_checker {
        print_call(loc, "check function call")
    }
    function_name, is_var_ref := call.function.value.(VariableReference)
    if !is_var_ref {
        err(s, pos, "TODO: Handle function calls where the function isn't a variable reference")
        return nil, false
    }
    return handle_named_function_call(s, pos, ([]string)(function_name), call.args, body)
}

pop_scope :: proc(s: ^CheckerState) {
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
    var_type: CheckedType,
    array_index: ^Value,
    body: ^[dynamic]CheckedStatement,
) -> (
    CheckedType,
    CheckedValue,
    bool,
) {
    if array_index == nil {
        return var_type, nil, true
    }
    warn(s, array_index.pos, "This array access is not bounds checked\nTODO: Bounds checks")
    array_ref, is_array := var_type.(ArrayRef)
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
    array_type := get_array_type(s.array_types[:], &array_ref)
    index_value := check_value(s, array_index^, body)
    if index_value == nil {
        return array_type.item_type, nil, false
    }
    index_type_ok := expect_type(
        s,
        array_index.pos,
        I64Type{},
        get_type(s, index_value),
        "Array index must be `I64`",
    )
    if !index_type_ok {
        return array_type.item_type, nil, false
    }
    return array_type.item_type, index_value, true
}

check_mutation :: proc(
    s: ^CheckerState,
    destination: VariableDest,
    mutation_type: MutationType,
    value_type: CheckedType,
    value_pos: uint,
    body: ^[dynamic]CheckedStatement,
) -> (
    CheckedMutationDestination,
    MutationType,
    bool,
) {
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
        var_type := get_type(s, var_ref)
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
    CheckedBlock,
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
            checked_value := check_value(s, value.value, body)
            if len(value.destination) != 1 {
                err(
                    s,
                    stmt.position,
                    "TODO: Handle variable management where len(value.destination) != 1",
                )
                return CheckedBlock{}, false
            }
            if checked_value == nil {
                return CheckedBlock{}, false
            }
            mutation_dest, mutation_type, mutation_ok := check_mutation(
                s,
                value.destination[0],
                value.mutation_type,
                get_type(s, checked_value),
                value.value.pos,
                body,
            )
            if !mutation_ok {
                return CheckedBlock{}, false
            }
            append_elem(body, CheckedMutation{mutation_dest, mutation_type, checked_value})
        case FunctionCall:
            func_value, ok := check_function_call(s, stmt.position, value, body)
            if !ok {
                return CheckedBlock{}, false
            }
            if func_value != nil {
                err(s, stmt.position, "Cannot use this value as a statement")
                return CheckedBlock{}, false
            }
        case ConditionControlledLoop:
            append_elem(&s.scopes, Scope{})
            defer pop_scope(s)
            loop_index := s.loop_index
            s.loop_index += 1
            condition := check_value(s, value.condition, body)
            if condition != nil {
                if !expect_type(
                    s,
                    value.condition.pos,
                    BoolType{},
                    get_type(s, condition),
                    "\nExpect loop condition to be a boolean",
                ) {
                    condition = nil
                }
            }
            loop_body_array := make([dynamic]CheckedStatement)
            loop_body, loop_body_ok := check_block(s, value.body, &loop_body_array)
            if condition == nil || !loop_body_ok {
                return CheckedBlock{}, false
            }

            exit_loop := make([]CheckedStatement, 1)
            exit_loop[0] = BreakLoop{loop_index}
            condition_check := CheckedIf{condition, CheckedBlock{}, CheckedBlock{nil, exit_loop}}
            loop_body_with_condition := make([]CheckedStatement, len(loop_body.body) + 1)
            if value.type == .WhileLoop {
                loop_body_with_condition[0] = condition_check
                copy_slice(loop_body_with_condition[1:], loop_body.body)
            } else {
                index := copy_slice(loop_body_with_condition, loop_body.body)
                loop_body_with_condition[index] = condition_check
            }
            append_elem(
                body,
                CheckedLoop{loop_index, loop_body.variables, loop_body_with_condition, nil},
            )
        case ForInLoop:
            append_elem(&s.scopes, Scope{})
            defer pop_scope(s)
            loop_index := s.loop_index
            s.loop_index += 1
            loop_body_array := make([dynamic]CheckedStatement)
            loop_enter: []CheckedStatement
            loop_start: []CheckedStatement
            loop_end: []CheckedStatement
            switch iter in value.iterator {
            case Value:
                v := check_value(s, iter, body)
                if v == nil {
                    return CheckedBlock{}, false
                }
                type := get_type(s, v)
                array_ref, is_array := type.(ArrayRef)
                if !is_array {
                    err(
                        s,
                        iter.pos,
                        "Can only iterate over an array\nGot a value of type `%s`",
                        type_to_string(s, type),
                    )
                    return CheckedBlock{}, false
                }
                array := get_array_type(s.array_types[:], &array_ref)
                if value.variables[2].ident != "" {
                    err(
                        s,
                        stmt.position,
                        "You can only capture at most 2 variables from iterating over an array",
                    )
                    return CheckedBlock{}, false
                }
                elem_ref, elem_ok := add_variable(s, array.item_type, false, value.variables[0])
                index_ref, index_ok := add_variable(s, I64Type{}, false, value.variables[1])
                if !elem_ok || !index_ok {
                    return CheckedBlock{}, false
                }
                loop_enter = make([]CheckedStatement, 1)
                loop_enter[0] = CheckedMutation {
                    CheckedMutationDestination{index_ref, nil},
                    .SetTo,
                    I64Value(0),
                }
                loop_start = make([]CheckedStatement, 2)
                if_block := make([]CheckedStatement, 1)
                if_block[0] = BreakLoop{loop_index}
                loop_start[0] = CheckedIf {
                    CheckedJoinedValues {
                        .IsGreaterThanOrEqual,
                        new_clone(CheckedValue(index_ref)),
                        new_clone(
                            array.length == 0 ? CheckedValue(LengthOfArray{new_clone(v)}) : CheckedValue(I64Value(array.length)),
                        ),
                    },
                    CheckedBlock{nil, if_block},
                    CheckedBlock{},
                }
                loop_start[1] = CheckedMutation {
                    CheckedMutationDestination{elem_ref, nil},
                    .SetTo,
                    CheckedArrayAccess{new_clone(v), new_clone(CheckedValue(index_ref))},
                }
                loop_end = make([]CheckedStatement, 1)
                loop_end[0] = CheckedMutation {
                    CheckedMutationDestination{index_ref, nil},
                    .IncrementBy,
                    I64Value(1),
                }
            case NumericIterator:
                if value.variables[1].ident != "" || value.variables[2].ident != "" {
                    err(
                        s,
                        stmt.position,
                        "You can only capture at most one variable in a numeric iterator",
                    )
                    return CheckedBlock{}, false
                }
                index_variable, var_ok := add_variable(
                    s,
                    I64Type{}, // TODO: Support types other than I64
                    false,
                    value.variables[0],
                )
                start := check_value(s, iter.start, &loop_body_array)
                end := check_value(s, iter.end, &loop_body_array)
                step :=
                    iter.step == nil ? CheckedValue(I64Value(1)) : check_value(s, iter.step^, &loop_body_array)
                if !var_ok || start == nil || end == nil || step == nil {
                    return CheckedBlock{}, false
                }
                loop_enter = make([]CheckedStatement, 1)
                loop_enter[0] = CheckedMutation {
                    CheckedMutationDestination{index_variable, nil},
                    .SetTo,
                    start,
                }
                if_block := make([]CheckedStatement, 1)
                if_block[0] = BreakLoop{loop_index}
                loop_start = make([]CheckedStatement, 1)
                loop_start[0] = CheckedIf {
                    CheckedJoinedValues {
                        iter.type == .IncludeEndValue ? .IsGreaterThan : .IsGreaterThanOrEqual,
                        new_clone(CheckedValue(index_variable)),
                        new_clone(end),
                    },
                    CheckedBlock{nil, if_block},
                    CheckedBlock{},
                }
                loop_end = make([]CheckedStatement, 1)
                loop_end[0] = CheckedMutation {
                    CheckedMutationDestination{index_variable, nil},
                    .IncrementBy,
                    step,
                }
            }
            loop_body, loop_body_ok := check_block(s, value.body, &loop_body_array)
            if !loop_body_ok {
                return CheckedBlock{}, false
            }
            full_body := make(
                []CheckedStatement,
                len(loop_start) + len(loop_body.body) + len(loop_end),
            )
            copy_slice(full_body, loop_start)
            copy_slice(full_body[len(loop_start):], loop_body.body)
            copy_slice(full_body[len(loop_start) + len(loop_body.body):], loop_end)
            append_elem(body, CheckedLoop{loop_index, loop_body.variables, full_body, loop_enter})
        case IfElseStatement:
            condition := check_value(s, value.condition, body)
            if condition != nil {
                type := get_type(s, condition)
                _, is_bool := get_type(s, condition).(BoolType)
                if !is_bool {
                    err(
                        s,
                        value.condition.pos,
                        "If statement condition must be of type bool\nGot %s",
                        type_to_string(s, type),
                    )
                    condition = nil
                }
            }

            append_elem(&s.scopes, Scope{})
            if_block_array := make([dynamic]CheckedStatement)
            if_block, if_block_ok := check_block(s, value.if_block, &if_block_array)
            pop_scope(s)

            append_elem(&s.scopes, Scope{})
            else_block_array := make([dynamic]CheckedStatement)
            else_block, else_block_ok := check_block(s, value.else_block, &else_block_array)
            pop_scope(s)

            if condition == nil || !if_block_ok || !else_block_ok {
                return CheckedBlock{}, false
            }
            append_elem(body, CheckedIf{condition, if_block, else_block})
        case ReturnStatement:
            if stmt_index + 1 != len(block) {
                err(s, stmt.position, "Return statement must be last statement in block")
                return CheckedBlock{}, false
            }
            if len(value) != 1 {
                err(
                    s,
                    stmt.position,
                    "Can only have one value in return statement (TODO: add support for returning multiple values)",
                )
                return CheckedBlock{}, false
            }
            v := check_value(s, value[0], body)
            if v == nil {
                return CheckedBlock{}, false
            }
            type_ok := expect_type(s, value[0].pos, s.return_type, get_type(s, v), "")
            if !type_ok {
                return CheckedBlock{}, false
            }
            append_elem(body, CheckedReturn{v})
        case YieldStatement:
            err(s, stmt.position, "TODO: Handle yield statement")
            return CheckedBlock{}, false
        }
    }
    return CheckedBlock{s.scopes[len(s.scopes) - 1].variable_types[:], body[:]}, true
}

// Returns nil if there was an error
check_array_index :: proc(s: ^CheckerState, pos: uint, index: union {
        SingleElemAccess,
        RangedAccess,
    }, body: ^[dynamic]CheckedStatement) -> CheckedValue {
    warn(s, pos, "This array access is not bounds checked\nTODO: Bounds checks")
    unchecked_value, is_single_elem_access := index.(SingleElemAccess)
    if !is_single_elem_access {
        err(s, pos, "TODO: Multi elem array access")
        return nil
    }
    checked_value := check_value(s, unchecked_value^, body)
    if checked_value == nil {
        return nil
    }
    type := get_type(s, checked_value)
    is_i64 := expect_type(s, pos, I64Type{}, type, "")
    if !is_i64 {
        return nil
    }
    return checked_value
}

check_var_ref :: proc(s: ^CheckerState, ref: VariableReference, pos: uint) -> (VariableRef, bool) {
    if len(ref) != 1 {
        err(
            s,
            pos,
            "TODO: Handle where the number of segments in an identifier in a value isn't 1",
        )
        return VariableRef{}, false
    }
    var_index, ok := s.variables_map[ref[0]]
    if ok {
        return var_index, true
    } else {
        err(s, pos, "The variable `%s` is not defined", ref[0])
        return VariableRef{}, false
    }
}

// - Returns `nil` if there are errors in the value
// - The `body` arg may be appended to with statements that should be executed
//   before the value is accessed
check_value :: proc(
    s: ^CheckerState,
    v: Value,
    body: ^[dynamic]CheckedStatement,
    loc := #caller_location,
) -> CheckedValue {
    when debug_checker {
        print_call(loc, "check value")
    }
    switch value in v.value {
    case:
        err(s, v.pos, "Internal error: got nil value in check_value")
        return nil
    case MarkedValue:
        err(s, v.pos, "TODO: Handle marked values")
        return nil
    case ValueInBrackets:
        return check_value(s, value^, body)
    case ArrayAccess:
        array_value := check_value(s, value.array^, body)
        index_value := check_array_index(s, value.index_pos, value.index, body)
        if array_value == nil {
            return nil
        }
        array_type := get_type(s, array_value)
        array_ref, is_array := array_type.(ArrayRef)
        if !is_array {
            err(
                s,
                value.array.pos,
                "Expected an array, but got the type `%s`",
                type_to_string(s, array_type),
            )
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
        return CheckedArrayAccess{new_clone(array_value), new_clone(index_value)}
    case TypeInitialisation:
        type := check_type(s, Type{v.pos, value.type})
        if type == nil {
            return nil
        }
        switch &t in type {
        case StringType,
             I64Type,
             I32Type,
             I16Type,
             I8Type,
             U64Type,
             U32Type,
             U16Type,
             U8Type,
             // JsObjectType,
             FuncType,
             BoolType:
            err(
                s,
                v.pos,
                "The type `%s` is not initialised like this\nOnly array types can by initialised using a type initialiser",
                type_to_string(s, type),
            )
            return nil
        case ArrayRef:
            array_type := get_array_type(s.array_types[:], &t)
            if array_type.length != 0 && uint(len(value.args)) != array_type.length {
                err(
                    s,
                    v.pos,
                    "Type initialisation provides %d values\nType expects %d values",
                    len(value.args),
                    array_type.length,
                )
                return nil
            }
            array_segments := make([]ArraySegment, len(value.args))
            ok := true
            for arg, i in value.args {
                value := check_value(s, arg, body)
                if value == nil {
                    ok = false
                } else {
                    array_segments[i] = SingleElemSegment{value}
                }
            }
            if !ok {
                return nil
            }
            array_ref := add_unnamed_variable(s, t, false)
            append_elem(body, CheckedArrayMutation{array_ref, array_type, array_segments})
            return array_ref
        case:
            panic("Unreachable")
        }
    case Bool:
        return BoolValue(value)
    case uint:
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
    case FunctionCall:
        val, ok := check_function_call(s, v.pos, value, body)
        if !ok {
            return nil
        }
        if val == nil {
            err(s, v.pos, "This function call cannot be used as a value")
            return nil
        }
        return val
    case JoinedValues:
        val0 := check_value(s, value.val0^, body)
        val1 := check_value(s, value.val1^, body)
        if val0 == nil || val1 == nil {
            return nil
        }
        type0 := get_type(s, val0)
        type1 := get_type(s, val1)
        switch value.join_method {
        case .BooleanAnd, .BooleanOr:
            ok0 := expect_type(s, value.val0.pos, BoolType{}, type0, "")
            ok1 := expect_type(s, value.val0.pos, BoolType{}, type0, "")
            if !ok0 | !ok1 {
                return nil
            }
        case .IsEqual, .IsNotEqual:
            if !expect_type(s, value.val1.pos, type0, type1, "") {
                return nil
            }
        case .IsGreaterThan,
             .IsGreaterThanOrEqual,
             .IsLessThan,
             .IsLessThanOrEqual,
             .Multiplication,
             .Subtraction,
             .Division,
             .Addition,
             .Modulo:
            if !type_is_numeric(type0) {
                err(
                    s,
                    value.val0.pos,
                    "Expected type in numeric operation to be numeric, but got the type `%s`",
                    type_to_string(s, type0),
                )
                return nil
            }
            if !type_is_numeric(type1) {
                err(
                    s,
                    value.val1.pos,
                    "Expected type in numeric operation to be numeric, but got the type `%s`",
                    type_to_string(s, type1),
                )
                return nil
            }
            if !type_is_equal(s, type0, type1) {
                err(
                    s,
                    value.val0.pos,
                    "Expected types in numeric operation to be the same, but got `%s` and `%s`",
                    type_to_string(s, type0),
                    type_to_string(s, type1),
                )
                return nil
            }
        }
        return CheckedJoinedValues{value.join_method, new_clone(val0), new_clone(val1)}
    case VariableReference:
        var_ref, ok := check_var_ref(s, value, v.pos)
        if !ok {
            return nil
        }
        return var_ref
    case Number:
        parsed, ok := strconv.parse_i64(string(value))
        if !ok {
            err(s, v.pos, "Could not convert number `%s` to I64", value)
            return nil
        }
        return I64Value(parsed)
    case String:
        return StringLiteralValue(strings.join(([]string)(value), ""))
    case Char:
        return U8Value(value)
    }
}

// The bool returned is whether the function checked successfully
check_function :: proc(
    s: ^CheckerState,
    index: uint,
    loc := #caller_location,
) -> (
    CheckedFunction,
    bool,
) {
    when debug_checker {
        print_call(loc, "check function")
    }
    f := s.funcs[index]
    f_props := s.funcs_props[index]
    s.return_type = f_props.return_type
    append_elem(&s.scopes, Scope{})
    defer pop_scope(s)
    inputs := make([]CheckedType, len(f.inputs))
    ok := true
    for arg, i in f_props.args {
        _, var_ok := add_variable(s, arg.type, arg.is_mutable, arg.name)
        if var_ok {
            inputs[i] = arg.type
        } else {
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
    block, block_ok := check_block(s, f.body, &body)
    if !block_ok {
        return CheckedFunction{}, false
    }
    return CheckedFunction{inputs, s.funcs_props[index].return_type, block.variables, block.body},
        true
}

// Returns `nil, 0, nil` if there was an error
// The `CheckedValue` returned is the length of the array
// The `ArrayRef` returned is the simplified reference to the array
// The `CheckedType` returned is the item type of the array
check_array :: proc(
    s: ^CheckerState,
    pos: uint,
    value: CheckedValue,

    // The error message for if the value is not an array
    // Must have one `%s` in it for the actual type of the value
    err_msg: string,
) -> (
    CheckedValue,
    ArrayRef,
    ArrayType,
) {
    type := get_type(s, value)
    array_ref, is_array := type.(ArrayRef)
    if !is_array {
        err(s, pos, err_msg, type_to_string(s, type))
        return nil, 0, ArrayType{}
    }
    array_type := get_array_type(s.array_types[:], &array_ref)
    if array_type.length != 0 {
        return I64Value(array_type.length), array_ref, array_type
    }
    return LengthOfArray{new_clone(value)}, array_ref, array_type
}

CheckedArg :: struct {
    type:       CheckedType,
    is_mutable: bool,
    name:       IdentAndPos,
}

CheckedFunctionProps :: struct {
    args:        []CheckedArg,
    return_type: CheckedType,
    func_type:   FunctionType,
}

get_global_function :: proc(
    s: ^CheckerState,
    pos: uint,
    name: string,
    extra_text: string,
) -> (
    uint,
    bool,
) {
    global_props, exists := s.globals[name]
    if !exists {
        err(s, pos, "The global `%s` is not defined%s", name, extra_text)
        return 0, false
    }
    value, is_value := global_props.value.(Value)
    if !is_value {
        err(
            s,
            pos,
            "The global `%s` is a type\nExpected it to be a function so it can be called%s",
            name,
            extra_text,
        )
        return 0, false
    }
    func_index, is_func := value.value.(uint)
    if !is_func {
        err(
            s,
            pos,
            "The global value `%s` is not a function and so cannot be called%s",
            name,
            extra_text,
        )
        return 0, false
    }
    return func_index, true
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
    checked_funcs:    []CheckedFunction,
    array_types:      []union {
        ArrayType,
        ArrayRef,
    },
    entry_func_index: uint,
    entry_func_type:  EntryFuncType,
    diagnostics_info: DiagnosticsInfo,
}

check :: proc(
    file: CompilerFile,
    imports: []Import,
    globals: map[string]ParsedGlobal,
    funcs: []FunctionDefinition,
    global_types: []TypeValue,
) -> CheckerOutput {
    state := CheckerState {
        file         = file,
        funcs        = funcs,
        globals      = globals,
        global_types = global_types,
        funcs_props  = make([]CheckedFunctionProps, len(funcs)),
        array_types  = make([dynamic]union {
                ArrayType,
                ArrayRef,
            }),
    }
    for file_import in imports {
        warn(&state, file_import.pos, "TODO: Support modules")
    }
    for func, i in funcs {
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
        return_type: CheckedType
        switch len(func.outputs) {
        case 0:
        case 1:
            return_type = check_type(&state, func.outputs[0].value_type)
            if return_type == nil {
                continue
            }
        case:
            err(&state, func.outputs[1].value_type.pos, "TODO: Support more than one return type")
            continue
        }
        args := make([]CheckedArg, len(func.inputs))
        for input, i in func.inputs {
            type := check_type(&state, input.value_type)
            if type == nil {
                continue
            }
            args[i] = CheckedArg{type, input.arg_type == .Mutable, input.name}
        }
        state.funcs_props[i] = CheckedFunctionProps{args, return_type, func_type}
    }
    if state.diagnostics_info.number_of_errors > 0 {
        return CheckerOutput{diagnostics_info = state.diagnostics_info}
    }

    checked_functions := make([]CheckedFunction, len(funcs))

    for global_name, global in globals {
        switch value in global.value {
        case Value:
            expect_snake_case(&state, "variable names", IdentAndPos{global_name, global.pos})
            func_index, is_func := value.value.(uint)
            if !is_func {
                warn(&state, global.pos, "TODO: Handle global values that aren't function defs")
                continue
            }
            state.func_type = state.funcs_props[func_index].func_type
            state.loop_index = 0
            checked_func, checking_ok := check_function(&state, func_index)
            assert(len(state.scopes) == 0)
            assert(len(state.variables_map) == 0)
            if checking_ok {
                checked_functions[func_index] = checked_func
            }
        case uint:
            expect_camel_case(&state, "type names", IdentAndPos{global_name, global.pos})
            warn(&state, global.pos, "TODO: Handle types")
        }
    }

    // TODO: Check the arguments and return types of the `build` or `main` functions
    hint ::
        "\n\nHint: If you define a `build` function, the compiler will run that " +
        "function at compile time to build the program, for example:\n\n" +
        "```\n" +
        "build = #comptime || {\n" +
        "    code = compiler.emit_c_code(this_can_have_any_name)\n" +
        "    compiler.write_file(\"code.c\", code)\n" +
        "}\n" +
        "this_can_have_any_name = || -> I64 {\n    println(\"Hello world\")\n    return 0\n}\n" +
        "```\n\nIf no `build` function is defined, then you must specify a " +
        "`main` function, and the compiler will just emit C code to run that " +
        "`main` function, for example:\n\n" +
        "```\n" +
        "main = || -> I64 {\n    println(\"Hello world\")\n    return 0\n}\n" +
        "```\n\n" +
        "TODO: Add link to docs"

    entry_func_index: uint = ---
    entry_func_type: EntryFuncType = ---
    if build_props, build_exists := globals["build"]; build_exists {
        build_value, build_is_value := build_props.value.(Value)
        if !build_is_value {
            err(&state, build_props.pos, "`build` is a type\nExpected it to be a function%s", hint)
            return CheckerOutput{diagnostics_info = state.diagnostics_info}
        }
        build_index, build_is_func := build_value.value.(uint)
        if !build_is_func {
            err(
                &state,
                build_props.pos,
                "`build` is a value other than a function\nExpected it to be a function%s",
                hint,
            )
            return CheckerOutput{diagnostics_info = state.diagnostics_info}
        }
        if state.funcs_props[build_index].func_type != .ComptimeFunc {
            err(
                &state,
                build_props.pos,
                "`build` is not marked with `#comptime`\nExpected it to be marked with `#comptime`%s",
                hint,
            )
            return CheckerOutput{diagnostics_info = state.diagnostics_info}
        }
        entry_func_index = build_index
        entry_func_type = .BuildFunc
    } else {
        main_index, main_ok := get_global_function(&state, max(uint), "main", hint)
        if !main_ok {
            return CheckerOutput{diagnostics_info = state.diagnostics_info}
        }
        if state.funcs_props[main_index].func_type != .Normal {
            err(
                &state,
                build_props.pos,
                "`main` has a marker\nExpected `main` to not have a marker",
            )
            return CheckerOutput{diagnostics_info = state.diagnostics_info}
        }
        entry_func_index = main_index
        entry_func_type = .MainFunc
    }
    if state.diagnostics_info.number_of_errors > 0 {
        return CheckerOutput{diagnostics_info = state.diagnostics_info}
    }
    return CheckerOutput {
        checked_functions,
        state.array_types[:],
        entry_func_index,
        entry_func_type,
        state.diagnostics_info,
    }
}

