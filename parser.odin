#+feature dynamic-literals
package main

import "core:fmt"
import "core:strconv"

ParserState :: struct {
    function_defs:   [dynamic]FunctionDefinition,
    using tokenizer: TokenizerState,
}

// Does not include the `{`
parse_struct :: proc(s: ^ParserState) -> (Struct, bool) {
    fields_map := make(map[string]uint)
    fields := make([dynamic]Type)
    for {
        field_name := ""
        get_next_token(s, true)
        #partial switch token in s.last_token {
        case:
            wrong_token_err(s, []string{"an identifier", "`}`"}, "While parsing struct type")
        case CloseBraceToken:
            return Struct{fields_map, fields[:]}, true
        case IdentToken:
            field_name = string(token)
        }
        if field_name in fields_map {
            err_ok(
                s.file,
                s.last_token_pos,
                "There is already a field called `%s` in this struct",
                field_name,
            )
            return Struct{}, false
        }

        get_next_token(s, false)
        #partial switch token in s.last_token {
        case:
            wrong_token_err(
                s,
                []string{fmt.aprintf("`:` to specify the type of the `%s` field", field_name)},
            )
        case ColonToken:
        }

        get_next_token(s, true)
        field_type, other_possible_tokens, ok := parse_type(s)
        if !ok {
            return Struct{}, false
        }

        fields_map[field_name] = len(fields)
        append_elem(&fields, field_type)

        #partial switch _ in s.last_token {
        case:
            wrong_token_err(
                s,
                join(other_possible_tokens, "`,` to add a new field to the struct", "`}`"),
            )
        case CommaToken:
        case CloseBraceToken:
            return Struct{fields_map, fields[:]}, true
        }
    }
}

parse_type :: proc(
    state: ^ParserState,
    descriptions_of_other_possible_tokens: ..string,
) -> (
    Type,
    []string,
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
                "`dynamic` for a dynamic type",
            ),
        )
        return Type{}, nil, false

    case DynamicToken:
        get_next_token(state, false)
        type, other_possible_tokens, ok := parse_type(state)
        if !ok {
            return Type{}, nil, false
        }
        return Type{type_pos, DynamicType(new_clone(type))}, other_possible_tokens, true

    case OpenBraceToken:
        t, ok := parse_struct(state)
        if !ok {
            return Type{}, nil, false
        }
        get_next_token(state, true)
        return Type{type_pos, t}, nil, true

    case OpenAngleBracketToken:
        variants_map := make(map[string]uint)
        variants := make([dynamic]Struct)
        loop: for {
            get_next_token(state, true)
            #partial switch token2 in state.last_token {
            case:
                wrong_token_err(state, []string{"an identifier", "`>`"})
                return Type{}, nil, false
            case CloseAngleBracketToken:
                break loop
            case IdentToken:
                variant_name := string(token2)
                if variant_name in variants_map {
                    err_ok(
                        state.file,
                        state.last_token_pos,
                        "There is already a variant called `%s` in this sum type",
                        variant_name,
                    )
                    return Type{}, nil, false
                }
                variant_payload := Struct{}
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
                variants_map[variant_name] = len(variants)
                append_elem(&variants, variant_payload)
                #partial switch _ in state.last_token {
                case:
                    expected := [dynamic]string{"`,`", "`>`"}
                    if !has_payload {
                        append_elem(
                            &expected,
                            fmt.aprintf("`{` to add a payload to the `%s` variant", variant_name),
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
        return Type{type_pos, SumType{variants_map, variants[:]}}, nil, true

    case OpenSquareBracketToken:
        get_next_token(state, false)
        length: uint = 0
        #partial switch token2 in state.last_token {
        case CloseSquareBracketToken:
        case DigitsToken:
            ok: bool
            length, ok = strconv.parse_uint(string(token2))
            if !ok {
                err_ok(state.file, state.last_token_pos, "Failed to parse uint")
                return Type{}, nil, false
            }
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
        segments, other_possible_tokens, ok := parse_segmented_identifier(state)
        return Type{type_pos, TypeVariable(segments)}, other_possible_tokens[:], true
    }
}

// Does not handle trailing commas correctly
parse_value_list :: proc(s: ^ParserState) -> ([]Value, []string, bool) {
    out := [dynamic]Value{}
    for {
        get_next_token(&s.tokenizer, true)
        v := parse_value(s, "`)`")
        if !v.ok {
            return nil, nil, false
        }
        append_elem(&out, v.value^)

        #partial switch token in s.last_token {
        case CommaToken:
            continue
        case:
            return out[:], v.descriptions_of_other_possible_tokens, true
        }
    }
}

