#+feature dynamic-literals
package main

import "core:fmt"
import "core:os"
import "core:path/filepath"
import "core:strings"

/*
FileRef :: struct {
    index: uint, // An index into `ParsedProject.files`
}
*/
FileRef :: ^CompilerFile
get_next_token :: proc(
    s: ^ParserState,
    skip_newlines_and_comments_and_semicolons: bool,
    loc := #caller_location,
) {
    tokenizer_get_next_token(
        &s.tokenizer_state,
        s.file_ref^,
        skip_newlines_and_comments_and_semicolons,
        loc,
    )
}

// The index of the first unparsed file is always `ParserState.file_ref.index + 1`
ParserState :: struct {
    // Updated every time the parser starts parsing a different file
    file_ref:                       FileRef,
    using tokenizer_state:          TokenizerState,

    // Grow as the project is parsed
    using r:                        DiagnosticReporter,
    files_map:                      map[string]FileRef,
    parsed_files:                   [dynamic]map[string]ParsedGlobal,
    global_values_without_generics: [dynamic]GlobalValueWithoutGeneric,
    global_values_with_generics:    [dynamic]GlobalValueWithGeneric,
    function_defs:                  [dynamic]FunctionDefinition,
}

// Does not include the `{`
parse_struct :: proc(s: ^ParserState) -> (Struct(Unit, struct {}), bool) {
    fields_map := make(map[string]uint)
    fields := make(#soa[dynamic]StructField(Unit))
    for {
        field: IdentAndPos = ---
        get_next_token(s, true)
        wrong_token :: proc(s: ^ParserState) -> (Struct(Unit, struct {}), bool) {
            wrong_token_err(
                s,
                []string{"an identifier with one segment", "`}`"},
                "While parsing struct type",
            )
            return Struct(Unit, struct {}){}, false
        }
        #partial switch token in s.last_token {
        case CloseBraceToken:
            return Struct(Unit, struct {}){struct{}{}, fields_map, fields[:]}, true
        case IdentToken:
            if len(token) != 1 {
                return wrong_token(s)
            }
            field = IdentAndPos{token[0].ident, Pos{token[0].index, s.file_ref}}
        case:
            return wrong_token(s)
        }
        if field.ident in fields_map {
            diagnostic(
                &s.r,
                field.pos,
                "There is already a field called `%s` defined in this struct at %v",
                field.ident,
                fields[fields_map[field.ident]].name.pos,
            )
            return Struct(Unit, struct {}){}, false
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
        parsed := parse_unit(s)
        if !parsed.ok {
            return Struct(Unit, struct {}){}, false
        }

        fields_map[field.ident] = len(fields)
        append(&fields, StructField(Unit){field, parsed.unit})

        #partial switch _ in s.last_token {
        case:
            append_elems(
                &parsed.descriptions_of_other_possible_tokens,
                "`,` to add a new field to the struct",
                "`}`",
            )
            wrong_token_err(s, parsed.descriptions_of_other_possible_tokens[:])
            return Struct(Unit, struct {}){}, false
        case CommaToken:
        case CloseBraceToken:
            return Struct(Unit, struct {}){struct{}{}, fields_map, fields[:]}, true
        }
    }
}

