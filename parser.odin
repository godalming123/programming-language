#+feature dynamic-literals
package main

parse_type :: proc(
    state: ^TokenizerState,
    descriptions_of_other_possible_tokens: ..string,
) -> (
    Type,
    bool,
) {
    type_pos := state.last_token_pos
    #partial switch token in state.last_token {
    case:
        wrong_token_err(state, join(descriptions_of_other_possible_tokens, "the name of a type"))
        return Type{}, false

    case StructToken:
        get_next_token(state, false)
        #partial switch _ in state.last_token {
        case OpenBraceToken:
        case:
            wrong_token_err(state, []string{"{"})
            return Type{}, false
        }
        err_ok(state.file, state.last_token_pos, "TODO: Implement struct type parsing")
        return Type{}, false


    case OpenAngleBracketToken:
        variants := [dynamic]SumTypeVariant{}
        for {
            get_next_token(state, true)
            #partial switch token2 in state.last_token {
            case CloseAngleBracketToken:
                return Type{type_pos, SumType{variants[:]}}, true
            case IdentToken:
                variant := SumTypeVariant{}
                variant.name = string(token2)
                get_next_token(state, false)
                #partial switch _ in state.last_token {
                case ColonToken:
                    get_next_token(state, false)
                    type, ok := parse_type(state)
                    if !ok {
                        return Type{}, false
                    }
                    variant.type = type
                    get_next_token(state, false)
                    #partial switch _ in state.last_token {
                    case CommaToken:
                    case:
                        wrong_token_err(state, []string{"`,`"})
                    }
                case CommaToken:
                case:
                    wrong_token_err(state, []string{"`:`", "`,`"})
                }
                append_elem(&variants, variant)
            case:
                wrong_token_err(state, []string{"an identifier", "]"})
                return Type{}, false
            }
        }

    case OpenSquareBracketToken:
        get_next_token(state, false)
        length: uint = 0
        #partial switch token2 in state.last_token {
        case CloseSquareBracketToken:
        case DigitsToken:
            err_ok(
                state.file,
                state.last_token_pos,
                "TODO: Add support for parsing fixed length arrays",
            )
            return Type{}, false
        case:
            wrong_token_err(state, []string{"`]`", "a number for the length of the array"})
            return Type{}, false
        }
        get_next_token(state, false)
        item_type, ok := parse_type(state)
        if !ok {
            return Type{}, false
        }
        return Type{type_pos, Array{length, new_clone(item_type)}}, true
    case IdentToken:
        return Type{type_pos, TypeVariable(token)}, true
    }
}

parse_value_list :: proc(state: ^TokenizerState) -> ([]Value, []string, bool) {
    out := [dynamic]Value{}
    for {
        get_next_token(state, true)
        v := parse_value(state, "`)`")
        if !v.ok {
            return nil, nil, false
        }
        append_elem(&out, v.value^)

        #partial switch token in state.last_token {
        case CommaToken:
            continue
        case:
            return out[:], v.descriptions_of_other_possible_tokens, true
        }
    }
}

// Does not include the `(`
parse_function_args :: proc(state: ^TokenizerState) -> ([]Value, bool) {
    args := [dynamic]Value{}
    for {
        get_next_token(state, true)
        other_possible_tokens: []string
        #partial switch token in state.last_token {
        case CloseBracketToken:
            return args[:], true
        case:
            v := parse_value(state, "`)`")
            other_possible_tokens = v.descriptions_of_other_possible_tokens
            if !v.ok {
                return nil, false
            }
            append_elem(&args, v.value^)
        }

        #partial switch token in state.last_token {
        case:
            wrong_token_err(state, join(other_possible_tokens, "`)`", "`,`"))
            return nil, false
        case CommaToken:
            continue
        case CloseBracketToken:
            return args[:], true
        }
    }
}

ParsedValue :: struct {
    ok:                                    bool,
    value:                                 ^Value,
    descriptions_of_other_possible_tokens: []string,
}

