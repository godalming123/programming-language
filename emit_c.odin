package main

import "core:fmt"
import "core:strings"

EmitterState :: struct {
    b:                      strings.Builder,
    types:                  Types,
    type_equivalancy_array: []ExactCheckedType,
    c:                      Checked,
}

variable_format :: "nesting_level%dindex%d"
generic_name_format :: "GenericWhereGenericIndexIs%dAndUniqueTypeIndexIs%d"

emit_variable :: proc(b: ^strings.Builder, variable: VariableRef) {
    var := fmt.aprintf(variable_format, variable.nesting_level, variable.index)
    strings.write_string(b, var)
    delete_string(var)
}

emit_generic_name :: proc(
    b: ^strings.Builder,
    generic_type_index: u32,
    generic_arg: u32,
    emit_struct_keyword: bool,
) {
    if emit_struct_keyword {
        strings.write_string(b, "struct ")
    }
    name := fmt.aprintf(generic_name_format, generic_type_index, generic_arg)
    strings.write_string(b, name)
    delete_string(name)
}

emit_array_type :: proc(b: ^strings.Builder, length: u32, item_type: Type) {
    strings.write_string(b, "struct ArrayWhereLengthIs")
    strings.write_uint(b, uint(length))
    strings.write_string(b, "AndUniqueTypeIndexIs")
    strings.write_uint(b, uint(item_type.index))
}

// Does not include the `struct`
emit_struct_type :: proc(
    s: ^EmitterState,
    type: Struct(ExactCheckedType),
    loc := #caller_location,
) {
    when debug_emitter {
        print_call(loc, "emit_struct_type")
    }
    strings.write_byte(&s.b, '{')
    for field, index in type.fields {
        name := fmt.aprintf("field%d", index)
        emit_type(s, name, field.type)
        delete_string(name)
        strings.write_byte(&s.b, ';')
    }
    strings.write_byte(&s.b, '}')
}

emit_sum_variant :: proc(
    s: ^EmitterState,
    sum_type: ExactCheckedType,
    variant_index: uint,
    emit_struct_keyword: bool,
) {
    #partial switch type in sum_type {
    case SumType(ExactCheckedType, FuncTypeRef):
        panic(
            "TODO: Handle inline sum types in checker so that C emitter does not have to emit them",
        )
    case Type:
        tv := get_value(s.c.types, type).(GenericTypeValue)
        emit_generic_name(
            &s.b,
            tv.generic_type_index,
            u32(tv.generic_arg.index),
            emit_struct_keyword,
        )
        strings.write_string(&s.b, "Variant")
        strings.write_uint(&s.b, variant_index)
    case GlobalTypeWithoutGenericRef:
        strings.write_string(&s.b, "Global")
        strings.write_uint(&s.b, type.index)
        strings.write_string(&s.b, "Variant")
        strings.write_uint(&s.b, variant_index)
    case nil:
        panic("Unreahcable")
    case:
        panic("Unreahcable")
    }
}

