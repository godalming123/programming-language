package main

import "core:fmt"
import "core:strings"

EmitterState :: struct {
    b:             strings.Builder,
    generic_types: []EquivalencyArrayElem(GenericType),
    array_types:   []EquivalencyArrayElem(ArrayType),
}

emit_variable :: proc(b: ^strings.Builder, variable: VariableRef) {
    strings.write_string(b, "nesting_level")
    strings.write_uint(b, variable.nesting_level)
    strings.write_string(b, "index")
    strings.write_uint(b, variable.index)
}

// Does not include the `struct`
emit_struct_type :: proc(s: ^EmitterState, type: CheckedStructType, loc := #caller_location) {
    when debug_emitter {
        print_call(loc, "emit_struct_type")
    }
    strings.write_byte(&s.b, '{')
    for field, index in type.fields {
        emit_type(s, field.type)
        strings.write_string(&s.b, " field")
        strings.write_int(&s.b, index)
        strings.write_byte(&s.b, ';')
    }
    strings.write_byte(&s.b, '}')
}

emit_sum_variant :: proc(s: ^EmitterState, sum_type: CheckedType, variant_index: uint) {
    #partial switch type in sum_type {
    case CheckedSumType:
        panic(
            "TODO: Handle inline sum types in checker so that C emitter does not have to emit them",
        )
    case GenericTypeRef:
        strings.write_string(&s.b, "struct Generic")
        _, generic_index := get_info(s.generic_types, type.generic_type_index)
        strings.write_uint(&s.b, generic_index)
        strings.write_string(&s.b, "Variant")
        strings.write_uint(&s.b, variant_index)
    case TypeRef:
        strings.write_string(&s.b, "Global")
        strings.write_uint(&s.b, uint(type))
        strings.write_string(&s.b, "Variant")
        strings.write_uint(&s.b, variant_index)
    case:
        panic("Unreahcable")
    }
}

emit_type :: proc(s: ^EmitterState, type: CheckedType, loc := #caller_location) {
    when debug_emitter {
        print_call(loc, "emit_type")
        print_arg("type", type)
    }
    switch &t in type {
    case:
        panic(fmt.aprintf("Unreachable (type was %v)", type))
    case TypeOfGenericArg, GenericTypeWhereArgIsTypeOfGenericArg:
        panic(fmt.aprintf("Unreachable (type was %v)", type))
    case CheckedSumType:
        panic("TODO: Emit inline checked sum type for C emitter")
    case FuncType:
        panic("TODO: Emit function type for C emitter")
    case TypeRef:
        panic("TODO: Emit type ref for C emitter")
    case GenericTypeRef:
        strings.write_string(&s.b, "struct Generic")
        _, index := get_info(s.generic_types, t.generic_type_index)
        strings.write_uint(&s.b, index)
    case SumVariant:
        emit_sum_variant(s, t.sum_type^, t.variant_index)
    case CheckedStructType:
        strings.write_string(&s.b, "struct")
        emit_struct_type(s, t)
    case BoolType:
        strings.write_string(&s.b, "bool")
    case StringType:
        strings.write_string(&s.b, "char*")
    case I64Type:
        strings.write_string(&s.b, "int64_t")
    case I32Type:
        strings.write_string(&s.b, "int32_t")
    case I16Type:
        strings.write_string(&s.b, "int16_t")
    case I8Type:
        strings.write_string(&s.b, "int8_t")
    case U64Type:
        strings.write_string(&s.b, "uint64_t")
    case U32Type:
        strings.write_string(&s.b, "uint32_t")
    case U16Type:
        strings.write_string(&s.b, "uint16_t")
    case U8Type:
        strings.write_string(&s.b, "uint8_t")
    case ArrayRef:
        _, t_index := get_info(s.array_types, uint(t))
        strings.write_string(&s.b, "Array")
        strings.write_uint(&s.b, t_index)
    }
}

emit_func_call :: proc(b: ^strings.Builder, c: CheckedFunctionCall) {
    strings.write_string(b, "func")
    strings.write_uint(b, c.index)
    strings.write_byte(b, '(')
    for arg, i in c.args {
        emit_value(b, arg)
        if i + 1 < len(c.args) {
            strings.write_byte(b, ',')
        }
    }
    strings.write_byte(b, ')')
}

