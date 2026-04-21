#+feature dynamic-literals
package main

import "core:fmt"
import "core:strconv"
import "core:strings"

ParserState :: struct {
    function_defs:   [dynamic]FunctionDefinition,
    using tokenizer: TokenizerState,
}

// Does not include the `{`
parse_struct :: proc(s: ^ParserState) -> (Struct(Type), bool) {
    fields_map := make(map[string]uint)
    fields := make(#soa[dynamic]StructField(Type))
    for {
        field: IdentAndPos = ---
        get_next_token(s, true)
        wrong_token :: proc(s: ^ParserState) -> (Struct(Type), bool) {
            wrong_token_err(
                s,
                []string{"an identifier with one segment", "`}`"},
                "While parsing struct type",
            )
            return Struct(Type){}, false
        }
        #partial switch token in s.last_token {
        case CloseBraceToken:
            return Struct(Type){fields_map, fields[:]}, true
        case IdentToken:
            if len(token) != 1 {
                return wrong_token(s)
            }
            field = token[0]
        case:
            return wrong_token(s)
        }
        if field.ident in fields_map {
            diagnostic(
                s.file,
                field.pos,
                "There is already a field called `%s` in this struct",
                field.ident,
            )
            return Struct(Type){}, false
        }

        get_next_token(s, false)
        #partial switch token in s.last_token {
        case:
            wrong_token_err(
                s,
                []string{fmt.aprintf("`:` to specify the type of the `%s` field", field.ident)},
            )
        case ColonToken:
        }

        get_next_token(s, true)
        field_type, other_possible_tokens, ok := parse_type(s)
        if !ok {
            return Struct(Type){}, false
        }

        fields_map[field.ident] = len(fields)
        append(&fields, StructField(Type){field, field_type})

        #partial switch _ in s.last_token {
        case:
            append_elems(&other_possible_tokens, "`,` to add a new field to the struct", "`}`")
            wrong_token_err(s, other_possible_tokens[:])
            return Struct(Type){}, false
        case CommaToken:
        case CloseBraceToken:
            return Struct(Type){fields_map, fields[:]}, true
        }
    }
}

parse_type :: proc(
    state: ^ParserState,
    descriptions_of_other_possible_tokens: ..string,
) -> (
    Type,
    [dynamic]string,
    bool,
) {
    type_pos := state.last_token_pos
    #partial switch token in state.last_token {
    case:
        wrong_token_err(
            state,
            join(
                descriptions_of_other_possible_tokens,
                "the name of a type",
                "`<` to create a sum type",
                "`[` to create an array type",
                "`{` to create a struct type",
                "`(`  to create a function type",
                // "`dynamic` for a dynamic type",
            ),
        )
        return Type{}, nil, false

    case OpenBracketToken:
        get_next_token(state, true)
        close_bracket :: "`)` to end the arguments section of this function type"
        args := make([dynamic]Type)
        function_type_loop: for {
            _, is_close_bracket := state.last_token.(CloseBracketToken)
            if is_close_bracket {
                break
            }
            type, descriptions_of_other_possible_tokens, ok := parse_type(state, close_bracket)
            if !ok {
                return Type{}, nil, false
            }
            append_elem(&args, type)
            #partial switch _ in state.last_token {
            case:
                append_elems(&descriptions_of_other_possible_tokens, "`,`", close_bracket)
                wrong_token_err(state, descriptions_of_other_possible_tokens[:])
                return Type{}, nil, false
            case CommaToken:
                continue
            case CloseBracketToken:
                break function_type_loop
            }
        }

        get_next_token(state, true)
        _, is_arrow := state.last_token.(ArrowToken)
        if !is_arrow {
            return Type{type_pos, Function{args[:], nil}},
                [dynamic]string{"`->` to specify the return type of the function"},
                true
        }

        get_next_token(state, true)
        return_type, descriptions_of_other_possible_tokens, ok := parse_type(state)
        if !ok {
            return Type{}, nil, false
        }
        function_outputs := make([]Type, 1)
        function_outputs[0] = return_type
        return Type{type_pos, Function{args[:], function_outputs}},
            descriptions_of_other_possible_tokens,
            true

    // case DynamicToken:
    //     get_next_token(state, false)
    //     type, other_possible_tokens, ok := parse_type(state)
    //     if !ok {
    //         return Type{}, nil, false
    //     }
    //     return Type{type_pos, DynamicType(new_clone(type))}, other_possible_tokens, true

    case OpenBraceToken:
        t, ok := parse_struct(state)
        if !ok {
            return Type{}, nil, false
        }
        get_next_token(state, true)
        return Type{type_pos, t}, nil, true

    case OpenAngleBracketToken:
        variants_map := make(map[string]uint)
        variants := make(#soa[dynamic]SumTypeVariant(Type, struct {}))
        loop: for {
            get_next_token(state, true)
            expected :: []string{"an identifier with one segment", "`>`"}
            #partial switch token2 in state.last_token {
            case:
                wrong_token_err(state, expected)
                return Type{}, nil, false
            case CloseAngleBracketToken:
                break loop
            case IdentToken:
                if len(token2) != 1 {
                    wrong_token_err(state, expected)
                    return Type{}, nil, false
                }
                variant_name := token2[0]
                if variant_name.ident in variants_map {
                    diagnostic(
                        state.file,
                        variant_name.pos,
                        "There is already a variant called `%s` in this sum type",
                        variant_name.ident,
                    )
                    return Type{}, nil, false
                }
                variant_payload := Struct(Type){}
                has_payload := false
                get_next_token(state, true)
                #partial switch _ in state.last_token {
                case OpenBraceToken:
                    variant_payload, has_payload = parse_struct(state)
                    if !has_payload {
                        return Type{}, nil, false
                    }
                    get_next_token(state, false)
                }
                variants_map[variant_name.ident] = len(&variants)
                append(
                    &variants,
                    SumTypeVariant(Type, struct {}){variant_name, variant_payload, struct{}{}},
                )
                #partial switch _ in state.last_token {
                case:
                    expected := [dynamic]string{"`,`", "`>`"}
                    if !has_payload {
                        append_elem(
                            &expected,
                            fmt.aprintf(
                                "`{` to add a payload to the `%s` variant",
                                variant_name.ident,
                            ),
                        )
                    }
                    wrong_token_err(state, expected[:])
                    return Type{}, nil, false
                case CommaToken:
                case CloseAngleBracketToken:
                    break loop
                }
            }
        }
        get_next_token(state, true)
        return Type{type_pos, SumType(Type, struct {}){variants_map, variants[:]}}, nil, true

    case OpenSquareBracketToken:
        get_next_token(state, false)
        length: u32 = 0
        #partial switch token2 in state.last_token {
        case CloseSquareBracketToken:
        case DigitsToken:
            length_uint, ok := strconv.parse_uint(string(token2))
            if !ok || length_uint > uint(max(u32)) {
                diagnostic(state.file, state.last_token_pos, "Failed to parse uint")
                return Type{}, nil, false
            }
            length = u32(length_uint)
            get_next_token(state, false)
            _, is_close_square_bracket := state.last_token.(CloseSquareBracketToken)
            if !is_close_square_bracket {
                wrong_token_err(state, []string{"`]`"})
                return Type{}, nil, false
            }
        case:
            wrong_token_err(state, []string{"`]`", "a number for the length of the array"})
            return Type{}, nil, false
        }
        get_next_token(state, false)
        item_type, other_possible_tokens, ok := parse_type(state)
        if !ok {
            return Type{}, nil, false
        }
        return Type{type_pos, Array{length, new_clone(item_type)}}, other_possible_tokens, true

    case IdentToken:
        get_next_token(state, true)
        _, is_open_square_bracket := state.last_token.(OpenSquareBracketToken)
        if !is_open_square_bracket {
            return Type{type_pos, TypeVariable{token, nil}},
                [dynamic]string{"`[` to specify the type of a generic argument"},
                true
        }
        get_next_token(state, true)
        type, other_possible_tokens, ok := parse_type(state)
        if !ok {
            return Type{}, nil, false
        }
        _, is_close_square_bracket := state.last_token.(CloseSquareBracketToken)
        if !is_close_square_bracket {
            append_elem(&other_possible_tokens, "`]`")
            wrong_token_err(state, other_possible_tokens[:])
            return Type{}, nil, false
        }
        get_next_token(state, true)
        return Type{type_pos, TypeVariable{token, new_clone(type)}}, nil, true
    }
}