// Does not include the `(`
parse_function_args :: proc(s: ^ParserState) -> ([]Value, bool) {
    args := [dynamic]Value{}
    for {
        get_next_token(&s.tokenizer, true)
        other_possible_tokens: []string
        #partial switch token in s.last_token {
        case CloseBracketToken:
            return args[:], true
        case:
            v := parse_value(s, "`)`")
            other_possible_tokens = v.descriptions_of_other_possible_tokens
            if !v.ok {
                return nil, false
            }
            append_elem(&args, v.value^)
        }

        #partial switch token in s.last_token {
        case:
            wrong_token_err(&s.tokenizer, join(other_possible_tokens, "`)`", "`,`"))
            return nil, false
        case CommaToken:
            continue
        case CloseBracketToken:
            return args[:], true
        }
    }
}

// Does not include the `{`
parse_type_args :: proc(s: ^ParserState) -> ([]Value, bool) {
    args := [dynamic]Value{}
    for {
        get_next_token(&s.tokenizer, true)
        other_possible_tokens: []string
        #partial switch token in s.last_token {
        case CloseBraceToken:
            return args[:], true
        case:
            v := parse_value(s, "`}`")
            other_possible_tokens = v.descriptions_of_other_possible_tokens
            if !v.ok {
                return nil, false
            }
            append_elem(&args, v.value^)
        }

        #partial switch token in s.last_token {
        case:
            wrong_token_err(
                &s.tokenizer,
                join(other_possible_tokens, "`}`", "`,`"),
                "While parsing type args",
            )
            return nil, false
        case CommaToken:
            continue
        case CloseBraceToken:
            return args[:], true
        }
    }
}

ParsedValue :: struct {
    ok:                                    bool,
    value:                                 ^Value,
    descriptions_of_other_possible_tokens: []string,
}