emit_value :: proc(b: ^strings.Builder, v: CheckedValue) {
    strings.write_byte(b, '(')
    switch value in v {
    case uint:
        strings.write_string(b, "&func")
        strings.write_uint(b, value)
    case CheckedFieldAccess:
        emit_value(b, value.value^)
        strings.write_string(b, ".field")
        strings.write_uint(b, value.field_index)
    //case CheckedJsFunctionCall:
    //    panic("Internal error: JsFunctionCall received by C emitter")
    //case ArrayValue:
    //    panic("Internal error: Unexpected array value")
    case LengthOfArray:
        emit_value(b, value.array^)
        strings.write_string(b, ".length")
    case CheckedArrayAccess:
        emit_value(b, value.array^)
        strings.write_string(b, ".elems[")
        emit_value(b, value.index^)
        strings.write_byte(b, ']')
    case BoolValue:
        if value {
            strings.write_string(b, "true")
        } else {
            strings.write_string(b, "false")
        }
    case CheckedFunctionCall:
        emit_func_call(b, value)
    case StringLiteralValue:
        strings.write_byte(b, '"')
        strings.write_string(b, string(value))
        strings.write_byte(b, '"')
    case I64Value:
        strings.write_i64(b, i64(value))
    case U8Value:
        strings.write_uint(b, uint(value))
    case BooleanNotValue:
        strings.write_byte(b, '!')
        emit_value(b, value)
    case CheckedJoinedValues:
        emit_value(b, value.val0^)
        switch value.join_method {
        case .BooleanAnd:
            strings.write_string(b, "&&")
        case .BooleanOr:
            strings.write_string(b, "||")
        case .IsEqual:
            strings.write_string(b, "==")
        case .IsNotEqual:
            strings.write_string(b, "!=")
        case .IsGreaterThan:
            strings.write_byte(b, '>')
        case .IsGreaterThanOrEqual:
            strings.write_string(b, ">=")
        case .IsLessThan:
            strings.write_byte(b, '<')
        case .IsLessThanOrEqual:
            strings.write_string(b, "<=")
        case .Addition:
            strings.write_byte(b, '+')
        case .Subtraction:
            strings.write_byte(b, '-')
        case .Multiplication:
            strings.write_byte(b, '*')
        case .Division:
            strings.write_byte(b, '/')
        case .Modulo:
            strings.write_byte(b, '%')
        }
        emit_value(b, value.val1^)
    case VariableRef:
        emit_variable(b, value)
    }
    strings.write_byte(b, ')')
}

emit_block_head :: proc(
    s: ^EmitterState,
    nesting_level: uint,
    variables: []CheckedType,
    loc := #caller_location,
) {
    when debug_emitter {
        print_call(loc, "emit_block_head")
    }
    for type, index in variables {
        emit_type(s, type)
        strings.write_byte(&s.b, ' ')
        emit_variable(&s.b, VariableRef{nesting_level, uint(index)})
        strings.write_byte(&s.b, ';')
    }
}

