package main

import "base:intrinsics"
import "core:fmt"

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

ArrayRef :: distinct uint // An index into `CheckerState.array_types`

CheckerState :: struct {
    file:               CompilerFile,
    globals:            map[string]ParsedGlobal,
    global_funcs:       []FunctionDefinition,
    global_types:       []TypeValue,
    global_funcs_props: []CheckedFunctionProps,
    scopes:             [dynamic]Scope,
    variables_map:      map[string]VariableRef,
    return_type:        CheckedType,
    // TODO: Use some sort of hash map to store the types in a program so that
    // you can figure out if a new type is the same as any type which has already
    // been used in the program in O(1) time.
    array_types:        [dynamic]union {
        ArrayType,
        ArrayRef,
    },
    // TODO: represent the order of the programmer controlled stack
}

CheckedFunction :: struct {
    inputs:    []CheckedType,
    output:    CheckedType,
    variables: []CheckedType,
    body:      []CheckedStatement,
}

StringValue :: distinct string
U8Value :: distinct u8
I64Value :: distinct string // TODO: use i64 instead of string
VariableValue :: distinct VariableRef
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
ArrayValue :: struct {
    array_type:   ArrayRef,
    array_values: []CheckedValue,
}
CheckedArrayAccess :: struct {
    // The code emitter might not emit code to sanity check the index
    array: ^CheckedValue,
    index: ^CheckedValue,
}
BoolValue :: distinct bool
CheckedValue :: union {
    StringValue,
    U8Value,
    I64Value,
    VariableValue,
    BooleanNotValue,
    CheckedJoinedValues,
    CheckedFunctionCall,
    ArrayValue,
    BoolValue,
    CheckedArrayAccess,
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

// The boolean returned is whether the identifier is snake case
expect_snake_case :: proc(s: ^CheckerState, expected: string, ident: IdentAndPos) -> bool {
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
                err_ok(
                    s.file,
                    ident.pos + i,
                    "Expect %s to be `snake_case`\nUnexpected lowercase letter '%c' in an uppercase block of a snake case identifier\nExpected an underscore, a number, or an uppercase letter",
                    expected,
                    ident.ident[i],
                )
                return false
            }
        case .UpperCase:
            switch state {
            case .NotInBlock:
                state = .InUppercaseBlock
            case .InUppercaseBlock:
            case .InLowercaseBlock:
                err_ok(
                    s.file,
                    ident.pos + i,
                    "Expect %s to be `snake_case`\nUnexpected uppercase letter '%c' in a lowercase block of a snake case identifier\nExpected an underscore, a number, or a lowercase letter",
                    expected,
                    ident.ident[i],
                )
                return false
            }
        case .Digit:
        case .Underscore:
            state = .NotInBlock
        case .Unknown:
            err_ok(
                s.file,
                ident.pos + i,
                "Unexpected character '%c' in identifier `%s`",
                ident.ident[i],
                ident.ident,
            )
            return false
        }
        i += 1
    }
    return true
}

// The boolean returned is whether the identifier is camel case
expect_camel_case :: proc(s: ^CheckerState, expected: string, ident: IdentAndPos) -> bool {
    if get_character_group(ident.ident[0]) != .UpperCase {
        err_ok(
            s.file,
            ident.pos,
            "Expect %s to be `CamelCase`\nFirst character in camel case ident must be an uppercase letter\nGot '%c'",
            expected,
            ident.ident[0],
        )
        return false
    }
    for c, i in ident.ident[1:] {
        switch get_character_group(u8(c)) {
        case .Underscore:
            err_ok(
                s.file,
                ident.pos + uint(i) + 1,
                "Expect %s to be `CamelCase`\nCannot have `_` in a camel case identifier",
                expected,
            )
            return false
        case .LowerCase, .UpperCase, .Digit:
        case .Unknown:
            err_ok(
                s.file,
                ident.pos + uint(i) + 1,
                "Unexpected character '%c' in identifier `%s`",
                ident.ident[i],
                ident.ident,
            )
            return false
        }
    }
    return true
}