emit_type2 :: proc(s: ^EmitterState, name: string, type: Type) {
    switch type {
    case bool_type:
        strings.write_string(&s.b, "bool")
    case string_type:
        strings.write_string(&s.b, "char*")
    case i64_type:
        strings.write_string(&s.b, "int64_t")
    case i32_type:
        strings.write_string(&s.b, "int32_t")
    case i16_type:
        strings.write_string(&s.b, "int16_t")
    case i8_type:
        strings.write_string(&s.b, "int8_t")
    case u64_type:
        strings.write_string(&s.b, "uint64_t")
    case u32_type:
        strings.write_string(&s.b, "uint32_t")
    case u16_type:
        strings.write_string(&s.b, "uint16_t")
    case u8_type:
        strings.write_string(&s.b, "uint8_t")
    case:
        switch t in get_type(s.types, type) {
        case nil:
            panic("unreachable")
        case ArrayType(Type):
            emit_array_type(&s.b, t.length, t.item_type)
        case SumType(Type, struct {}):
            panic("TODO")
        case TypeEquivilancyArrayRef:
            emit_type(s, name, s.type_equivalancy_array[t.index])
            return
        case FuncType(Type):
            switch len(t.return_types) {
            case 0:
                strings.write_string(&s.b, "void")
            case 1:
                emit_type(s, "", t.return_types[0])
            case:
                panic("TODO")
            }
            strings.write_string(&s.b, " (*")
            strings.write_string(&s.b, name)
            strings.write_string(&s.b, ")(")
            is_first_arg := true
            for arg in t.args {
                if !is_first_arg {
                    strings.write_byte(&s.b, ',')
                }
                emit_type(s, "", arg)
                is_first_arg = false
            }
            strings.write_byte(&s.b, ')')
            return
        case GenericTypeValue:
            emit_generic_name(&s.b, t.generic_type_index, u32(t.generic_arg.index), true)
        }
    }
    strings.write_byte(&s.b, ' ')
    strings.write_string(&s.b, name)
}

emit_type :: proc(
    s: ^EmitterState,
    name: string,
    type: ExactCheckedType,
    loc := #caller_location,
) {
    when debug_emitter {
        print_call(loc, "emit_type")
        print_arg("name", name)
        print_arg("type", type)
    }
    switch t in type {
    case:
        panic(fmt.aprintf("Unreachable (type was %v)", type))
    case SumType(ExactCheckedType, FuncTypeRef):
        panic("TODO: Emit inline checked sum type for C emitter")
    case Type:
        emit_type2(s, name, t)
        return
    case TypeEquivilancyArrayRef:
        when debug_emitter {
            debug("Type equivalancy array index: %d", t.index)
        }
        emit_type(s, name, s.type_equivalancy_array[t.index])
        return
    case GlobalTypeWithoutGenericRef:
        strings.write_string(&s.b, "struct Global")
        strings.write_uint(&s.b, t.index)
    case SumVariant(^ExactCheckedType):
        emit_sum_variant(s, t.sum_type^, t.variant_index, true)
    case Struct(ExactCheckedType):
        strings.write_string(&s.b, "struct ")
        emit_struct_type(s, t)
    // case ArrayType(u32):
    // emit_array_type(&s.b, t.length, u32(t.item_type))
    }
    strings.write_byte(&s.b, ' ')
    strings.write_string(&s.b, name)
}

emit_c_func_call :: proc(s: ^EmitterState, c: CheckedFunctionCall) {
    emit_c_value(s, c.function^)
    strings.write_byte(&s.b, '(')
    for arg, i in c.args {
        emit_c_value(s, arg)
        if i + 1 < len(c.args) {
            strings.write_byte(&s.b, ',')
        }
    }
    strings.write_byte(&s.b, ')')
}