parse_initial_unit :: proc(
    s: ^ParserState,
    descriptions_of_other_possible_tokens: []string,
) -> (
    Unit,
    [dynamic]string,
    bool,
) {
    out := Unit {
        pos = Pos{s.last_token_pos, s.file_ref},
    }
    e :: proc(
        s: ^ParserState,
        descriptions_of_other_possible_tokens: []string,
    ) -> (
        Unit,
        [dynamic]string,
        bool,
    ) {
        wrong_token_err(
            s,
            join(
                descriptions_of_other_possible_tokens,
                "`true`",
                "`false`",
                "`|` to create a lambda function value",
                "`(` to create a tuple of values or types",
                "a digits token",
                "a string literal",
                "a character literal",
                "a marker token (# followed by one or more alphanumerics)",
                "a name",
                "`<` to create a sum type",
                "`[` to create an array type",
                "`{` to create a struct type",
                // "`dynamic` for a dynamic type",
            ),
            "While passing either a value or a type",
        )
        return Unit{}, nil, false
    }
    #partial switch token in s.last_token {
    case:
        return e(s, descriptions_of_other_possible_tokens)

    case ImportToken:
        get_next_token(s, false)
        path, is_string_literal := s.last_token.(StringToken)
        if !is_string_literal {
            wrong_token_err(s, []string{"A string literal"})
            return Unit{}, nil, false
        }
        joined, join_err := filepath.join(
            []string{s.file_ref.dir_path, string(path)},
            context.allocator,
        )
        if join_err != nil {
            diagnostic(&s.r, unknown_pos, "Failed to join filepath: %v", join_err)
            return Unit{}, nil, false
        }
        if file_ref, exists := s.files_map[joined]; exists {
            out.value = Import{file_ref}
        } else {
            data, data_err := os.read_entire_file(joined, context.allocator)
            if data_err != nil {
                diagnostic(
                    &s.r,
                    Pos{s.last_token_pos, s.file_ref},
                    "Failed to read `%s`: %#v",
                    joined,
                    data_err,
                )
                return Unit{}, nil, false
            }
            ref := &s.files[len(s.parsed_files)]
            out.value = Import{ref}
            append2(
                &s.parsed_files,
                &s.files,
                nil,
                CompilerFile{string(data), joined, filepath.dir(joined)},
            )
            s.files_map[joined] = ref
        }

    case OpenBracketToken:
        elements, ok := parse_units_until(s, is_close_bracket, "`)` to end the tuple")
        if !ok {
            return Unit{}, nil, false
        }
        out.value = Tuple{elements}

    // case DynamicToken:
    //     get_next_token(state, false)
    //     type, other_possible_tokens, ok := parse_type(state)
    //     if !ok {
    //         return Unit{}, nil, false
    //     }
    //     return Unit{type_pos, DynamicUnit(new_clone(type))}, other_possible_tokens, true

    case OpenBraceToken:
        ok: bool = ---
        out.value, ok = parse_struct(s)
        if !ok {
            return Unit{}, nil, false
        }

    case OpenAngleBracketToken:
        variants_map := make(map[string]uint)
        variants := make(#soa[dynamic]SumTypeVariant(Struct(Unit, struct {})))
        loop: for {
            get_next_token(s, true)
            expected :: []string{"an identifier with one segment", "`>`"}
            #partial switch token2 in s.last_token {
            case:
                wrong_token_err(s, expected)
                return Unit{}, nil, false
            case CloseAngleBracketToken:
                break loop
            case IdentToken:
                if len(token2) != 1 {
                    wrong_token_err(s, expected)
                    return Unit{}, nil, false
                }
                variant_name := token2[0]
                if variant_name.ident in variants_map {
                    diagnostic(
                        &s.r,
                        Pos{variant_name.index, s.file_ref},
                        "There is already a variant called `%s` in this sum type",
                        variant_name.ident,
                    )
                    return Unit{}, nil, false
                }
                variant_payload := Struct(Unit, struct {}){}
                get_next_token(s, true)
                _, has_payload := s.last_token.(OpenBraceToken)
                if has_payload {
                    variant_payload, has_payload = parse_struct(s)
                    if !has_payload {
                        return Unit{}, nil, false
                    }
                    get_next_token(s, false)
                }
                variants_map[variant_name.ident] = len(&variants)
                append(
                    &variants,
                    SumTypeVariant(Struct(Unit, struct {})) {
                        IdentAndPos{variant_name.ident, Pos{variant_name.index, s.file_ref}},
                        variant_payload,
                    },
                )
                #partial switch _ in s.last_token {
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
                    wrong_token_err(s, expected[:])
                    return Unit{}, nil, false
                case CommaToken:
                case CloseAngleBracketToken:
                    break loop
                }
            }
        }
        out.value = SumType(Struct(Unit, struct {})){variants_map, variants[:]}

    case OpenSquareBracketToken:
        args, args_ok := parse_units_until(s, is_close_square_bracket, "`]`")
        if !args_ok {
            return Unit{}, nil, false
        }
        get_next_token(s, false)
        unit, other_possible_tokens, ok2 := parse_initial_unit(s, nil)
        if !ok2 {
            return Unit{}, nil, false
        }
        // TODO: Update the syntax so that this exception to the parsed order of operations is not necersarry
        if _, is_open_square_bracket := s.last_token.(OpenSquareBracketToken);
           is_open_square_bracket {
            args2, args2_ok := parse_units_until(s, is_close_square_bracket, "`]`")
            if !args2_ok {
                return Unit{}, nil, false
            }
            unit.value = CallWithSquareBrackets{new_clone(unit), args2}
            clear(&other_possible_tokens)
            get_next_token(s, true)
        }
        out.value = CallWithFrontedSquareBrackets{new_clone(unit), args}
        return out, other_possible_tokens, true

    case IdentToken:
        out.value = make_ident(token, s.file_ref)

    case MarkerToken:
        markers := [dynamic]IdentAndPos{{string(token), Pos{s.last_token_pos, s.file_ref}}}
        for {
            get_next_token(s, false)
            marker, is_marker := s.last_token.(MarkerToken)
            if !is_marker {
                break
            }
            append_elem(&markers, IdentAndPos{string(marker), Pos{s.last_token_pos, s.file_ref}})
        }
        val, descriptions_of_other_possible_tokens, ok := parse_initial_unit(s, nil)
        if !ok {
            return Unit{}, nil, false
        }
        out.value = MarkedUnit{new_clone(val), markers[:]}
        return out, descriptions_of_other_possible_tokens, true

    case TrueToken:
        out.value = Bool(true)

    case FalseToken:
        out.value = Bool(false)

    case DigitsToken:
        out.value = Number{false, string(token)}

    case SymbolsToken:
        if token != "-" {
            return e(s, descriptions_of_other_possible_tokens)
        }
        get_next_token(s, true)
        digits, is_digits := s.last_token.(DigitsToken)
        if !is_digits {
            wrong_token_err(s, []string{"A digits token"})
            return Unit{}, nil, false
        }
        out.value = Number{true, string(digits)}

    case StringToken:
        strings := [dynamic]string{string(token)}
        for {
            get_next_token(s, true)
            #partial switch token2 in s.last_token {
            case:
                out.value = String(strings[:])
                return out, [dynamic]string{"a string token"}, true
            case StringToken:
                append_elem(&strings, string(token2))
            }
        }

    case CharToken:
        out.value = Char(token)

    case BarToken:
        func, ok := parse_function_def(s)
        if !ok {
            return Unit{}, nil, false
        }
        out.value = FuncDefinitionRef{uint(len(s.function_defs))}
        append_elem(&s.function_defs, func)

    }

    get_next_token(s, true)
    return out, nil, true
}

