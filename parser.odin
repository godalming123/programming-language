#+feature dynamic-literals
package main

import "core:fmt"
import "core:mem"
import "core:os"
import "core:path/filepath"
import "core:strings"

FileRef :: ^CompilerFile

get_file_index :: proc(files: Multi(CompilerFile), ref: FileRef, loc := #caller_location) -> int {
    return mem.ptr_sub(ref, &files.d[0])
}

// The index of the first unparsed file is always `ParserState.file_ref.index + 1`
ParserState :: struct {
    a:                              ^Arena,
    // Updated every time the parser starts parsing a different file
    using tokenizer_state:          TokenizerState,

    // Grow as the project is parsed
    using r:                        DiagnosticReporter,
    files_map:                      map[string]FileRef,
    parsed_files:                   []map[string]ParsedGlobal,
    global_values_without_generics: [dynamic]GlobalValueWithoutGeneric,
    global_values_with_generics:    [dynamic]GlobalValueWithGeneric,
    function_defs:                  [dynamic]FunctionDefinition,
}

// Does not include the `{`
parse_struct :: proc(s: ^ParserState) -> (StructUnit, bool) {
    out := StructUnit {
        make_key_to_index(s.a, KeyToIndex(string)),
        arena_make_multi(s.a, Multi(Pos), 0, resizable = true),
        arena_make_multi(s.a, Multi(Unit), 0, resizable = true),
    }
    defer {
        fix_key_to_index(out.m)
        fix_resizable_multi(out.types)
        fix_resizable_multi(out.positions)
    }
    for {
        field: IdentAndPos = ---
        get_next_token(s, true)
        wrong_token :: proc(s: ^ParserState) -> (StructUnit, bool) {
            clear_dynamic(&s.last_token_descriptions_of_other_possible_tokens)
            append_dynamic_elems(
                &s.last_token_descriptions_of_other_possible_tokens,
                "an identifier with one segment",
                "`}`",
            )
            wrong_token_err(s, "While parsing struct type")
            return StructUnit{}, false
        }
        #partial switch token in s.last_token {
        case CloseBraceToken:
            return out, true
        case IdentToken:
            if len(token) != 1 {
                return wrong_token(s)
            }
            field = IdentAndPos{token[0].ident, token[0].pos}
        case:
            return wrong_token(s)
        }

        get_next_token(s, false)
        #partial switch token in s.last_token {
        case:
            clear_dynamic(&s.last_token_descriptions_of_other_possible_tokens)
            append_dynamic(
                &s.last_token_descriptions_of_other_possible_tokens,
                fmt.aprintf("`:` to specify the type of the `%s` field", field.ident),
            )
            wrong_token_err(s)
            return StructUnit{}, false
        case ColonToken:
        }

        get_next_token(s, true)
        parsed := parse_unit(s)
        if !parsed.ok {
            return StructUnit{}, false
        }
        i, result := lookup_or_insert(&out.m, field.ident, string_to_index_procs)
        if result == .LookedUp {
            diagnostic(
                &s.r,
                field.pos,
                "There is already a field called `%s` defined in this struct at %v",
                field.ident,
                out.positions.d[i.index],
            )
            return StructUnit{}, false
        }
        resize_multi(&out.positions, len(out.m.keys))
        resize_multi(&out.types, len(out.m.keys))
        out.positions.d[i.index] = field.pos
        out.types.d[i.index] = parsed.unit

        #partial switch _ in s.last_token {
        case:
            append_dynamic_elems(
                &s.last_token_descriptions_of_other_possible_tokens,
                "`,` to add a new field to the struct",
                "`}`",
            )
            wrong_token_err(s)
            return StructUnit{}, false
        case CommaToken:
        case CloseBraceToken:
            return out, true
        }
    }
}