parse_value :: proc(
    state: ^TokenizerState,
    in_descriptions_of_other_possible_tokens: ..string,
) -> ParsedValue {
    // Parse initial value
    value_pos := state.last_token_pos
    value: ^Value
    #partial switch token in state.last_token {
    case:
        wrong_token_err(
            state,
            join(
                in_descriptions_of_other_possible_tokens,
                "`(` to create a value in brackets",
                "an identifier",
                "a digits token",
                "a string literal",
                "a character literal",
            ),
        )
        return ParsedValue{ok = false}
    case OpenBracketToken:
        get_next_token(state, true)
        val := parse_value(state)
        if !val.ok {
            return ParsedValue{ok = false}
        }
        #partial switch _ in state.last_token {
        case:
            wrong_token_err(state, join(val.descriptions_of_other_possible_tokens, ")"))
            return ParsedValue{ok = false}
        case CloseBraceToken:
        }
        value = new_clone(Value{value_pos, ValueInBrackets(val.value)})
    case IdentToken:
        value = new_clone(Value{value_pos, VariableReference(token)})
    case DigitsToken:
        value = new_clone(Value{value_pos, Number(token)})
    case StringToken:
        value = new_clone(Value{value_pos, String(token)})
    case CharToken:
        value = new_clone(Value{value_pos, Char(token)})
    }
    get_next_token(state, true)

    // Parse possible function call or indexed array access
    other_possible_tokens: [dynamic]string
    loop: for {
        #partial switch token in state.last_token {
        // TODO: Parse field access with `.`
        case:
            other_possible_tokens = [dynamic]string {
                "`(` to call a function", // TODO: add name of function
                "`[` to access a specific index in an array", // TODO: add name of array
            }
            break loop
        case OpenBracketToken:
            args, ok := parse_function_args(state)
            if !ok {
                return ParsedValue{ok = false}
            }
            value = new_clone(Value{value_pos, FunctionCall{value, args}})
            other_possible_tokens = nil
            get_next_token(state, true)
        case OpenSquareBracketToken:
            get_next_token(state, false)
            array_index := parse_value(state)
            if !array_index.ok {
                return ParsedValue{ok = false}
            }
            #partial switch token2 in state.last_token {
            case:
                wrong_token_err(
                    state,
                    join(array_index.descriptions_of_other_possible_tokens, "`]`"),
                )
                return ParsedValue{ok = false}
            case CloseSquareBracketToken:
                value = new_clone(Value{value_pos, ArrayAccess{value, array_index.value}})
                other_possible_tokens = nil
                get_next_token(state, true)
            }
        }
    }

    // Parse possible arithmatic
    append_elems(
        &other_possible_tokens,
        "a value joiner (`and`, `or`, `==`, `!=`, `>`, `>=`, `<`, `<=`, `*`, `/`, `+`, `-`, `%`)",
    )
    value_type: ValueJoinMethod
    #partial switch token in state.last_token {
    case:
        return ParsedValue{true, value, other_possible_tokens[:]}
    case AndToken:
        value_type = .BooleanAnd
    case OrToken:
        value_type = .BooleanOr
    case OpenAngleBracketToken:
        value_type = .IsLessThan
    case CloseAngleBracketToken:
        value_type = .IsGreaterThan
    case SymbolsToken:
        switch token {
        case:
            return ParsedValue{true, value, other_possible_tokens[:]}
        case "==":
            value_type = .IsEqual
        case "!=":
            value_type = .IsNotEqual
        case ">=":
            value_type = .IsGreaterThanOrEqual
        case "<=":
            value_type = .IsLessThanOrEqual
        case "*":
            value_type = .Multiplication
        case "/":
            value_type = .Division
        case "+":
            value_type = .Addition
        case "-":
            value_type = .Subtraction
        case "%":
            value_type = .Modulo
        }
    }
    get_next_token(state, true)
    next_value := parse_value(state)
    if !next_value.ok {
        return ParsedValue{ok = false}
    }
    joined_values, is_joined_values := next_value.value.value.(JoinedValues)
    if is_joined_values && get_prioraty(joined_values.join_method) <= get_prioraty(value_type) {
        val0 := new_clone(Value{value_pos, JoinedValues{value_type, value, joined_values.val0}})
        return ParsedValue {
            true,
            new_clone(
                Value {
                    value_pos,
                    JoinedValues{joined_values.join_method, val0, joined_values.val1},
                },
            ),
            next_value.descriptions_of_other_possible_tokens,
        }
    }
    return ParsedValue {
        true,
        new_clone(Value{value_pos, JoinedValues{value_type, value, next_value.value}}),
        next_value.descriptions_of_other_possible_tokens,
    }
}

