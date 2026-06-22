package main

import "core:fmt"
import "core:os"
import "core:strings"

RuntimeValue :: union {
    i64,
    i32,
    i16,
    i8,
    u64,
    u32,
    u16,
    u8,
    bool,
    string,
    RuntimeArray,
    RuntimeStruct,
    RuntimeSumType,
    FuncDefinitionRef,
    BuiltinFunction,
}

RuntimeArray :: struct {
    elems: [dynamic]RuntimeValue,
}

RuntimeStruct :: struct {
    field_values: [dynamic]RuntimeValue,
}

RuntimeSumType :: struct {
    variant_index: u32,
    payload:       ^RuntimeValue,
}

Frame :: struct {
    func_index: uint,
    scopes:     [dynamic][dynamic]RuntimeValue,
}

InterpState :: struct {
    checked:       Checked,
    frames:        [dynamic]Frame,
    returning:     bool,
    return_value:  RuntimeValue,
    breaking:      bool,
    break_loop:    uint,
    continuing:    bool,
    continue_loop: uint,
    current_loop:  uint,
}

interpret :: proc(c: Checked, entry_func_ref: FuncDefinitionRef) -> RuntimeValue {
    state := InterpState {
        checked = c,
        frames  = make([dynamic]Frame),
    }

    args := make([]RuntimeValue, 0)
    defer delete(args)

    result := interp_execute_function(&state, entry_func_ref.index, args)
    for frame in state.frames {
        for scope in frame.scopes {
            for val in scope {
                interp_destroy_value(val)
            }
            delete(scope)
        }
        delete(frame.scopes)
    }
    delete(state.frames)
    return result
}

interp_execute_function :: proc(
    state: ^InterpState,
    func_index: uint,
    args: []RuntimeValue,
) -> RuntimeValue {
    checked_func := state.checked.checked_funcs[func_index]

    frame := Frame {
        func_index = func_index,
        scopes     = make([dynamic][dynamic]RuntimeValue),
    }
    append_elem(&frame.scopes, make([dynamic]RuntimeValue))
    for arg_val in args {
        append_elem(&frame.scopes[0], arg_val)
    }

    append_elem(&frame.scopes, make([dynamic]RuntimeValue))
    for var_type in checked_func.variables {
        append_elem(&frame.scopes[1], interp_default_value(state, var_type))
    }

    append_elem(&state.frames, frame)
    defer {
        f := pop(&state.frames)
        for s in f.scopes {
            for v in s {
                interp_destroy_value(v)
            }
            delete(s)
        }
        delete(f.scopes)
    }

    state.returning = false
    interp_exec_block(state, 1, checked_func.body)

    return state.return_value
}

interp_default_value :: proc(state: ^InterpState, t: Type) -> RuntimeValue {
    switch t {
    case i64_type:
        return i64(0)
    case i32_type:
        return i32(0)
    case i16_type:
        return i16(0)
    case i8_type:
        return i8(0)
    case u64_type:
        return u64(0)
    case u32_type:
        return u32(0)
    case u16_type:
        return u16(0)
    case u8_type:
        return u8(0)
    case bool_type:
        return false
    case string_type:
        return ""
    case:
        type_val := get_type(state.checked.types, t)
        switch v in type_val {
        case ArrayType:
            return RuntimeArray{make([dynamic]RuntimeValue)}
        case Struct(Type, Type):
            fields := make([dynamic]RuntimeValue, len(v.fields))
            for field_type, i in v.fields {
                fields[i] = interp_default_value(state, field_type.type)
            }
            return RuntimeStruct{fields}
        case SumType(Type):
            payload := interp_default_value(state, v.variants[0].payload)
            return RuntimeSumType{0, new_clone(payload)}
        case FuncType, GenericTypeValue:
            return i64(0)
        }
        return i64(0)
    }
}

interp_exec_block :: proc(state: ^InterpState, nesting_level: uint, body: []CheckedStatement) {
    for stmt in body {
        if state.returning || state.breaking || state.continuing {
            return
        }
        interp_exec_statement(state, nesting_level, stmt)
    }
}