emit_block_body :: proc(
    s: ^EmitterState,
    nesting_level: uint,
    body: []CheckedStatement,
    loc := #caller_location,
) {
    when debug_emitter {
        print_call(loc, "emit_block_body")
    }
    for statement in body {
        switch stmt in statement {
        //case CheckedJsFunctionCall, CheckedJsAssignment:
        //    panic("Internal error: JS received by C emitter")
        case CheckedFunctionCall:
            emit_func_call(&s.b, stmt)
            strings.write_byte(&s.b, ';')
        case CheckedReturn:
            strings.write_string(&s.b, "return ")
            emit_value(&s.b, stmt.value)
            strings.write_byte(&s.b, ';')
        case CheckedIf:
            strings.write_string(&s.b, "if ")
            emit_value(&s.b, stmt.condition)
            strings.write_byte(&s.b, '{')
            emit_block(s, nesting_level + 1, stmt.if_block.variables, stmt.if_block.body)
            strings.write_string(&s.b, "} else {")
            emit_block(s, nesting_level + 1, stmt.else_block.variables, stmt.else_block.body)
            strings.write_byte(&s.b, '}')
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
                emit_value(&s.b, field)
                strings.write_byte(&s.b, ';')
            }
        case CheckedMatch:
            strings.write_string(&s.b, "switch (")
            emit_variable(&s.b, stmt.value)
            strings.write_string(&s.b, ".variant) {")
            for branch, i in stmt.branches {
                strings.write_string(&s.b, "case ")
                strings.write_int(&s.b, i)
                strings.write_string(&s.b, ": {")
                emit_block_head(s, nesting_level + 1, branch.block.variables)
                emit_variable(&s.b, branch.value_var)
                strings.write_string(&s.b, " = *")
                emit_variable(&s.b, stmt.value)
                strings.write_string(&s.b, ".payload.variant")
                strings.write_int(&s.b, i)
                strings.write_byte(&s.b, ';')
                emit_block_body(s, nesting_level + 1, branch.block.body)
                strings.write_string(&s.b, "break;}")
            }
            strings.write_string(&s.b, "}")
        case CheckedLoop:
            strings.write_byte(&s.b, '{')
            emit_block(s, nesting_level + 1, stmt.variables, stmt.enter)
            strings.write_string(&s.b, "while (1) {")
            strings.write_string(&s.b, "loop")
            strings.write_uint(&s.b, stmt.loop_index)
            strings.write_string(&s.b, "start:")
            emit_block(s, nesting_level + 1, nil, stmt.body)
            strings.write_string(&s.b, "}}loop")
            strings.write_uint(&s.b, stmt.loop_index)
            strings.write_string(&s.b, "end:;")
        case CheckedPrint:
            strings.write_string(&s.b, "printf(\"%s\",")
            emit_value(&s.b, CheckedValue(stmt))
            strings.write_string(&s.b, ");")
        case ContinueLoop:
            strings.write_string(&s.b, "goto loop")
            strings.write_uint(&s.b, stmt.loop_index)
            strings.write_string(&s.b, "start;")
        case BreakLoop:
            strings.write_string(&s.b, "goto loop")
            strings.write_uint(&s.b, stmt.loop_index)
            strings.write_string(&s.b, "end;")
        case CheckedWriteFile:
            strings.write_string(&s.b, "compiler_write_file(")
            emit_value(&s.b, stmt.file_name)
            strings.write_byte(&s.b, ',')
            emit_value(&s.b, stmt.file_contents)
            strings.write_string(&s.b, ");")
        case StringInterpolation:
            strings.write_string(&s.b, "asprintf(&")
            emit_variable(&s.b, stmt.variable)
            strings.write_byte(&s.b, ',')
            strings.write_string(&s.b, stmt.format)
            for elem in stmt.values {
                strings.write_byte(&s.b, ',')
                emit_value(&s.b, elem)
            }
            strings.write_string(&s.b, ");")
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
                        emit_value(&s.b, segment_value.array_length)
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
                emit_type(s, stmt.variable_type.item_type)
                strings.write_string(&s.b, "));")
            }
            strings.write_string(&s.b, "{uint64_t index = 0;")
            for segment in stmt.segments {
                switch segment_value in segment {
                case SingleElemSegment:
                    emit_variable(&s.b, stmt.variable)
                    strings.write_string(&s.b, ".elems[index] = ")
                    emit_value(&s.b, segment_value.elem)
                    strings.write_string(&s.b, "; index += 1;")
                case InlineArraySegment:
                    strings.write_string(&s.b, "{uint64_t index2 = 0; while (index2 < ")
                    emit_value(&s.b, segment_value.array_length)
                    strings.write_string(&s.b, ") {")
                    emit_variable(&s.b, stmt.variable)
                    strings.write_string(&s.b, ".elems[index+index2] = ")
                    emit_value(&s.b, segment_value.array)
                    strings.write_string(&s.b, ".elems[index2];index2 += 1;}index += index2;}")
                }
            }
            strings.write_byte(&s.b, '}')
        case CheckedMutation:
            emit_variable(&s.b, stmt.destination.variable)
            if stmt.destination.index != nil {
                strings.write_string(&s.b, ".elems[")
                emit_value(&s.b, stmt.destination.index)
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
            emit_value(&s.b, stmt.value)
            strings.write_byte(&s.b, ';')
        }
    }
}

emit_block :: proc(
    s: ^EmitterState,
    nesting_level: uint,
    variables: []CheckedType,
    body: []CheckedStatement,
    loc := #caller_location,
) {
    when debug_emitter {
        print_call(loc, "emit_block")
    }
    emit_block_head(s, nesting_level, variables)
    emit_block_body(s, nesting_level, body)
}