// Returns nil if there are errors in the type
check_type :: proc(file: CompilerFile, array_types: ^[dynamic]union {
        ArrayType,
        ArrayRef,
    }, type: Type) -> CheckedType {
    switch t in type.type {
    case DynamicType:
        err_ok(file, type.pos, "TODO: Support checking dynamic type")
        return nil
    case Struct:
        err_ok(file, type.pos, "TODO: Support checking struct type")
        return nil
    case Function:
        err_ok(file, type.pos, "TODO: Support checking function type")
        return nil
    case TypeVariable:
        if len(t) != 1 {
            err_ok(file, type.pos, "TODO: Type references with `.` in them")
            return nil
        }
        return handle_named_type(file, type.pos, t[0])
    case Array:
        item_type := check_type(file, array_types, t.item_type^)
        if item_type == nil {
            return nil
        }
        append_elem(array_types, ArrayType{t.length, item_type})
        return ArrayRef(len(array_types) - 1)
    case SumType:
        err_ok(file, type.pos, "TODO: Support checking sum type")
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

CheckedPrint :: struct {
    format: string, // Should not be wrapped in ""
    values: []CheckedValue,
}

CheckedLoop :: struct {
    variables: []CheckedType,
    body:      []CheckedStatement,
    enter:     []CheckedStatement,
}

ContinueLoop :: struct {
    block_nesting_level: uint,
}
BreakLoop :: struct {
    block_nesting_level: uint,
}

CheckedBlock :: struct {
    variables: []CheckedType,
    body:      []CheckedStatement,
}

MutationType :: enum {
    Increment,
    Decrement,
    MultiplyBy,
    DivideBy,
    SetTo,
}

CheckedSingleVariableMutation :: struct {
    mutation_type: MutationType,
    variable:      VariableRef,
    value:         CheckedValue,
}

CheckedArrayElementMutation :: struct {
    // The code emitter might not emit code to sanity check the index
    array: VariableRef,
    index: CheckedValue,
    value: CheckedValue,
}

CheckedStatement :: union {
    CheckedReturn,
    CheckedIf,
    CheckedLoop,
    CheckedPrint,
    ContinueLoop,
    BreakLoop,
    CheckedSingleVariableMutation,
    CheckedArrayElementMutation,
    CheckedFunctionCall,
}

type_is_numeric :: proc(type: CheckedType) -> bool {
    switch _ in type {
    case I64Type, I32Type, I16Type, I8Type, U64Type, U32Type, U16Type, U8Type:
        return true
    case StringType, BoolType, ArrayRef:
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
expect_type :: proc(s: ^CheckerState, pos: uint, expected: CheckedType, got: CheckedType) -> bool {
    if !type_is_equal(s, got, expected) {
        err_ok(
            s.file,
            pos,
            "Expected the type %s but got the type %s", // TODO: Say why that type is expected
            type_to_string(s, expected),
            type_to_string(s, got),
        )
        return false
    }
    return true
}

get_type :: proc(s: ^CheckerState, value: CheckedValue) -> CheckedType {
    switch v in value {
    case CheckedArrayAccess:
        array_ref := get_type(s, v.array^).(ArrayRef)
        array_type := get_array_type(s.array_types[:], &array_ref)
        return array_type.item_type
    case BoolValue:
        return BoolType{}
    case CheckedFunctionCall:
        return s.global_funcs_props[v.index].return_type
    case StringValue:
        return StringType{}
    case U8Value:
        return U8Type{}
    case I64Value:
        return I64Type{}
    case VariableValue:
        scope := s.scopes[v.nesting_level]
        return scope.variable_types[v.index]
    case BooleanNotValue:
        return BoolType{}
    case ArrayValue:
        return v.array_type
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
    }
    panic("Unreachable")
}

type_to_string :: proc(s: ^CheckerState, t: CheckedType) -> string {
    switch &type in t {
    case StringType:
        return "String"
    case I64Type:
        return "I64"
    case I32Type:
        return "I32"
    case I16Type:
        return "I16"
    case I8Type:
        return "I8"
    case U64Type:
        return "U64"
    case U32Type:
        return "U32"
    case U16Type:
        return "U16"
    case U8Type:
        return "U8"
    case BoolType:
        return "Bool"
    case ArrayRef:
        array_type := get_array_type(s.array_types[:], &type)
        if array_type.length == 0 {
            return fmt.aprintf("[]%s", type_to_string(s, array_type.item_type))
        }
        return fmt.aprintf("[%d]%s", type_to_string(s, array_type.item_type))
    }
    panic("Unreachable")
}

// Returns nil if there are errors in the function call
check_function_call :: proc(s: ^CheckerState, pos: uint, call: FunctionCall) -> union {
        CheckedPrint,
        CheckedFunctionCall,
        I64Value,
    } {
    function_name, is_var_ref := call.function.value.(VariableReference)
    if !is_var_ref {
        err_ok(
            s.file,
            pos,
            "TODO: Handle function calls where the function isn't a variable reference",
        )
        return nil
    }
    if len(function_name) != 1 {
        err_ok(
            s.file,
            pos,
            "TODO: Handle function calls where the number of segments in the function name isn't 1",
        )
        return nil
    }
    return handle_named_function_call(s, pos, function_name[0], call.args)
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

// The boolean returned is whether there are errors in the block
check_block :: proc(s: ^CheckerState, block: []Statement) -> (CheckedBlock, bool) {
    assert(
        len(s.scopes[len(s.scopes) - 1].variable_types) ==
        len(s.scopes[len(s.scopes) - 1].variable_is_muts),
    )
    body := make([dynamic]CheckedStatement)
    for stmt, stmt_index in block {
        switch value in stmt.value {
        case VariableManagement:
            checked_value, value_ok := check_value(s, value.value)
            type := value_ok ? get_type(s, checked_value) : nil
            ok := true
            variable_is_mutable := false
            if len(value.destination) != 1 {
                err_ok(
                    s.file,
                    stmt.position,
                    "TODO: Handle variable management where len(value.destination) != 1",
                )
                ok = false
            } else if value.destination[0].array_index != nil {
                if value.destination[0].type != .Mutated {
                    err_ok(
                        s.file,
                        value.destination[0].name.pos,
                        "Expected value to be mutated\nTry adding `~`",
                    )
                    return CheckedBlock{}, false
                }
                var_index, ok := s.variables_map[value.destination[0].name.ident]
                if !ok {
                    err_ok(
                        s.file,
                        value.destination[0].name.pos,
                        "The variable `%s` is not defined",
                        value.destination[0].name.ident,
                    )
                    return CheckedBlock{}, false
                }
                if s.scopes[var_index.nesting_level].variable_is_muts[var_index.index] == false {
                    err_ok(
                        s.file,
                        value.destination[0].name.pos,
                        "The variable `%s` is not mutable",
                        value.destination[0].name.ident,
                    )
                    return CheckedBlock{}, false
                }
                var_type := get_type(s, VariableValue(var_index))
                array_ref, is_array := var_type.(ArrayRef)
                if !is_array {
                    err_ok(
                        s.file,
                        value.destination[0].name.pos,
                        "The variable `%s` is of type `%s`\nExpected an array",
                        value.destination[0].name.ident,
                        type_to_string(s, var_type),
                    )
                    return CheckedBlock{}, false
                }
                array := get_array_type(s.array_types[:], &array_ref)
                array_type_ok := expect_type(s, value.value.pos, array.item_type, type)
                if !array_type_ok {
                    return CheckedBlock{}, false
                }
                index_value, index_value_ok := check_value(s, value.destination[0].array_index^)
                if !index_value_ok {
                    return CheckedBlock{}, false
                }
                index_type := get_type(s, index_value)
                index_type_ok := expect_type(s, value.value.pos, I64Type{}, index_type)
                if !index_type_ok {
                    return CheckedBlock{}, false
                }
                append_elem(
                    &body,
                    CheckedArrayElementMutation {
                        VariableRef(var_index),
                        index_value,
                        checked_value,
                    },
                )
                break
            } else {
                switch value.destination[0].type {
                case .Constant:
                case .Mutable:
                    variable_is_mutable = true
                case .ConstantAddedToPcs, .MutableAddedToPcs, .Mutated:
                    err_ok(s.file, stmt.position, "TODO: Handle more variable management types")
                    ok = false
                }
            }
            // TODO: Handle value.destination[0].array_index
            if value.mutation_type != .SetTo {
                err_ok(
                    s.file,
                    stmt.position,
                    "TODO: Handle variable management where value.mutation_type != .SetTo",
                )
                ok = false
            }
            if !ok || !value_ok {
                return CheckedBlock{}, false
            }
            variable, variable_ok := add_variable(
                s,
                type,
                variable_is_mutable,
                value.destination[0].name,
            )
            if !variable_ok {
                return CheckedBlock{}, false
            }
            array_value, is_array_value := checked_value.(ArrayValue)
            if is_array_value {
                array_type := get_array_type(s.array_types[:], &array_value.array_type)
                assert(array_type.length != 0)
                if len(array_value.array_values) != 0 {
                    for i in 0 ..< array_type.length {
                        append_elem(
                            &body,
                            CheckedArrayElementMutation {
                                variable,
                                I64Value(fmt.aprint(i)),
                                array_value.array_values[i],
                            },
                        )
                    }
                }
            } else {
                append_elem(&body, CheckedSingleVariableMutation{.SetTo, variable, checked_value})
            }
        case FunctionCall:
            switch checked in check_function_call(s, stmt.position, value) {
            case nil:
                return CheckedBlock{}, false
            case CheckedPrint:
                append_elem(&body, checked)
            case CheckedFunctionCall:
                append_elem(&body, checked)
            case I64Value:
                err_ok(s.file, stmt.position, "Cannot use this value as a statement")
                return CheckedBlock{}, false
            }
        case DoWhileLoop, WhileLoop:
            err_ok(s.file, stmt.position, "TODO: Handle while loops")
            return CheckedBlock{}, false
        case ForInLoop:
            append_elem(&s.scopes, Scope{})
            defer pop_scope(s)
            loop_enter: []CheckedStatement
            loop_start: []CheckedStatement
            loop_end: []CheckedStatement
            switch iter in value.iterator {
            case Value:
                v, ok := check_value(s, iter)
                if !ok {
                    return CheckedBlock{}, false
                }
                type := get_type(s, v)
                array_ref, is_array := type.(ArrayRef)
                if !is_array {
                    err_ok(
                        s.file,
                        iter.pos,
                        "Can only iterate over an array\nGot a value of type `%s`",
                        type_to_string(s, type),
                    )
                    return CheckedBlock{}, false
                }
                array := get_array_type(s.array_types[:], &array_ref)
                if array.length == 0 {
                    err_ok(s.file, iter.pos, "TODO: Be able to iterate over dynamic length arrays")
                    return CheckedBlock{}, false
                }
                if value.variables[2].ident != "" {
                    err_ok(
                        s.file,
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
                loop_enter[0] = CheckedSingleVariableMutation{.SetTo, index_ref, I64Value("0")}
                loop_start = make([]CheckedStatement, 2)
                if_block := make([]CheckedStatement, 1)
                if_block[0] = BreakLoop{index_ref.nesting_level}
                loop_start[0] = CheckedIf {
                    CheckedJoinedValues {
                        .IsGreaterThanOrEqual,
                        new_clone(CheckedValue(VariableValue(index_ref))),
                        new_clone(CheckedValue(I64Value(fmt.aprint(array.length)))),
                    },
                    CheckedBlock{nil, if_block},
                    CheckedBlock{},
                }
                loop_start[1] = CheckedSingleVariableMutation {
                    .SetTo,
                    elem_ref,
                    CheckedArrayAccess {
                        new_clone(v),
                        new_clone(CheckedValue(VariableValue(index_ref))),
                    },
                }
                loop_end = make([]CheckedStatement, 1)
                loop_end[0] = CheckedSingleVariableMutation{.Increment, index_ref, I64Value("1")}
            case NumericIterator:
                if value.variables[1].ident != "" || value.variables[2].ident != "" {
                    err_ok(
                        s.file,
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
                start, start_ok := check_value(s, iter.start)
                end, end_ok := check_value(s, iter.end)
                step := CheckedValue(I64Value("1"))
                step_ok := true
                if iter.step != nil {
                    step, step_ok = check_value(s, iter.step^)
                }
                if !var_ok || !start_ok || !end_ok || !step_ok {
                    return CheckedBlock{}, false
                }
                loop_enter = make([]CheckedStatement, 1)
                loop_enter[0] = CheckedSingleVariableMutation{.SetTo, index_variable, start}
                if_block := make([]CheckedStatement, 1)
                if_block[0] = BreakLoop{index_variable.nesting_level}
                loop_start = make([]CheckedStatement, 1)
                loop_start[0] = CheckedIf {
                    CheckedJoinedValues {
                        iter.type == .IncludeEndValue ? .IsGreaterThan : .IsGreaterThanOrEqual,
                        new_clone(CheckedValue(VariableValue(index_variable))),
                        new_clone(end),
                    },
                    CheckedBlock{nil, if_block},
                    CheckedBlock{},
                }
                loop_end = make([]CheckedStatement, 1)
                loop_end[0] = CheckedSingleVariableMutation{.Increment, index_variable, step}
            }
            loop_body, loop_body_ok := check_block(s, value.body)
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
            append(
                &body,
                CheckedLoop{variables = loop_body.variables, body = full_body, enter = loop_enter},
            )
        case IfElseStatement:
            condition, condition_ok := check_value(s, value.condition)
            if condition_ok {
                type := get_type(s, condition)
                #partial switch _ in type {
                case BoolType:
                case:
                    err_ok(
                        s.file,
                        value.condition.pos,
                        "If statement condition must be of type bool\nGot %s",
                        type_to_string(s, type),
                    )
                    condition_ok = false
                }
            }

            append_elem(&s.scopes, Scope{})
            if_block, if_block_ok := check_block(s, value.if_block)
            pop_scope(s)

            append_elem(&s.scopes, Scope{})
            else_block, else_block_ok := check_block(s, value.else_block)
            pop_scope(s)

            if !condition_ok | !if_block_ok | !else_block_ok {
                return CheckedBlock{}, false
            }
            append_elem(&body, CheckedIf{condition, if_block, else_block})
        case ReturnStatement:
            if stmt_index + 1 != len(block) {
                err_ok(s.file, stmt.position, "Return statement must be last statement in block")
                return CheckedBlock{}, false
            }
            if len(value) != 1 {
                err_ok(
                    s.file,
                    stmt.position,
                    "Can only have one value in return statement (TODO: add support for returning multiple values)",
                )
                return CheckedBlock{}, false
            }
            v, value_ok := check_value(s, value[0])
            if !value_ok {
                return CheckedBlock{}, false
            }
            type_ok := expect_type(s, value[0].pos, s.return_type, get_type(s, v))
            if !type_ok {
                return CheckedBlock{}, false
            }
            append_elem(&body, CheckedReturn{v})
        case YieldStatement:
            err_ok(s.file, stmt.position, "TODO: Handle yield statement")
            return CheckedBlock{}, false
        }
    }
    return CheckedBlock{s.scopes[len(s.scopes) - 1].variable_types[:], body[:]}, true
}

// Returns nil if there was an error
check_array_index :: proc(s: ^CheckerState, pos: uint, index: union {
        SingleElemAccess,
        RangedAccess,
    }) -> CheckedValue {
    err_ok(s.file, pos, "WARNING: This array access is not bounds checked\nTODO: Bounds checks")
    unchecked_value, is_single_elem_access := index.(SingleElemAccess)
    if !is_single_elem_access {
        err_ok(s.file, pos, "TODO: Multi elem array access")
        return nil
    }
    checked_value, ok := check_value(s, unchecked_value^)
    if !ok {
        return nil
    }
    type := get_type(s, checked_value)
    is_i64 := expect_type(s, pos, I64Type{}, type)
    if !is_i64 {
        return nil
    }
    return checked_value
}

// The boolean returned is whether there are errors in the value
check_value :: proc(s: ^CheckerState, v: Value) -> (CheckedValue, bool) {
    switch value in v.value {
    case:
        err_ok(s.file, v.pos, "Internal error: got nil value in check_value")
        return nil, false
    case ValueInBrackets:
        return check_value(s, value^)
    case ArrayAccess:
        index_value := check_array_index(s, value.index_pos, value.index)
        array_value, ok := check_value(s, value.array^)
        if !ok {
            return nil, false
        }
        array_type := get_type(s, array_value)
        array_ref, is_array := array_type.(ArrayRef)
        if !is_array {
            err_ok(
                s.file,
                value.array.pos,
                "Expected an array, but got the type `%s`",
                type_to_string(s, array_type),
            )
            return nil, false
        }
        array := get_array_type(s.array_types[:], &array_ref)
        if array.length == 0 {
            err_ok(
                s.file,
                value.array.pos,
                "TODO: Implement element access for dynamically sized arrays",
                type_to_string(s, array_type),
            )
            return nil, false
        }
        if index_value == nil {
            return nil, false
        }
        return CheckedArrayAccess{new_clone(array_value), new_clone(index_value)}, true
    case TypeInitialisation:
        type := check_type(s.file, &s.array_types, Type{v.pos, value.type})
        if type == nil {
            return nil, false
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
             BoolType:
            err_ok(
                s.file,
                v.pos,
                "The type `%s` is not initialised like this\nOnly array types can by initialised using a type initialiser",
                type_to_string(s, type),
            )
            return nil, false
        case ArrayRef:
            array_type := get_array_type(s.array_types[:], &t)
            if array_type.length == 0 {
                err_ok(s.file, v.pos, "TODO: Support dynamic sized array initialisations")
                return nil, false
            }
            if len(value.args) == 0 {
                return ArrayValue{t, nil}, true
            }
            if uint(len(value.args)) != array_type.length {
                err_ok(
                    s.file,
                    v.pos,
                    "Type initialisation provides %d values\nType expects %d values",
                    len(value.args),
                    array_type.length,
                )
                return nil, false
            }
            array_values := make([]CheckedValue, len(value.args))
            ok := true
            for arg, i in value.args {
                value, value_ok := check_value(s, arg)
                if value_ok {
                    array_values[i] = value
                } else {
                    ok = false
                }
            }
            if !ok {
                return nil, false
            }
            return ArrayValue{t, array_values}, true
        case:
            panic("Unreachable")
        }
    case Bool:
        return BoolValue(value), true
    case uint:
        err_ok(s.file, v.pos, "TODO: Handle function definition")
        return nil, false
    case FunctionCall:
        switch stmt in check_function_call(s, v.pos, value) {
        case nil:
            return nil, false
        case CheckedFunctionCall:
            return stmt, true
        case I64Value:
            return stmt, true
        case CheckedPrint:
            err_ok(s.file, v.pos, "This function call cannot be used as a value")
            return nil, false
        }
        panic("Unreachable")
    case JoinedValues:
        val0, val0_ok := check_value(s, value.val0^)
        val1, val1_ok := check_value(s, value.val1^)
        if !val0_ok | !val1_ok {
            return nil, false
        }
        type0 := get_type(s, val0)
        type1 := get_type(s, val1)
        switch value.join_method {
        case .BooleanAnd, .BooleanOr:
            ok0 := expect_type(s, value.val0.pos, BoolType{}, type0)
            ok1 := expect_type(s, value.val0.pos, BoolType{}, type0)
            if !ok0 | !ok1 {
                return nil, false
            }
        case .IsEqual, .IsNotEqual:
            if !expect_type(s, value.val1.pos, type0, type1) {
                return nil, false
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
                err_ok(
                    s.file,
                    value.val0.pos,
                    "Expected type in numeric operation to be numeric, but got the type `%s`",
                    type_to_string(s, type0),
                )
                return nil, false
            }
            if !type_is_numeric(type1) {
                err_ok(
                    s.file,
                    value.val1.pos,
                    "Expected type in numeric operation to be numeric, but got the type `%s`",
                    type_to_string(s, type1),
                )
                return nil, false
            }
            if !type_is_equal(s, type0, type1) {
                err_ok(
                    s.file,
                    value.val0.pos,
                    "Expected types in numeric operation to be the same, but got `%s` and `%s`",
                    type_to_string(s, type0),
                    type_to_string(s, type1),
                )
                return nil, false
            }
        }
        return CheckedJoinedValues{value.join_method, new_clone(val0), new_clone(val1)}, true
    case VariableReference:
        if len(value) != 1 {
            err_ok(
                s.file,
                v.pos,
                "TODO: Handle where the number of segments in an identifier in a value isn't 1",
            )
            return nil, false
        }
        var_index, ok := s.variables_map[value[0]]
        if ok {
            return VariableValue(var_index), true
        } else {
            err_ok(s.file, v.pos, "The variable `%s` is not defined", value[0])
            return nil, false
        }
    case Number:
        return I64Value(value), true
    case String:
        return StringValue(value), true
    case Char:
        return U8Value(value), true
    }
}

// The boolean returned is whether there are errors in the function
check_function :: proc(
    s: ^CheckerState,
    index: uint,
    loc := #caller_location,
) -> (
    CheckedFunction,
    bool,
) {
    when debug_checker {
        print_call(Loc(loc), "check function")
    }
    assert(len(s.scopes) == 0)
    assert(len(s.variables_map) == 0)
    assert(s.return_type == nil)
    s.return_type = s.global_funcs_props[index].return_type
    defer s.return_type = nil
    f := s.global_funcs[index]
    append(&s.scopes, Scope{})
    defer pop_scope(s)
    inputs := make([]CheckedType, len(f.inputs))
    for arg, i in s.global_funcs_props[index].args {
        add_variable(s, arg.type, arg.is_mutable, arg.name)
        inputs[i] = arg.type
    }
    append(&s.scopes, Scope{})
    defer pop_scope(s)
    // TODO: Check that the function always returns if it has a return type
    block, ok := check_block(s, f.body)
    if !ok {
        return CheckedFunction{}, false
    }
    return CheckedFunction {
            inputs,
            s.global_funcs_props[index].return_type,
            block.variables,
            block.body,
        },
        true
}

CheckedArg :: struct {
    type:       CheckedType,
    is_mutable: bool,
    name:       IdentAndPos,
}

CheckedFunctionProps :: struct {
    args:        []CheckedArg,
    return_type: CheckedType,
}

get_global_function :: proc(
    file: CompilerFile,
    globals: map[string]ParsedGlobal,
    pos: uint,
    name: string,
    extra_text: string,
) -> (
    uint,
    bool,
) {
    global_props, exists := globals[name]
    if !exists {
        err_ok(file, pos, "The global `%s` is not defined%s", name, extra_text)
        return 0, false
    }
    value, is_value := global_props.value.(Value)
    if !is_value {
        err_ok(
            file,
            pos,
            "The global `%s` is a type\nExpected it to be a function so it can be called%s",
            name,
            extra_text,
        )
        return 0, false
    }
    func_index, is_func := value.value.(uint)
    if !is_func {
        err_ok(
            file,
            pos,
            "The global value `%s` is not a function and so cannot be called%s",
            name,
            extra_text,
        )
        return 0, false
    }
    return func_index, true
}

// The boolean returned is whether there are errors in the code
// The uint returned is the index of the main function
check :: proc(
    file: CompilerFile,
    imports: []Import,
    globals: map[string]ParsedGlobal,
    global_funcs: []FunctionDefinition,
    global_types: []TypeValue,
) -> (
    []CheckedFunction,
    []union {
        ArrayType,
        ArrayRef,
    },
    uint,
    bool,
) {
    main_index, ok := get_global_function(
        file,
        globals,
        max(uint),
        "main",
        "\nHint: A hello world program is defined like so:\n```\nmain = () {{\n    println(\"Hello world\")\n}\n```\nTODO: Add link to docs",
    )
    if !ok {
        return nil, nil, max(uint), false
    }

    global_funcs_props := make([]CheckedFunctionProps, len(global_funcs))
    array_types := make([dynamic]union {
            ArrayType,
            ArrayRef,
        })
    for func, i in global_funcs {
        return_type: CheckedType
        switch len(func.outputs) {
        case 0:
        case 1:
            return_type = check_type(file, &array_types, func.outputs[0].value_type)
            if return_type == nil {
                ok = false
                continue
            }
        case:
            err_ok(file, func.outputs[1].value_type.pos, "TODO: Support more than one return type")
            ok = false
            continue
        }
        args := make([]CheckedArg, len(func.inputs))
        for input, i in func.inputs {
            type := check_type(file, &array_types, input.value_type)
            if type == nil {
                ok = false
                continue
            }
            args[i] = CheckedArg{type, input.arg_type == .Mutable, input.name}
        }
        global_funcs_props[i] = CheckedFunctionProps{args, return_type}
    }
    if !ok {
        return nil, nil, max(uint), false
    }

    checked_functions := make([]CheckedFunction, len(global_funcs))
    state := CheckerState {
        file               = file,
        globals            = globals,
        global_funcs       = global_funcs,
        global_types       = global_types,
        global_funcs_props = global_funcs_props,
        array_types        = array_types,
    }

    for global_name, global in globals {
        switch value in global.value {
        case Value:
            expect_snake_case(&state, "variable names", IdentAndPos{global_name, global.pos})
            index, is_func := value.value.(uint)
            if !is_func {
                err_ok(file, global.pos, "TODO: Handle global values that aren't function defs")
                ok = false
                continue
            }
            checked_func, func_ok := check_function(&state, index)
            if func_ok {
                checked_functions[index] = checked_func
            } else {
                ok = false
            }
        case uint:
            expect_camel_case(&state, "type names", IdentAndPos{global_name, global.pos})
            err_ok(file, global.pos, "TODO: Handle types")
            ok = false
        }
    }
    if !ok {
        return nil, nil, max(uint), false
    }

    return checked_functions, state.array_types[:], main_index, true
}

