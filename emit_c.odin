package main

import "core:strings"

EmitterState :: struct {
    b:           strings.Builder,
    array_types: []union {
        ArrayType,
        ArrayRef,
    },
}

emit_variable :: proc(b: ^strings.Builder, nesting_level: uint, index: uint) {
    strings.write_string(b, "nesting_level")
    strings.write_uint(b, nesting_level)
    strings.write_string(b, "index")
    strings.write_uint(b, index)
}

emit_type :: proc(s: ^EmitterState, type: CheckedType) {
    switch &t in type {
    case FuncType:
        panic("TODO: Emit function type for C emitter")
    //case JsObjectType:
    //    panic("Internal error: JS object type received by c emitter")
    case nil:
        strings.write_string(&s.b, "void")
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
        simplify_array_ref(s.array_types, &t)
        strings.write_string(&s.b, "Array")
        strings.write_uint(&s.b, uint(t))
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
        emit_variable(b, value.nesting_level, value.index)
    }
    strings.write_byte(b, ')')
}

emit_block :: proc(
    s: ^EmitterState,
    nesting_level: uint,
    variables: []CheckedType,
    body: []CheckedStatement,
) {
    for type, index in variables {
        emit_type(s, type)
        strings.write_byte(&s.b, ' ')
        emit_variable(&s.b, nesting_level, uint(index))
        strings.write_byte(&s.b, ';')
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
            strings.write_string(&s.b, "printf(")
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
            emit_variable(&s.b, stmt.variable.nesting_level, stmt.variable.index)
            strings.write_byte(&s.b, ',')
            strings.write_string(&s.b, stmt.format)
            for elem in stmt.values {
                strings.write_byte(&s.b, ',')
                emit_value(&s.b, elem)
            }
            strings.write_string(&s.b, ");")
        case CheckedArrayMutation:
            if stmt.variable_type.length == 0 {
                emit_variable(&s.b, stmt.variable.nesting_level, stmt.variable.index)
                strings.write_string(&s.b, ".length = 0;")
                number_of_single_elem_segments := 0
                for segment in stmt.segments {
                    switch segment_value in segment {
                    case SingleElemSegment:
                        number_of_single_elem_segments += 1
                    case InlineArraySegment:
                        emit_variable(&s.b, stmt.variable.nesting_level, stmt.variable.index)
                        strings.write_string(&s.b, ".length += ")
                        emit_value(&s.b, segment_value.array_length)
                        strings.write_byte(&s.b, ';')
                    }
                }
                if number_of_single_elem_segments > 0 {
                    emit_variable(&s.b, stmt.variable.nesting_level, stmt.variable.index)
                    strings.write_string(&s.b, ".length += ")
                    strings.write_int(&s.b, number_of_single_elem_segments)
                    strings.write_byte(&s.b, ';')
                }
                emit_variable(&s.b, stmt.variable.nesting_level, stmt.variable.index)
                strings.write_string(&s.b, ".elems = malloc(")
                emit_variable(&s.b, stmt.variable.nesting_level, stmt.variable.index)
                strings.write_string(&s.b, ".length * sizeof(")
                emit_type(s, stmt.variable_type.item_type)
                strings.write_string(&s.b, "));")
            }
            strings.write_string(&s.b, "{uint64_t index = 0;")
            for segment in stmt.segments {
                switch segment_value in segment {
                case SingleElemSegment:
                    emit_variable(&s.b, stmt.variable.nesting_level, stmt.variable.index)
                    strings.write_string(&s.b, ".elems[index] = ")
                    emit_value(&s.b, segment_value.elem)
                    strings.write_string(&s.b, "; index += 1;")
                case InlineArraySegment:
                    strings.write_string(&s.b, "{uint64_t index2 = 0; while (index2 < ")
                    emit_value(&s.b, segment_value.array_length)
                    strings.write_string(&s.b, ") {")
                    emit_variable(&s.b, stmt.variable.nesting_level, stmt.variable.index)
                    strings.write_string(&s.b, ".elems[index+index2] = ")
                    emit_value(&s.b, segment_value.array)
                    strings.write_string(&s.b, ".elems[index2];index2 += 1;}index += index2;}")
                }
            }
            strings.write_byte(&s.b, '}')
        case CheckedMutation:
            emit_variable(
                &s.b,
                stmt.destination.variable.nesting_level,
                stmt.destination.variable.index,
            )
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

emit_c :: proc(code: []CheckedFunction, array_types: []union {
        ArrayType,
        ArrayRef,
    }, main_func_index: uint) -> []byte {
    s := EmitterState{strings.builder_make(), array_types}
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
        emit_type(&s, func.output)
        strings.write_string(&s.b, " func")
        strings.write_int(&s.b, index)
        strings.write_byte(&s.b, '(')
        for arg, i in func.inputs {
            emit_type(&s, arg)
            strings.write_byte(&s.b, ' ')
            emit_variable(&s.b, 0, uint(i))
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

