package main

import "core:fmt"
import "core:strings"

GeneralEmitterState :: struct {
    b:     strings.Builder,
    types: Types,
    c:     Checked,
}

CEmitterState :: struct {
    forward_struct_definitions:    strings.Builder, // Several `typedef struct TypeStruct Type;`
    sum_type_definitions:          strings.Builder,
    other_type_definitions:        strings.Builder,
    sum_type_initialisation_funcs: strings.Builder,
    using s:                       GeneralEmitterState,
}

variable_format :: "nesting_level%dindex%d"

emit_variable :: proc(b: ^strings.Builder, variable: VariableRef) {
    var := fmt.aprintf(variable_format, variable.nesting_level, variable.index)
    strings.write_string(b, var)
    delete_string(var)
}

// Does not include the `struct`
emit_struct_type :: proc(b: ^strings.Builder, type: Struct(Type, Type), loc := #caller_location) {
    when debug_emitter {
        print_call(loc, "emit_struct_type")
    }
    strings.write_byte(b, '{')
    for field, index in type.fields {
        name := fmt.aprintf("field%d", index)
        emit_type(b, name, field.type)
        delete_string(name)
        strings.write_byte(b, ';')
    }
    strings.write_byte(b, '}')
}

emit_type :: proc(b: ^strings.Builder, name: string, type: Type) {
    switch type {
    case bool_type:
        strings.write_string(b, "bool")
    case string_type:
        strings.write_string(b, "char*")
    case i64_type:
        strings.write_string(b, "int64_t")
    case i32_type:
        strings.write_string(b, "int32_t")
    case i16_type:
        strings.write_string(b, "int16_t")
    case i8_type:
        strings.write_string(b, "int8_t")
    case u64_type:
        strings.write_string(b, "uint64_t")
    case u32_type:
        strings.write_string(b, "uint32_t")
    case u16_type:
        strings.write_string(b, "uint16_t")
    case u8_type:
        strings.write_string(b, "uint8_t")
    case:
        strings.write_string(b, "Type")
        strings.write_uint(b, uint(type.index))
    }
    strings.write_byte(b, ' ')
    strings.write_string(b, name)
}