parse_units_until :: proc(
    s: ^ParserState,
    is_end: proc(t: TokenContents) -> bool,
    end_description: string,
) -> (
    []Unit,
    bool,
) {
    units := [dynamic]Unit{}
    for {
        get_next_token(s, true)
        if is_end(s.last_token) {
            return units[:], true
        }
        v := parse_unit(s, end_description)
        if !v.ok {
            return nil, false
        }
        append_elem(&units, v.unit)

        if is_end(s.last_token) {
            return units[:], true
        }
        #partial switch token in s.last_token {
        case:
            append_elems(&v.descriptions_of_other_possible_tokens, end_description, "`,`")
            wrong_token_err(s, v.descriptions_of_other_possible_tokens[:])
            return nil, false
        case CommaToken:
            continue
        }
    }
}

ParsedUnit :: struct {
    ok:                                    bool,
    unit:                                  Unit,
    descriptions_of_other_possible_tokens: [dynamic]string,
}

create_joined_unit :: proc(
    join_method: UnitJoinMethod,
    unit0: Unit,
    unit1: ^Unit,
) -> UnitWithoutPos {
    joined_values, is_joined_values := unit1.value.(JoinedUnits)
    if is_joined_values && get_prioraty(joined_values.join_method) <= get_prioraty(join_method) {
        val0 := create_joined_unit(join_method, unit0, joined_values.unit0)
        return JoinedUnits {
            joined_values.join_method,
            new_clone(Unit{unit0.pos, val0}),
            joined_values.unit1,
        }
    }
    return JoinedUnits{join_method, new_clone(unit0), unit1}
}