// Does not handle trailing commas correctly
parse_value_list :: proc(s: ^ParserState) -> ([]Value, [dynamic]string, bool) {
    out := [dynamic]Value{}
    for {
        get_next_token(&s.tokenizer, true)
        v := parse_value(s)
        if !v.ok {
            return nil, nil, false
        }
        append_elem(&out, v.value^)

        #partial switch token in s.last_token {
        case CommaToken:
            continue
        case:
            append_elem(&v.descriptions_of_other_possible_tokens, "`,`")
            return out[:], v.descriptions_of_other_possible_tokens, true
        }
    }
}

// Does not include the `(`
parse_values_until_close_bracket :: proc(s: ^ParserState) -> ([]Value, bool) {
    values := [dynamic]Value{}
    for {
        get_next_token(&s.tokenizer, true)
        other_possible_tokens: [dynamic]string
        #partial switch token in s.last_token {
        case CloseBracketToken:
            return values[:], true
        case:
            v := parse_value(s, "`)`")
            other_possible_tokens = v.descriptions_of_other_possible_tokens
            if !v.ok {
                return nil, false
            }
            append_elem(&values, v.value^)
        }

        #partial switch token in s.last_token {
        case:
            append_elems(&other_possible_tokens, "`)`", "`,`")
            wrong_token_err(&s.tokenizer, other_possible_tokens[:])
            return nil, false
        case CommaToken:
            continue
        case CloseBracketToken:
            return values[:], true
        }
    }
}

ParsedValue :: struct {
    ok:                                    bool,
    value:                                 ^Value,
    descriptions_of_other_possible_tokens: [dynamic]string,
}