// Does not include the `for`
parse_for_loop :: proc(state: ^TokenizerState) -> (ForInLoop, bool) {
    variables: [3]IdentAndPos
    variable_index := 0
    variables_loop: for {
        get_next_token(state, false)
        #partial switch token in state.last_token {
        case:
            wrong_token_err(state, []string{"the name of the variable in a for loop", "`in`"})
            return ForInLoop{}, false
        case InToken:
            if variables[0].ident == "" {
                err_ok(
                    state.file,
                    state.last_token_pos,
                    "There must be at least 1 variable to iterate over in a for loop",
                )
                return ForInLoop{}, false
            }
            break variables_loop
        case IdentToken:
            if variable_index >= 3 {
                err_ok(
                    state.file,
                    state.last_token_pos,
                    "There cannot be more than 3 variables in a for loop head (the iteration the for loop is on, the key of the thing being iterated over, and the value of the thing being iterated over)",
                )
                return ForInLoop{}, false
            }
            variables[variable_index] = IdentAndPos{string(token), state.last_token_pos}
            variable_index += 1
        }
    }
    iter: Iterator
    get_next_token(state, false)
    #partial switch token in state.last_token {
    case:
        wrong_token_err(
            state,
            []string{"a variable name to iterate over", "some digits to create an iterator"},
        )
        return ForInLoop{}, false
    case IdentToken:
        iter = string(token)
        get_next_token(state, true)
        #partial switch _ in state.last_token {
        case OpenBraceToken:
        case:
            wrong_token_err(state, []string{")"})
            return ForInLoop{}, false
        }
    case DigitsToken:
        start := string(token)
        type: NumericIteratorType
        get_next_token(state, false)
        expected :: []string{"`..=`", "`..<`"}
        #partial switch token2 in state.last_token {
        case:
            wrong_token_err(state, expected)
            return ForInLoop{}, false
        case SymbolsToken:
            switch token2 {
            case "..=":
                type = .IncludeEndValue
            case "..<":
                type = .ExcludeEndValue
            case:
                wrong_token_err(state, expected)
                return ForInLoop{}, false
            }
        }
        end: string
        get_next_token(state, false)
        #partial switch token2 in state.last_token {
        case:
            wrong_token_err(state, []string{"some digits for the end value of the iterator"})
            return ForInLoop{}, false
        case DigitsToken:
            end = string(token2)
        }
        step := ""
        get_next_token(state, false)
        #partial switch token2 in state.last_token {
        case:
            wrong_token_err(state, []string{"`step`", "`{`"})
            return ForInLoop{}, false
        case StepToken:
            get_next_token(state, false)
            #partial switch token3 in state.last_token {
            case:
                wrong_token_err(state, []string{"some digits for the step of the iterator"})
                return ForInLoop{}, false
            case DigitsToken:
                step = string(token3)
            }
            get_next_token(state, false)
            #partial switch _ in state.last_token {
            case OpenBraceToken:
            case:
                wrong_token_err(state, []string{"{"})
                return ForInLoop{}, false
            }
        case OpenBraceToken:
        }
        iter = NumericIterator{start, end, step, type}
    }
    block, ok := parse_block(state)
    if !ok {
        return ForInLoop{}, false
    }
    return ForInLoop{variables, iter, block}, true
}

// Does not include the `if`
parse_if :: proc(state: ^TokenizerState) -> (^IfElseStatement, []string, bool) {
    if_pos := state.last_token_pos
    get_next_token(state, true)
    condition := parse_value(state)
    if !condition.ok {
        return nil, nil, false
    }
    #partial switch _ in state.last_token {
    case OpenBraceToken:
    case:
        wrong_token_err(
            state,
            join(
                condition.descriptions_of_other_possible_tokens,
                "`{` to start the body of the if statement",
            ),
        )
        return nil, nil, false
    }

    block, ok := parse_block(state)
    if !ok {
        return nil, nil, false
    }

    get_next_token(state, true)
    #partial switch _ in state.last_token {
    case ElseToken:
        else_pos := state.last_token_pos
        get_next_token(state, true)
        #partial switch _ in state.last_token {
        case:
            wrong_token_err(state, []string{"`{`", "`if`"})
            return nil, nil, false
        case OpenBraceToken:
            else_block, ok := parse_block(state)
            if !ok {
                return nil, nil, false
            }
            get_next_token(state, true)
            return new_clone(IfElseStatement{condition.value^, block, else_block}),
                []string{},
                true

        case IfToken:
            else_block := make([]Statement, 1)
            else_statement, other_possible_tokens, ok := parse_if(state)
            if !ok {
                return nil, nil, false
            }
            else_block[0] = Statement{else_pos, else_statement^}
            return new_clone(IfElseStatement{condition.value^, block, else_block}),
                other_possible_tokens,
                true
        }
    case:
        array := make([]string, 1)
        array[0] = "`else`"
        return new_clone(IfElseStatement{condition.value^, block, []Statement{}}), array, true
    }
}