parse_unit :: proc(
    s: ^ParserState,
    descriptions_of_other_possible_tokens: ..string,
) -> ParsedUnit {
    value_pos := Pos{s.last_token_pos, s.file_ref}
    val, other_possible_tokens, ok := parse_initial_unit(s, descriptions_of_other_possible_tokens)
    if !ok {
        return ParsedUnit{ok = false}
    }

    // Parse possible calls
    loop: for {
        #partial switch token in s.last_token {
        case:
            append_elems(
                &other_possible_tokens,
                // TODO: pretty print the unit being called
                "`(` to create a bracket call",
                "`[` to create a square bracket call",
            )
            break loop
        case OpenBracketToken:
            args, args_ok := parse_units_until(s, is_close_bracket, "`)`")
            if !args_ok {
                return ParsedUnit{ok = false}
            }
            val = Unit{value_pos, CallWithBrackets{new_clone(val), args}}
            clear(&other_possible_tokens)
            get_next_token(s, true)
        case OpenSquareBracketToken:
            args, args_ok := parse_units_until(s, is_close_square_bracket, "`]`")
            if !args_ok {
                return ParsedUnit{ok = false}
            }
            val = Unit{value_pos, CallWithSquareBrackets{new_clone(val), args}}
            clear(&other_possible_tokens)
            get_next_token(s, true)
        }
    }

    // Parse possible arithmetic
    append_elems(
        &other_possible_tokens,
        "a value joiner (`and`, `or`, `==`, `!=`, `>`, `>=`, `<`, `<=`, `*`, `/`, `+`, `-`, `%`, `::`, `:`, `->`, `in`)",
    )
    value_type: UnitJoinMethod
    #partial switch token in s.last_token {
    case:
        return ParsedUnit{true, val, other_possible_tokens}
    case InToken:
        value_type = .In
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
    case ColonToken:
        value_type = .Colon
    case ArrowToken:
        value_type = .Arrow
    case SymbolsToken:
        switch token {
        case:
            return ParsedUnit{true, val, other_possible_tokens}
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
        case "++":
            value_type = .Concat
        case "&":
            value_type = .StringConcat
        case "-":
            value_type = .Subtraction
        case "%":
            value_type = .Modulo
        }
    }
    get_next_token(s, true)
    next_value := parse_unit(s)
    if !next_value.ok {
        return ParsedUnit{ok = false}
    }
    return ParsedUnit {
        true,
        Unit{value_pos, create_joined_unit(value_type, val, new_clone(next_value.unit))},
        next_value.descriptions_of_other_possible_tokens,
    }
}

// Returns `nil, nil` if there was an error
parse_iterator :: proc(s: ^ParserState) -> (Iterator, [dynamic]string) {
    get_next_token(s, false)
    value1 := parse_unit(s)
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
        return value1.unit, value1.descriptions_of_other_possible_tokens
    }

    get_next_token(s, false)
    value2 := parse_unit(s)
    if !value2.ok {
        return nil, nil
    }

    _, is_step_token := s.last_token.(StepToken)
    if is_step_token {
        get_next_token(s, false)
        step := parse_unit(s)
        if !step.ok {
            return nil, nil
        }
        return NumericIterator{value1.unit, value2.unit, new_clone(step.unit), type},
            step.descriptions_of_other_possible_tokens
    }
    append_elem(&value2.descriptions_of_other_possible_tokens, "`step`")
    return NumericIterator{value1.unit, value2.unit, nil, type},
        value2.descriptions_of_other_possible_tokens
}

at_description := "`@` to set the label of the loop"
parse_possible_loop_label :: proc(s: ^ParserState) -> (IdentAndPos, bool) {
    get_next_token(s, false)
    if _, is_at_token := s.last_token.(AtToken); is_at_token {
        get_next_token(s, false)
        ident, is_ident := s.last_token.(IdentToken)
        if !is_ident || len(ident) != 1 {
            wrong_token_err(
                s,
                []string{"An identifier with one segment for the label of the loop"},
            )
            return IdentAndPos{}, false
        }
        get_next_token(s, false)
        return IdentAndPos{ident[0].ident, Pos{ident[0].index, s.file_ref}}, true
    }
    return IdentAndPos{}, true
}