emit_c_value :: proc(s: ^EmitterState, v: CheckedValue) {
    switch value in v {
    case CompileTimeValue:
        switch comptime in value {
        case NumberValue:
            if comptime.value.is_negated {
                strings.write_byte(&s.b, '-')
            }
            strings.write_string(&s.b, big_uint_to_string(comptime.value.absolute_value))
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
        }
    case ToString:
        strings.write_string(&s.b, "asprintf_value(")
        switch value.from_type {
        case .BoolType:
            strings.write_string(&s.b, "\"%b\"")
        case .I64Type:
            strings.write_string(&s.b, "\"%\" PRId64")
        case .I32Type:
            strings.write_string(&s.b, "\"%\" PRId32")
        case .I16Type:
            strings.write_string(&s.b, "\"%\" PRId16")
        case .I8Type:
            strings.write_string(&s.b, "\"%\" PRId8")
        case .U64Type:
            strings.write_string(&s.b, "\"%\" PRIu64")
        case .U32Type:
            strings.write_string(&s.b, "\"%\" PRIu32")
        case .U16Type:
            strings.write_string(&s.b, "\"%\" PRIu16")
        case .U8Type:
            strings.write_string(&s.b, "\"%\" PRIu8")
        }
        strings.write_byte(&s.b, ',')
        emit_c_value(s, value.value^)
        strings.write_string(&s.b, ")")
    case BuiltinFunction:
        strings.write_string(&s.b, "builtin")
        strings.write_uint(&s.b, uint(value.index))
    case CheckedFieldAccess:
        emit_c_value(s, value.value^)
        strings.write_string(&s.b, ".field")
        strings.write_uint(&s.b, value.field_index)
    //case CheckedJsFunctionCall:
    //    panic("Internal error: JsFunctionCall received by C emitter")
    //case ArrayValue:
    //    panic("Internal error: Unexpected array value")
    case LengthOfArray:
        emit_c_value(s, value.array^)
        strings.write_string(&s.b, ".length")
    case CheckedArrayAccess:
        emit_c_value(s, value.array^)
        strings.write_string(&s.b, ".elems[")
        emit_c_value(s, value.index^)
        strings.write_byte(&s.b, ']')
    case CheckedFunctionCall:
        emit_c_func_call(s, value)
    //case CheckedStructTypeInitialisation:
    //    emit_type(s, "", value.type)
    //    strings.write_byte(&s.b, '{')
    //    first_value := true
    //    for v in value.args {
    //        if !first_value {
    //            strings.write_byte(&s.b, ',')
    //        }
    //        first_value = false
    //        emit_c_value(s, v)
    //    }
    //    strings.write_byte(&s.b, '}')
    case TypeInitFunc:
        strings.write_string(&s.b, "init_")
        #partial switch type in value.type {
        case nil:
            panic("unreachable")
        case SumVariant(^ExactCheckedType):
            emit_sum_variant(s, type.sum_type^, type.variant_index, false)
        case GlobalTypeWithoutGenericRef:
            strings.write_string(&s.b, "Global")
            strings.write_uint(&s.b, type.index)
        case:
            panic(fmt.aprintf("TODO: %#v", value.type))
        }
    case BooleanNotValue:
        strings.write_byte(&s.b, '(')
        strings.write_byte(&s.b, '!')
        emit_c_value(s, value)
        strings.write_byte(&s.b, ')')
    case StringsAreEqual:
        strings.write_string(&s.b, "(strcmp(")
        emit_c_value(s, value.str0^)
        strings.write_byte(&s.b, ',')
        emit_c_value(s, value.str1^)
        strings.write_string(&s.b, ")==0)")
    case CheckedJoinedValues:
        if value.join_method == .StringConcat {
            strings.write_string(&s.b, "asprintf_value(\"%s%s\",")
            emit_c_value(s, value.val0^)
            strings.write_byte(&s.b, ',')
            emit_c_value(s, value.val1^)
            strings.write_byte(&s.b, ')')
            return
        }
        strings.write_byte(&s.b, '(')
        emit_c_value(s, value.val0^)
        switch value.join_method {
        case .Append, .Concat, .StringConcat, .Colon, .Arrow:
            panic("Unreachable")
        case .BooleanAnd:
            strings.write_string(&s.b, "&&")
        case .BooleanOr:
            strings.write_string(&s.b, "||")
        case .IsEqual:
            strings.write_string(&s.b, "==")
        case .IsNotEqual:
            strings.write_string(&s.b, "!=")
        case .IsGreaterThan:
            strings.write_byte(&s.b, '>')
        case .IsGreaterThanOrEqual:
            strings.write_string(&s.b, ">=")
        case .IsLessThan:
            strings.write_byte(&s.b, '<')
        case .IsLessThanOrEqual:
            strings.write_string(&s.b, "<=")
        case .Addition:
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
        emit_c_value(s, value.val1^)
        strings.write_byte(&s.b, ')')
    case VariableRef:
        emit_variable(&s.b, value)
    //case CheckedReadFile:
    //    strings.write_string(&s.b, "compiler_read_file(")
    //    emit_c_value(s, value.file_name^)
    //    strings.write_byte(&s.b, ')')
    //case CheckedReadLine:
    //    strings.write_string(&s.b, "readline(")
    //    emit_c_value(s, value.prompt^)
    //    strings.write_byte(&s.b, ')')
    case FuncDefinitionRef:
        strings.write_string(&s.b, "func")
        strings.write_uint(&s.b, value.index)
    }
}