// Does not include the `{`
parse_block :: proc(state: ^TokenizerState) -> ([]Statement, bool) {
    out := [dynamic]Statement{}
    get_next_token(state, true)
    pos := state.last_token_pos
    other_possible_tokens := []string{}
    for {
        #partial switch token in state.last_token {
        case:
            wrong_token_err(
                state,
                join(other_possible_tokens, "an identifier", "`for`", "`if`", "`return`", "`}`"),
            )
            return nil, false
        case IfToken:
            if_else: ^IfElseStatement
            ok: bool
            if_else, other_possible_tokens, ok = parse_if(state)
            if !ok {
                return nil, false
            }
            append_elem(&out, Statement{pos, if_else^})
        case ForToken:
            loop, ok := parse_for_loop(state)
            if !ok {
                return nil, false
            }
            append_elem(&out, Statement{pos, loop})
            get_next_token(state, true)
        case IdentToken:
            ident_pos := state.last_token_pos
            get_next_token(state, false)
            #partial switch token2 in state.last_token {
            case:
                wrong_token_err(state, []string{"`(`", "`,`", "`=`"})
                return nil, false
            case OpenBracketToken:
                args, ok := parse_function_args(state)
                if !ok {
                    return nil, false
                }
                append_elem(
                    &out,
                    Statement {
                        pos,
                        FunctionCall{new_clone(Value{ident_pos, VariableReference(token)}), args},
                    },
                )
            case CommaToken, SymbolsToken:
                // TODO: Parse variable mutation/assignment
                err_ok(state.file, state.last_token_pos, "todo (ident) in parse_block")
                return nil, false
            }
            get_next_token(state, true)
        case ReturnToken:
            values: []Value
            ok: bool
            values, other_possible_tokens, ok = parse_value_list(state)
            if !ok {
                return nil, false
            }
            append_elem(&out, Statement{pos, ReturnStatement(values)})
        case YieldToken:
            values: []Value
            ok: bool
            values, other_possible_tokens, ok = parse_value_list(state)
            if !ok {
                return nil, false
            }
            append_elem(&out, Statement{pos, YieldStatement(values)})
        case CloseBraceToken:
            return out[:], true
        }
    }
}

// Does not include the `(`
//parse_name_and_type_list :: proc(
//    state: ^TokenizerState,
//    type_required: bool,
//    descriptions_of_possible_end_token: ..string,
//) -> []NameAndType {
//    out := [dynamic]NameAndType{}
//    for {
//        arg: NameAndType
//        switch type, token := get_next_token(state, true, []string{"`)`", "a name"}); type {
//        case: return state.last_error
//        case close_bracket_token: return out[:]
//        case ident_token: arg.name = token.str
//        }
//
//        switch result in try_parse_type(
//            state,
//            ..(type_necesisity == .TypeRequired ? []string{} : join([]string{","}, ..descriptions_of_possible_end_token)),
//        ) {
//        case Failed: return state.last_error
//        case WrongFirstTokenType:
//        case Type: arg.type = result
//        }
//        append_elem(&out, arg)
//        #partial switch token in get_next_token(
//            state,
//            true,
//            type_necesisity == .TypeRequired ? []string{"`,`", "a type"} : []string{"`,`", "`)`"},
//        ) {
//        case: return state.last_error
//        case TypelessToken(Comma): continue
//        case TypelessToken(CloseBracket): return out[:]
//        }
//    }
//}

// parse_import :: proc(state: ^TokenizerState) -> Import {
//     import_components := [dynamic]string{}
//     loop: for {
//         #partial switch token in get_next_token(
//             state,
//             false,
//             []string{"an identifier for the import component"},
//         ) {
//         case: return state.last_error
//         case TypelessToken(Ident):
//             append_elem(&import_components, string(token.contents))
//             #partial switch value in get_next_token(
//                 state,
//                 false,
//                 []string{"`.`", "a newline", "a comment"},
//             ) {
//             case: return state.last_error
//             case EndOfFile, TypelessToken(Newline), TypelessToken(Comment): break loop
//             case TypelessToken(Symbols): if string(value.contents) == "." {
//                         continue loop
//                     }
//             }
//         }
//     }
//     return Import{import_components[:]}
// }

GlobalKind :: enum {
    Function,
    Type,
}

