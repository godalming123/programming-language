package main

VariableRef :: struct {
    nesting_level: uint,
    index:         uint,
}

Scope :: struct {
    // The length of these arrays should be the same
    variable_types:   [dynamic]CheckedType,
    variable_is_muts: [dynamic]bool,
}

CheckerState :: struct {
    file:          CompilerFile,
    globals:       map[string]Global,
    scopes:        [dynamic]Scope,
    variables_map: map[string]VariableRef,
    // TODO: represent the order of the programmer controlled stack
}

CheckedFunction :: struct {
    inputs:    []CheckedType,
    outputs:   []CheckedType,
    variables: []CheckedType,
    body:      []CheckedStatement,
}

StringValue :: distinct string
I64Value :: distinct string // TODO: use i64 instead of string
VariableValue :: distinct VariableRef
BooleanNotValue :: distinct ^CheckedValue
CheckedJoinedValues :: struct {
    join_method: ValueJoinMethod,
    val0:        ^CheckedValue,
    val1:        ^CheckedValue,
}
CheckedValue :: union {
    StringValue,
    I64Value,
    VariableValue,
    BooleanNotValue,
    CheckedJoinedValues,
}

StringType :: struct {}
I64Type :: struct {}
BoolType :: struct {}
CheckedType :: union {
    StringType,
    I64Type,
    BoolType,
    // Type,
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

CheckedStatement :: union {
    CheckedReturn,
    CheckedIf,
    CheckedLoop,
    CheckedPrint,
    ContinueLoop,
    BreakLoop,
    CheckedSingleVariableMutation,
}

type_is_equal :: proc(type0: CheckedType, type1: CheckedType) -> bool {
    switch _ in type0 {
    case StringType:
        _, is_string := type1.(StringType)
        return is_string
    case I64Type:
        _, is_i64 := type1.(I64Type)
        return is_i64
    case BoolType:
        _, is_bool := type1.(BoolType)
        return is_bool
    }
    panic("Unreachable")
}

expect_type :: proc(
    file: CompilerFile,
    pos: uint,
    expected: CheckedType,
    got: CheckedType,
) -> bool {
    if !type_is_equal(got, expected) {
        err_ok(
            file,
            pos,
            "Expected the type %s but got the type %s", // TODO: Say why that type is expected
            type_to_string(expected),
            type_to_string(got),
        )
        return false
    }
    return true
}


add_variable :: proc(
    s: ^CheckerState,
    variable_type: CheckedType,
    variable_is_mut: bool,
    variable: IdentAndPos,
) -> (
    var_ref: VariableRef,
    ok: bool,
) {
    // TODO: Add a warning for unused variables
    assert(
        len(s.scopes[len(s.scopes) - 1].variable_is_muts) ==
        len(s.scopes[len(s.scopes) - 1].variable_types),
    )
    var_ref = VariableRef {
        len(s.scopes) - 1,
        uint(len(s.scopes[len(s.scopes) - 1].variable_is_muts)),
    }
    if variable.ident != "" {
        if variable.ident in s.variables_map {
            err_ok(s.file, variable.pos, "Redeclaration of variable `%s`", variable.ident)
            ok = false
            return
        }
        s.variables_map[variable.ident] = var_ref
    }
    append_elem(&s.scopes[len(s.scopes) - 1].variable_types, variable_type)
    append_elem(&s.scopes[len(s.scopes) - 1].variable_is_muts, variable_is_mut)
    ok = true
    return
}

get_type :: proc(s: ^CheckerState, value: CheckedValue) -> CheckedType {
    switch v in value {
    case StringValue:
        return StringType{}
    case I64Value:
        return I64Type{}
    case VariableValue:
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
            return I64Type{} // TODO
        }
    }
    panic("Unreachable")
}

type_to_string :: proc(t: CheckedType) -> string {
    switch type in t {
    case StringType:
        return "string"
    case I64Type:
        return "i64"
    case BoolType:
        return "bool"
    }
    panic("Unreachable")
}