parse_initial_unit :: proc(s: ^ParserState) -> (Unit, bool) {
    out := Unit {
        pos = Pos{s.last_token_pos, s.file_ref},
    }
    e :: proc(s: ^ParserState) -> (Unit, bool) {
        append_dynamic_elems(
            &s.last_token_descriptions_of_other_possible_tokens,
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
        )
        wrong_token_err(s, "While passing either a value or a type")
        return Unit{}, false
    }
    #partial switch token in s.last_token {
    case:
        return e(s)

    case ImportToken:
        get_next_token(s, false)
        path, is_string_literal := s.last_token.(StringToken)
        if !is_string_literal {
            clear_dynamic(&s.last_token_descriptions_of_other_possible_tokens)
            append_dynamic(&s.last_token_descriptions_of_other_possible_tokens, "A string literal")
            wrong_token_err(s)
            return Unit{}, false
        }
        joined, join_err := filepath.join(
            []string{s.file_ref.dir_path, string(path)},
            context.allocator,
        )
        if join_err != nil {
            diagnostic(&s.r, unknown_pos, "Failed to join filepath: %v", join_err)
            return Unit{}, false
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
                return Unit{}, false
            }
            append_multi_dynamic(
                &s.files,
                len(s.parsed_files),
                CompilerFile{string(data), joined, filepath.dir(joined)},
            )
            ref := &s.files.d[len(s.parsed_files)]
            append_dynamic(&s.parsed_files, nil)
            out.value = Import{ref}
            s.files_map[joined] = ref
        }

    case OpenBracketToken:
        elements, ok := parse_units_until(s, is_close_bracket, "`)` to end the tuple")
        if !ok {
            return Unit{}, false
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
            return Unit{}, false
        }

    case OpenAngleBracketToken:
        sum_type := SumUnit {
            make_key_to_index(s.a, KeyToIndex(string)),
            arena_make_multi(s.a, Multi(Pos), 0, resizable = true),
            arena_make_multi(s.a, Multi(StructUnit), 0, resizable = true),
        }
        defer {
            fix_key_to_index(sum_type.m)
            fix_resizable_multi(sum_type.payloads)
            fix_resizable_multi(sum_type.positions)
        }
        loop: for {
            get_next_token(s, true)
            clear_dynamic(&s.last_token_descriptions_of_other_possible_tokens)
            append_dynamic_elems(
                &s.last_token_descriptions_of_other_possible_tokens,
                "an identifier with one segment",
                "`>`",
            )
            #partial switch token2 in s.last_token {
            case:
                wrong_token_err(s)
                return Unit{}, false
            case CloseAngleBracketToken:
                break loop
            case IdentToken:
                if len(token2) != 1 {
                    wrong_token_err(s)
                    return Unit{}, false
                }
                variant_name := token2[0]
                variant_payload := StructUnit{}
                get_next_token(s, true)
                _, has_payload := s.last_token.(OpenBraceToken)
                if has_payload {
                    variant_payload, has_payload = parse_struct(s)
                    if !has_payload {
                        return Unit{}, false
                    }
                    get_next_token(s, false)
                }
                i, result := lookup_or_insert(
                    &sum_type.m,
                    variant_name.ident,
                    string_to_index_procs,
                )
                if result == .LookedUp {
                    diagnostic(
                        &s.r,
                        variant_name.pos,
                        "There is already a variant called `%s` in this sum type at %v",
                        variant_name.ident,
                        sum_type.positions.d[i.index],
                    )
                    return Unit{}, false
                }
                resize_multi(&sum_type.positions, len(sum_type.m.keys))
                resize_multi(&sum_type.payloads, len(sum_type.m.keys))
                sum_type.positions.d[i.index] = variant_name.pos
                sum_type.payloads.d[i.index] = variant_payload
                #partial switch _ in s.last_token {
                case:
                    clear_dynamic(&s.last_token_descriptions_of_other_possible_tokens)
                    append_dynamic_elems(
                        &s.last_token_descriptions_of_other_possible_tokens,
                        "`,`",
                        "`>`",
                    )
                    if !has_payload {
                        append_dynamic(
                            &s.last_token_descriptions_of_other_possible_tokens,
                            fmt.aprintf(
                                "`{` to add a payload to the `%s` variant",
                                variant_name.ident,
                            ),
                        )
                    }
                    wrong_token_err(s)
                    return Unit{}, false
                case CommaToken:
                case CloseAngleBracketToken:
                    break loop
                }
            }
        }
        out.value = sum_type

    case OpenSquareBracketToken:
        args, args_ok := parse_units_until(s, is_close_square_bracket, "`]`")
        if !args_ok {
            return Unit{}, false
        }
        get_next_token(s, false)
        unit, ok2 := parse_initial_unit(s)
        if !ok2 {
            return Unit{}, false
        }
        // TODO: Update the syntax so that this exception to the parsed order of operations is not necersarry
        if _, is_open_square_bracket := s.last_token.(OpenSquareBracketToken);
           is_open_square_bracket {
            args2, args2_ok := parse_units_until(s, is_close_square_bracket, "`]`")
            if !args2_ok {
                return Unit{}, false
            }
            unit.value = CallWithSquareBrackets{new_clone(unit), args2}
            get_next_token(s, true)
        }
        out.value = CallWithFrontedSquareBrackets{new_clone(unit), args}
        return out, true

    case IdentToken:
        out.value = Ident{token}

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
        val, ok := parse_initial_unit(s)
        if !ok {
            return Unit{}, false
        }
        out.value = MarkedUnit{new_clone(val), markers[:]}
        return out, true

    case TrueToken:
        out.value = Bool(true)

    case FalseToken:
        out.value = Bool(false)

    case DigitsToken:
        out.value = Number{false, string(token)}

    case SymbolsToken:
        if token != "-" {
            return e(s)
        }
        get_next_token(s, true)
        digits, is_digits := s.last_token.(DigitsToken)
        if !is_digits {
            append_dynamic(&s.last_token_descriptions_of_other_possible_tokens, "A digits token")
            wrong_token_err(s)
            return Unit{}, false
        }
        out.value = Number{true, string(digits)}

    case StringToken:
        strings := [dynamic]string{string(token)}
        for {
            get_next_token(s, true)
            #partial switch token2 in s.last_token {
            case:
                out.value = String(strings[:])
                append_dynamic(
                    &s.last_token_descriptions_of_other_possible_tokens,
                    "a string token",
                )
                return out, true
            case StringToken:
                append_elem(&strings, string(token2))
            }
        }

    case CharToken:
        out.value = Char(token)

    case BarToken:
        func, ok := parse_function_def(s)
        if !ok {
            return Unit{}, false
        }
        out.value = FuncDefinitionRef{uint(len(s.function_defs))}
        append_elem(&s.function_defs, func)

    }

    get_next_token(s, true)
    return out, true
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
        append_dynamic(&s.last_token_descriptions_of_other_possible_tokens, end_description)
        v := parse_unit(s)
        if !v.ok {
            return nil, false
        }
        append_elem(&units, v.unit)

        if is_end(s.last_token) {
            return units[:], true
        }
        #partial switch token in s.last_token {
        case:
            append_dynamic_elems(
                &s.last_token_descriptions_of_other_possible_tokens,
                end_description,
                "`,`",
            )
            wrong_token_err(s)
            return nil, false
        case CommaToken:
            continue
        }
    }
}

