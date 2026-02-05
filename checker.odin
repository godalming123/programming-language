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
    file:               CompilerFile,
    globals:            map[string]ParsedGlobal,
    global_funcs:       []FunctionDefinition,
    global_types:       []TypeValue,
    global_funcs_props: []CheckedFunctionProps,
    scopes:             [dynamic]Scope,
    variables_map:      map[string]VariableRef,
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
CheckedValue :: union {
    StringValue,
    U8Value,
    I64Value,
    VariableValue,
    BooleanNotValue,
    CheckedJoinedValues,
    CheckedFunctionCall,
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
    // Type,
}

// Returns nil if there are errors in the type
check_type :: proc(file: CompilerFile, type: Type) -> CheckedType {
    switch t in type.type {
    case Struct:
        err_ok(file, type.pos, "TODO: Support checking struct type")
        return nil
    case Function:
        err_ok(file, type.pos, "TODO: Support checking function type")
        return nil
    case TypeVariable:
        return handle_named_type(file, type.pos, string(t))
    case Array:
        err_ok(file, type.pos, "TODO: Support checking array type")
        return nil
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

CheckedStatement :: union {
    CheckedReturn,
    CheckedIf,
    CheckedLoop,
    CheckedPrint,
    ContinueLoop,
    BreakLoop,
    CheckedSingleVariableMutation,
    CheckedFunctionCall,
}

type_is_numeric :: proc(type: CheckedType) -> bool {
    switch _ in type {
    case I64Type, I32Type, I16Type, I8Type, U64Type, U32Type, U16Type, U8Type:
        return true
    case StringType, BoolType:
        return false
    }
    panic("Unreachable")
}

type_is_equal :: proc(type0: CheckedType, type1: CheckedType) -> bool {
    switch _ in type0 {
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
    }
    panic("Unreachable")
}

// The boolean returned is wether the `got` type matches the `expected` type
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

get_type :: proc(s: ^CheckerState, value: CheckedValue) -> CheckedType {
    switch v in value {
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

type_to_string :: proc(t: CheckedType) -> string {
    switch type in t {
    case StringType:
        return "string"
    case I64Type:
        return "i64"
    case I32Type:
        return "i32"
    case I16Type:
        return "i16"
    case I8Type:
        return "i8"
    case U64Type:
        return "u64"
    case U32Type:
        return "u32"
    case U16Type:
        return "u16"
    case U8Type:
        return "u8"
    case BoolType:
        return "bool"
    }
    panic("Unreachable")
}

// Returns nil if there are errors in the function call
check_function_call :: proc(s: ^CheckerState, pos: uint, call: FunctionCall) -> CheckedStatement {
    function_name, is_var_ref := call.function.value.(VariableReference)
    if !is_var_ref {
        err_ok(
            s.file,
            pos,
            "TODO: Handle function calls where the function isn't a variable reference",
        )
        return nil
    }
    return handle_named_function_call(s, pos, string(function_name), call.args)
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
            checked := check_function_call(s, stmt.position, value)
            if checked == nil {
                return CheckedBlock{}, false
            }
            append_elem(&body, checked)
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
                    I64Type{}, // TODO: Support types other than I64
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
                    condition_ok = false
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
            // TODO: Check that the value is the right type for the surrounding function
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
    case ValueInBrackets:
        return check_value(s, value^)
    case ArrayAccess:
        err_ok(s.file, v.pos, "TODO: Handle array access")
        return nil, false
    case FunctionCall:
        stmt := check_function_call(s, v.pos, value)
        if stmt == nil {
            return nil, false
        }
        func_call, is_func_call := stmt.(CheckedFunctionCall)
        if !is_func_call {
            err_ok(s.file, v.pos, "This function call cannot be used as a value")
        }
        return func_call, true
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
            if !type_is_numeric(type0) {
                err_ok(
                    s.file,
                    value.val0.pos,
                    "Expected type in numeric operation to be numeric, but got the type `%s`",
                    type_to_string(type0),
                )
                return nil, false
            }
            if !type_is_numeric(type1) {
                err_ok(
                    s.file,
                    value.val1.pos,
                    "Expected type in numeric operation to be numeric, but got the type `%s`",
                    type_to_string(type1),
                )
                return nil, false
            }
            if !type_is_equal(type0, type1) {
                err_ok(
                    s.file,
                    value.val0.pos,
                    "Expected types in numeric operation to be the same, but got `%s` and `%s`",
                    type_to_string(type0),
                    type_to_string(type1),
                )
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
    case Char:
        return U8Value(value), true
    }
}

// The boolean returned is wether there are errors in the function
check_function :: proc(s: ^CheckerState, index: uint) -> (CheckedFunction, bool) {
    assert(len(s.scopes) == 0)
    f := s.global_funcs[index]
    append(&s.scopes, Scope{})
    inputs := make([]CheckedType, len(f.inputs))
    for arg, i in s.global_funcs_props[index].args {
        add_variable(s, arg.type, arg.is_mutable, arg.name)
        inputs[i] = arg.type
    }
    append(&s.scopes, Scope{})
    // TODO: Check that the function always returns if it has a return type
    block, ok := check_block(s, f.body)
    if !ok {
        return CheckedFunction{}, false
    }
    pop(&s.scopes)
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

// The boolean returned is wether there are errors in the code
// The uint returned is the index of the main function
check :: proc(
    file: CompilerFile,
    imports: []Import,
    globals: map[string]ParsedGlobal,
    global_funcs: []FunctionDefinition,
    global_types: []TypeValue,
) -> (
    []CheckedFunction,
    uint,
    bool,
) {
    main, main_exists := globals["main"]
    incorrect_main_hint :: "Hint: A hello world program is defined like so:\n```\nmain = () {{\n    println(\"Hello world\")\n}\n```\nTODO: Add link to docs"
    if !main_exists {
        err_ok(file, max(uint), "No main function defined\n%s", incorrect_main_hint)
        return nil, max(uint), false
    } else if main.kind != .Function {
        err_ok(
            file,
            max(uint),
            "`main` is a type, but it must be a function\n%s",
            incorrect_main_hint,
        )
        return nil, max(uint), false
    }

    ok := true
    global_funcs_props := make([]CheckedFunctionProps, len(global_funcs))
    for func, i in global_funcs {
        return_type: CheckedType
        switch len(func.outputs) {
        case 0:
        case 1:
            return_type = check_type(file, func.outputs[0].type)
            if return_type == nil {
                ok = false
                continue
            }
        case:
            err_ok(file, func.outputs[1].type.pos, "TODO: Support more than one return type")
            ok = false
            continue
        }
        args := make([]CheckedArg, len(func.inputs))
        for input, i in func.inputs {
            type := check_type(file, input.value_type)
            if type == nil {
                ok = false
                continue
            }
            args[i] = CheckedArg{type, input.arg_type == .Mutable, input.name}
        }
        global_funcs_props[i] = CheckedFunctionProps{args, return_type}
    }
    if !ok {
        return nil, max(uint), false
    }

    checked_functions := make([]CheckedFunction, len(global_funcs))
    state := CheckerState {
        file               = file,
        globals            = globals,
        global_funcs       = global_funcs,
        global_types       = global_types,
        global_funcs_props = global_funcs_props,
    }

    for global_name, global in globals {
        switch global.kind {
        case .Function:
            checked_func, func_ok := check_function(&state, global.index)
            if func_ok {
                checked_functions[global.index] = checked_func
            } else {
                ok = false
            }
        case .Type:
            err_ok(file, global.pos, "TODO: Handle types")
            ok = false
        }
    }
    if !ok {
        return nil, max(uint), false
    }

    return checked_functions, main.index, ok
}