parse_initial_value :: proc(
    s: ^ParserState,
    descriptions_of_other_possible_tokens: []string,
) -> (
    ValueWithoutPos,
    [dynamic]string,
    bool,
) {
    value: ValueWithoutPos
    #partial switch token in s.last_token {
    case:
        wrong_token_err(
            s,
            join(
                descriptions_of_other_possible_tokens,
                "`true`",
                "`false`",
                "`|` to create a lambda function value",
                "`(` to create a value in brackets",
                "`[` to create an array literal",
                "a digits token",
                "a string literal",
                "a character literal",
                "a marker token (# followed by one or more alphanumerics)",
            ),
        )
        return nil, nil, false
    case IdentToken:
        value = VariableReference(token)
    case MarkerToken:
        pos := s.last_token_pos
        markers := [dynamic]IdentAndPos{{string(token), s.last_token_pos}}
        for {
            get_next_token(s, false)
            marker, is_marker := s.last_token.(MarkerToken)
            if !is_marker {
                break
            }
            append_elem(&markers, IdentAndPos{string(marker), s.last_token_pos})
        }
        value_pos := s.last_token_pos
        val, descriptions_of_other_possible_tokens, ok := parse_initial_value(s, nil)
        if !ok {
            return nil, nil, false
        }
        func_index, is_func := val.(uint)
        if is_func {
            assert(s.function_defs[func_index].markers == nil)
            s.function_defs[func_index].markers = markers[:]
            return func_index, descriptions_of_other_possible_tokens, true
        }
        return MarkedValue{new_clone(Value{value_pos, val}), markers[:]},
            descriptions_of_other_possible_tokens,
            true
    case TrueToken:
        value = Bool(true)
    case FalseToken:
        value = Bool(false)
    case OpenBracketToken:
        get_next_token(&s.tokenizer, true)
        val := parse_value(s)
        if !val.ok {
            return nil, nil, false
        }
        _, is_close_bracket_token := s.last_token.(CloseBracketToken)
        if !is_close_bracket_token {
            append_elem(&val.descriptions_of_other_possible_tokens, "`)`")
            wrong_token_err(&s.tokenizer, val.descriptions_of_other_possible_tokens[:])
            return nil, nil, false
        }
        value = ValueInBrackets(val.value)
    case OpenSquareBracketToken:
        type, other_possible_tokens, ok := parse_type(s)
        if !ok {
            return nil, nil, false
        }
        _, is_open := s.last_token.(OpenBracketToken)
        if !is_open {
            append_elem(&other_possible_tokens, "`(`")
            wrong_token_err(s, other_possible_tokens[:])
            return nil, nil, false
        }
        args, args_ok := parse_values_until_close_bracket(s)
        if !args_ok {
            return nil, nil, false
        }
        value = TypeInitialisation{type.type, args}
    case DigitsToken:
        value = Number(token)
    case StringToken:
        strings := [dynamic]string{string(token)}
        for {
            get_next_token(&s.tokenizer, true)
            #partial switch token2 in s.last_token {
            case:
                return String(strings[:]), [dynamic]string{"a string token"}, true
            case StringToken:
                append_elem(&strings, string(token2))
            }
        }
    case CharToken:
        value = Char(token)
    case BarToken:
        func, ok := parse_function_def(s)
        if !ok {
            return nil, nil, false
        }
        value = uint(len(s.function_defs))
        append_elem(&s.function_defs, func)
    }
    get_next_token(&s.tokenizer, true)
    return value, nil, true
}