emit_generic_type_def :: proc(
    s: ^EmitterState,
    generic: GenericType,
    index: int,
    loc := #caller_location,
) {
    when debug_emitter {
        print_call(loc, "emit_generic_type_def")
        print_arg("generic", generic)
        print_arg("index", index)
    }
    sum_type, is_sum_type := generic.type.(CheckedSumType)
    if is_sum_type {
        strings.write_string(&s.b, "struct Generic")
        strings.write_int(&s.b, index)
        strings.write_string(&s.b, "{uint64_t variant; union {")
        for variant, i in sum_type.variants {
            strings.write_string(&s.b, "struct Generic")
            strings.write_int(&s.b, index)
            strings.write_string(&s.b, "Variant")
            strings.write_int(&s.b, i)
            strings.write_string(&s.b, "* variant")
            strings.write_int(&s.b, i)
            strings.write_byte(&s.b, ';')
        }
        strings.write_string(&s.b, "} payload;};")
        for variant, i in sum_type.variants {
            strings.write_string(&s.b, "struct Generic")
            strings.write_int(&s.b, index)
            strings.write_string(&s.b, "Variant")
            strings.write_int(&s.b, i)
            emit_struct_type(s, variant.payload)
            strings.write_byte(&s.b, ';')
        }
    } else {
        strings.write_string(&s.b, "typedef ")
        emit_type(s, generic.type)
        strings.write_string(&s.b, " Generic")
        strings.write_int(&s.b, index)
        strings.write_byte(&s.b, ';')
    }
}

emit_c :: proc(
    code: []CheckedFunction,
    checked_global_types: []CheckedType,
    generic_types: []EquivalencyArrayElem(GenericType),
    array_types: []EquivalencyArrayElem(ArrayType),
    main_func_index: uint,
) -> []byte {
    s := EmitterState{strings.builder_make(), generic_types, array_types}
    strings.write_string(
        &s.b,
        "#include <stdint.h>\n" +
        "#include <stdlib.h>\n" +
        "#include <stdio.h>\n" +
        "#include <inttypes.h>\n" +
        "#include <stdbool.h>\n" +
        "void compiler_write_file(char* name, char* text) {" +
        "  FILE* file_pointer = fopen(name, \"w\");" +
        "  if (file_pointer == 0) {" +
        "    printf(\"Failed to read file called `%s`\", name);" +
        "    exit(1);" +
        "  }" +
        "  fputs(text, file_pointer);" +
        "  fclose(file_pointer);" +
        "}",
    )

    for type, index in generic_types {
        generic, is_generic_type := type.(GenericType)
        if !is_generic_type {continue}
        if generic.type == nil {continue}
        emit_generic_type_def(&s, generic, index)
    }

    for type, index in array_types {
        array_type, is_array_type := type.(ArrayType)
        if !is_array_type {continue}
        strings.write_string(&s.b, "typedef ")
        if array_type.length != 0 {
            strings.write_string(&s.b, "struct {")
            emit_type(&s, array_type.item_type)
            strings.write_string(&s.b, " elems[")
            strings.write_uint(&s.b, array_type.length)
            strings.write_string(&s.b, "];}")
        } else {
            strings.write_string(&s.b, "struct {uint64_t length;")
            emit_type(&s, array_type.item_type)
            strings.write_string(&s.b, "* elems;}")
        }
        strings.write_string(&s.b, " Array")
        strings.write_int(&s.b, index)
        strings.write_byte(&s.b, ';')
    }

    for func, index in code {
        if func.output != nil {
            emit_type(&s, func.output)
        } else {
            strings.write_string(&s.b, "void")
        }
        strings.write_string(&s.b, " func")
        strings.write_int(&s.b, index)
        strings.write_byte(&s.b, '(')
        for arg, i in func.inputs {
            emit_type(&s, arg)
            strings.write_byte(&s.b, ' ')
            emit_variable(&s.b, VariableRef{0, uint(i)})
            if i + 1 < len(func.inputs) {
                strings.write_byte(&s.b, ',')
            }
        }
        strings.write_string(&s.b, ") {")
        emit_block(&s, 1, func.variables, func.body)
        strings.write_byte(&s.b, '}')
    }
    strings.write_string(&s.b, "int main() {return func")
    strings.write_uint(&s.b, main_func_index)
    strings.write_string(&s.b, "();}")
    return transmute([]byte)strings.to_string(s.b)
}