// Does not include the `for`
parse_for_loop :: proc(s: ^ParserState) -> (ForInLoop, bool) {
    label, ok := parse_possible_loop_label(s)
    if !ok {
        return ForInLoop{}, false
    }
    variables: [3]IdentAndPos
    variable_index := 0
    variables_loop: for {
        ident, is_ident := s.last_token.(IdentToken)
        if !is_ident || len(ident) != 1 {
            can_be_at := label.ident == ""
            possible := make([]string, can_be_at ? 2 : 1)
            defer delete(possible)
            possible[0] = "the name of the variable in a for loop (an identifier with one segment)"
            if can_be_at {
                possible[1] = at_description
            }
            wrong_token_err(s, possible)
            return ForInLoop{}, false
        }
        variables[variable_index] = IdentAndPos{ident[0].ident, Pos{ident[0].index, s.file_ref}}
        variable_index += 1

        get_next_token(s, false)
        #partial switch token in s.last_token {
        case:
            wrong_token_err(s, []string{"`,`", "`in`"})
            return ForInLoop{}, false
        case InToken:
            break variables_loop
        case CommaToken:
            if variable_index >= 3 {
                diagnostic(
                    &s.r,
                    Pos{s.last_token_pos, s.file_ref},
                    "There cannot be more than 3 variables in a for loop head (the iteration the for loop is on, the key of the thing being iterated over, and the value of the thing being iterated over)",
                )
                return ForInLoop{}, false
            }
            get_next_token(s, false)
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

    block, ok2 := parse_block(s)
    if !ok2 {
        return ForInLoop{}, false
    }

    return ForInLoop{label, variables, iter, block}, true
}

// Does not include the `if`
parse_if :: proc(s: ^ParserState) -> (^IfElseStatement, [dynamic]string, bool) {
    get_next_token(s, true)
    condition := parse_unit(s)
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
        wrong_token_err(s, condition.descriptions_of_other_possible_tokens[:])
        return nil, nil, false
    }

    block, block_ok := parse_block(s)
    if !block_ok {
        return nil, nil, false
    }

    get_next_token(s, true)
    #partial switch _ in s.last_token {
    case ElseToken:
        else_pos := Pos{s.last_token_pos, s.file_ref}
        get_next_token(s, true)
        #partial switch _ in s.last_token {
        case:
            wrong_token_err(s, []string{"`{`", "`if`"})
            return nil, nil, false
        case OpenBraceToken:
            else_block, ok := parse_block(s)
            if !ok {
                return nil, nil, false
            }
            get_next_token(s, true)
            return new_clone(IfElseStatement{condition.unit, block, else_block}),
                [dynamic]string{},
                true

        case IfToken:
            else_block := make([]Statement, 1)
            else_statement, other_possible_tokens, ok := parse_if(s)
            if !ok {
                return nil, nil, false
            }
            else_block[0] = Statement{else_pos, else_statement^}
            return new_clone(IfElseStatement{condition.unit, block, else_block}),
                other_possible_tokens,
                true
        }
    case:
        array := make([dynamic]string, 1)
        array[0] = "`else`"
        return new_clone(IfElseStatement{condition.unit, block, []Statement{}}), array, true
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
        return VariableDest {
                IdentAndPos{ident.ident, Pos{ident.index, s.file_ref}},
                variable_dest_type,
                nil,
            },
            others,
            true
    }
    get_next_token(s, true)
    value := parse_unit(s)
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
    return VariableDest {
            IdentAndPos{ident.ident, Pos{ident.index, s.file_ref}},
            variable_dest_type,
            new_clone(value.unit),
        },
        nil,
        true
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
        pos := Pos{s.last_token_pos, s.file_ref}
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
                "`continue`",
                "`unreachable`",
                "`}`",
            )
            ok: bool = ---
            var: VariableDest = ---
            var, other_possible_tokens, ok = parse_managed_variable(s, ..other_possible_tokens[:])
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
            // TODO: Support specifying label with @
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
            condition := parse_unit(s)
            if !condition.ok {
                return nil, false
            }
            other_possible_tokens = condition.descriptions_of_other_possible_tokens
            append_elem(
                &out,
                Statement{pos, ConditionControlledLoop{.DoWhileLoop, condition.unit, body}},
            )
        case WhileToken:
            // TODO: Support specifying label with @
            get_next_token(s, false)
            condition := parse_unit(s)
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
                Statement{pos, ConditionControlledLoop{.WhileLoop, condition.unit, body}},
            )
        case IdentToken:
            get_next_token(s, true)
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
                args, ok := parse_units_until(s, is_close_bracket, "`)`")
                if !ok {
                    return nil, false
                }
                get_next_token(s, true)
                variable := make_ident(token, s.file_ref)
                append_elem(
                    &out,
                    Statement{pos, CallWithBrackets{new_clone(Unit{pos, variable}), args}},
                )
                break switch_stmt
            case CommaToken:
                get_next_token(s, true)
            case AssignToken:
            }
            if len(token) != 1 {
                diagnostic(
                    &s.r,
                    Pos{s.last_token_pos, s.file_ref},
                    "TODO: Support assigns where the destination has more than one segment",
                )
                return nil, false
            }
            stmt: VariableManagement = ---
            ok: bool = ---
            stmt, other_possible_tokens, ok = parse_variable_management_after_first_var(
                s,
                VariableDest {
                    IdentAndPos{token[0].ident, Pos{s.last_token_pos, s.file_ref}},
                    .Constant,
                    nil,
                },
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
        case ContinueToken:
            get_next_token(s, true)
            label := IdentAndPos{}
            _, is_at := s.last_token.(AtToken)
            if is_at {
                get_next_token(s, true)
                ident, is_ident := s.last_token.(IdentToken)
                if !is_ident || len(ident) != 1 {
                    wrong_token_err(s, []string{"An identifier with one segment"})
                    return nil, false
                }
                label = IdentAndPos{ident[0].ident, Pos{ident[0].index, s.file_ref}}
                get_next_token(s, true)
            }
            clear_dynamic_array(&other_possible_tokens)
            append_elem(&out, Statement{pos, ContinueStatement{label}})
        case UnreachableToken:
            get_next_token(s, true)
            clear_dynamic_array(&other_possible_tokens)
            append_elem(&out, Statement{pos, UnreachableStatement{}})
        case MatchToken:
            get_next_token(s, true)
            value := parse_unit(s)
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
                _, is_close_brace := s.last_token.(CloseBraceToken)
                if is_close_brace {
                    break match_loop
                }

                branch_label := parse_unit(s, "`}` to finish the match statement")
                if !branch_label.ok {
                    return nil, false
                }

                if _, is_open_brace := s.last_token.(OpenBraceToken); !is_open_brace {
                    append_elem(&branch_label.descriptions_of_other_possible_tokens, "`{`")
                    wrong_token_err(s, branch_label.descriptions_of_other_possible_tokens[:])
                    return nil, false
                }

                body, body_ok := parse_block(s)
                if !body_ok {
                    return nil, false
                }

                append_elem(&branches, MatchBranch{branch_label.unit, body})
            }
            append_elem(&out, Statement{pos, MatchStatement{value.unit, branches[:]}})
            clear(&other_possible_tokens)
            get_next_token(s, true)
        case ForToken:
            loop, ok := parse_for_loop(s)
            if !ok {
                return nil, false
            }
            append_elem(&out, Statement{pos, loop})
            clear_dynamic_array(&other_possible_tokens)
            get_next_token(s, true)
        case ReturnToken:
            values, ok := parse_units_until(s, is_close_brace, "`}`")
            if !ok {
                return nil, false
            }
            append_elem(&out, Statement{pos, ReturnStatement(values)})
            clear_dynamic_array(&other_possible_tokens)
            return out[:], true
        case YieldToken:
            values, ok := parse_units_until(s, is_close_brace, "`}`")
            if !ok {
                return nil, false
            }
            append_elem(&out, Statement{pos, YieldStatement(values)})
            clear_dynamic_array(&other_possible_tokens)
            return out[:], true
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
    value := parse_unit(s)
    if !value.ok {
        return VariableManagement{}, nil, false
    }
    return VariableManagement{value.unit, variables[:], type},
        value.descriptions_of_other_possible_tokens,
        true
}