interp_push_scope :: proc(state: ^InterpState, variable_types: []Type) {
    scope := make([dynamic]RuntimeValue)
    for var_type in variable_types {
        append_elem(&scope, interp_default_value(state, var_type))
    }
    append_elem(&state.frames[len(state.frames) - 1].scopes, scope)
}

interp_pop_scope :: proc(state: ^InterpState) {
    frame := &state.frames[len(state.frames) - 1]
    scope := pop(&frame.scopes)
    interp_destroy_dynamic_value(scope)
}

interp_destroy_value :: proc(val: RuntimeValue) {
    switch v in val {
    case RuntimeArray:
        for elem in v.elems {
            interp_destroy_value(elem)
        }
        delete(v.elems)
    case RuntimeStruct:
        for field in v.field_values {
            interp_destroy_value(field)
        }
        delete(v.field_values)
    case RuntimeSumType:
        interp_destroy_value(v.payload^)
        free(v.payload)
    case string:
        delete(v)
    case i64, i32, i16, i8, u64, u32, u16, u8, bool, FuncDefinitionRef, BuiltinFunction:
    }
}

interp_destroy_dynamic_value :: proc(v: [dynamic]RuntimeValue) {
    for val in v {
        interp_destroy_value(val)
    }
    delete(v)
}

interp_clone_value :: proc(val: RuntimeValue) -> RuntimeValue {
    switch v in val {
    case RuntimeArray:
        new_elems := make([dynamic]RuntimeValue, len(v.elems))
        for elem, i in v.elems {
            new_elems[i] = interp_clone_value(elem)
        }
        return RuntimeArray{new_elems}
    case RuntimeStruct:
        new_fields := make([dynamic]RuntimeValue, len(v.field_values))
        for field, i in v.field_values {
            new_fields[i] = interp_clone_value(field)
        }
        return RuntimeStruct{new_fields}
    case RuntimeSumType:
        return RuntimeSumType{v.variant_index, new_clone(interp_clone_value(v.payload^))}
    case string:
        return strings.clone(v)
    case i64, i32, i16, i8, u64, u32, u16, u8, bool, FuncDefinitionRef, BuiltinFunction:
        return val
    }
    return RuntimeValue{}
}

