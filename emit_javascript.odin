package main

import "core:fmt"
import "core:strings"

emit_js_func_call :: proc(s: ^EmitterState, c: CheckedFunctionCall) {
    emit_js_value(s, c.function^)
    strings.write_byte(&s.b, '(')
    for arg, i in c.args {
        emit_js_value(s, arg)
        if i + 1 < len(c.args) {
            strings.write_byte(&s.b, ',')
        }
    }
    strings.write_byte(&s.b, ')')
}

emit_js_value :: proc(s: ^EmitterState, value: CheckedValue) {
    switch v in value {
    case ToString:
        strings.write_string(&s.b, "String(")
        emit_js_value(s, v.value^)
        strings.write_byte(&s.b, ')')
    case uint:
        strings.write_string(&s.b, "func")
        strings.write_uint(&s.b, v)
    case BuiltinFunction:
        strings.write_string(&s.b, "builtin")
        strings.write_uint(&s.b, uint(v.index))
    case CheckedFieldAccess:
        emit_js_value(s, v.value^)
        strings.write_string(&s.b, ".field")
        strings.write_uint(&s.b, v.field_index)
    case LengthOfArray:
        emit_js_value(s, v.array^)
        strings.write_string(&s.b, ".length")
    case CheckedArrayAccess:
        emit_js_value(s, v.array^)
        strings.write_byte(&s.b, '[')
        emit_js_value(s, v.index^)
        strings.write_byte(&s.b, ']')
    case BoolValue:
        strings.write_string(&s.b, v ? "true" : "false")
    case CheckedFunctionCall:
        emit_js_func_call(s, v)
    case TypeInitFunc:
        strings.write_string(&s.b, "init_")
        #partial switch type in v.type {
        case nil:
            panic("unreachable")
        case SumVariant(^ExactCheckedType):
            emit_sum_variant(s, type.sum_type^, type.variant_index, false)
        case GlobalTypeWithoutGenericRef:
            strings.write_string(&s.b, "Global")
            strings.write_uint(&s.b, type.index)
        case:
            panic(fmt.aprintf("TODO: %#v", v.type))
        }
    case StringLiteralValue:
        strings.write_byte(&s.b, '"')
        strings.write_string(&s.b, string(v))
        strings.write_byte(&s.b, '"')
    case I64Value:
        strings.write_i64(&s.b, i64(v))
    case U8Value:
        strings.write_uint(&s.b, uint(v))
    case BooleanNotValue:
        strings.write_byte(&s.b, '(')
        strings.write_byte(&s.b, '!')
        emit_js_value(s, v)
        strings.write_byte(&s.b, ')')
    case StringsAreEqual:
        strings.write_byte(&s.b, '(')
        emit_js_value(s, v.str0^)
        strings.write_string(&s.b, "===")
        emit_js_value(s, v.str1^)
        strings.write_byte(&s.b, ')')
    case CheckedJoinedValues:
        strings.write_byte(&s.b, '(')
        emit_js_value(s, v.val0^)
        switch v.join_method {
        case .Append, .Concat, .Colon, .Arrow:
            panic("Unreachable")
        case .BooleanAnd:
            strings.write_string(&s.b, "&&")
        case .BooleanOr:
            strings.write_string(&s.b, "||")
        case .IsEqual:
            strings.write_string(&s.b, "===")
        case .IsNotEqual:
            strings.write_string(&s.b, "!==")
        case .IsGreaterThan:
            strings.write_byte(&s.b, '>')
        case .IsGreaterThanOrEqual:
            strings.write_string(&s.b, ">=")
        case .IsLessThan:
            strings.write_byte(&s.b, '<')
        case .IsLessThanOrEqual:
            strings.write_string(&s.b, "<=")
        case .Addition, .StringConcat:
            strings.write_byte(&s.b, '+')
        case .Subtraction:
            strings.write_byte(&s.b, '-')
        case .Multiplication:
            strings.write_byte(&s.b, '*')
        case .Division:
            strings.write_byte(&s.b, '/')
        case .Modulo:
            strings.write_byte(&s.b, '%')
        }
        emit_js_value(s, v.val1^)
        strings.write_byte(&s.b, ')')
    case VariableRef:
        emit_variable(&s.b, v)
    case GlobalFuncRef:
        strings.write_string(&s.b, "func")
        strings.write_uint(&s.b, v.index)
    }
}