parse_value :: proc(
    s: ^ParserState,
    descriptions_of_other_possible_tokens: ..string,
) -> ParsedValue {
    value_pos := s.last_token_pos
    value_without_pos, other_possible_tokens, ok := parse_initial_value(
        s,
        descriptions_of_other_possible_tokens,
    )
    if !ok {
        return ParsedValue{ok = false}
    }
    value := new_clone(Value{value_pos, value_without_pos})

    // Parse possible function call or indexed array access
    loop: for {
        #partial switch token in s.last_token {
        case:
            append_elems(
                &other_possible_tokens,
                "`(` to call a function", // TODO: add name of function
                "`[` to access a specific index in an array", // TODO: add name of array
            )
            break loop
        case OpenBracketToken:
            args, ok := parse_values_until_close_bracket(s)
            if !ok {
                return ParsedValue{ok = false}
            }
            value = new_clone(Value{value_pos, FunctionCall{value, args}})
            clear(&other_possible_tokens)
            get_next_token(&s.tokenizer, true)
        case OpenSquareBracketToken:
            get_next_token(&s.tokenizer, false)
            index_pos := s.last_token_pos
            array_index := parse_value(s)
            if !array_index.ok {
                return ParsedValue{ok = false}
            }
            #partial switch token2 in s.last_token {
            case:
                append_elems(&array_index.descriptions_of_other_possible_tokens, "`]`", "`:`")
                wrong_token_err(&s.tokenizer, array_index.descriptions_of_other_possible_tokens[:])
                return ParsedValue{ok = false}
            case CloseSquareBracketToken:
                value = new_clone(
                    Value {
                        value_pos,
                        ArrayAccess{value, index_pos, SingleElemAccess(array_index.value)},
                    },
                )
                clear(&other_possible_tokens)
                get_next_token(&s.tokenizer, true)
            case ColonToken:
                get_next_token(&s.tokenizer, false)
                array_index2 := parse_value(s)
                if !array_index2.ok {
                    return ParsedValue{ok = false}
                }
                _, is_close_square_bracket := s.last_token.(CloseSquareBracketToken)
                if !is_close_square_bracket {
                    append_elem(&array_index2.descriptions_of_other_possible_tokens, "`]`")
                    wrong_token_err(
                        &s.tokenizer,
                        array_index2.descriptions_of_other_possible_tokens[:],
                    )
                    return ParsedValue{ok = false}
                }
                value = new_clone(
                    Value {
                        value_pos,
                        ArrayAccess {
                            value,
                            index_pos,
                            RangedAccess{array_index.value, array_index2.value},
                        },
                    },
                )
                clear(&other_possible_tokens)
                get_next_token(&s.tokenizer, true)
            }
        }
    }

    // Parse possible arithmetic
    append_elems(
        &other_possible_tokens,
        "a value joiner (`and`, `or`, `==`, `!=`, `>`, `>=`, `<`, `<=`, `*`, `/`, `+`, `-`, `%`, `::`)",
    )
    value_type: ValueJoinMethod
    #partial switch token in s.last_token {
    case:
        return ParsedValue{true, value, other_possible_tokens}
    case AndToken:
        value_type = .BooleanAnd
    case ColonColonToken:
        value_type = .Append
    case OrToken:
        value_type = .BooleanOr
    case OpenAngleBracketToken:
        value_type = .IsLessThan
    case LessThanOrEqualToken:
        value_type = .IsLessThanOrEqual
    case CloseAngleBracketToken:
        value_type = .IsGreaterThan
    case GreaterThanOrEqualToken:
        value_type = .IsGreaterThanOrEqual
    case SymbolsToken:
        switch token {
        case:
            return ParsedValue{true, value, other_possible_tokens}
        case "==":
            value_type = .IsEqual
        case "!=":
            value_type = .IsNotEqual
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
    get_next_token(&s.tokenizer, true)
    next_value := parse_value(s)
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

// Returns `nil, nil` if there was an error
parse_iterator :: proc(s: ^ParserState) -> (Iterator, [dynamic]string) {
    get_next_token(&s.tokenizer, false)
    value1 := parse_value(s)
    if !value1.ok {
        return nil, nil
    }

    symbols, is_symbols_token := s.last_token.(SymbolsToken)
    type: NumericIteratorType
    if is_symbols_token && symbols == "..=" {
        type = .IncludeEndValue
    } else if is_symbols_token && symbols == "..<" {
        type = .ExcludeEndValue
    } else {
        append_elems(&value1.descriptions_of_other_possible_tokens, "`..=`", "`..<`")
        return value1.value^, value1.descriptions_of_other_possible_tokens
    }

    get_next_token(&s.tokenizer, false)
    value2 := parse_value(s)
    if !value2.ok {
        return nil, nil
    }

    _, is_step_token := s.last_token.(StepToken)
    if is_step_token {
        get_next_token(&s.tokenizer, false)
        step := parse_value(s)
        if !step.ok {
            return nil, nil
        }
        return NumericIterator{value1.value^, value2.value^, step.value, type},
            step.descriptions_of_other_possible_tokens
    }
    append_elem(&value2.descriptions_of_other_possible_tokens, "`step`")
    return NumericIterator{value1.value^, value2.value^, nil, type},
        value2.descriptions_of_other_possible_tokens
}

// Does not include the `for`
parse_for_loop :: proc(s: ^ParserState) -> (ForInLoop, bool) {
    variables: [3]IdentAndPos
    variable_index := 0
    variables_loop: for {
        get_next_token(&s.tokenizer, false)
        ident, is_ident := s.last_token.(IdentToken)
        if !is_ident || len(ident) != 1 {
            wrong_token_err(
                s,
                []string {
                    "the name of the variable in a for loop (an identifier with one segment)",
                },
            )
            return ForInLoop{}, false
        }
        variables[variable_index] = ident[0]
        variable_index += 1

        get_next_token(&s.tokenizer, false)
        #partial switch token in s.last_token {
        case:
            wrong_token_err(&s.tokenizer, []string{"`,`", "`in`"})
            return ForInLoop{}, false
        case InToken:
            break variables_loop
        case CommaToken:
            if variable_index >= 3 {
                diagnostic(
                    s.file,
                    s.last_token_pos,
                    "There cannot be more than 3 variables in a for loop head (the iteration the for loop is on, the key of the thing being iterated over, and the value of the thing being iterated over)",
                )
                return ForInLoop{}, false
            }
        }
    }

    iter, other_possible_tokens := parse_iterator(s)
    if iter == nil {
        return ForInLoop{}, false
    }

    _, is_open_brace := s.last_token.(OpenBraceToken)
    if !is_open_brace {
        append_elem(&other_possible_tokens, "`{` to start the body of the for loop")
        wrong_token_err(s, other_possible_tokens[:])
        return ForInLoop{}, false
    }

    block, ok := parse_block(s)
    if !ok {
        return ForInLoop{}, false
    }

    return ForInLoop{variables, iter, block}, true
}

