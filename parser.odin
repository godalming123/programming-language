#+feature dynamic-literals
package main

import "core:fmt"

parse_type :: proc(
    state: ^TokenizerState,
    descriptions_of_other_possible_tokens: ..string,
) -> (
    Type,
    bool,
) {
    #partial switch token in state.last_token {
    case:
        wrong_token_err(state, join(descriptions_of_other_possible_tokens, "the name of a type"))
        return nil, false
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
            return nil, false
        case:
            wrong_token_err(state, []string{"`]`", "a number for the length of the array"})
            return Type{}, false
        }
        get_next_token(state, false)
        item_type, ok := parse_type(state)
        if !ok {
            return nil, false
        }
        return Array{length, new_clone(item_type)}, true
    case IdentToken:
        return TypeVariable(token), true
    }
}

parse_value_list :: proc(state: ^TokenizerState) -> ([]Value, []string, bool) {
    out := [dynamic]Value{}
    for {
        get_next_token(state, true)
        v, _, other_possible_tokens, ok := parse_value(state, "`)`")
        if !ok {
            return nil, nil, false
        }
        append_elem(&out, v^)

        #partial switch token in state.last_token {
        case CommaToken:
            continue
        case:
            return out[:], other_possible_tokens, true
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
            v: ^Value
            ok: bool
            v, _, other_possible_tokens, ok = parse_value(state, "`)`")
            if !ok {
                return nil, false
            }
            append_elem(&args, v^)
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

parse_value :: proc(
    state: ^TokenizerState,
    in_descriptions_of_other_possible_tokens: ..string,
) -> (
    out: ^Value,
    enclosed_in_brackets: bool = false,
    out_descriptions_of_other_possible_tokens: []string,
    ok: bool = false,
) {
    // Parse initial value
    value_pos := state.last_token_pos
    #partial switch token in state.last_token {
    case:
        wrong_token_err(
            state,
            join(in_descriptions_of_other_possible_tokens, "'('", "an identifier"),
        )
        return
    case OpenBracketToken:
        get_next_token(state, true)
        other_possible_tokens: []string
        out, _, other_possible_tokens, ok = parse_value(state)
        if !ok {
            return
        }
        enclosed_in_brackets = true
        #partial switch _ in state.last_token {
        case:
            wrong_token_err(state, join(other_possible_tokens, ")"))
            return
        case CloseBraceToken:
            get_next_token(state, true)
        }
    case IdentToken:
        get_next_token(state, false)
        #partial switch token2 in state.last_token {
        case:
            out = new_clone(Value{value_pos, VariableReference(token)})
            out_descriptions_of_other_possible_tokens = []string {
                fmt.aprintf("`(` to call a function called %s", token),
            }
        case OpenBracketToken:
            args, ok := parse_function_args(state)
            if !ok {
                return
            }
            out = new_clone(Value{value_pos, FunctionCall{string(token), args}})
            get_next_token(state, true)
        }
    case DigitsToken:
        out = new_clone(Value{value_pos, Number(token)})
        get_next_token(state, true)
    case StringToken:
        out = new_clone(Value{value_pos, String(token)})
        get_next_token(state, true)
    }

    // Parse possible arithmatic
    out_descriptions_of_other_possible_tokens = join(
        out_descriptions_of_other_possible_tokens,
        "a value joiner (and, or, ==, !=, >, >=, <, <=, *, /, +, -, %)",
        "the end of the value",
    )
    value_type: ValueJoinMethod
    #partial switch token in state.last_token {
    case:
        ok = true
        return
    case AndToken:
        value_type = .BooleanAnd
    case OrToken:
        value_type = .BooleanOr
    case SymbolsToken:
        switch token {
        case:
            return
        case "==":
            value_type = .IsEqual
        case "!=":
            value_type = .IsNotEqual
        case ">":
            value_type = .IsGreaterThan
        case ">=":
            value_type = .IsGreaterThanOrEqual
        case "<":
            value_type = .IsLessThan
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
    value: ^Value
    value_enclosed_in_brackets: bool
    value, value_enclosed_in_brackets, out_descriptions_of_other_possible_tokens, ok = parse_value(
        state,
    )
    if !ok {
        return
    }
    joined_values, is_joined_values := value.value.(JoinedValues)
    if !value_enclosed_in_brackets &&
       is_joined_values &&
       get_prioraty(joined_values.join_method) <= get_prioraty(value_type) {
        val0 := new_clone(Value{value_pos, JoinedValues{value_type, out, joined_values.val0}})
        out = new_clone(
            Value{value_pos, JoinedValues{joined_values.join_method, val0, joined_values.val1}},
        )
    } else {
        out = new_clone(Value{value_pos, JoinedValues{value_type, out, value}})
    }
    ok = true
    return
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
    condition, _, other_possible_tokens, ok := parse_value(state)
    if !ok {
        return nil, nil, false
    }
    #partial switch _ in state.last_token {
    case OpenBraceToken:
    case:
        wrong_token_err(state, join(other_possible_tokens, "`{`"))
        return nil, nil, false
    }

    block: []Statement
    block, ok = parse_block(state)
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
            return new_clone(IfElseStatement{condition^, block, else_block}), []string{}, true

        case IfToken:
            else_block := make([]Statement, 1)
            else_statement, other_possible_tokens, ok := parse_if(state)
            if !ok {
                return nil, nil, false
            }
            else_block[0] = Statement{else_pos, else_statement^}
            return new_clone(IfElseStatement{condition^, block, else_block}),
                other_possible_tokens,
                true
        }
    case:
        array := make([]string, 1)
        array[0] = "`else`"
        return new_clone(IfElseStatement{condition^, block, []Statement{}}), array, true
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
                append_elem(&out, Statement{pos, FunctionCall{string(token), args}})
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