emit_c_block_head :: proc(
    s: ^EmitterState,
    nesting_level: uint,
    variables: []ExactCheckedType,
    loc := #caller_location,
) {
    when debug_emitter {
        print_call(loc, "emit_c_block_head")
    }
    for type, index in variables {
        name := fmt.aprintf(variable_format, nesting_level, index)
        emit_type(s, name, type)
        delete_string(name)
        strings.write_byte(&s.b, ';')
    }
}

emit_c_block_body :: proc(
    s: ^EmitterState,
    nesting_level: uint,
    body: []CheckedStatement,
    loc := #caller_location,
) {
    when debug_emitter {
        print_call(loc, "emit_c_block_body")
        print_arg("nesting_level", nesting_level)
        print_arg("body", body)
    }
    for statement in body {
        switch stmt in statement {
        //case CheckedJsFunctionCall, CheckedJsAssignment:
        //    panic("Internal error: JS received by C emitter")
        case CheckedFunctionCall:
            emit_c_func_call(s, stmt)
            strings.write_byte(&s.b, ';')
        case CheckedReturn:
            strings.write_string(&s.b, "return ")
            emit_c_value(s, stmt.value)
            strings.write_byte(&s.b, ';')
        case CheckedIf:
            strings.write_string(&s.b, "if (")
            emit_c_value(s, stmt.condition)
            strings.write_string(&s.b, "){")
            emit_c_block(s, nesting_level + 1, stmt.if_block.variables, stmt.if_block.body)
            strings.write_string(&s.b, "} else {")
            emit_c_block(s, nesting_level + 1, stmt.else_block.variables, stmt.else_block.body)
            strings.write_byte(&s.b, '}')
        /*
        case CheckedSumTypeInitialisation:
            emit_variable(&s.b, stmt.destination)
            strings.write_string(&s.b, ".variant=")
            strings.write_uint(&s.b, stmt.variant_index)
            strings.write_byte(&s.b, ';')

            emit_variable(&s.b, stmt.destination)
            strings.write_string(&s.b, ".payload.variant")
            strings.write_uint(&s.b, stmt.variant_index)
            strings.write_string(&s.b, "=malloc(sizeof(")
            emit_sum_variant(s, stmt.sum_type, stmt.variant_index)
            strings.write_string(&s.b, "));")

            for field, i in stmt.args {
                emit_variable(&s.b, stmt.destination)
                strings.write_string(&s.b, ".payload.variant")
                strings.write_uint(&s.b, stmt.variant_index)
                strings.write_string(&s.b, "->field")
                strings.write_int(&s.b, i)
                strings.write_byte(&s.b, '=')
                emit_c_value(s, field)
                strings.write_byte(&s.b, ';')
            }
            */
        case CheckedMatch:
            strings.write_string(&s.b, "switch (")
            emit_variable(&s.b, stmt.value)
            strings.write_string(&s.b, ".variant) {")
            for branch, i in stmt.branches {
                strings.write_string(&s.b, "case ")
                strings.write_int(&s.b, i)
                strings.write_string(&s.b, ": {")
                emit_c_block_head(s, nesting_level + 1, branch.block.variables)
                if value_var, has_value_var := branch.value_var.(VariableRef); has_value_var {
                    emit_variable(&s.b, value_var)
                    strings.write_string(&s.b, " = *")
                    emit_variable(&s.b, stmt.value)
                    strings.write_string(&s.b, ".payload.variant")
                    strings.write_int(&s.b, i)
                    strings.write_byte(&s.b, ';')
                }
                emit_c_block_body(s, nesting_level + 1, branch.block.body)
                strings.write_string(&s.b, "break;}")
            }
            strings.write_string(&s.b, "}")
        case CheckedLoop:
            strings.write_byte(&s.b, '{')
            emit_c_block(s, nesting_level + 1, stmt.variables, stmt.enter)
            strings.write_string(&s.b, "while (1) {")
            strings.write_string(&s.b, "loop")
            strings.write_uint(&s.b, stmt.loop_index)
            strings.write_string(&s.b, "start:")
            emit_c_block(s, nesting_level + 1, nil, stmt.body)
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
            if stmt.variable_type.length == 0 {
                emit_variable(&s.b, stmt.variable)
                strings.write_string(&s.b, ".length = 0;")
                number_of_single_elem_segments := 0
                for segment in stmt.segments {
                    switch segment_value in segment {
                    case SingleElemSegment:
                        number_of_single_elem_segments += 1
                    case InlineArraySegment:
                        emit_variable(&s.b, stmt.variable)
                        strings.write_string(&s.b, ".length += ")
                        emit_c_value(s, segment_value.array_length)
                        strings.write_byte(&s.b, ';')
                    }
                }
                if number_of_single_elem_segments > 0 {
                    emit_variable(&s.b, stmt.variable)
                    strings.write_string(&s.b, ".length += ")
                    strings.write_int(&s.b, number_of_single_elem_segments)
                    strings.write_byte(&s.b, ';')
                }
                emit_variable(&s.b, stmt.variable)
                strings.write_string(&s.b, ".elems = malloc(")
                emit_variable(&s.b, stmt.variable)
                strings.write_string(&s.b, ".length * sizeof(")
                emit_type(s, "", stmt.variable_type.item_type)
                strings.write_string(&s.b, "));")
            }
            strings.write_string(&s.b, "{uint64_t index = 0;")
            for segment in stmt.segments {
                switch segment_value in segment {
                case SingleElemSegment:
                    emit_variable(&s.b, stmt.variable)
                    strings.write_string(&s.b, ".elems[index] = ")
                    emit_c_value(s, segment_value.elem)
                    strings.write_string(&s.b, "; index += 1;")
                case InlineArraySegment:
                    strings.write_string(&s.b, "{uint64_t index2 = 0; while (index2 < ")
                    emit_c_value(s, segment_value.array_length)
                    strings.write_string(&s.b, ") {")
                    emit_variable(&s.b, stmt.variable)
                    strings.write_string(&s.b, ".elems[index+index2] = ")
                    emit_c_value(s, segment_value.array)
                    strings.write_string(&s.b, ".elems[index2];index2 += 1;}index += index2;}")
                }
            }
            strings.write_byte(&s.b, '}')
        case CheckedMutation:
            emit_variable(&s.b, stmt.destination.variable)
            if stmt.destination.index != nil {
                strings.write_string(&s.b, ".elems[")
                emit_c_value(s, stmt.destination.index)
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
            emit_c_value(s, stmt.value)
            strings.write_byte(&s.b, ';')
        }
    }
}

emit_c_block :: proc(
    s: ^EmitterState,
    nesting_level: uint,
    variables: []ExactCheckedType,
    body: []CheckedStatement,
    loc := #caller_location,
) {
    when debug_emitter {
        print_call(loc, "emit_c_block")
    }
    emit_c_block_head(s, nesting_level, variables)
    emit_c_block_body(s, nesting_level, body)
}

emit_c_global_type :: proc(
    s: ^EmitterState,
    name: string,
    type: ExactCheckedType,
    loc := #caller_location,
) {
    when debug_emitter {
        print_call(loc, "emit_c_global_type")
    }
    sum_type, is_sum_type := type.(SumType(ExactCheckedType, FuncTypeRef))
    if is_sum_type {
        strings.write_string(&s.b, "struct ")
        strings.write_string(&s.b, name)
        strings.write_string(&s.b, "{uint64_t variant; union {")
        for _, i in sum_type.variants {
            strings.write_string(&s.b, "struct ")
            strings.write_string(&s.b, name)
            strings.write_string(&s.b, "Variant")
            strings.write_int(&s.b, i)
            strings.write_string(&s.b, "* variant")
            strings.write_int(&s.b, i)
            strings.write_byte(&s.b, ';')
        }
        strings.write_string(&s.b, "} payload;};")
        for variant, i in sum_type.variants {
            // Type def
            strings.write_string(&s.b, "struct ")
            strings.write_string(&s.b, name)
            strings.write_string(&s.b, "Variant")
            strings.write_int(&s.b, i)
            emit_struct_type(s, variant.payload)
            strings.write_byte(&s.b, ';')

            // Initialisation func def
            strings.write_string(&s.b, "struct ")
            strings.write_string(&s.b, name)
            strings.write_string(&s.b, " init_")
            strings.write_string(&s.b, name)
            strings.write_string(&s.b, "Variant")
            strings.write_int(&s.b, i)
            strings.write_byte(&s.b, '(')
            first_arg := true
            for field, j in variant.payload.fields {
                if !first_arg {
                    strings.write_byte(&s.b, ',')
                }
                first_arg = false
                field_name := fmt.aprintf("field%d", j)
                defer delete_string(field_name)
                emit_type(s, field_name, field.type)
            }
            strings.write_string(&s.b, ") {struct ")
            strings.write_string(&s.b, name)
            strings.write_string(&s.b, " out;out.variant = ")
            strings.write_int(&s.b, i)
            strings.write_string(&s.b, "; out.payload.variant")
            strings.write_int(&s.b, i)
            strings.write_string(&s.b, " = malloc(sizeof(struct ")
            strings.write_string(&s.b, name)
            strings.write_string(&s.b, "));")
            for _, j in variant.payload.fields {
                strings.write_string(&s.b, "out.payload.variant")
                strings.write_int(&s.b, i)
                strings.write_string(&s.b, "->field")
                strings.write_int(&s.b, j)
                strings.write_string(&s.b, " = field")
                strings.write_int(&s.b, j)
                strings.write_byte(&s.b, ';')
            }
            strings.write_string(&s.b, "return out;}")
        }
        return
    }
    struct_type, is_struct := type.(Struct(ExactCheckedType))
    if is_struct {
        strings.write_string(&s.b, "struct ")
        strings.write_string(&s.b, name)
        emit_struct_type(s, struct_type)
        strings.write_byte(&s.b, ';')
        strings.write_string(&s.b, "struct ")
        strings.write_string(&s.b, name)
        strings.write_string(&s.b, " init_")
        strings.write_string(&s.b, name)
        strings.write_byte(&s.b, '(')
        first_field := true
        for field, i in struct_type.fields {
            if first_field == false {
                strings.write_byte(&s.b, ',')
            } else {
                first_field = false
            }
            field_name := fmt.aprintf("field%d", i)
            defer delete(field_name)
            emit_type(s, field_name, field.type)
        }
        strings.write_string(&s.b, ") {struct ")
        strings.write_string(&s.b, name)
        strings.write_string(&s.b, " out;")
        for _, i in struct_type.fields {
            strings.write_string(&s.b, "out.field")
            strings.write_int(&s.b, i)
            strings.write_string(&s.b, "=field")
            strings.write_int(&s.b, i)
            strings.write_byte(&s.b, ';')
        }
        strings.write_string(&s.b, "return out;}")
    } else {
        strings.write_string(&s.b, "typedef ")
        emit_type(s, name, type)
        strings.write_byte(&s.b, ';')
    }
}

emit_function_head :: proc(s: ^EmitterState, func_index: int, type: FuncTypeRef) {
    when debug_emitter {
        debug("emitting function index %d", func_index)
    }
    info := get_type(s.types, Type(type)).(FuncType(Type))
    switch len(info.return_types) {
    case 0:
        strings.write_string(&s.b, "void")
    case 1:
        emit_type(s, "", info.return_types[0])
    case:
        panic("Unreachable")
    }
    strings.write_string(&s.b, " func")
    strings.write_int(&s.b, func_index)
    strings.write_byte(&s.b, '(')
    first_arg := true
    for arg, i in info.args {
        if !first_arg {
            strings.write_byte(&s.b, ',')
        }
        name := fmt.aprintf(variable_format, 0, i)
        emit_type(s, name, arg)
        delete_string(name)
        first_arg = false
    }
    strings.write_byte(&s.b, ')')
}

emit_c :: proc(c: Checked, main_func_ref: FuncDefinitionRef, main_extra_code: string) -> []byte {
    s := EmitterState{strings.builder_make(), c.types, c.type_equivalancy_array, c}
    strings.write_bytes(&s.b, #load("glue.c"))

    for global, index in c.checked_global_types_without_generic {
        name := fmt.aprintf("Global%d", index)
        defer delete_string(name)
        emit_c_global_type(&s, name, global)
    }

    emitted_array_type_defs := map[u64]struct{}{}
    for value in c.types.values {
        array_type, is_array := value.value.(ArrayType(Type))
        if !is_array {
            continue
        }
        length := array_type.length
        new_key := combine_u32(length, array_type.item_type.index)
        _, emitted := emitted_array_type_defs[new_key]
        if emitted {
            continue
        }
        emitted_array_type_defs[new_key] = struct{}{}

        emit_array_type(&s.b, length, array_type.item_type)
        if length != 0 {
            strings.write_byte(&s.b, '{')
            emit_type(&s, "", array_type.item_type)
            strings.write_string(&s.b, " elems[")
            strings.write_uint(&s.b, uint(length))
            strings.write_string(&s.b, "];};")
        } else {
            strings.write_string(&s.b, "{uint64_t length;")
            emit_type(&s, "", array_type.item_type)
            strings.write_string(&s.b, "* elems;};")
        }
    }

    emitted_generic_type_defs := map[u64]struct{}{}
    for _, i in c.types.values {
        tv := c.types.values[i].value
        gen_value, ok := tv.(GenericTypeValue)
        if !ok || !gen_value.is_initialised {
            continue
        }
        new_key := combine_u32(gen_value.generic_type_index, u32(gen_value.generic_arg.index))
        _, emitted := emitted_generic_type_defs[new_key]
        if emitted {
            continue
        }
        emitted_generic_type_defs[new_key] = struct{}{}
        name := fmt.aprintf(
            generic_name_format,
            gen_value.generic_type_index,
            gen_value.generic_arg.index,
        )
        defer delete(name)
        emit_c_global_type(&s, name, gen_value.initialised_type)
    }

    for func, index in c.checked_funcs {
        emit_function_head(&s, index, func.type)
        strings.write_byte(&s.b, ';')
    }

    for func, index in c.checked_funcs {
        emit_function_head(&s, index, func.type)
        strings.write_byte(&s.b, '{')
        emit_c_block(&s, 1, func.variables, func.body)
        strings.write_byte(&s.b, '}')
    }

    strings.write_string(&s.b, "int main() {int ret = func")
    strings.write_uint(&s.b, main_func_ref.index)
    strings.write_string(&s.b, "();")
    strings.write_string(&s.b, main_extra_code)
    strings.write_string(&s.b, "return ret;}")
    return transmute([]byte)strings.to_string(s.b)
}