ParsedUnit :: struct {
    ok:   bool,
    unit: Unit,
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

parse_unit :: proc(s: ^ParserState) -> ParsedUnit {
    value_pos := Pos{s.last_token_pos, s.file_ref}
    val, ok := parse_initial_unit(s)
    if !ok {
        return ParsedUnit{ok = false}
    }

    // Parse possible calls
    loop: for {
        #partial switch token in s.last_token {
        case:
            append_dynamic_elems(
                &s.last_token_descriptions_of_other_possible_tokens,
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
            get_next_token(s, true)
        case OpenSquareBracketToken:
            args, args_ok := parse_units_until(s, is_close_square_bracket, "`]`")
            if !args_ok {
                return ParsedUnit{ok = false}
            }
            val = Unit{value_pos, CallWithSquareBrackets{new_clone(val), args}}
            get_next_token(s, true)
        }
    }

    // Parse possible arithmetic
    append_dynamic(
        &s.last_token_descriptions_of_other_possible_tokens,
        "a value joiner (`and`, `or`, `==`, `!=`, `>`, `>=`, `<`, `<=`, `*`, `/`, `+`, `-`, `%`, `::`, `:`, `->`, `in`)",
    )
    value_type: UnitJoinMethod
    #partial switch token in s.last_token {
    case:
        return ParsedUnit{true, val}
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
            return ParsedUnit{true, val}
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
    }
}