// Does not include the `if`
parse_if :: proc(s: ^ParserState) -> (^IfElseStatement, [dynamic]string, bool) {
    if_pos := s.last_token_pos
    get_next_token(&s.tokenizer, true)
    condition := parse_value(s)
    if !condition.ok {
        return nil, nil, false
    }
    #partial switch _ in s.last_token {
    case OpenBraceToken:
    case:
        append_elem(
            &condition.descriptions_of_other_possible_tokens,
            "`{` to start the body of the if statement",
        )
        wrong_token_err(&s.tokenizer, condition.descriptions_of_other_possible_tokens[:])
        return nil, nil, false
    }

    block, ok := parse_block(s)
    if !ok {
        return nil, nil, false
    }

    get_next_token(&s.tokenizer, true)
    #partial switch _ in s.last_token {
    case ElseToken:
        else_pos := s.last_token_pos
        get_next_token(&s.tokenizer, true)
        #partial switch _ in s.last_token {
        case:
            wrong_token_err(&s.tokenizer, []string{"`{`", "`if`"})
            return nil, nil, false
        case OpenBraceToken:
            else_block, ok := parse_block(s)
            if !ok {
                return nil, nil, false
            }
            get_next_token(&s.tokenizer, true)
            return new_clone(IfElseStatement{condition.value^, block, else_block}),
                [dynamic]string{},
                true

        case IfToken:
            else_block := make([]Statement, 1)
            else_statement, other_possible_tokens, ok := parse_if(s)
            if !ok {
                return nil, nil, false
            }
            else_block[0] = Statement{else_pos, else_statement^}
            return new_clone(IfElseStatement{condition.value^, block, else_block}),
                other_possible_tokens,
                true
        }
    case:
        array := make([dynamic]string, 1)
        array[0] = "`else`"
        return new_clone(IfElseStatement{condition.value^, block, []Statement{}}), array, true
    }
}

// The `[]string` returned is an array of other possible tokens
get_identifier :: proc(
    s: ^ParserState,
    variable_dest_type: VariableDestType,
) -> (
    VariableDest,
    [dynamic]string,
    bool,
) {
    idents, is_ident := s.last_token.(IdentToken)
    if !is_ident || len(idents) != 1 {
        wrong_token_err(s, []string{"an identifier with one segment"})
        return VariableDest{}, nil, false
    }
    ident := idents[0]
    get_next_token(s, false)
    _, is_open_square_brace := s.last_token.(OpenSquareBracketToken)
    if !is_open_square_brace {
        others := make([dynamic]string, 1)
        others[0] = "`[`"
        return VariableDest{ident, variable_dest_type, nil}, others, true
    }
    get_next_token(s, true)
    value := parse_value(s)
    if !value.ok {
        return VariableDest{}, nil, false
    }
    _, is_close_square_brace := s.last_token.(CloseSquareBracketToken)
    if !is_close_square_brace {
        append_elem(&value.descriptions_of_other_possible_tokens, "`[`")
        wrong_token_err(s, value.descriptions_of_other_possible_tokens[:])
        return VariableDest{}, nil, false
    }
    get_next_token(s, true)
    return VariableDest{ident, variable_dest_type, value.value}, nil, true
}


// The `[]string` returned is an array of other possible tokens
parse_managed_variable :: proc(
    s: ^ParserState,
    descriptions_of_other_possible_tokens: ..string,
) -> (
    VariableDest,
    [dynamic]string,
    bool,
) {
    #partial switch token in s.last_token {
    case IdentToken:
        return get_identifier(s, .Constant)
    case MutToken:
        get_next_token(s, false)
        #partial switch token2 in s.last_token {
        case IdentToken:
            return get_identifier(s, .Mutable)
        case SymbolsToken:
            if token2 != "+" {
                break
            }
            get_next_token(s, false)
            return get_identifier(s, .MutableAddedToPcs)
        }
        wrong_token_err(s, []string{"`+`", "an identifier"})
        return VariableDest{}, nil, false
    case SymbolsToken:
        switch token {
        case "~":
            get_next_token(s, false)
            return get_identifier(s, .Mutated)
        case "+":
            get_next_token(s, false)
            return get_identifier(s, .ConstantAddedToPcs)
        }
    }
    wrong_token_err(
        s,
        join(descriptions_of_other_possible_tokens, "`mut`", "`~`", "`+`", "an identifier"),
    )
    return VariableDest{}, nil, false
}