// The boolean returned is wether the function passed successfully
parse_function_def :: proc(state: ^TokenizerState) -> (FunctionDefinition, bool) {
    args := [dynamic]FunctionArg{}
    loop: for {
        arg: FunctionArg
        get_next_token(state, true)

        expected :: []string {
            "an identifier for the name of a normal function argument",
            "~ to add a mutable function argument",
            "- to add a function argument which is deallocated from the PCS during the execution of this function",
            ")",
        }
        #partial switch token2 in state.last_token {
        case:
            wrong_token_err(state, expected)
            return FunctionDefinition{}, false
        case SymbolsToken:
            switch token2 {
            case "~":
                arg.arg_type = .Mutable
            case "-":
                arg.arg_type = .RemovedFromStack
            case:
                wrong_token_err(state, expected)
                return FunctionDefinition{}, false
            }
            get_next_token(state, true)
            #partial switch token3 in state.last_token {
            case:
                wrong_token_err(state, expected)
                return FunctionDefinition{}, false
            case IdentToken:
                arg.name = IdentAndPos{string(token3), state.last_token_pos}
            }
        case IdentToken:
            arg.name = IdentAndPos{string(token2), state.last_token_pos}
        case CloseBracketToken:
            break loop
        }

        get_next_token(state, true)
        #partial switch _ in state.last_token {
        case ColonToken:
        case:
            wrong_token_err(state, []string{"`:`"})
            return FunctionDefinition{}, false
        }

        get_next_token(state, true)
        ok: bool
        arg.value_type, ok = parse_type(state)
        if !ok {
            return FunctionDefinition{}, false
        }
        append_elem(&args, arg)

        get_next_token(state, true)
        #partial switch _ in state.last_token {
        case:
            wrong_token_err(state, []string{"`,`", "`)`"})
            return FunctionDefinition{}, false
        case CommaToken:
            continue
        case CloseBracketToken:
            break loop
        }
    }

    get_next_token(state, true)
    outputs := []NameAndType{}
    #partial switch _ in state.last_token {
    case ArrowToken:
        get_next_token(state, true)
        #partial switch _ in state.last_token {
        case:
            outputs = make([]NameAndType, 1)
            type, ok := parse_type(state, "`{`", "`(`")
            if !ok {
                return FunctionDefinition{}, false
            }
            outputs[0] = NameAndType{"", type}
        case OpenBracketToken:
            // parse_name_and_type_list(state, .TypeRequired, "`)`")
            err_ok(
                state.file,
                state.last_token_pos,
                "TODO: Implement parsing functions with multiple return values",
            )
            return FunctionDefinition{}, false
        }
        get_next_token(state, true)
        #partial switch _ in state.last_token {
        case OpenBraceToken:
        case:
            wrong_token_err(state, []string{"{"})
            return FunctionDefinition{}, false
        }
    case OpenBraceToken:
    }

    block, ok := parse_block(state)
    if !ok {
        return FunctionDefinition{}, false
    }
    return FunctionDefinition{args[:], outputs, block}, true
}

ParsedGlobal :: struct {
    pos:   uint,
    kind:  GlobalKind,
    // If `kind == .Function`, `index` is an index into the global functions
    // If `kind == .Type`, `index` is an index into the global types
    index: uint,
}

parse :: proc(
    state: ^TokenizerState,
) -> (
    []Import,
    map[string]ParsedGlobal,
    []FunctionDefinition,
    []TypeValue,
    bool,
) {
    imports := [dynamic]Import{}
    globals := make(map[string]ParsedGlobal)
    global_functions := make([dynamic]FunctionDefinition)
    global_types := make([dynamic]TypeValue)
    for {
        get_next_token(state, true)
        #partial switch token in state.last_token {
        case:
            wrong_token_err(state, []string{"a newline", "a comment", "an identifier"})
            return nil, nil, nil, nil, false
        case EndOfFileToken:
            return imports[:], globals, global_functions[:], global_types[:], true
        case ImportToken:
            err_ok(state.file, state.last_token_pos, "TODO: Implement import token parsing")
            return nil, nil, nil, nil, false
        case IdentToken:
            position := state.last_token_pos
            name := string(token)
            get_next_token(state, false)
            symbols, is_symbols := state.last_token.(SymbolsToken)
            if !is_symbols || symbols != "=" {
                wrong_token_err(state, []string{"`=`"})
                return nil, nil, nil, nil, false
            }
            if name in globals {
                line, column := get_location(state.code, globals[name].pos)
                err_ok(
                    state.file,
                    position,
                    "The global `%s` is already declared at line %d and column %d",
                    name,
                    line,
                    column,
                )
                return nil, nil, nil, nil, false
            }
            get_next_token(state, false)
            #partial switch token in state.last_token {
            case:
                type, ok := parse_type(state, "`(` to create a function definition")
                if !ok {
                    return nil, nil, nil, nil, false
                }
                globals[name] = ParsedGlobal{position, .Type, len(global_types)}
                append_elem(&global_types, type.type)
            case OpenBracketToken:
                func, ok := parse_function_def(state)
                if !ok {
                    return nil, nil, nil, nil, false
                }
                globals[name] = ParsedGlobal{position, .Function, len(global_functions)}
                append_elem(&global_functions, func)
            }
        }
    }
}