// Returns `nil` if there was an error
parse_iterator :: proc(s: ^ParserState) -> Iterator {
    get_next_token(s, false)
    value1 := parse_unit(s)
    if !value1.ok {
        return nil
    }

    symbols, is_symbols_token := s.last_token.(SymbolsToken)
    type: NumericIteratorType
    if is_symbols_token && symbols == "..=" {
        type = .IncludeEndValue
    } else if is_symbols_token && symbols == "..<" {
        type = .ExcludeEndValue
    } else {
        append_dynamic_elems(&s.last_token_descriptions_of_other_possible_tokens, "`..=`", "`..<`")
        return value1.unit
    }

    get_next_token(s, false)
    value2 := parse_unit(s)
    if !value2.ok {
        return nil
    }

    _, is_step_token := s.last_token.(StepToken)
    if is_step_token {
        get_next_token(s, false)
        step := parse_unit(s)
        if !step.ok {
            return nil
        }
        return NumericIterator{value1.unit, value2.unit, new_clone(step.unit), type}
    }
    append_dynamic(&s.last_token_descriptions_of_other_possible_tokens, "`step`")
    return NumericIterator{value1.unit, value2.unit, nil, type}
}

at_description := "`@` to set the label of the loop"
parse_possible_loop_label :: proc(s: ^ParserState) -> (IdentAndPos, bool) {
    get_next_token(s, false)
    if _, is_at_token := s.last_token.(AtToken); is_at_token {
        get_next_token(s, false)
        ident, is_ident := s.last_token.(IdentToken)
        if !is_ident || len(ident) != 1 {
            append_dynamic(
                &s.last_token_descriptions_of_other_possible_tokens,
                "An identifier with one segment for the label of the loop",
            )
            wrong_token_err(s)
            return IdentAndPos{}, false
        }
        get_next_token(s, false)
        return IdentAndPos{ident[0].ident, ident[0].pos}, true
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
            append_dynamic(
                &s.last_token_descriptions_of_other_possible_tokens,
                "the name of the variable in a for loop (an identifier with one segment)",
            )
            if can_be_at := label.ident == ""; can_be_at {
                append_dynamic(&s.last_token_descriptions_of_other_possible_tokens, at_description)
            }
            wrong_token_err(s)
            return ForInLoop{}, false
        }
        variables[variable_index] = IdentAndPos{ident[0].ident, ident[0].pos}
        variable_index += 1

        get_next_token(s, false)
        #partial switch token in s.last_token {
        case:
            append_dynamic_elems(
                &s.last_token_descriptions_of_other_possible_tokens,
                "`,`",
                "`in`",
            )
            wrong_token_err(s)
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

    iter := parse_iterator(s)
    if iter == nil {
        return ForInLoop{}, false
    }

    _, is_open_brace := s.last_token.(OpenBraceToken)
    if !is_open_brace {
        append_dynamic(
            &s.last_token_descriptions_of_other_possible_tokens,
            "`{` to start the body of the for loop",
        )
        wrong_token_err(s)
        return ForInLoop{}, false
    }

    block, ok2 := parse_block(s)
    if !ok2 {
        return ForInLoop{}, false
    }

    return ForInLoop{label, variables, iter, block}, true
}

// Does not include the `if`
parse_if :: proc(s: ^ParserState) -> (^IfElseStatement, bool) {
    get_next_token(s, true)
    condition := parse_unit(s)
    if !condition.ok {
        return nil, false
    }
    #partial switch _ in s.last_token {
    case OpenBraceToken:
    case:
        append_dynamic(
            &s.last_token_descriptions_of_other_possible_tokens,
            "`{` to start the body of the if statement",
        )
        wrong_token_err(s)
        return nil, false
    }

    block, block_ok := parse_block(s)
    if !block_ok {
        return nil, false
    }

    get_next_token(s, true)
    #partial switch _ in s.last_token {
    case ElseToken:
        else_pos := Pos{s.last_token_pos, s.file_ref}
        get_next_token(s, true)
        #partial switch _ in s.last_token {
        case:
            append_dynamic_elems(
                &s.last_token_descriptions_of_other_possible_tokens,
                "`{`",
                "`if`",
            )
            wrong_token_err(s)
            return nil, false
        case OpenBraceToken:
            else_block, ok := parse_block(s)
            if !ok {
                return nil, false
            }
            get_next_token(s, true)
            return new_clone(IfElseStatement{condition.unit, block, else_block}), true

        case IfToken:
            else_block := make([]Statement, 1)
            else_statement, ok := parse_if(s)
            if !ok {
                return nil, false
            }
            else_block[0] = Statement{else_pos, else_statement^}
            return new_clone(IfElseStatement{condition.unit, block, else_block}), true
        }
    case:
        append_dynamic(&s.last_token_descriptions_of_other_possible_tokens, "`else`")
        return new_clone(IfElseStatement{condition.unit, block, []Statement{}}), true
    }
}