// Parses identifiers with `.` to separate them
// The `[]string` returned is an array of descriptions of other possible tokens
parse_segmented_identifier :: proc(
    s: ^ParserState,
    descriptions_of_other_possible_tokens: ..string,
) -> (
    []string,
    [dynamic]string,
    bool,
) {
    components := make([dynamic]string)
    expected := join(descriptions_of_other_possible_tokens, "`.`", "an identifier")
    #partial switch token in s.last_token {
    case:
        wrong_token_err(s, expected)
        return nil, nil, false
    case SymbolsToken:
        if token != "." {
            wrong_token_err(s, expected)
            return nil, nil, false
        }
        append_elem(&components, "")
    case IdentToken:
        append_elem(&components, string(token))
        get_next_token(s, true)
    }
    for {
        symbols, is_symbols := s.last_token.(SymbolsToken)
        if !is_symbols || symbols != "." {
            others := make([dynamic]string, 1)
            others[0] = "`.`"
            return components[:], others, true
        }
        get_next_token(s, true)
        #partial switch token in s.last_token {
        case IdentToken:
            append_elem(&components, string(token))
        case:
            wrong_token_err(s, []string{"An identifier"})
            return nil, nil, false
        }
        get_next_token(s, true)
    }
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
        idents, other_possible_tokens, ok := parse_segmented_identifier(
            s,
            ..join(
                descriptions_of_other_possible_tokens,
                "`true`",
                "`false`",
                "`|` to create a lambda function value",
                "`(` to create a value in brackets",
                "`[` to create an array literal",
                "a digits token",
                "a string literal",
                "a character literal",
            ),
        )
        if !ok {
            return nil, nil, false
        }
        _, is_assign := s.last_token.(AssignToken)
        if !is_assign {
            append_elem(&other_possible_tokens, "`=`")
            return VariableReference(idents), other_possible_tokens, true
        }
        get_next_token(s, false)
        _, is_open_brace := s.last_token.(OpenBraceToken)
        if !is_open_brace {
            wrong_token_err(s, []string{"`{`"})
            return nil, nil, false
        }
        args: []Value
        args, ok = parse_type_args(s)
        if !ok {
            return nil, nil, false
        }
        value = TypeInitialisation{TypeVariable(idents), args}
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
            wrong_token_err(&s.tokenizer, join(val.descriptions_of_other_possible_tokens, "`)`"))
            return nil, nil, false
        }
        value = ValueInBrackets(val.value)
    case OpenSquareBracketToken:
        type, other_possible_tokens, ok := parse_type(s)
        if !ok {
            return nil, nil, false
        }
        _, is_assign := s.last_token.(AssignToken)
        if !is_assign {
            wrong_token_err(s, join(other_possible_tokens, "`=`"))
            return nil, nil, false
        }
        get_next_token(s, false)
        _, is_open := s.last_token.(OpenBraceToken)
        if !is_open {
            wrong_token_err(s, join(other_possible_tokens, "`{`"))
            return nil, nil, false
        }
        args: []Value
        args, ok = parse_type_args(s)
        if !ok {
            return nil, nil, false
        }
        value = TypeInitialisation{type.type, args}
    case DigitsToken:
        value = Number(token)
    case StringToken:
        value = String(token)
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
        // TODO: Parse field access with `.`
        case:
            append_elems(
                &other_possible_tokens,
                "`(` to call a function", // TODO: add name of function
                "`[` to access a specific index in an array", // TODO: add name of array
            )
            break loop
        case OpenBracketToken:
            args, ok := parse_function_args(s)
            if !ok {
                return ParsedValue{ok = false}
            }
            value = new_clone(Value{value_pos, FunctionCall{value, args}})
            other_possible_tokens = nil
            get_next_token(&s.tokenizer, true)
        case OpenSquareBracketToken:
            index_pos := s.last_token_pos
            get_next_token(&s.tokenizer, false)
            array_index := parse_value(s)
            if !array_index.ok {
                return ParsedValue{ok = false}
            }
            #partial switch token2 in s.last_token {
            case:
                wrong_token_err(
                    &s.tokenizer,
                    join(array_index.descriptions_of_other_possible_tokens, "`]`", "`:`"),
                )
                return ParsedValue{ok = false}
            case CloseSquareBracketToken:
                value = new_clone(
                    Value {
                        value_pos,
                        ArrayAccess{value, index_pos, SingleElemAccess(array_index.value)},
                    },
                )
                other_possible_tokens = nil
                get_next_token(&s.tokenizer, true)
            case ColonToken:
                get_next_token(&s.tokenizer, false)
                array_index2 := parse_value(s)
                if !array_index2.ok {
                    return ParsedValue{ok = false}
                }
                _, is_close_square_bracket := s.last_token.(CloseSquareBracketToken)
                if !is_close_square_bracket {
                    wrong_token_err(
                        &s.tokenizer,
                        join(array_index2.descriptions_of_other_possible_tokens, "`]`"),
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
                other_possible_tokens = nil
                get_next_token(&s.tokenizer, true)
            }
        }
    }

    // Parse possible arithmetic
    append_elems(
        &other_possible_tokens,
        "a value joiner (`and`, `or`, `==`, `!=`, `>`, `>=`, `<`, `<=`, `*`, `/`, `+`, `-`, `%`)",
    )
    value_type: ValueJoinMethod
    #partial switch token in s.last_token {
    case:
        return ParsedValue{true, value, other_possible_tokens[:]}
    case AndToken:
        value_type = .BooleanAnd
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
            return ParsedValue{true, value, other_possible_tokens[:]}
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
parse_iterator :: proc(s: ^ParserState) -> (Iterator, []string) {
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
        return value1.value^, join(value1.descriptions_of_other_possible_tokens, "`..=`", "`..<`")
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
    return NumericIterator {
        value1.value^,
        value2.value^,
        nil,
        type,
    }, join(value2.descriptions_of_other_possible_tokens, "`step`")
}