interp_exec_statement :: proc(state: ^InterpState, nesting_level: uint, stmt: CheckedStatement) {
    switch s in stmt {

    case CheckedReturn:
        state.returning = true
        if s.value != nil {
            state.return_value = interp_clone_value(
                interp_eval_value(state, nesting_level, s.value),
            )
        }

    case CheckedIf:
        cond := interp_eval_value(state, nesting_level, s.condition)
        cond_bool, cond_ok := cond.(bool)
        if !cond_ok {
            panic("Expected bool in if condition")
        }
        if cond_bool {
            interp_push_scope(state, s.if_block.variables)
            interp_exec_block(state, nesting_level + 1, s.if_block.body)
            interp_pop_scope(state)
        } else {
            interp_push_scope(state, s.else_block.variables)
            interp_exec_block(state, nesting_level + 1, s.else_block.body)
            interp_pop_scope(state)
        }

    case CheckedLoop:
        loop_index := s.loop_index
        interp_push_scope(state, s.variables)
        interp_exec_block(state, nesting_level + 1, s.enter)
        for {
            if state.returning do break

            old_loop := state.current_loop
            state.current_loop = loop_index
            interp_exec_block(state, nesting_level + 1, s.body)
            state.current_loop = old_loop

            if state.returning do break
            if state.breaking {
                if state.break_loop == loop_index {
                    state.breaking = false
                    break
                }
                return
            }
            if state.continuing {
                if state.continue_loop == loop_index {
                    state.continuing = false
                }
            }
        }
        interp_pop_scope(state)

    case ContinueLoop:
        state.continuing = true
        state.continue_loop = s.loop_index

    case BreakLoop:
        state.breaking = true
        state.break_loop = s.loop_index

    case CheckedMutation:
        var_ref := s.destination.variable
        value := interp_clone_value(interp_eval_value(state, nesting_level, s.value))
        target := &state.frames[len(state.frames) - 1].scopes[var_ref.nesting_level][var_ref.index]

        if s.destination.index != nil {
            index_val := interp_eval_value(state, nesting_level, s.destination.index)
            index_i64, index_ok := index_val.(i64)
            if !index_ok {panic("Expected i64 for array index")}
            arr_target, arr_ok := target.(RuntimeArray)
            if !arr_ok {panic("Expected array for indexed mutation")}
            arr_target.elems[index_i64] = value
        } else {
            switch s.mutation_type {
            case .SetTo:
                interp_destroy_value(target^)
                target^ = value
            case .IncrementBy:
                v := target.(i64)
                delta := value.(i64)
                target^ = v + delta
            case .DecrementBy:
                v := target.(i64)
                delta := value.(i64)
                target^ = v - delta
            case .MultiplyBy:
                v := target.(i64)
                factor := value.(i64)
                target^ = v * factor
            case .DivideBy:
                v := target.(i64)
                divisor := value.(i64)
                target^ = v / divisor
            }
        }

    case CheckedArrayMutation:
        arr := state.frames[len(state.frames) - 1].scopes[s.variable.nesting_level][s.variable.index].(RuntimeArray)
        clear(&arr.elems)
        for segment in s.segments {
            switch seg in segment {
            case SingleElemSegment:
                val := interp_eval_value(state, nesting_level, seg.elem)
                append_elem(&arr.elems, interp_clone_value(val))
            case InlineArraySegment:
                src := interp_eval_value(state, nesting_level, seg.array)
                src_arr, src_ok := src.(RuntimeArray)
                if !src_ok {panic("Expected array for inline array segment")}
                for elem in src_arr.elems {
                    append_elem(&arr.elems, interp_clone_value(elem))
                }
            }
        }
        state.frames[len(state.frames) - 1].scopes[s.variable.nesting_level][s.variable.index] =
            arr

    case CheckedFunctionCall:
        fn_val := interp_eval_value(state, nesting_level, s.function^)
        fn_builtin, fn_is_builtin := fn_val.(BuiltinFunction)
        fn_func_ref, fn_is_func_ref := fn_val.(FuncDefinitionRef)

        if fn_is_builtin {
            interp_call_builtin(state, nesting_level, fn_builtin.index, s.args)
        } else if fn_is_func_ref {
            args := make([]RuntimeValue, len(s.args))
            for arg_val, i in s.args {
                args[i] = interp_clone_value(interp_eval_value(state, nesting_level, arg_val))
            }
            interp_execute_function(state, fn_func_ref.index, args)
            for arg in args {
                interp_destroy_value(arg)
            }
            delete(args)
        }

    case CheckedMatch:
        val_ref := s.value
        val := state.frames[len(state.frames) - 1].scopes[val_ref.nesting_level][val_ref.index]
        sum_val, sum_ok := val.(RuntimeSumType)
        if !sum_ok {panic("Expected sum type for match")}

        branch_index := sum_val.variant_index
        if int(branch_index) < len(s.branches) {
            branch := s.branches[branch_index]
            interp_push_scope(state, branch.block.variables)
            val_var, has_val := branch.value_var.(VariableRef)
            if has_val {
                state.frames[len(state.frames) - 1].scopes[val_var.nesting_level][val_var.index] =
                    interp_clone_value(sum_val.payload^)
            }
            interp_exec_block(state, nesting_level + 1, branch.block.body)
            interp_pop_scope(state)
        }

    }
}

