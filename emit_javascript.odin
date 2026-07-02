package main

import "core:fmt"
import "core:strings"

emit_js_func_call :: proc(s: ^GeneralEmitterState, c: CheckedFunctionCall) {
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

emit_js_comptime_value :: proc(s: ^GeneralEmitterState, v: CompileTimeValue) {
    switch comptime in v {
    case CompileTimeStructInitialisation:
        strings.write_string(&s.b, "init_Type")
        strings.write_uint(&s.b, uint(comptime.func.type.index))
        strings.write_byte(&s.b, '(')
        first_arg := true
        for arg in comptime.args {
            if first_arg == false {
                strings.write_byte(&s.b, ',')
            }
            emit_js_comptime_value(s, arg)
            first_arg = false
        }
        strings.write_byte(&s.b, ')')

    case CheckedFuncRef:
        strings.write_string(&s.b, "func")
        strings.write_uint(&s.b, comptime.index)
    case Type, UninitialisedOrderedHashMapType:
        panic("Unreachable")
    case GlobalValueWithGenericRef, Import:
        panic("Unreachable")
    case StringLiteralValue:
        strings.write_byte(&s.b, '"')
        for char in comptime {
            switch char {
            case '\n':
                strings.write_string(&s.b, "\\n")
            case '"':
                strings.write_string(&s.b, "\\\"")
            case '\\':
                strings.write_string(&s.b, "\\\\")
            case:
                strings.write_rune(&s.b, char)
            }
        }
        strings.write_byte(&s.b, '"')
    case BoolValue:
        strings.write_string(&s.b, comptime ? "true" : "false")
    case NumberValue:
        if comptime.value.is_negated {
            strings.write_byte(&s.b, '-')
        }
        strings.write_string(&s.b, big_uint_to_string(comptime.value.absolute_value))
    }

}

// TODO: Deduplicate code between `emit_js_runtime_value` and `emit_js_value` / `emit_js_comptime_value`

emit_js_runtime_value :: proc(b: ^strings.Builder, value: RuntimeValue) {
    #partial switch v in value {
    case CheckedFuncRef:
        strings.write_string(b, "func")
        strings.write_uint(b, v.index)
    case RuntimeStruct:
        strings.write_byte(b, '{')
        for field, i in v.field_values {
            strings.write_string(b, "field")
            strings.write_int(b, i)
            strings.write_byte(b, ':')
            emit_js_runtime_value(b, field)
            strings.write_byte(b, ',')
        }
        strings.write_byte(b, '}')
    case RuntimeArray:
        strings.write_byte(b, '[')
        for elem in v.elems {
            emit_js_runtime_value(b, elem)
            strings.write_byte(b, ',')
        }
        strings.write_byte(b, ']')
    case i64:
        strings.write_i64(b, v)
    case bool:
        strings.write_string(b, v ? "true" : "false")
    case:
        strings.write_string(
            b,
            "undefined /* TODO: Be able to emit more kinds of RuntimeValue as javascript */",
        )
    }
}

emit_js_map_keys_func :: proc(s: ^GeneralEmitterState, hash_map: CheckedValue) {
    strings.write_string(&s.b, "Map.prototype.keys.call(")
    emit_js_value(s, hash_map)
    strings.write_byte(&s.b, ')')
}