// Does not include the `for`
parse_for_loop :: proc(s: ^ParserState) -> (ForInLoop, bool) {
    variables: [3]IdentAndPos
    variable_index := 0
    variables_loop: for {
        get_next_token(&s.tokenizer, false)
        ident, is_ident := s.last_token.(IdentToken)
        if !is_ident {
            wrong_token_err(s, []string{"the name of the variable in a for loop"})
            return ForInLoop{}, false
        }
        variables[variable_index] = IdentAndPos{string(ident), s.last_token_pos}
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
                err_ok(
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
        wrong_token_err(s, join(other_possible_tokens, "`{` to start the body of the for loop"))
        return ForInLoop{}, false
    }

    block, ok := parse_block(s)
    if !ok {
        return ForInLoop{}, false
    }

    return ForInLoop{variables, iter, block}, true
}

// Does not include the `if`
parse_if :: proc(s: ^ParserState) -> (^IfElseStatement, []string, bool) {
    if_pos := s.last_token_pos
    get_next_token(&s.tokenizer, true)
    condition := parse_value(s)
    if !condition.ok {
        return nil, nil, false
    }
    #partial switch _ in s.last_token {
    case OpenBraceToken:
    case:
        wrong_token_err(
            &s.tokenizer,
            join(
                condition.descriptions_of_other_possible_tokens,
                "`{` to start the body of the if statement",
            ),
        )
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
                []string{},
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
        array := make([]string, 1)
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
    []string,
    bool,
) {
    ident, is_ident := s.last_token.(IdentToken)
    if !is_ident {
        wrong_token_err(s, []string{"an identifier"})
        return VariableDest{}, nil, false
    }
    ident_pos := s.last_token_pos
    get_next_token(s, false)
    _, is_open_square_brace := s.last_token.(OpenSquareBracketToken)
    if !is_open_square_brace {
        others := make([]string, 1)
        others[0] = "`[`"
        return VariableDest{IdentAndPos{string(ident), s.last_token_pos}, variable_dest_type, nil},
            others,
            true
    }
    get_next_token(s, true)
    value := parse_value(s)
    if !value.ok {
        return VariableDest{}, nil, false
    }
    _, is_close_square_brace := s.last_token.(CloseSquareBracketToken)
    if !is_close_square_brace {
        wrong_token_err(s, join(value.descriptions_of_other_possible_tokens, "`]`"))
        return VariableDest{}, nil, false
    }
    get_next_token(s, true)
    return VariableDest{IdentAndPos{string(ident), ident_pos}, variable_dest_type, value.value},
        nil,
        true
}


// The `[]string` returned is an array of other possible tokens
parse_managed_variable :: proc(
    s: ^ParserState,
    descriptions_of_other_possible_tokens: ..string,
) -> (
    VariableDest,
    []string,
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
    other_possible_tokens := []string{}
    for {
        pos := s.last_token_pos
        #partial switch_stmt: switch token in s.last_token {
        case:
            var, other_possible_tokens, ok := parse_managed_variable(
                s,
                // TODO: I would like to remove this mingling of expected tokens as it makes the error messages less clear
                ..join(
                    other_possible_tokens,
                    "`do` to create a do while loop",
                    "`while` to create a while loop",
                    "`if`",
                    "`for`",
                    "`return`",
                    "`yield`",
                    "`}`",
                ),
            )
            if !ok {
                return nil, false
            }
            stmt: VariableManagement
            stmt, other_possible_tokens, ok = parse_variable_management_after_first_var(
                s,
                var,
                ..other_possible_tokens,
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
            append_elem(&out, Statement{pos, DoWhileLoop{condition.value^, body}})
        case WhileToken:
            get_next_token(s, false)
            condition := parse_value(s)
            if !condition.ok {
                return nil, false
            }
            _, is_open_brace := s.last_token.(OpenBraceToken)
            if !is_open_brace {
                wrong_token_err(s, join(condition.descriptions_of_other_possible_tokens, "`{`"))
                return nil, false
            }
            body, ok := parse_block(s)
            if !ok {
                return nil, false
            }
            other_possible_tokens = nil
            get_next_token(s, true)
            append_elem(&out, Statement{pos, WhileLoop{condition.value^, body}})
        case IdentToken:
            // TODO: Handle parsing something like `array[index] = value`
            get_next_token(&s.tokenizer, false)
            #partial switch _ in s.last_token {
            case:
                expected := []string {
                    fmt.aprintf("`(` to call a function called `%s`", string(token)),
                    "`,`",
                    "`=`",
                }
                wrong_token_err(s, expected)
            case OpenBracketToken:
                args, ok := parse_function_args(s)
                if !ok {
                    return nil, false
                }
                get_next_token(&s.tokenizer, true)
                variable := make(VariableReference, 1)
                variable[0] = string(token)
                append_elem(
                    &out,
                    Statement{pos, FunctionCall{new_clone(Value{pos, variable}), args}},
                )
                break switch_stmt
            case CommaToken:
                get_next_token(s, true)
            case AssignToken:
            }
            stmt: VariableManagement
            ok: bool
            stmt, other_possible_tokens, ok = parse_variable_management_after_first_var(
                s,
                VariableDest{IdentAndPos{string(token), s.last_token_pos}, .Constant, nil},
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
            wrong_token_err(
                s,
                join(other_possible_tokens, "A newline or `;` to separate statements"),
            )
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
    []string,
    bool,
) {
    variables := [dynamic]VariableDest{first_var}
    type: MutationType
    other_possible_tokens: []string
    loop: for {
        #partial switch token in s.last_token {
        case:
            wrong_token_err(
                s,
                join(other_possible_tokens, "`=`", "`,`", "`+=`", "`-=`", "`*=`", "`/=`"),
            )
            return VariableManagement{}, nil, false
        case SymbolsToken:
            switch token {
            case "+=":
                type = .Increment
                break loop
            case "-=":
                type = .Decrement
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
    get_next_token(s, false)
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
    Value,
    Type,
}

// The boolean returned is whether the function passed successfully
parse_function_def :: proc(s: ^ParserState) -> (FunctionDefinition, bool) {
    args := [dynamic]FunctionArg{}
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
            #partial switch token3 in s.last_token {
            case:
                wrong_token_err(s, expected)
                return FunctionDefinition{}, false
            case IdentToken:
                arg.name = IdentAndPos{string(token3), s.last_token_pos}
            }
        case IdentToken:
            arg.name = IdentAndPos{string(token), s.last_token_pos}
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
        other_possible_tokens: []string
        arg.value_type, other_possible_tokens, ok = parse_type(s)
        if !ok {
            return FunctionDefinition{}, false
        }
        append_elem(&args, arg)

        #partial switch token in s.last_token {
        case:
            wrong_token_err(s, join(other_possible_tokens, "`,`", "`|`"))
            return FunctionDefinition{}, false
        case CommaToken:
            continue
        case BarToken:
            break loop
        }
    }

    get_next_token(&s.tokenizer, true)
    outputs := []FunctionOutput{}
    open_brace :: "`{` to start the body of the function"
    #partial switch _ in s.last_token {
    case:
        wrong_token_err(&s.tokenizer, []string{"`->`", open_brace})
        return FunctionDefinition{}, false
    case ArrowToken:
        get_next_token(s, true)
        other_possible_tokens: []string
        #partial switch _ in s.last_token {
        case:
            outputs = make([]FunctionOutput, 1)
            symbols, is_symbols_token := s.last_token.(SymbolsToken)
            ok := true
            if is_symbols_token && symbols == "+" {
                outputs[0].output_type = .AllocatedOntoStack
                get_next_token(s, false)
                outputs[0].value_type, other_possible_tokens, ok = parse_type(s, "`(`")
            } else {
                outputs[0].value_type, other_possible_tokens, ok = parse_type(
                    s,
                    "`(`",
                    "`+` to specify that this output is allocated onto the PCS",
                )
            }
            if !ok {
                return FunctionDefinition{}, false
            }
        case OpenBracketToken:
            // parse_name_and_type_list(state, .TypeRequired, "`)`")
            err_ok(
                s.file,
                s.last_token_pos,
                "TODO: Implement parsing functions with multiple return values",
            )
            return FunctionDefinition{}, false
        }
        #partial switch _ in s.last_token {
        case OpenBraceToken:
        case:
            wrong_token_err(s, join(other_possible_tokens, open_brace))
            return FunctionDefinition{}, false
        }
    case OpenBraceToken:
    }

    block, ok := parse_block(s)
    if !ok {
        return FunctionDefinition{}, false
    }
    return FunctionDefinition{args[:], outputs, block}, true
}