get_identifier :: proc(
    s: ^ParserState,
    variable_dest_type: VariableDestType,
) -> (
    VariableDest,
    bool,
) {
    idents, is_ident := s.last_token.(IdentToken)
    if !is_ident || len(idents) != 1 {
        append_dynamic(
            &s.last_token_descriptions_of_other_possible_tokens,
            "an identifier with one segment",
        )
        wrong_token_err(s)
        return VariableDest{}, false
    }
    ident := idents[0]
    get_next_token(s, false)
    _, is_open_square_brace := s.last_token.(OpenSquareBracketToken)
    if !is_open_square_brace {
        append_dynamic(&s.last_token_descriptions_of_other_possible_tokens, "`[`")
        return VariableDest{IdentAndPos{ident.ident, ident.pos}, variable_dest_type, nil}, true
    }
    get_next_token(s, true)
    value := parse_unit(s)
    if !value.ok {
        return VariableDest{}, false
    }
    _, is_close_square_brace := s.last_token.(CloseSquareBracketToken)
    if !is_close_square_brace {
        append_dynamic(&s.last_token_descriptions_of_other_possible_tokens, "`]`")
        wrong_token_err(s)
        return VariableDest{}, false
    }
    get_next_token(s, true)
    return VariableDest {
            IdentAndPos{ident.ident, ident.pos},
            variable_dest_type,
            new_clone(value.unit),
        },
        true
}


parse_managed_variable :: proc(s: ^ParserState) -> (VariableDest, bool) {
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
        append_dynamic_elems(
            &s.last_token_descriptions_of_other_possible_tokens,
            "`+`",
            "an identifier",
        )
        wrong_token_err(s)
        return VariableDest{}, false
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
    append_dynamic_elems(
        &s.last_token_descriptions_of_other_possible_tokens,
        "`mut`",
        "`~`",
        "`+`",
        "an identifier",
    )
    wrong_token_err(s)
    return VariableDest{}, false
}