emit_c_func_call :: proc(s: ^CEmitterState, c: CheckedFunctionCall) {
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

emit_c_value :: proc(s: ^CEmitterState, v: CheckedValue) {
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
        case Type:
            panic("Unreachable")
        case GlobalTypeWithGenericRef:
            panic("Unreachable")
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
    case StructTypeInitFunc:
        strings.write_string(&s.b, "init_Type")
        strings.write_uint(&s.b, uint(value.type.index))
    case SumTypeInitFunc:
        strings.write_string(&s.b, "init_Type")
        strings.write_uint(&s.b, uint(value.sum_type.index))
        strings.write_string(&s.b, "Variant")
        strings.write_uint(&s.b, uint(value.variant_index))
    case BooleanNotValue:
        strings.write_byte(&s.b, '(')
        strings.write_byte(&s.b, '!')
        emit_c_value(s, value^)
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
    s: ^CEmitterState,
    nesting_level: uint,
    variables: []Type,
    loc := #caller_location,
) {
    when debug_emitter {
        print_call(loc, "emit_c_block_head")
    }
    for type, index in variables {
        name := fmt.aprintf(variable_format, nesting_level, index)
        emit_type(&s.b, name, type)
        delete_string(name)
        strings.write_byte(&s.b, ';')
    }
}

emit_c_block_body :: proc(
    s: ^CEmitterState,
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
                emit_type(&s.b, "", stmt.variable_type.item_type)
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
    s: ^CEmitterState,
    nesting_level: uint,
    variables: []Type,
    body: []CheckedStatement,
    loc := #caller_location,
) {
    when debug_emitter {
        print_call(loc, "emit_c_block")
    }
    emit_c_block_head(s, nesting_level, variables)
    emit_c_block_body(s, nesting_level, body)
}

emit_c_global_type :: proc(s: ^CEmitterState, index: int, loc := #caller_location) {
    when debug_emitter {
        print_call(loc, "emit_c_global_type")
    }
    name := fmt.aprintf("Type%d", index)
    defer delete(name)
    switch type in s.types.values[index].value.value {
    case ArrayType:
        strings.write_string(&s.other_type_definitions, "struct ")
        strings.write_string(&s.other_type_definitions, name)
        strings.write_string(&s.other_type_definitions, "Struct")
        if type.length != 0 {
            strings.write_byte(&s.other_type_definitions, '{')
            emit_type(&s.other_type_definitions, "", type.item_type)
            strings.write_string(&s.other_type_definitions, " elems[")
            strings.write_uint(&s.other_type_definitions, uint(type.length))
            strings.write_string(&s.other_type_definitions, "];};")
        } else {
            strings.write_string(&s.other_type_definitions, "{uint64_t length;")
            emit_type(&s.other_type_definitions, "", type.item_type)
            strings.write_string(&s.other_type_definitions, "* elems;};")
        }
        strings.write_string(&s.forward_struct_definitions, "typedef struct ")
        strings.write_string(&s.forward_struct_definitions, name)
        strings.write_string(&s.forward_struct_definitions, "Struct ")
        strings.write_string(&s.forward_struct_definitions, name)
        strings.write_byte(&s.forward_struct_definitions, ';')
    case FuncType:
        strings.write_string(&s.other_type_definitions, "typedef ")
        switch len(type.return_types) {
        case 0:
            strings.write_string(&s.other_type_definitions, "void")
        case 1:
            emit_type(&s.other_type_definitions, "", type.return_types[0])
        case:
            panic("TODO")
        }
        strings.write_string(&s.other_type_definitions, " (*")
        strings.write_string(&s.other_type_definitions, name)
        strings.write_string(&s.other_type_definitions, ")(")
        is_first_arg := true
        for arg, i in type.args {
            if !is_first_arg {
                strings.write_byte(&s.other_type_definitions, ',')
            }
            name := fmt.aprintf("arg%d", i)
            defer delete(name)
            emit_type(&s.other_type_definitions, name, arg)
            is_first_arg = false
        }
        strings.write_string(&s.other_type_definitions, ");")
    case GenericTypeValue:
        strings.write_string(&s.other_type_definitions, "typedef ")
        emit_type(&s.other_type_definitions, name, type.initialised_type)
        strings.write_byte(&s.other_type_definitions, ';')
    case SumType(Type):
        // Main struct type
        strings.write_string(&s.sum_type_definitions, "struct ")
        strings.write_string(&s.sum_type_definitions, name)
        strings.write_string(&s.sum_type_definitions, "Struct{uint64_t variant; union {")
        for variant, i in type.variants {
            strings.write_string(&s.sum_type_definitions, "Type")
            strings.write_uint(&s.sum_type_definitions, uint(variant.payload.index))
            strings.write_string(&s.sum_type_definitions, "* variant")
            strings.write_int(&s.sum_type_definitions, i)
            strings.write_byte(&s.sum_type_definitions, ';')
        }
        strings.write_string(&s.sum_type_definitions, "} payload;};")

        // Type def
        strings.write_string(&s.forward_struct_definitions, "typedef struct ")
        strings.write_string(&s.forward_struct_definitions, name)
        strings.write_string(&s.forward_struct_definitions, "Struct ")
        strings.write_string(&s.forward_struct_definitions, name)
        strings.write_byte(&s.forward_struct_definitions, ';')

        // Variant funcs
        for variant, i in type.variants {
            payload := get_type(s.types, variant.payload).(Struct(Type, Type))
            strings.write_string(&s.sum_type_initialisation_funcs, name)
            strings.write_string(&s.sum_type_initialisation_funcs, " init_")
            strings.write_string(&s.sum_type_initialisation_funcs, name)
            strings.write_string(&s.sum_type_initialisation_funcs, "Variant")
            strings.write_int(&s.sum_type_initialisation_funcs, i)
            strings.write_byte(&s.sum_type_initialisation_funcs, '(')
            first_arg := true
            for field, j in payload.fields {
                if !first_arg {
                    strings.write_byte(&s.sum_type_initialisation_funcs, ',')
                }
                first_arg = false
                field_name := fmt.aprintf("field%d", j)
                defer delete_string(field_name)
                emit_type(&s.sum_type_initialisation_funcs, field_name, field.type)
            }
            strings.write_string(&s.sum_type_initialisation_funcs, ") {")
            strings.write_string(&s.sum_type_initialisation_funcs, name)
            strings.write_string(&s.sum_type_initialisation_funcs, " out;out.variant = ")
            strings.write_int(&s.sum_type_initialisation_funcs, i)
            strings.write_string(&s.sum_type_initialisation_funcs, "; out.payload.variant")
            strings.write_int(&s.sum_type_initialisation_funcs, i)
            strings.write_string(&s.sum_type_initialisation_funcs, " = malloc(sizeof(Type")
            strings.write_uint(&s.sum_type_initialisation_funcs, uint(variant.payload.index))
            strings.write_string(&s.sum_type_initialisation_funcs, "));")
            strings.write_string(&s.sum_type_initialisation_funcs, "*out.payload.variant")
            strings.write_int(&s.sum_type_initialisation_funcs, i)
            strings.write_string(&s.sum_type_initialisation_funcs, " = init_Type")
            strings.write_uint(&s.sum_type_initialisation_funcs, uint(variant.payload.index))
            strings.write_string(&s.sum_type_initialisation_funcs, "(")
            first_arg = true
            for _, j in payload.fields {
                if !first_arg {
                    strings.write_byte(&s.sum_type_initialisation_funcs, ',')
                }
                first_arg = false
                strings.write_string(&s.sum_type_initialisation_funcs, "field")
                strings.write_int(&s.sum_type_initialisation_funcs, j)
            }
            strings.write_string(&s.sum_type_initialisation_funcs, ");return out;}")
        }
    case Struct(Type, Type):
        // Type def
        strings.write_string(&s.forward_struct_definitions, "typedef struct ")
        strings.write_string(&s.forward_struct_definitions, name)
        strings.write_string(&s.forward_struct_definitions, "Struct ")
        strings.write_string(&s.forward_struct_definitions, name)
        strings.write_byte(&s.forward_struct_definitions, ';')

        // Struct def
        strings.write_string(&s.other_type_definitions, "struct ")
        strings.write_string(&s.other_type_definitions, name)
        strings.write_string(&s.other_type_definitions, "Struct")
        emit_struct_type(&s.other_type_definitions, type)
        strings.write_byte(&s.other_type_definitions, ';')
        strings.write_string(&s.other_type_definitions, name)
        strings.write_string(&s.other_type_definitions, " init_")
        strings.write_string(&s.other_type_definitions, name)
        strings.write_byte(&s.other_type_definitions, '(')
        first_field := true
        for field, i in type.fields {
            if first_field == false {
                strings.write_byte(&s.other_type_definitions, ',')
            } else {
                first_field = false
            }
            field_name := fmt.aprintf("field%d", i)
            defer delete(field_name)
            emit_type(&s.other_type_definitions, field_name, field.type)
        }
        strings.write_string(&s.other_type_definitions, ") {")
        strings.write_string(&s.other_type_definitions, name)
        strings.write_string(&s.other_type_definitions, " out;")
        for _, i in type.fields {
            strings.write_string(&s.other_type_definitions, "out.field")
            strings.write_int(&s.other_type_definitions, i)
            strings.write_string(&s.other_type_definitions, "=field")
            strings.write_int(&s.other_type_definitions, i)
            strings.write_byte(&s.other_type_definitions, ';')
        }
        strings.write_string(&s.other_type_definitions, "return out;}")
    }
}

emit_function_head :: proc(s: ^CEmitterState, func_index: int, type: Type) {
    when debug_emitter {
        debug("emitting function index %d", func_index)
    }
    info := get_type(s.types, type).(FuncType)
    switch len(info.return_types) {
    case 0:
        strings.write_string(&s.b, "void")
    case 1:
        emit_type(&s.b, "", info.return_types[0])
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
        emit_type(&s.b, name, arg)
        delete_string(name)
        first_arg = false
    }
    strings.write_byte(&s.b, ')')
}

emit_c :: proc(c: Checked, main_func_ref: FuncDefinitionRef, main_extra_code: string) -> []byte {
    s := CEmitterState {
        strings.builder_make(),
        strings.builder_make(),
        strings.builder_make(),
        strings.builder_make(),
        GeneralEmitterState{strings.builder_make(), c.types, c},
    }

    for _, i in c.types.values {
        emit_c_global_type(&s, i)
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

    out := strings.builder_make()
    strings.write_bytes(&out, #load("glue.c"))
    strings.write_string(&out, strings.to_string(s.forward_struct_definitions))
    strings.write_string(&out, strings.to_string(s.sum_type_definitions))
    strings.write_string(&out, strings.to_string(s.other_type_definitions))
    strings.write_string(&out, strings.to_string(s.sum_type_initialisation_funcs))
    strings.write_string(&out, strings.to_string(s.b))

    strings.builder_destroy(&s.forward_struct_definitions)
    strings.builder_destroy(&s.sum_type_definitions)
    strings.builder_destroy(&s.other_type_definitions)
    strings.builder_destroy(&s.sum_type_initialisation_funcs)
    strings.builder_destroy(&s.b)

    return transmute([]byte)strings.to_string(out)
}