// Does not include the `{`
parse_block :: proc(s: ^ParserState) -> ([]Statement, bool) {
    out := [dynamic]Statement{}
    get_next_token(s, true)
    other_possible_tokens := [dynamic]string{}
    for {
        pos := s.last_token_pos
        #partial switch_stmt: switch token in s.last_token {
        case:
            // TODO: I would like to remove this mingling of expected tokens as it makes the error messages less clear
            append_elems(
                &other_possible_tokens,
                "`do` to create a do while loop",
                "`while` to create a while loop",
                "`if`",
                "`match`",
                "`for`",
                "`return`",
                "`yield`",
                "`}`",
            )
            var, other_possible_tokens, ok := parse_managed_variable(s, ..other_possible_tokens[:])
            if !ok {
                return nil, false
            }
            stmt: VariableManagement
            stmt, other_possible_tokens, ok = parse_variable_management_after_first_var(
                s,
                var,
                ..other_possible_tokens[:],
            )
            if !ok {
                return nil, false
            }
            append_elem(&out, Statement{pos, stmt})
        case DoToken:
            get_next_token(s, false)
            _, is_open_brace := s.last_token.(OpenBraceToken)
            if !is_open_brace {
                wrong_token_err(s, []string{"`{`"})
                return nil, false
            }
            body, ok := parse_block(s)
            if !ok {
                return nil, false
            }
            get_next_token(s, false)
            _, is_while := s.last_token.(WhileToken)
            if !is_while {
                wrong_token_err(s, []string{"`while`"})
                return nil, false
            }
            get_next_token(s, false)
            condition := parse_value(s)
            if !condition.ok {
                return nil, false
            }
            other_possible_tokens = condition.descriptions_of_other_possible_tokens
            append_elem(
                &out,
                Statement{pos, ConditionControlledLoop{.DoWhileLoop, condition.value^, body}},
            )
        case WhileToken:
            get_next_token(s, false)
            condition := parse_value(s)
            if !condition.ok {
                return nil, false
            }
            _, is_open_brace := s.last_token.(OpenBraceToken)
            if !is_open_brace {
                append_elem(&condition.descriptions_of_other_possible_tokens, "`{`")
                wrong_token_err(s, condition.descriptions_of_other_possible_tokens[:])
                return nil, false
            }
            body, ok := parse_block(s)
            if !ok {
                return nil, false
            }
            clear_dynamic_array(&other_possible_tokens)
            get_next_token(s, true)
            append_elem(
                &out,
                Statement{pos, ConditionControlledLoop{.WhileLoop, condition.value^, body}},
            )
        case IdentToken:
            get_next_token(s, true)
            // TODO: Handle parsing something like `array[index] = value`
            #partial switch token2 in s.last_token {
            case:
                wrong_token_err(
                    s,
                    []string {
                        fmt.aprintf(
                            "`(` to call a function called `%s`",
                            strings.join(token.ident[:len(token)], "."),
                        ),
                        "`,`",
                        "`=`",
                    },
                )
                return nil, false
            case OpenBracketToken:
                args, ok := parse_values_until_close_bracket(s)
                if !ok {
                    return nil, false
                }
                get_next_token(&s.tokenizer, true)
                variable := VariableReference(token)
                append_elem(
                    &out,
                    Statement{pos, FunctionCall{new_clone(Value{pos, variable}), args}},
                )
                break switch_stmt
            case CommaToken:
                get_next_token(s, true)
            case AssignToken:
            }
            if len(token) != 1 {
                diagnostic(
                    s.file,
                    s.last_token_pos,
                    "TODO: Support assigns where the destination has more than one segment",
                )
                return nil, false
            }
            stmt, other_possible_tokens, ok := parse_variable_management_after_first_var(
                s,
                VariableDest{IdentAndPos{token[0].ident, s.last_token_pos}, .Constant, nil},
            )
            if !ok {
                return nil, false
            }
            append_elem(&out, Statement{pos, stmt})
        case IfToken:
            if_else: ^IfElseStatement
            ok: bool
            if_else, other_possible_tokens, ok = parse_if(s)
            if !ok {
                return nil, false
            }
            append_elem(&out, Statement{pos, if_else^})
        case MatchToken:
            get_next_token(s, true)
            value := parse_value(s)
            if !value.ok {
                return nil, false
            }

            if _, is_open_brace := s.last_token.(OpenBraceToken); !is_open_brace {
                append_elem(&value.descriptions_of_other_possible_tokens, "`{`")
                wrong_token_err(s, value.descriptions_of_other_possible_tokens[:])
                return nil, false
            }

            branches := make([dynamic]MatchBranch)
            match_loop: for {
                get_next_token(s, true)
                name: IdentAndPos = ---
                #partial switch token2 in s.last_token {
                case CloseBraceToken:
                    break match_loop
                case IdentToken:
                    name = token2[0]
                case:
                    wrong_token_err(
                        s,
                        []string {
                            "An identifier with one segment to create another match branch",
                            "`}` to finish the match statement",
                        },
                    )
                    return nil, false
                }

                get_next_token(s, true)
                if _, is_colon := s.last_token.(ColonToken); !is_colon {
                    wrong_token_err(s, []string{"`:`"})
                    return nil, false
                }

                get_next_token(s, true)
                type, other_possible_tokens, type_ok := parse_type(s)
                if !type_ok {
                    return nil, false
                }

                if _, is_open_brace := s.last_token.(OpenBraceToken); !is_open_brace {
                    append_elem(&other_possible_tokens, "`{`")
                    wrong_token_err(s, other_possible_tokens[:])
                    return nil, false
                }

                body, body_ok := parse_block(s)
                if !body_ok {
                    return nil, false
                }

                append_elem(&branches, MatchBranch{name, type, body})
            }
            append_elem(&out, Statement{pos, MatchStatement{value.value^, branches[:]}})
            clear(&other_possible_tokens)
            get_next_token(s, true)
        case ForToken:
            loop, ok := parse_for_loop(s)
            if !ok {
                return nil, false
            }
            append_elem(&out, Statement{pos, loop})
            get_next_token(&s.tokenizer, true)
        case ReturnToken:
            values: []Value
            ok: bool
            values, other_possible_tokens, ok = parse_value_list(s)
            if !ok {
                return nil, false
            }
            append_elem(&out, Statement{pos, ReturnStatement(values)})
        case YieldToken:
            values: []Value
            ok: bool
            values, other_possible_tokens, ok = parse_value_list(s)
            if !ok {
                return nil, false
            }
            append_elem(&out, Statement{pos, YieldStatement(values)})
        case CloseBraceToken:
            return out[:], true
        }
        _, is_close_brace := s.last_token.(CloseBraceToken)
        if is_close_brace {
            return out[:], true
        } else if !s.last_token_skipped {
            append_elem(&other_possible_tokens, "A newline or `;` to separate statements")
            wrong_token_err(s, other_possible_tokens[:])
            return nil, false
        }
    }
}