// Does not include the `{`
parse_block :: proc(s: ^ParserState) -> ([]Statement, bool) {
    out := [dynamic]Statement{}
    get_next_token(s, true)
    for {
        pos := Pos{s.last_token_pos, s.file_ref}
        #partial switch_stmt: switch token in s.last_token {
        case:
            // TODO: I would like to remove this mingling of expected tokens as it makes the error messages less clear
            append_dynamic_elems(
                &s.last_token_descriptions_of_other_possible_tokens,
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
            var, ok = parse_managed_variable(s)
            if !ok {
                return nil, false
            }
            stmt: VariableManagement
            stmt, ok = parse_variable_management_after_first_var(s, var)
            if !ok {
                return nil, false
            }
            append_elem(&out, Statement{pos, stmt})
        case DoToken:
            // TODO: Support specifying label with @
            get_next_token(s, false)
            _, is_open_brace := s.last_token.(OpenBraceToken)
            if !is_open_brace {
                append_dynamic(&s.last_token_descriptions_of_other_possible_tokens, "`{`")
                wrong_token_err(s)
                return nil, false
            }
            body, ok := parse_block(s)
            if !ok {
                return nil, false
            }
            get_next_token(s, false)
            _, is_while := s.last_token.(WhileToken)
            if !is_while {
                append_dynamic(&s.last_token_descriptions_of_other_possible_tokens, "`while`")
                wrong_token_err(s)
                return nil, false
            }
            get_next_token(s, false)
            condition := parse_unit(s)
            if !condition.ok {
                return nil, false
            }
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
                append_dynamic(&s.last_token_descriptions_of_other_possible_tokens, "`{`")
                wrong_token_err(s)
                return nil, false
            }
            body, ok := parse_block(s)
            if !ok {
                return nil, false
            }
            get_next_token(s, true)
            append_elem(
                &out,
                Statement{pos, ConditionControlledLoop{.WhileLoop, condition.unit, body}},
            )
        case IdentToken:
            get_next_token(s, true)
            #partial switch token2 in s.last_token {
            case:
                append_dynamic_elems(
                    &s.last_token_descriptions_of_other_possible_tokens,
                    fmt.aprintf(
                        "`(` to call a function called `%s`",
                        strings.join(token.ident[:len(token)], "."),
                    ),
                    "`,`",
                    "`=`",
                )
                wrong_token_err(s)
                return nil, false
            case OpenBracketToken:
                args, ok := parse_units_until(s, is_close_bracket, "`)`")
                if !ok {
                    return nil, false
                }
                get_next_token(s, true)
                append_elem(
                    &out,
                    Statement{pos, CallWithBrackets{new_clone(Unit{pos, Ident{token}}), args}},
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
            stmt, ok = parse_variable_management_after_first_var(
                s,
                VariableDest{token[0], .Constant, nil},
            )
            if !ok {
                return nil, false
            }
            append_elem(&out, Statement{pos, stmt})
        case IfToken:
            if_else: ^IfElseStatement
            ok: bool
            if_else, ok = parse_if(s)
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
                    append_dynamic(
                        &s.last_token_descriptions_of_other_possible_tokens,
                        "An identifier with one segment",
                    )
                    wrong_token_err(s)
                    return nil, false
                }
                label = IdentAndPos{ident[0].ident, ident[0].pos}
                get_next_token(s, true)
            }
            append_elem(&out, Statement{pos, ContinueStatement{label}})
        case UnreachableToken:
            get_next_token(s, true)
            append_elem(&out, Statement{pos, UnreachableStatement{}})
        case MatchToken:
            get_next_token(s, true)
            value := parse_unit(s)
            if !value.ok {
                return nil, false
            }

            if _, is_open_brace := s.last_token.(OpenBraceToken); !is_open_brace {
                append_dynamic(&s.last_token_descriptions_of_other_possible_tokens, "`{`")
                wrong_token_err(s)
                return nil, false
            }

            branches := make([dynamic]MatchBranch)
            match_loop: for {
                get_next_token(s, true)
                _, is_close_brace := s.last_token.(CloseBraceToken)
                if is_close_brace {
                    break match_loop
                }

                append_dynamic(
                    &s.last_token_descriptions_of_other_possible_tokens,
                    "`}` to finish the match statement",
                )
                branch_label := parse_unit(s)
                if !branch_label.ok {
                    return nil, false
                }

                if _, is_open_brace := s.last_token.(OpenBraceToken); !is_open_brace {
                    append_dynamic(&s.last_token_descriptions_of_other_possible_tokens, "`{`")
                    wrong_token_err(s)
                    return nil, false
                }

                body, body_ok := parse_block(s)
                if !body_ok {
                    return nil, false
                }

                append_elem(&branches, MatchBranch{branch_label.unit, body})
            }
            append_elem(&out, Statement{pos, MatchStatement{value.unit, branches[:]}})
            get_next_token(s, true)
        case ForToken:
            loop, ok := parse_for_loop(s)
            if !ok {
                return nil, false
            }
            append_elem(&out, Statement{pos, loop})
            get_next_token(s, true)
        case ReturnToken:
            values, ok := parse_units_until(s, is_close_brace, "`}`")
            if !ok {
                return nil, false
            }
            append_elem(&out, Statement{pos, ReturnStatement(values)})
            return out[:], true
        case YieldToken:
            values, ok := parse_units_until(s, is_close_brace, "`}`")
            if !ok {
                return nil, false
            }
            append_elem(&out, Statement{pos, YieldStatement(values)})
            return out[:], true
        case CloseBraceToken:
            return out[:], true
        }
        _, is_close_brace := s.last_token.(CloseBraceToken)
        if is_close_brace {
            return out[:], true
        } else if !s.last_token_skipped {
            append_dynamic(
                &s.last_token_descriptions_of_other_possible_tokens,
                "A newline or `;` to separate statements",
            )
            wrong_token_err(s)
            return nil, false
        }
    }
}