parse_global_definition :: proc(state: ^TokenizerState) -> union {
        Type,
        FunctionDefinition,
    } {
    get_next_token(state, false)
    #partial switch token in state.last_token {
    case:
        wrong_token_err(state, []string{"`(`", "`struct`", "`sum`"})
        return nil

    case StructToken:
        get_next_token(state, false)
        #partial switch _ in state.last_token {
        case OpenBraceToken:
        case:
            wrong_token_err(state, []string{"{"})
            return nil
        }
        err_ok(state.file, state.last_token_pos, "TODO: Implement struct type parsing")
        return nil


    case SumToken:
        get_next_token(state, false)
        #partial switch _ in state.last_token {
        case OpenBraceToken:
        case:
            wrong_token_err(state, []string{"{"})
            return nil
        }
        err_ok(state.file, state.last_token_pos, "TODO: Implement sum type parsing")
        return nil

    case OpenBracketToken:
        args := [dynamic]NameAndType{}
        loop: for {
            arg: NameAndType
            get_next_token(state, true)

            #partial switch token2 in state.last_token {
            case:
                wrong_token_err(state, []string{"the name of a function argument", ")"})
                return nil
            case IdentToken:
                arg.name = string(token2)
            case CloseBracketToken:
                break loop
            }

            get_next_token(state, true)
            #partial switch _ in state.last_token {
            case ColonToken:
            case:
                wrong_token_err(state, []string{"`:`"})
                return nil
            }

            get_next_token(state, true)
            ok: bool
            arg.type, ok = parse_type(state)
            if !ok {
                return nil
            }
            append_elem(&args, arg)

            get_next_token(state, true)
            #partial switch _ in state.last_token {
            case:
                wrong_token_err(state, []string{"`,`", "`)`"})
                return nil
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
                    return nil
                }
                outputs[0] = NameAndType{"", type}
            case OpenBracketToken:
                // parse_name_and_type_list(state, .TypeRequired, "`)`")
                err_ok(
                    state.file,
                    state.last_token_pos,
                    "TODO: Implement parsing functions with multiple return values",
                )
                return nil
            }
            get_next_token(state, true)
            #partial switch _ in state.last_token {
            case OpenBraceToken:
            case:
                wrong_token_err(state, []string{"{"})
                return nil
            }
        case OpenBraceToken:
        }

        block, ok := parse_block(state)
        if !ok {
            return nil
        }
        return FunctionDefinition{args[:], outputs, block}
    }
}

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

parse :: proc(state: ^TokenizerState) -> ([]Import, map[string]Global, bool) {
    imports := [dynamic]Import{}
    globals := make(map[string]Global)
    for {
        get_next_token(state, true)
        #partial switch token in state.last_token {
        case:
            wrong_token_err(state, []string{"a newline", "a comment", "an identifier"})
            return nil, nil, false
        case EndOfFileToken:
            return imports[:], globals, true
        case ImportToken:
            err_ok(state.file, state.last_token_pos, "TODO: Implement import token parsing")
            return nil, nil, false
        case IdentToken:
            position := state.last_token_pos
            name := string(token)
            get_next_token(state, false)
            symbols, is_symbols := state.last_token.(SymbolsToken)
            if !is_symbols || symbols != "=" {
                wrong_token_err(state, []string{"`=`"})
                return nil, nil, false
            }
            if name in globals {
                line, column := get_location(state.code, globals[name].position)
                err_ok(
                    state.file,
                    position,
                    "The global `%s` is already declared at line %d and column %d",
                    name,
                    line,
                    column,
                )
                return nil, nil, false
            }
            parsed := parse_global_definition(state)
            if parsed == nil {
                return nil, nil, false
            }
            globals[name] = Global{position, parsed}
        }
    }
}