// The boolean returned is wether there are errors in the print statement
check_print :: proc(
    s: ^CheckerState,
    pos: uint,
    args: []Value,
    add_newline: bool,
) -> (
    CheckedPrint,
    bool,
) {
    if len(args) < 1 {
        err_ok(s.file, pos, "Print function must have atleast one argument")
        return CheckedPrint{}, false
    }
    if len(args) != 1 {
        err_ok(s.file, pos, "TODO: Handle print function with more than one arguments")
        return CheckedPrint{}, false
    }
    val, val_ok := check_value(s, args[0])
    if !val_ok {
        return CheckedPrint{}, false
    }
    type := get_type(s, val)
    format: string
    switch _ in type {
    case BoolType:
        format = add_newline ? "\"%b\\n\"" : "\"%b\""
    case StringType:
        format = add_newline ? "\"%s\\n\"" : "\"%s\""
    case I64Type:
        format = add_newline ? "\"%\" PRId64 \"\\n\"" : "\"%\" PRId64"
    }
    values := make([]CheckedValue, 1)
    values[0] = val
    return CheckedPrint{format, values}, true
}

// The boolean returned is wether there are errors in the block
check_block :: proc(s: ^CheckerState, block: []Statement) -> (CheckedBlock, bool) {
    last_scope := s.scopes[len(s.scopes) - 1]
    assert(len(last_scope.variable_types) == len(last_scope.variable_is_muts))
    defer {
        pop(&s.scopes)
        for var_name, var_ref in s.variables_map {
            if var_ref.nesting_level == len(s.scopes) {
                delete_key(&s.variables_map, var_name)
            } else {
                assert(var_ref.nesting_level < len(s.scopes))
            }
        }
    }
    body := make([dynamic]CheckedStatement)
    for stmt, stmt_index in block {
        switch value in stmt.value {
        case VariableManagement:
            err_ok(s.file, stmt.position, "TODO: Handle variable management")
        case FunctionCall:
            switch value.function_name {
            case:
                err_ok(s.file, stmt.position, "TODO: Handle function calls other than print")
                return CheckedBlock{}, false
            case "print":
                print, ok := check_print(s, stmt.position, value.args, false)
                if !ok {
                    return CheckedBlock{}, false
                }
                append(&body, print)
            case "println":
                print, ok := check_print(s, stmt.position, value.args, true)
                if !ok {
                    return CheckedBlock{}, false
                }
                append(&body, print)
            }
        case ForInLoop:
            append_elem(&s.scopes, Scope{})
            loop_enter: []CheckedStatement
            loop_start: []CheckedStatement
            loop_end: []CheckedStatement
            switch iter in value.iterator {
            case string:
                err_ok(s.file, stmt.position, "TODO: Handle iterating over a variable")
                return CheckedBlock{}, false
            case NumericIterator:
                if value.variables[1].ident != "" || value.variables[2].ident != "" {
                    err_ok(
                        s.file,
                        stmt.position,
                        "You can only capture at most one variable in a numeric iterator",
                    )
                    return CheckedBlock{}, false
                }
                index_variable, ok := add_variable(
                    s,
                    I64Type{}, // TODO: Suuport types other than I64
                    false,
                    value.variables[0],
                )
                if !ok {
                    return CheckedBlock{}, false
                }
                loop_enter = make([]CheckedStatement, 1)
                loop_enter[0] = CheckedSingleVariableMutation {
                    .SetTo,
                    index_variable,
                    I64Value(iter.start),
                }
                if_block := make([]CheckedStatement, 1)
                if_block[0] = BreakLoop{index_variable.nesting_level}
                loop_start = make([]CheckedStatement, 1)
                loop_start[0] = CheckedIf {
                    CheckedJoinedValues {
                        iter.type == .IncludeEndValue ? .IsGreaterThan : .IsGreaterThanOrEqual,
                        new_clone(CheckedValue(VariableValue(index_variable))),
                        new_clone(CheckedValue(I64Value(iter.end))),
                    },
                    CheckedBlock{nil, if_block},
                    CheckedBlock{},
                }
                loop_end = make([]CheckedStatement, 1)
                loop_end[0] = CheckedSingleVariableMutation {
                    .Increment,
                    index_variable,
                    I64Value("1"), // TODO: Handle the iterators step
                }
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
                        type_to_string(type),
                    )
                }
            }
            append_elem(&s.scopes, Scope{})
            if_block, if_block_ok := check_block(s, value.if_block)
            append_elem(&s.scopes, Scope{})
            else_block, else_block_ok := check_block(s, value.else_block)
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
            v, ok := check_value(s, value[0])
            if !ok {
                return CheckedBlock{}, false
            }
            append_elem(&body, CheckedReturn{v})
        case YieldStatement:
            err_ok(s.file, stmt.position, "TODO: Handle yield statement")
            return CheckedBlock{}, false
        }
    }
    return CheckedBlock{last_scope.variable_types[:], body[:]}, true
}