ParsedGlobal :: struct {
    pos:   uint,
    value: union {
        Value,
        uint, // an index into the global types
    },
}

parse :: proc(s: ^ParserState) -> ([]Import, map[string]ParsedGlobal, []TypeValue, bool) {
    imports := [dynamic]Import{}
    globals := make(map[string]ParsedGlobal)
    global_types := make([dynamic]TypeValue)
    get_next_token(&s.tokenizer, true)
    other_possible_tokens := []string{}
    loop: for {
        #partial switch token in s.last_token {
        case:
            wrong_token_err(
                &s.tokenizer,
                join(
                    other_possible_tokens,
                    "a newline",
                    "a comment",
                    "an identifier to define a global",
                ),
            )
            return nil, nil, nil, false
        case EndOfFileToken:
            return imports[:], globals, global_types[:], true
        case ImportToken:
            err_ok(s.file, s.last_token_pos, "TODO: Implement import token parsing")
            return nil, nil, nil, false
        case IdentToken:
            position := s.last_token_pos
            name := string(token)
            if name in globals {
                line, column := get_location(s.code, globals[name].pos)
                err_ok(
                    s.file,
                    position,
                    "The global `%s` is already declared at line %d and column %d",
                    name,
                    line,
                    column,
                )
                return nil, nil, nil, false
            }
            get_next_token(&s.tokenizer, false)
            #partial switch _ in s.last_token {
            case:
                wrong_token_err(
                    &s.tokenizer,
                    []string{"`=` to define a global value", "`:` to define a global type"},
                )
                return nil, nil, nil, false
            case ColonToken:
                get_next_token(&s.tokenizer, false)
                type: Type
                ok: bool
                type, other_possible_tokens, ok = parse_type(s)
                if !ok {
                    return nil, nil, nil, false
                }
                globals[name] = ParsedGlobal{position, uint(len(global_types))}
                append_elem(&global_types, type.type)
            case AssignToken:
                get_next_token(&s.tokenizer, false)
                value := parse_value(s)
                if !value.ok {
                    return nil, nil, nil, false
                }
                globals[name] = ParsedGlobal{position, value.value^}
                other_possible_tokens = value.descriptions_of_other_possible_tokens
            }
        }
    }
}