emit_js_global_type :: proc(s: ^EmitterState, name: string, type: ExactCheckedType) {
    #partial switch t in type {
    case SumType(ExactCheckedType, FuncTypeRef):
        for variant, i in t.variants {
            strings.write_string(&s.b, "function init_")
            strings.write_string(&s.b, name)
            strings.write_string(&s.b, "Variant")
            strings.write_int(&s.b, i)
            strings.write_byte(&s.b, '(')
            first_arg := true
            for _, j in variant.payload.fields {
                if first_arg {
                    first_arg = false
                } else {
                    strings.write_byte(&s.b, ',')
                }
                strings.write_string(&s.b, "field")
                strings.write_int(&s.b, j)
            }
            strings.write_string(&s.b, ") {return {variant:")
            strings.write_int(&s.b, i)
            for _, j in variant.payload.fields {
                strings.write_byte(&s.b, ',')
                strings.write_string(&s.b, "field")
                strings.write_int(&s.b, j)
            }
            strings.write_string(&s.b, "}}")
        }
    case Struct(ExactCheckedType):
        strings.write_string(&s.b, "function init_")
        strings.write_string(&s.b, name)
        strings.write_byte(&s.b, '(')
        first_field := true
        for _, i in t.fields {
            if first_field {
                first_field = false
            } else {
                strings.write_byte(&s.b, ',')
            }
            field_name := fmt.aprintf("field%d", i)
            defer delete(field_name)
        }
        strings.write_string(&s.b, ") {return {")
        first_field = true
        for _, i in t.fields {
            if first_field {
                first_field = false
            } else {
                strings.write_byte(&s.b, ',')
            }
            strings.write_string(&s.b, "field")
            strings.write_int(&s.b, i)
        }
        strings.write_string(&s.b, "}}")
    }
}

emit_js_block_body :: proc(
    s: ^EmitterState,
    nesting_level: uint,
    body: []CheckedStatement,
    loc := #caller_location,
) {
    for statement in body {
        switch stmt in statement {
        case CheckedFunctionCall:
            emit_js_func_call(s, stmt)
            strings.write_byte(&s.b, ';')
        case CheckedReturn:
            strings.write_string(&s.b, "return ")
            emit_js_value(s, stmt.value)
            strings.write_byte(&s.b, ';')
        case CheckedIf:
            strings.write_string(&s.b, "if (")
            emit_js_value(s, stmt.condition)
            strings.write_string(&s.b, "){")
            emit_js_block(s, nesting_level + 1, stmt.if_block.variables, stmt.if_block.body)
            strings.write_string(&s.b, "} else {")
            emit_js_block(s, nesting_level + 1, stmt.else_block.variables, stmt.else_block.body)
            strings.write_byte(&s.b, '}')
        case CheckedMatch:
            strings.write_string(&s.b, "switch (")
            emit_variable(&s.b, stmt.value)
            strings.write_string(&s.b, ".variant) {")
            for branch, i in stmt.branches {
                strings.write_string(&s.b, "case ")
                strings.write_int(&s.b, i)
                strings.write_string(&s.b, ": {")
                emit_js_block_head(s, nesting_level + 1, branch.block.variables)
                emit_variable(&s.b, branch.value_var)
                strings.write_string(&s.b, " = *")
                emit_variable(&s.b, stmt.value)
                strings.write_string(&s.b, ".payload.variant")
                strings.write_int(&s.b, i)
                strings.write_byte(&s.b, ';')
                emit_js_block_body(s, nesting_level + 1, branch.block.body)
                strings.write_string(&s.b, "break;}")
            }
            strings.write_string(&s.b, "}")
        case CheckedLoop:
            strings.write_byte(&s.b, '{')
            emit_js_block(s, nesting_level + 1, stmt.variables, stmt.enter)
            strings.write_string(&s.b, "while (1) {")
            strings.write_string(&s.b, "loop")
            strings.write_uint(&s.b, stmt.loop_index)
            strings.write_string(&s.b, "start:")
            emit_js_block(s, nesting_level + 1, nil, stmt.body)
            strings.write_string(&s.b, "}}loop")
            strings.write_uint(&s.b, stmt.loop_index)
            strings.write_string(&s.b, "end:;")
        case ContinueLoop:
            strings.write_string(&s.b, "goto loop")
            strings.write_uint(&s.b, stmt.loop_index)
            strings.write_string(&s.b, "start;")
        case BreakLoop:
            strings.write_string(&s.b, "goto loop")
            strings.write_uint(&s.b, stmt.loop_index)
            strings.write_string(&s.b, "end;")
        case CheckedArrayMutation:
            emit_variable(&s.b, stmt.variable)
            strings.write_string(&s.b, "=[")
            first_segment := true
            for segment in stmt.segments {
                if first_segment {
                    first_segment = false
                } else {
                    strings.write_byte(&s.b, ',')
                }
                switch segment_value in segment {
                case SingleElemSegment:
                    emit_js_value(s, segment_value.elem)
                case InlineArraySegment:
                    strings.write_string(&s.b, "...")
                    emit_js_value(s, segment_value.array)
                }
            }
            strings.write_string(&s.b, "];")
        case CheckedMutation:
            emit_variable(&s.b, stmt.destination.variable)
            if stmt.destination.index != nil {
                strings.write_string(&s.b, ".elems[")
                emit_js_value(s, stmt.destination.index)
                strings.write_byte(&s.b, ']')

            }
            switch stmt.mutation_type {
            case .SetTo:
                strings.write_byte(&s.b, '=')
            case .IncrementBy:
                strings.write_string(&s.b, "+=")
            case .DecrementBy:
                strings.write_string(&s.b, "-=")
            case .MultiplyBy:
                strings.write_string(&s.b, "*=")
            case .DivideBy:
                strings.write_string(&s.b, "/=")
            }
            emit_js_value(s, stmt.value)
            strings.write_byte(&s.b, ';')
        }
    }
}