// Does not include the `(`
//parse_name_and_type_list :: proc(
//    state: ^TokenizerState,
//    type_required: bool,
//    descriptions_of_possible_end_token: ..string,
//) -> []NameAndUnit {
//    out := [dynamic]NameAndUnit{}
//    for {
//        arg: NameAndUnit
//        switch type, token := get_next_token(state, true, []string{"`)`", "a name"}); type {
//        case: return state.last_error
//        case close_bracket_token: return out[:]
//        case ident_token: arg.name = token.str
//        }
//
//        switch result in try_parse_type(
//            state,
//            ..(type_necesisity == .UnitRequired ? []string{} : join([]string{","}, ..descriptions_of_possible_end_token)),
//        ) {
//        case Failed: return state.last_error
//        case WrongFirstTokenUnit:
//        case Unit: arg.type = result
//        }
//        append_elem(&out, arg)
//        #partial switch token in get_next_token(
//            state,
//            true,
//            type_necesisity == .UnitRequired ? []string{"`,`", "a type"} : []string{"`,`", "`)`"},
//        ) {
//        case: return state.last_error
//        case UnitlessToken(Comma): continue
//        case UnitlessToken(CloseBracket): return out[:]
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
                arg.name = IdentAndPos{token2[0].ident, Pos{token2[0].index, s.file_ref}}
            }
        case IdentToken:
            if len(token) != 1 {
                wrong_token_err(s, expected)
                return FunctionDefinition{}, false
            }
            arg.name = IdentAndPos{token[0].ident, Pos{token[0].index, s.file_ref}}
        }

        get_next_token(s, true)
        #partial switch _ in s.last_token {
        case ColonToken:
        case:
            wrong_token_err(s, []string{"`:`"})
            return FunctionDefinition{}, false
        }

        get_next_token(s, true)
        arg_value_type := parse_unit(s)
        if !arg_value_type.ok {
            return FunctionDefinition{}, false
        }
        arg.value_type = arg_value_type.unit
        append_soa_elem(&args, arg)

        #partial switch token in s.last_token {
        case:
            append_elems(&arg_value_type.descriptions_of_other_possible_tokens, "`,`", "`|`")
            wrong_token_err(s, arg_value_type.descriptions_of_other_possible_tokens[:])
            return FunctionDefinition{}, false
        case CommaToken:
            continue
        case BarToken:
            break loop
        }
    }

    get_next_token(s, true)
    return_type: ^Unit = nil
    open_brace :: "`{` to start the body of the function"
    #partial switch _ in s.last_token {
    case:
        wrong_token_err(s, []string{"`->`", open_brace})
        return FunctionDefinition{}, false
    case ArrowToken:
        get_next_token(s, true)
        parsed_return_type := parse_unit(s)
        if !parsed_return_type.ok {
            return FunctionDefinition{}, false
        }
        _, is_open_brace := s.last_token.(OpenBraceToken)
        if !is_open_brace {
            append_elem(&parsed_return_type.descriptions_of_other_possible_tokens, open_brace)
            wrong_token_err(s, parsed_return_type.descriptions_of_other_possible_tokens[:])
            return FunctionDefinition{}, false
        }
        return_type = new_clone(parsed_return_type.unit)
    case OpenBraceToken:
    }

    block, ok := parse_block(s)
    if !ok {
        return FunctionDefinition{}, false
    }
    return FunctionDefinition{args[:], return_type, block}, true
}