// The boolean returned is wether there are errors in the value
check_value :: proc(s: ^CheckerState, v: Value) -> (CheckedValue, bool) {
    switch value in v.value {
    case:
        err_ok(s.file, v.pos, "Internal error: got nil value in check_value")
        return nil, false
    case FunctionCall:
        err_ok(s.file, v.pos, "TODO: Handle function call values")
        return nil, false
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
            ok0 := expect_type(s.file, value.val0.pos, BoolType{}, type0)
            ok1 := expect_type(s.file, value.val0.pos, BoolType{}, type0)
            if !ok0 | !ok1 {
                return nil, false
            }
        case .IsEqual, .IsNotEqual:
            if !expect_type(s.file, value.val1.pos, type0, type1) {
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
            ok0 := expect_type(s.file, value.val0.pos, I64Type{}, type0) // TODO
            ok1 := expect_type(s.file, value.val0.pos, I64Type{}, type0)
            if !ok0 | !ok1 {
                return nil, false
            }
        }
        return CheckedJoinedValues{value.join_method, new_clone(val0), new_clone(val1)}, true
    case VariableReference:
        var_index, ok := s.variables_map[string(value)]
        if ok {
            return VariableValue(var_index), true
        } else {
            err_ok(s.file, v.pos, "The variable `%s` is not defined", string(value))
            return nil, false
        }
    case Number:
        return I64Value(value), true
    case String:
        return StringValue(value), true
    }
}

// The boolean returned is wether there are errors in the function
check_function :: proc(s: ^CheckerState, f: FunctionDefinition) -> (CheckedFunction, bool) {
    append(&s.scopes, Scope{}) // TODO: Add function args to scope
    block, ok := check_block(s, f.body)
    if !ok {
        return CheckedFunction{}, false
    }
    return CheckedFunction{variables = block.variables, body = block.body}, true
}

// The boolean returned is wether there are errors in the code
// The int returned is the index of the main function
check :: proc(
    file: CompilerFile,
    imports: []Import,
    globals: map[string]Global,
) -> (
    []CheckedFunction,
    int,
    bool,
) {
    number_of_functions := 0
    for _, global in globals {
        switch _ in global.value {
        case FunctionDefinition:
            number_of_functions += 1
        case Type:
        }
    }
    checked_functions := make([]CheckedFunction, number_of_functions)
    state := CheckerState {
        file    = file,
        globals = globals,
    }

    function_index := 0
    main_function_index := -1
    ok := true
    for global_name, global in globals {
        switch value in global.value {
        case FunctionDefinition:
            if global_name == "main" {
                main_function_index = function_index
            }
            checked_func, func_ok := check_function(&state, value)
            if func_ok {
                checked_functions[function_index] = checked_func
            } else {
                ok = false
            }
            function_index += 1
        case Type:
            err_ok(file, global.position, "TODO: Handle types")
        }
    }
    return checked_functions, main_function_index, ok
}