emit_js_block_head :: proc(
    s: ^EmitterState,
    nesting_level: uint,
    variables: []ExactCheckedType,
    loc := #caller_location,
) {
    for _, index in variables {
        strings.write_string(&s.b, "var ")
        emit_variable(&s.b, VariableRef{nesting_level, uint(index)})
        strings.write_byte(&s.b, ';')
    }
}

emit_js_block :: proc(
    s: ^EmitterState,
    nesting_level: uint,
    variables: []ExactCheckedType,
    body: []CheckedStatement,
    loc := #caller_location,
) {
    when debug_emitter {
        print_call(loc, "emit_js_block")
    }
    emit_js_block_head(s, nesting_level, variables)
    emit_js_block_body(s, nesting_level, body)
}

emit_javascript :: proc(
    code: []CheckedFunction,
    global_types_without_generics: []ExactCheckedType,
    generic_type_initialisations: GenericTypeInitialisationsStore,
    array_type_initialisations: ArrayTypeInitialisationsStore,
    func_types: []EquivalencyArrayElem(ExactFuncType),
    type_equivalancy_array: []EquivalencyArrayElem(ExactCheckedType),
) -> strings.Builder {
    s := EmitterState{strings.builder_make(), func_types, type_equivalancy_array}

    for global, index in global_types_without_generics {
        name := fmt.aprintf("Global%d", index)
        defer delete_string(name)
        emit_js_global_type(&s, name, global)
    }

    emitted_generic_type_defs := map[u64]struct{}{}
    for key, value in generic_type_initialisations {
        global_type_index, generic_arg_ref := seperate_u64(key)
        _, simplified_generic_arg_ref := get_info(type_equivalancy_array, uint(generic_arg_ref))
        new_key := combine_u32(global_type_index, u32(simplified_generic_arg_ref))
        _, emitted := emitted_generic_type_defs[new_key]
        if emitted {
            continue
        }
        new_value: ExactCheckedType = ---
        if value == nil {
            new_value = generic_type_initialisations[new_key]
            if new_value == nil {
                continue
            }
        } else {
            new_value = value
        }
        emitted_generic_type_defs[new_key] = struct{}{}
        name := fmt.aprintf(generic_name_format, global_type_index, simplified_generic_arg_ref)
        defer delete(name)
        emit_js_global_type(&s, name, new_value)
    }

    for func, index in code {
        when debug_emitter {
            debug("emitting function index %d", index)
        }
        strings.write_string(&s.b, "function func")
        strings.write_int(&s.b, index)
        strings.write_byte(&s.b, '(')
        info, _ := get_info(func_types, uint(index))
        first_arg := true
        for _, i in info.args {
            if first_arg {
                first_arg = false
            } else {
                strings.write_byte(&s.b, ',')
            }
            emit_variable(&s.b, VariableRef{0, uint(i)})
        }
        strings.write_string(&s.b, ") {")
        emit_js_block(&s, 1, func.variables, func.body)
        strings.write_byte(&s.b, '}')
    }

    return s.b
}