emit_js_value :: proc(s: ^GeneralEmitterState, value: CheckedValue) {
    switch v in value {
    case OrderedHashMapInitFunc:
        strings.write_string(&s.b, "new Map")
    case KeysOfOrderedHashMapWithStringKey:
        emit_js_map_keys_func(s, v.hash_map^)
    case KeysOfOrderedHashMapWithI64Key:
        emit_js_map_keys_func(s, v.hash_map^)
    case CheckedOrderedHashMapAccess:
        strings.write_string(&s.b, "Map.prototype.get.call(")
        emit_js_value(s, v.hash_map^)
        strings.write_byte(&s.b, ',')
        emit_js_value(s, v.key^)
        strings.write_byte(&s.b, ')')
    case CompileTimeValue:
        emit_js_comptime_value(s, v)
    case ToString:
        strings.write_string(&s.b, "String(")
        emit_js_value(s, v.value^)
        strings.write_byte(&s.b, ')')
    case BuiltinFunction:
        strings.write_string(&s.b, "builtin")
        strings.write_uint(&s.b, uint(v))
    case CheckedFieldAccess:
        emit_js_value(s, v.value^)
        strings.write_string(&s.b, ".field")
        strings.write_uint(&s.b, v.field_index)
    case LengthOfArray:
        emit_js_value(s, v.array^)
        strings.write_string(&s.b, ".length")
    case LengthOfOrderedHashMapWithStringKey:
        panic("TODO")
    case LengthOfOrderedHashMapWithI64Key:
        panic("TODO")
    case CheckedArrayAccess:
        emit_js_value(s, v.array^)
        strings.write_byte(&s.b, '[')
        emit_js_value(s, v.index^)
        strings.write_byte(&s.b, ']')
    case CheckedFunctionCall:
        emit_js_func_call(s, v)
    case StructTypeInitFunc:
        strings.write_string(&s.b, "init_Type")
        strings.write_uint(&s.b, uint(v.type.index))
    case SumTypeInitFunc:
        strings.write_string(&s.b, "init_Type")
        strings.write_uint(&s.b, uint(v.sum_type.index))
        strings.write_string(&s.b, "Variant")
        strings.write_uint(&s.b, uint(v.variant_index))
    case BooleanNotValue:
        strings.write_byte(&s.b, '(')
        strings.write_byte(&s.b, '!')
        emit_js_value(s, v^)
        strings.write_byte(&s.b, ')')
    case StringsAreEqual:
        strings.write_byte(&s.b, '(')
        emit_js_value(s, v.str0^)
        strings.write_string(&s.b, "===")
        emit_js_value(s, v.str1^)
        strings.write_byte(&s.b, ')')
    case CheckedJoinedValues:
        if v.join_method == .In {
            strings.write_string(&s.b, "in_map(")
            emit_js_value(s, v.val0^)
            strings.write_string(&s.b, ", ")
            emit_js_value(s, v.val1^)
            strings.write_string(&s.b, ")")
            return
        }
        strings.write_byte(&s.b, '(')
        emit_js_value(s, v.val0^)
        switch v.join_method {
        case .Append, .Concat, .Colon, .Arrow, .In:
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
    }
}

emit_js_global_type :: proc(s: ^GeneralEmitterState, index: int) {
    name := fmt.aprintf("Type%d", index)
    defer delete(name)
    switch t in s.types.values[index].value.value {
    case OrderedHashMapTypeWithStringKey:
    case OrderedHashMapTypeWithI64Key:
    case ArrayType:
    case FuncType:
    case GenericTypeValue:
    case SumType(Type):
        for variant, i in t.variants {
            payload := get_type(s.types, variant.payload).(Struct(Type, Type))
            strings.write_string(&s.b, "function init_")
            strings.write_string(&s.b, name)
            strings.write_string(&s.b, "Variant")
            strings.write_int(&s.b, i)
            strings.write_byte(&s.b, '(')
            first_arg := true
            for _, j in payload.fields {
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
            for _, j in payload.fields {
                strings.write_byte(&s.b, ',')
                strings.write_string(&s.b, "field")
                strings.write_int(&s.b, j)
            }
            strings.write_string(&s.b, "}}")
        }
    case Struct(Type, Type):
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
            strings.write_string(&s.b, "field")
            strings.write_int(&s.b, i)
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
    s: ^GeneralEmitterState,
    nesting_level: uint,
    body: []CheckedStatement,
    loc := #caller_location,
) {
    for statement in body {
        switch stmt in statement {
        case UnreachableStatement:
            strings.write_string(&s.b, "throw new Error(\"Unreachable\")")
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
                if value_var, has_value_var := branch.value_var.(VariableRef); has_value_var {
                    emit_variable(&s.b, value_var)
                    strings.write_string(&s.b, " = *")
                    emit_variable(&s.b, stmt.value)
                    strings.write_string(&s.b, ".payload.variant")
                    strings.write_int(&s.b, i)
                    strings.write_byte(&s.b, ';')
                }
                emit_js_block_body(s, nesting_level + 1, branch.block.body)
                strings.write_string(&s.b, "break;}")
            }
            strings.write_string(&s.b, "}")
        case CheckedLoop:
            strings.write_byte(&s.b, '{')
            emit_js_block(s, nesting_level + 1, stmt.variables, stmt.enter)
            strings.write_string(&s.b, "loop")
            strings.write_uint(&s.b, stmt.loop_index)
            strings.write_string(&s.b, ": while (true) {loop")
            strings.write_uint(&s.b, stmt.loop_index)
            strings.write_string(&s.b, "_body: do {")
            emit_js_block(s, nesting_level + 1, nil, stmt.body)
            strings.write_string(&s.b, "} while (false)")
            emit_js_block(s, nesting_level + 1, nil, stmt.continue_code)
            strings.write_string(&s.b, "}}")
        case ContinueLoop:
            strings.write_string(&s.b, "break loop")
            strings.write_uint(&s.b, stmt.loop_index)
            strings.write_string(&s.b, "_body;")
        case BreakLoop:
            strings.write_string(&s.b, "break loop")
            strings.write_uint(&s.b, stmt.loop_index)
            strings.write_byte(&s.b, ';')
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
            emit_js_value(s, stmt.destination)
            strings.write_byte(&s.b, '=')
            emit_js_value(s, stmt.value)
            strings.write_byte(&s.b, ';')
        }
    }
}

emit_js_block_head :: proc(
    s: ^GeneralEmitterState,
    nesting_level: uint,
    variables: []Type,
    loc := #caller_location,
) {
    for _, index in variables {
        strings.write_string(&s.b, "var ")
        emit_variable(&s.b, VariableRef{nesting_level, uint(index)})
        strings.write_byte(&s.b, ';')
    }
}

emit_js_block :: proc(
    s: ^GeneralEmitterState,
    nesting_level: uint,
    variables: []Type,
    body: []CheckedStatement,
    loc := #caller_location,
) {
    when debug_emitter {
        print_call(loc, "emit_js_block")
    }
    emit_js_block_head(s, nesting_level, variables)
    emit_js_block_body(s, nesting_level, body)
}

emit_javascript :: proc(c: Checked) -> strings.Builder {
    s := GeneralEmitterState{strings.builder_make(), c.types, c}
    strings.write_string(&s.b, "function in_map(a, b) {return Map.prototype.has.call(b, a)}")

    for _, index in c.types.values {
        emit_js_global_type(&s, index)
    }

    /*
    for _, i in c.types.values {
        tv := c.types.values[i].value
        gen_value, ok := tv.(GenericTypeValue)
        if !ok || !gen_value.is_initialised {
            continue
        }
        name := fmt.aprintf(
            generic_name_format,
            gen_value.generic_type_index,
            gen_value.generic_arg.index,
        )
        defer delete(name)
        emit_js_global_type(&s, name, gen_value.initialised_type)
    }
    */

    for func, index in c.checked_funcs {
        when debug_emitter {
            debug("emitting function index %d", index)
        }
        strings.write_string(&s.b, "function func")
        strings.write_int(&s.b, index)
        strings.write_byte(&s.b, '(')
        info := get_type(c.types, func.type).(FuncType)
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