interp_eval_value :: proc(
    state: ^InterpState,
    nesting_level: uint,
    v: CheckedValue,
) -> RuntimeValue {
    switch value in v {

    case CompileTimeValue:
        switch comptime in value {
        case StringLiteralValue:
            return string(comptime)
        case NumberValue:
            as_u64, ok := big_uint_to_u64(comptime.value.absolute_value)
            if ok {
                if comptime.value.is_negated {
                    return i64(-i64(as_u64))
                }
                return i64(i64(as_u64))
            }
            return i64(0)
        case BoolValue:
            return bool(comptime)
        case Type, GlobalTypeWithGenericRef:
            panic("Cannot use compile time only value at runtime")
        }

    case ToString:
        inner := interp_eval_value(state, nesting_level, value.value^)
        switch inner_val in inner {
        case i64:
            return fmt.aprintf("%d", inner_val)
        case i32:
            return fmt.aprintf("%d", inner_val)
        case i16:
            return fmt.aprintf("%d", inner_val)
        case i8:
            return fmt.aprintf("%d", inner_val)
        case u64:
            return fmt.aprintf("%d", inner_val)
        case u32:
            return fmt.aprintf("%d", inner_val)
        case u16:
            return fmt.aprintf("%d", inner_val)
        case u8:
            return fmt.aprintf("%d", inner_val)
        case bool:
            return inner_val ? "true" : "false"
        case string:
            return inner_val
        case RuntimeArray, RuntimeStruct, RuntimeSumType, FuncDefinitionRef, BuiltinFunction:
            return ""
        }

    case VariableRef:
        return state.frames[len(state.frames) - 1].scopes[value.nesting_level][value.index]

    case BooleanNotValue:
        inner := interp_eval_value(state, nesting_level, value^)
        inner_bool, inner_ok := inner.(bool)
        if !inner_ok {panic("Expected bool for not")}
        return !inner_bool

    case CheckedJoinedValues:
        lhs := interp_eval_value(state, nesting_level, value.val0^)
        rhs := interp_eval_value(state, nesting_level, value.val1^)

        switch value.join_method {

        case .Addition:
            a, _ := lhs.(i64)
            b, _ := rhs.(i64)
            return a + b

        case .Subtraction:
            a, _ := lhs.(i64)
            b, _ := rhs.(i64)
            return a - b

        case .Multiplication:
            a, _ := lhs.(i64)
            b, _ := rhs.(i64)
            return a * b

        case .Division:
            a, _ := lhs.(i64)
            b, _ := rhs.(i64)
            return a / b

        case .Modulo:
            a, _ := lhs.(i64)
            b, _ := rhs.(i64)
            return a % b

        case .IsEqual:
            a_i64, a_is_i64 := lhs.(i64)
            b_i64, b_is_i64 := rhs.(i64)
            if a_is_i64 && b_is_i64 {
                return a_i64 == b_i64
            }
            a_bool, a_is_bool := lhs.(bool)
            b_bool, b_is_bool := rhs.(bool)
            if a_is_bool && b_is_bool {
                return a_bool == b_bool
            }
            return false

        case .IsNotEqual:
            a_i64, a_is_i64 := lhs.(i64)
            b_i64, b_is_i64 := rhs.(i64)
            if a_is_i64 && b_is_i64 {
                return a_i64 != b_i64
            }
            a_bool, a_is_bool := lhs.(bool)
            b_bool, b_is_bool := rhs.(bool)
            if a_is_bool && b_is_bool {
                return a_bool != b_bool
            }
            return true

        case .IsLessThan:
            a, _ := lhs.(i64)
            b, _ := rhs.(i64)
            return a < b

        case .IsLessThanOrEqual:
            a, _ := lhs.(i64)
            b, _ := rhs.(i64)
            return a <= b

        case .IsGreaterThan:
            a, _ := lhs.(i64)
            b, _ := rhs.(i64)
            return a > b

        case .IsGreaterThanOrEqual:
            a, _ := lhs.(i64)
            b, _ := rhs.(i64)
            return a >= b

        case .BooleanAnd:
            a, _ := lhs.(bool)
            b, _ := rhs.(bool)
            return a && b

        case .BooleanOr:
            a, _ := lhs.(bool)
            b, _ := rhs.(bool)
            return a || b

        case .StringConcat:
            a, a_ok := lhs.(string)
            b, b_ok := rhs.(string)
            if a_ok && b_ok {
                return strings.concatenate([]string{a, b})
            }
            return ""

        case .Append, .Concat, .Colon, .Arrow:
            panic("Unreachable in interpreter")
        }

    case CheckedFunctionCall:
        fn_val := interp_eval_value(state, nesting_level, value.function^)
        args := make([]RuntimeValue, len(value.args))
        for arg_val, i in value.args {
            args[i] = interp_clone_value(interp_eval_value(state, nesting_level, arg_val))
        }

        result: RuntimeValue
        fn_builtin, fn_is_builtin := fn_val.(BuiltinFunction)
        fn_func_ref, fn_is_func_ref := fn_val.(FuncDefinitionRef)

        if fn_is_builtin {
            interp_call_builtin_in_expr(state, nesting_level, fn_builtin.index, args)
        } else if fn_is_func_ref {
            result = interp_execute_function(state, fn_func_ref.index, args)
        }

        for arg in args {
            interp_destroy_value(arg)
        }
        delete(args)
        return result

    case StructTypeInitFunc:
        struct_type := get_type(state.checked.types, value.type).(Struct(Type, Type))
        fields := make([dynamic]RuntimeValue, len(struct_type.fields))
        for field_type, i in struct_type.fields {
            fields[i] = interp_default_value(state, field_type.type)
        }
        return RuntimeStruct{fields}

    case SumTypeInitFunc:
        sum_type := get_type(state.checked.types, value.sum_type).(SumType(Type))
        payload_type := sum_type.variants[value.variant_index].payload
        payload := interp_default_value(state, payload_type)
        return RuntimeSumType{u32(value.variant_index), new_clone(payload)}

    case CheckedArrayAccess:
        arr_val := interp_eval_value(state, nesting_level, value.array^)
        index_val := interp_eval_value(state, nesting_level, value.index^)
        arr, arr_ok := arr_val.(RuntimeArray)
        if !arr_ok {panic("Expected array for array access")}
        idx, idx_ok := index_val.(i64)
        if !idx_ok {panic("Expected i64 for array index")}
        return arr.elems[idx]

    case CheckedFieldAccess:
        struct_val := interp_eval_value(state, nesting_level, value.value^)
        s, s_ok := struct_val.(RuntimeStruct)
        if !s_ok {panic("Expected struct for field access")}
        return s.field_values[value.field_index]

    case LengthOfArray:
        arr_val := interp_eval_value(state, nesting_level, value.array^)
        arr, arr_ok := arr_val.(RuntimeArray)
        if !arr_ok {panic("Expected array for length")}
        return i64(len(arr.elems))

    case StringsAreEqual:
        str0 := interp_eval_value(state, nesting_level, value.str0^)
        str1 := interp_eval_value(state, nesting_level, value.str1^)
        s0, _ := str0.(string)
        s1, _ := str1.(string)
        return s0 == s1

    case FuncDefinitionRef:
        return value

    case BuiltinFunction:
        return value

    }
    panic("Unreachable")
}