// The `[]string` returned is descriptions of other possible tokens
parse_variable_management_after_first_var :: proc(
    s: ^ParserState,
    first_var: VariableDest,
    descriptions_of_other_possible_tokens: ..string,
) -> (
    VariableManagement,
    [dynamic]string,
    bool,
) {
    variables := [dynamic]VariableDest{first_var}
    type: MutationType
    other_possible_tokens: [dynamic]string
    loop: for {
        #partial switch token in s.last_token {
        case:
            append_elems(&other_possible_tokens, "`=`", "`,`", "`+=`", "`-=`", "`*=`", "`/=`")
            wrong_token_err(s, other_possible_tokens[:])
            return VariableManagement{}, nil, false
        case SymbolsToken:
            switch token {
            case "+=":
                type = .IncrementBy
                break loop
            case "-=":
                type = .DecrementBy
                break loop
            case "*=":
                type = .MultiplyBy
                break loop
            case "/=":
                type = .DivideBy
                break loop
            }
        case AssignToken:
            type = MutationType.SetTo
            break loop
        case CommaToken:
            get_next_token(s, false)
        }
        ok := false
        var := VariableDest{}
        var, other_possible_tokens, ok = parse_managed_variable(s)
        if !ok {
            return VariableManagement{}, nil, false
        }
        append_elem(&variables, var)
    }
    get_next_token(s, true)
    value := parse_value(s)
    if !value.ok {
        return VariableManagement{}, nil, false
    }
    return VariableManagement{value.value^, variables[:], type},
        value.descriptions_of_other_possible_tokens,
        true
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

// The boolean returned is whether the function passed successfully
parse_function_def :: proc(s: ^ParserState) -> (FunctionDefinition, bool) {
    args := make(#soa[dynamic]FunctionArg)
    loop: for {
        arg: FunctionArg
        get_next_token(s, true)

        expected :: []string {
            "an identifier for the name of a normal function argument",
            "`~` to add a mutable function argument",
            "`-` to add a function argument which is deallocated from the PCS during the execution of this function",
            "`|`",
        }
        #partial switch token in s.last_token {
        case:
            wrong_token_err(s, expected)
            return FunctionDefinition{}, false
        case BarToken:
            break loop
        case SymbolsToken:
            switch token {
            case "~":
                arg.arg_type = .Mutable
            case "-":
                arg.arg_type = .RemovedFromStack
            case:
                wrong_token_err(s, expected)
                return FunctionDefinition{}, false
            }
            get_next_token(s, true)
            #partial switch token2 in s.last_token {
            case:
                wrong_token_err(s, expected)
                return FunctionDefinition{}, false
            case IdentToken:
                if len(token2) != 1 {
                    wrong_token_err(s, expected)
                    return FunctionDefinition{}, false
                }
                arg.name = token2[0]
            }
        case IdentToken:
            if len(token) != 1 {
                wrong_token_err(s, expected)
                return FunctionDefinition{}, false
            }
            arg.name = token[0]
        }

        get_next_token(s, true)
        #partial switch _ in s.last_token {
        case ColonToken:
        case:
            wrong_token_err(s, []string{"`:`"})
            return FunctionDefinition{}, false
        }

        get_next_token(s, true)
        ok: bool
        other_possible_tokens: [dynamic]string
        arg.value_type, other_possible_tokens, ok = parse_type(s)
        if !ok {
            return FunctionDefinition{}, false
        }
        append_soa_elem(&args, arg)

        #partial switch token in s.last_token {
        case:
            append_elems(&other_possible_tokens, "`,`", "`|`")
            wrong_token_err(s, other_possible_tokens[:])
            return FunctionDefinition{}, false
        case CommaToken:
            continue
        case BarToken:
            break loop
        }
    }

    get_next_token(&s.tokenizer, true)
    outputs := make(#soa[dynamic]FunctionOutput)
    open_brace :: "`{` to start the body of the function"
    #partial switch _ in s.last_token {
    case:
        wrong_token_err(&s.tokenizer, []string{"`->`", open_brace})
        return FunctionDefinition{}, false
    case ArrowToken:
        get_next_token(s, true)
        other_possible_tokens: [dynamic]string
        #partial switch _ in s.last_token {
        case:
            symbols, is_symbols_token := s.last_token.(SymbolsToken)
            ok := true
            output := FunctionOutput{}
            if is_symbols_token && symbols == "+" {
                get_next_token(s, false)
                output.output_type = .AllocatedOntoStack
                output.value_type, other_possible_tokens, ok = parse_type(s)
            } else {
                output.value_type, other_possible_tokens, ok = parse_type(
                    s,
                    "`(`",
                    "`+` to specify that this output is allocated onto the PCS",
                )
            }
            if !ok {
                return FunctionDefinition{}, false
            }
            append(&outputs, output)
        case OpenBracketToken:
            // parse_name_and_type_list(state, .TypeRequired, "`)`")
            diagnostic(
                s.file,
                s.last_token_pos,
                "TODO: Implement parsing functions with multiple return values",
            )
            return FunctionDefinition{}, false
        }
        #partial switch _ in s.last_token {
        case OpenBraceToken:
        case:
            append_elem(&other_possible_tokens, open_brace)
            wrong_token_err(s, other_possible_tokens[:])
            return FunctionDefinition{}, false
        }
    case OpenBraceToken:
    }

    block, ok := parse_block(s)
    if !ok {
        return FunctionDefinition{}, false
    }
    return FunctionDefinition{args[:], outputs[:], block, nil}, true
}