GlobalValueWithGeneric :: struct {
    name:     string,
    generics: []IdentAndPos, // The parser checks that the name of each generic argument is unique
    value:    Unit,
    file:     FileRef,
}

GlobalValueWithoutGeneric :: struct {
    name: string,
    unit: Unit,
    file: FileRef,
}

GlobalValueWithGenericRef :: struct {
    index: u32, // An index into `CheckerState.global_values_with_generic`
}

GlobalValueWithoutGenericRef :: struct {
    index: uint, // An index into `CheckerState.global_values_without_generics`
}

Import :: struct {
    file: FileRef,
}

ParsedGlobal :: struct {
    pos:          uint,
    index:        u32,
    has_generics: bool,
}

parse_file :: proc(s: ^ParserState) -> bool {
    get_next_token(s, true)
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
            wrong_token_err(s, other_possible_tokens[:])
            return false
        case EndOfFileToken:
            return true
        case IdentToken:
            position := Pos{s.last_token_pos, s.file_ref}
            if len(token) != 1 {
                wrong_token_err(s, other_possible_tokens[:])
                return false
            }
            name := token[0].ident
            if def, exists := s.parsed_files[s.file_ref.index][name]; exists {
                d := diagnostic(&s.r, position)
                fmt.sbprintf(&d.b, "The global `%s` is already declared at ", name)
                write_location(&d.b, Pos{def.pos, s.file_ref})
                write(d)
                return false
            }
            get_next_token(s, false)
            generic_map := make(map[string]Pos) // The key is the position of the generic arg
            generic := make([dynamic]IdentAndPos)
            _, is_open_square_bracket := s.last_token.(OpenSquareBracketToken)
            if is_open_square_bracket {
                for {
                    clear(&other_possible_tokens)

                    get_next_token(s, false)
                    segments, is_ident := s.last_token.(IdentToken)
                    if !is_ident || len(segments) != 1 {
                        append_elem(&other_possible_tokens, "An identifier with one segment")
                        break
                    }

                    if segments[0].ident in generic_map {
                        pos := generic_map[segments[0].ident]
                        loc := get_location(s.files, pos)
                        diagnostic(
                            &s.r,
                            Pos{s.last_token_pos, s.file_ref},
                            "There is already a generic argument called `%s` defined on %s in this global type",
                            segments[0].ident,
                            loc,
                        )
                        return false
                    }
                    pos := Pos{segments[0].index, s.file_ref}
                    append_elem(&generic, IdentAndPos{segments[0].ident, pos})
                    generic_map[segments[0].ident] = pos

                    get_next_token(s, false)
                    _, is_comma := s.last_token.(CommaToken)
                    if !is_comma {
                        append_elem(&other_possible_tokens, "A comma")
                        break
                    }
                }

                _, is_close_square_bracket := s.last_token.(CloseSquareBracketToken)
                if !is_close_square_bracket {
                    append_elem(&other_possible_tokens, "`]`")
                    wrong_token_err(s, other_possible_tokens[:])
                    return false
                }

                get_next_token(s, false)

                if len(generic) == 0 {
                    diagnostic(
                        &s.r,
                        position,
                        "The parser is interpreting this as a non-generic value\nThe empty `[]` can be omitted",
                        type = .Warning,
                    )
                }

                clear(&other_possible_tokens)
            } else {
                clear(&other_possible_tokens)
                append_elem(
                    &other_possible_tokens,
                    "`[` to define the name of a generic argument to the value",
                )
            }
            #partial switch _ in s.last_token {
            case:
                append_elem(&other_possible_tokens, "`=` to define a global value")
                wrong_token_err(s, other_possible_tokens[:])
                return false
            case AssignToken:
                get_next_token(s, false)
                type := parse_unit(s)
                if !type.ok {
                    return false
                }
                if len(generic) == 0 {
                    s.parsed_files[s.file_ref.index][name] = ParsedGlobal {
                        position.index,
                        u32(len(s.global_values_without_generics)),
                        false,
                    }
                    append_elem(
                        &s.global_values_without_generics,
                        GlobalValueWithoutGeneric{name, type.unit, s.file_ref},
                    )
                } else {
                    s.parsed_files[s.file_ref.index][name] = ParsedGlobal {
                        position.index,
                        u32(len(s.global_values_with_generics)),
                        true,
                    }
                    append_elem(
                        &s.global_values_with_generics,
                        GlobalValueWithGeneric{name, generic[:], type.unit, s.file_ref},
                    )
                }
                other_possible_tokens = type.descriptions_of_other_possible_tokens
            }
        }
    }
}