interp_call_builtin :: proc(
    state: ^InterpState,
    nesting_level: uint,
    index: u32,
    args: []CheckedValue,
) {
    switch index {
    case builtin_print:
        if len(args) >= 1 {
            val := interp_eval_value(state, nesting_level, args[0])
            s, ok := val.(string)
            if ok {fmt.print(s)}
        }
    case builtin_println:
        if len(args) >= 1 {
            val := interp_eval_value(state, nesting_level, args[0])
            s, ok := val.(string)
            if ok {fmt.println(s)}
        }
    case builtin_eprint:
        if len(args) >= 1 {
            val := interp_eval_value(state, nesting_level, args[0])
            s, ok := val.(string)
            if ok {fmt.eprint(s)}
        }
    case builtin_eprintln:
        if len(args) >= 1 {
            val := interp_eval_value(state, nesting_level, args[0])
            s, ok := val.(string)
            if ok {fmt.eprintln(s)}
        }
    case builtin_clear:
    case builtin_exit:
        os.exit(0)
    }
}

interp_call_builtin_in_expr :: proc(
    state: ^InterpState,
    nesting_level: uint,
    index: u32,
    args: []RuntimeValue,
) {
    switch index {
    case builtin_print:
        if len(args) >= 1 {
            s, ok := args[0].(string)
            if ok {fmt.print(s)}
        }
    case builtin_println:
        if len(args) >= 1 {
            s, ok := args[0].(string)
            if ok {fmt.println(s)}
        }
    case builtin_eprint:
        if len(args) >= 1 {
            s, ok := args[0].(string)
            if ok {fmt.eprint(s)}
        }
    case builtin_eprintln:
        if len(args) >= 1 {
            s, ok := args[0].(string)
            if ok {fmt.eprintln(s)}
        }
    case builtin_clear:
    case builtin_exit:
        os.exit(0)
    }
}