parse_variable_management_after_first_var :: proc(
    s: ^ParserState,
    first_var: VariableDest,
) -> (
    VariableManagement,
    bool,
) {
    variables := [dynamic]VariableDest{first_var}
    type: MutationType
    loop: for {
        #partial switch token in s.last_token {
        case:
            append_dynamic_elems(
                &s.last_token_descriptions_of_other_possible_tokens,
                "`=`",
                "`,`",
                "`+=`",
                "`-=`",
                "`*=`",
                "`/=`",
            )
            wrong_token_err(s)
            return VariableManagement{}, false
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
        var, ok = parse_managed_variable(s)
        if !ok {
            return VariableManagement{}, false
        }
        append_elem(&variables, var)
    }
    get_next_token(s, true)
    value := parse_unit(s)
    if !value.ok {
        return VariableManagement{}, false
    }
    return VariableManagement{value.unit, variables[:], type}, true
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

        append_dynamic_elems(
            &s.last_token_descriptions_of_other_possible_tokens,
            "an identifier for the name of a normal function argument",
            "`~` to add a mutable function argument",
            "`-` to add a function argument which is deallocated from the PCS during the execution of this function",
            "`|`",
        )
        #partial switch token in s.last_token {
        case:
            wrong_token_err(s)
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
                wrong_token_err(s)
                return FunctionDefinition{}, false
            }
            get_next_token(s, true)
            #partial switch token2 in s.last_token {
            case:
                wrong_token_err(s)
                return FunctionDefinition{}, false
            case IdentToken:
                if len(token2) != 1 {
                    wrong_token_err(s)
                    return FunctionDefinition{}, false
                }
                arg.name = IdentAndPos{token2[0].ident, token2[0].pos}
            }
        case IdentToken:
            if len(token) != 1 {
                wrong_token_err(s)
                return FunctionDefinition{}, false
            }
            arg.name = IdentAndPos{token[0].ident, token[0].pos}
        }

        get_next_token(s, true)
        #partial switch _ in s.last_token {
        case ColonToken:
        case:
            append_dynamic(&s.last_token_descriptions_of_other_possible_tokens, "`:`")
            wrong_token_err(s)
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
            append_dynamic_elems(&s.last_token_descriptions_of_other_possible_tokens, "`,`", "`|`")
            wrong_token_err(s)
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
        append_dynamic_elems(
            &s.last_token_descriptions_of_other_possible_tokens,
            "`->`",
            open_brace,
        )
        wrong_token_err(s)
        return FunctionDefinition{}, false
    case ArrowToken:
        get_next_token(s, true)
        parsed_return_type := parse_unit(s)
        if !parsed_return_type.ok {
            return FunctionDefinition{}, false
        }
        _, is_open_brace := s.last_token.(OpenBraceToken)
        if !is_open_brace {
            append_dynamic(&s.last_token_descriptions_of_other_possible_tokens, open_brace)
            wrong_token_err(s)
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
    loop: for {
        append_dynamic_elems(
            &s.last_token_descriptions_of_other_possible_tokens,
            "a newline",
            "a comment",
            "an identifier with one segment to define a global",
        )
        #partial switch token in s.last_token {
        case:
            wrong_token_err(s)
            return false
        case EndOfFileToken:
            return true
        case IdentToken:
            position := Pos{s.last_token_pos, s.file_ref}
            if len(token) != 1 {
                wrong_token_err(s)
                return false
            }
            name := token[0].ident
            if def, exists := s.parsed_files[get_file_index(s.files, s.file_ref)][name]; exists {
                diagnostic(
                    &s.r,
                    position,
                    "The global `%s` is already declared at %v",
                    name,
                    Pos{def.pos, s.file_ref},
                )
                return false
            }
            get_next_token(s, false)
            generic_map := make(map[string]Pos) // The key is the position of the generic arg
            generic := make([dynamic]IdentAndPos)
            _, is_open_square_bracket := s.last_token.(OpenSquareBracketToken)
            if is_open_square_bracket {
                for {
                    get_next_token(s, false)
                    segments, is_ident := s.last_token.(IdentToken)
                    if !is_ident || len(segments) != 1 {
                        append_dynamic(
                            &s.last_token_descriptions_of_other_possible_tokens,
                            "An identifier with one segment",
                        )
                        break
                    }

                    if segments[0].ident in generic_map {
                        pos := generic_map[segments[0].ident]
                        diagnostic(
                            &s.r,
                            Pos{s.last_token_pos, s.file_ref},
                            "There is already a generic argument called `%s` defined on %v in this global type",
                            segments[0].ident,
                            pos,
                        )
                        return false
                    }
                    pos := segments[0].pos
                    append_elem(&generic, IdentAndPos{segments[0].ident, pos})
                    generic_map[segments[0].ident] = pos

                    get_next_token(s, false)
                    _, is_comma := s.last_token.(CommaToken)
                    if !is_comma {
                        append_dynamic(
                            &s.last_token_descriptions_of_other_possible_tokens,
                            "A comma",
                        )
                        break
                    }
                }

                _, is_close_square_bracket := s.last_token.(CloseSquareBracketToken)
                if !is_close_square_bracket {
                    append_dynamic(&s.last_token_descriptions_of_other_possible_tokens, "`]`")
                    wrong_token_err(s)
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
            } else {
                append_dynamic(
                    &s.last_token_descriptions_of_other_possible_tokens,
                    "`[` to define the name of a generic argument to the value",
                )
            }
            #partial switch _ in s.last_token {
            case:
                append_dynamic(
                    &s.last_token_descriptions_of_other_possible_tokens,
                    "`=` to define a global value",
                )
                wrong_token_err(s)
                return false
            case AssignToken:
                get_next_token(s, false)
                type := parse_unit(s)
                if !type.ok {
                    return false
                }
                if len(generic) == 0 {
                    s.parsed_files[get_file_index(s.files, s.file_ref)][name] = ParsedGlobal {
                        position.index,
                        u32(len(s.global_values_without_generics)),
                        false,
                    }
                    append_elem(
                        &s.global_values_without_generics,
                        GlobalValueWithoutGeneric{name, type.unit, s.file_ref},
                    )
                } else {
                    s.parsed_files[get_file_index(s.files, s.file_ref)][name] = ParsedGlobal {
                        position.index,
                        u32(len(s.global_values_with_generics)),
                        true,
                    }
                    append_elem(
                        &s.global_values_with_generics,
                        GlobalValueWithGeneric{name, generic[:], type.unit, s.file_ref},
                    )
                }
            }
        }
    }
}

