package main

import "core:strings"

emit_variable :: proc(b: ^strings.Builder, nesting_level: uint, index: uint) {
    strings.write_string(b, "nesting_level")
    strings.write_uint(b, nesting_level)
    strings.write_string(b, "index")
    strings.write_uint(b, index)
}

emit_type :: proc(b: ^strings.Builder, type: CheckedType) {
    switch _ in type {
    case BoolType:
        strings.write_string(b, "bool")
    case StringType:
        strings.write_string(b, "[]char")
    case I64Type:
        strings.write_string(b, "int64_t")
    }
}

emit_value :: proc(b: ^strings.Builder, v: CheckedValue) {
    strings.write_byte(b, '(')
    switch value in v {
    case StringValue:
        strings.write_byte(b, '"')
        strings.write_string(b, string(value))
        strings.write_byte(b, '"')
    case I64Value:
        strings.write_string(b, string(value))
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
    case VariableValue:
        emit_variable(b, value.nesting_level, value.index)
    }
    strings.write_byte(b, ')')
}

emit_block :: proc(
    b: ^strings.Builder,
    nesting_level: uint,
    variables: []CheckedType,
    body: []CheckedStatement,
) {
    for type, index in variables {
        emit_type(b, type)
        strings.write_byte(b, ' ')
        emit_variable(b, nesting_level, uint(index))
        strings.write_byte(b, ';')
    }
    for statement in body {
        switch stmt in statement {
        case CheckedReturn:
            strings.write_string(b, "return ")
            emit_value(b, stmt.value)
            strings.write_byte(b, ';')
        case CheckedIf:
            strings.write_string(b, "if ")
            emit_value(b, stmt.condition)
            strings.write_byte(b, '{')
            emit_block(b, nesting_level + 1, stmt.if_block.variables, stmt.if_block.body)
            strings.write_string(b, "} else {")
            emit_block(b, nesting_level + 1, stmt.else_block.variables, stmt.else_block.body)
            strings.write_byte(b, '}')
        case CheckedLoop:
            strings.write_byte(b, '{')
            emit_block(b, nesting_level + 1, stmt.variables, stmt.enter)
            strings.write_string(b, "while (1) {")
            strings.write_string(b, "loop")
            strings.write_uint(b, nesting_level + 1)
            strings.write_string(b, "start:")
            emit_block(b, nesting_level + 1, nil, stmt.body)
            strings.write_string(b, "}}loop")
            strings.write_uint(b, nesting_level + 1)
            strings.write_string(b, "end:;")
        case CheckedPrint:
            strings.write_string(b, "printf(")
            strings.write_string(b, stmt.format)
            for value in stmt.values {
                strings.write_byte(b, ',')
                emit_value(b, value)
            }
            strings.write_string(b, ");")
        case ContinueLoop:
            strings.write_string(b, "goto loop")
            strings.write_uint(b, stmt.block_nesting_level)
            strings.write_string(b, "start;")
        case BreakLoop:
            strings.write_string(b, "goto loop")
            strings.write_uint(b, stmt.block_nesting_level)
            strings.write_string(b, "end;")
        case CheckedSingleVariableMutation:
            emit_variable(b, stmt.variable.nesting_level, stmt.variable.index)
            switch stmt.mutation_type {
            case .SetTo:
                strings.write_byte(b, '=')
            case .Increment:
                strings.write_string(b, "+=")
            case .Decrement:
                strings.write_string(b, "-=")
            case .MultiplyBy:
                strings.write_string(b, "*=")
            case .DivideBy:
                strings.write_string(b, "/=")
            }
            emit_value(b, stmt.value)
            strings.write_byte(b, ';')
        }
    }
}

emit_c :: proc(code: []CheckedFunction, main_func_index: int) -> []byte {
    b := strings.builder_make()
    strings.write_string(&b, "#include <stdint.h>\n#include <stdio.h>\n#include <inttypes.h>\n")

    for func, index in code {
        if index == main_func_index {
            strings.write_string(&b, "int main() {")
        } else {
            strings.write_string(&b, "void func")
            strings.write_int(&b, index)
            strings.write_string(&b, "() {")
        }
        emit_block(&b, 0, func.variables, func.body)
        strings.write_byte(&b, '}')
    }
    return transmute([]byte)strings.to_string(b)
}