GlobalTypeWithGeneric :: struct {
    name:    string,
    generic: IdentAndPos,
    value:   Type,
}

GlobalTypeWithoutGeneric :: struct {
    name:  string,
    value: Type,
}

GlobalTypeWithGenericRef :: struct {
    index: u32,
}

GlobalTypeWithoutGenericRef :: struct {
    index: uint, // An index into `CheckerState.global_types_without_generics`
}

ParsedGlobal :: struct {
    pos:   uint,
    value: union {
        Value,
        GlobalTypeWithGenericRef,
        GlobalTypeWithoutGenericRef,
    },
}

ParserOutput :: struct {
    imports:                       []Import,
    globals:                       map[string]ParsedGlobal,
    global_types_without_generics: []GlobalTypeWithoutGeneric,
    global_types_with_generics:    []GlobalTypeWithGeneric,
    ok:                            bool,
}

parse :: proc(s: ^ParserState) -> ParserOutput {
    imports := [dynamic]Import{}
    globals := make(map[string]ParsedGlobal)
    global_types_without_generics := make([dynamic]GlobalTypeWithoutGeneric)
    global_types_with_generics := make([dynamic]GlobalTypeWithGeneric)
    get_next_token(&s.tokenizer, true)
    other_possible_tokens := [dynamic]string{}
    loop: for {
        append_elems(
            &other_possible_tokens,
            "a newline",
            "a comment",
            "an identifier with one segment to define a global",
        )
        #partial switch token in s.last_token {
        case:
            wrong_token_err(&s.tokenizer, other_possible_tokens[:])
            return ParserOutput{ok = false}
        case EndOfFileToken:
            return ParserOutput {
                imports[:],
                globals,
                global_types_without_generics[:],
                global_types_with_generics[:],
                true,
            }
        case ImportToken:
            // TODO: Check that all imports are at the top of the file
            import_pos := s.last_token_pos
            get_next_token(s, false)
            components, is_ident := s.last_token.(IdentToken)
            if !is_ident {
                wrong_token_err(s, []string{"An identifier"})
                return ParserOutput{ok = false}
            }
            append_elem(&imports, Import{import_pos, components})
            get_next_token(s, true)
            clear(&other_possible_tokens)
        case IdentToken:
            position := s.last_token_pos
            if len(token) != 1 {
                wrong_token_err(&s.tokenizer, other_possible_tokens[:])
                return ParserOutput{ok = false}
            }
            name := token[0].ident
            if name in globals {
                line, column := get_location(s.code, globals[name].pos)
                diagnostic(
                    s.file,
                    position,
                    "The global `%s` is already declared at line %d and column %d",
                    name,
                    line,
                    column,
                )
                return ParserOutput{ok = false}
            }
            get_next_token(&s.tokenizer, false)
            generic := IdentAndPos{}
            _, is_open_square_bracket := s.last_token.(OpenSquareBracketToken)
            if is_open_square_bracket {
                get_next_token(&s.tokenizer, false)
                segments, is_ident := s.last_token.(IdentToken)
                if !is_ident || len(segments) != 1 {
                    wrong_token_err(&s.tokenizer, []string{"An identifier with one segment"})
                    return ParserOutput{ok = false}
                }
                generic = segments[0]

                get_next_token(&s.tokenizer, false)
                _, is_close_square_bracket := s.last_token.(CloseSquareBracketToken)
                if !is_close_square_bracket {
                    wrong_token_err(&s.tokenizer, []string{"`]`"})
                    return ParserOutput{ok = false}
                }

                get_next_token(&s.tokenizer, false)
            }
            #partial switch _ in s.last_token {
            case:
                if generic.ident == "" {
                    expected :: []string {
                        "`=` to define a global value",
                        "`:` to define a global type",
                        "`[` to define the name of a generic argument to a type",
                    }
                    wrong_token_err(&s.tokenizer, expected)
                } else {
                    wrong_token_err(&s.tokenizer, []string{"`:` to define a global type"})
                }
                return ParserOutput{ok = false}
            case ColonToken:
                get_next_token(&s.tokenizer, false)
                type: Type
                ok: bool
                type, other_possible_tokens, ok = parse_type(s)
                if !ok {
                    return ParserOutput{ok = false}
                }
                if generic.ident == "" {
                    globals[name] = ParsedGlobal {
                        position,
                        GlobalTypeWithoutGenericRef{len(global_types_without_generics)},
                    }
                    append_elem(
                        &global_types_without_generics,
                        GlobalTypeWithoutGeneric{name, type},
                    )
                } else {
                    globals[name] = ParsedGlobal {
                        position,
                        GlobalTypeWithGenericRef{u32(len(global_types_with_generics))},
                    }
                    append_elem(
                        &global_types_with_generics,
                        GlobalTypeWithGeneric{name, generic, type},
                    )
                }
            case AssignToken:
                if generic.ident != "" {
                    diagnostic(
                        s.file,
                        s.last_token_pos,
                        "Cannot define global value with generic argument",
                    )
                    return ParserOutput{ok = false}
                }
                get_next_token(&s.tokenizer, false)
                value := parse_value(s)
                if !value.ok {
                    return ParserOutput{ok = false}
                }
                globals[name] = ParsedGlobal{position, value.value^}
                other_possible_tokens = value.descriptions_of_other_possible_tokens
            }
        }
    }
}