ParsedProject :: struct {
    files_map:                     map[string]FileRef,
    parsed_files:                  []map[string]ParsedGlobal,
    files:                         [^]CompilerFile,
    global_values_without_generic: []GlobalValueWithoutGeneric,
    global_values_with_generics:   []GlobalValueWithGeneric,
    function_defs:                 []FunctionDefinition,
}

parse_project :: proc(
    first_file_relative_path: string,
    io: Pipe(^os.File),
    exit_early: EarlyExitInfo,
) -> (
    ParsedProject,
    bool,
) {
    // TODO: There are some return paths where `exit_early` is not updated and
    // therefore the `-watch` flag does not auto reload
    first_file_absolute_path, err := filepath.abs(first_file_relative_path, context.allocator)
    if err != nil {
        fmt.fprintfln(
            io.stderr,
            "Failed to make filepath `%s` absolute: %v",
            first_file_relative_path,
            err,
        )
        return ParsedProject{}, false
    }

    fmt.fprintfln(io.stdout, "Reading `%s`...", first_file_absolute_path)
    data, data_err := os.read_entire_file(first_file_absolute_path, context.allocator)
    if data_err != nil {
        fmt.fprintfln(io.stderr, "Failed to read `%s`: %#v", first_file_absolute_path, data_err)
        return ParsedProject{}, false
    }

    state := ParserState {
        r = DiagnosticReporter{io = io},
    }
    append2(
        &state.parsed_files,
        &state.files,
        nil,
        CompilerFile {
            string(data),
            first_file_absolute_path,
            filepath.dir(first_file_absolute_path),
        },
    )
    state.files_map[first_file_absolute_path] = FileRef{0}

    ok := true
    for state.file_ref.index < len(state.parsed_files) {
        file_path := state.files[state.file_ref.index].file_path
        fmt.printfln("Parsing `%s`...", file_path)
        state.tokenizer_state = TokenizerState{}
        file_ok := parse_file(&state)
        if !file_ok {
            ok = false
        }
        state.file_ref.index += 1
    }
    if exit_early_info, exiting_early := exit_early.(^ExitEarly); exiting_early {
        #partial switch &exit_early_info_value in exit_early_info {
        case ExitEarlyAwaitingSourceCodeChange:
            exit_early_info_value.files = state.files[:len(state.parsed_files)]
        case:
            panic("Unreachable")
        }
    }
    if !ok {
        return ParsedProject{}, false
    }
    return ParsedProject {
            state.files_map,
            state.parsed_files[:],
            state.files,
            state.global_values_without_generics[:],
            state.global_values_with_generics[:],
            state.function_defs[:],
        },
        true
}