ParsedProject :: struct {
    files_map:                     map[string]FileRef,
    parsed_files:                  []map[string]ParsedGlobal,
    files:                         Multi(CompilerFile),
    global_values_without_generic: []GlobalValueWithoutGeneric,
    global_values_with_generics:   []GlobalValueWithGeneric,
    function_defs:                 []FunctionDefinition,
}

parse_project :: proc(
    a: ^Arena,
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
        r = DiagnosticReporter {
            io = io,
            files = arena_make_multi(a, Multi(CompilerFile), 1, resizable = true),
        },
        parsed_files = arena_make(a, []map[string]ParsedGlobal, 1, resizable = true),
        a = a,
    }
    defer {
        fix_resizable_dynamic(state.parsed_files)
        fix_resizable_multi(state.r.files)
    }
    state.parsed_files[0] = nil
    state.r.files.d[0] = CompilerFile {
        string(data),
        first_file_absolute_path,
        filepath.dir(first_file_absolute_path),
    }
    state.files_map[first_file_absolute_path] = &state.files.d[0]
    state.file_ref = &state.files.d[0]

    ok := true
    for {
        file_path := state.file_ref.file_path
        fmt.printfln("Parsing `%s`...", file_path)
        state.tokenizer_state = TokenizerState {
            last_token_descriptions_of_other_possible_tokens = arena_make(
                a,
                []string,
                0,
                resizable = true,
            ),
            file_ref                                         = state.file_ref,
        }
        defer fix_resizable_dynamic(
            state.tokenizer_state.last_token_descriptions_of_other_possible_tokens,
        )
        file_ok := parse_file(&state)
        if !file_ok {
            ok = false
        }
        next_index := get_file_index(state.files, state.file_ref) + 1
        if next_index >= len(state.parsed_files) {
            break
        }
        state.file_ref = &state.files.d[next_index]
    }
    if exit_early_info, exiting_early := exit_early.(^ExitEarly); exiting_early {
        #partial switch &exit_early_info_value in exit_early_info {
        case ExitEarlyAwaitingSourceCodeChange:
            exit_early_info_value.files = multi_to_array(state.files, len(state.parsed_files))
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

