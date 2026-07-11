package main

import "core:fmt"

// This file may become an implementation of the node simplifier in a sea of nodes style optimizer
// See https://github.com/seaofnodes/simple

// TODO: Improve simplifications, for example:
// (Constant + Runtime) -> (Runtime + Constant)
// (Runtime + Constant) + Constant -> Runtime + (Constant + Constant)

create_not :: proc(value: CheckedValue) -> CheckedValue {
    comptime_value, is_comptime := value.(CompileTimeValue)
    if is_comptime {
        return CompileTimeValue(BoolValue(!comptime_value.(BoolValue)))
    }
    return BooleanNotValue(new_clone(value))
}

create_joined_values :: proc(
    method: UnitJoinMethod,
    val0: CheckedValue,
    val1: CheckedValue,
) -> CheckedValue {
    flip_values := false
    switch method {
    case .BooleanAnd, .BooleanOr:
        comptime0, val0_is_comptime := val0.(CompileTimeValue)
        comptime1, val1_is_comptime := val1.(CompileTimeValue)
        if val0_is_comptime && val1_is_comptime {
            if method == .BooleanAnd {
                return CompileTimeValue(BoolValue(comptime0.(BoolValue) && comptime1.(BoolValue)))
            }
            return CompileTimeValue(BoolValue(comptime0.(BoolValue) || comptime1.(BoolValue)))
        }
        flip_values = val0_is_comptime
    case .IsEqual,
         .IsNotEqual,
         .IsGreaterThan,
         .IsLessThan,
         .IsGreaterThanOrEqual,
         .IsLessThanOrEqual,
         .Modulo,
         .StringConcat,
         .In: // TODO
    case .Append, .Concat, .Colon, .Arrow:
        panic(fmt.aprintf("Unreachable (%v)", method))
    case .Multiplication, .Division, .Addition, .Subtraction:
        comptime0, val0_is_comptime := val0.(CompileTimeValue)
        comptime1, val1_is_comptime := val1.(CompileTimeValue)
        if val0_is_comptime && val1_is_comptime {
            num0 := comptime0.(NumberValue).value
            num1 := comptime1.(NumberValue).value
            #partial switch method {
            case .Multiplication:
                return CompileTimeValue(NumberValue{mul_int(num0, num1)})
            case .Division: // TODO
            case .Addition:
                return CompileTimeValue(NumberValue{add_int(num0, num1)})
            case .Subtraction:
                return CompileTimeValue(NumberValue{sub_int(num0, num1)})
            case:
                panic("Unreachable")
            }
        }
        // TODO: Be able to move the constant right for non-commutative operations
        flip_values = val0_is_comptime && (method == .Multiplication || method == .Addition)
    }
    if flip_values {
        return CheckedJoinedValues{method, new_clone(val1), new_clone(val0)}
    }
    return CheckedJoinedValues{method, new_clone(val0), new_clone(val1)}
}

create_field_access :: proc(value: CheckedValue, field_index: uint) -> CheckedValue {
    #partial switch v in value {
    case CompileTimeValue:
        return v.(CompileTimeStructInitialisation).args[field_index]
    case CheckedFunctionCall:
    // Cannot simplify something like `{a: 5, b: do_stuff()}.a` to `5` because the `do_stuff` call may cause side effects
    // TODO: Be able to make simplifications like this and preserve side effects
    }
    return CheckedFieldAccess{new_clone(value), field_index}
}

create_checked_func_call :: proc(func: CheckedValue, args: []CheckedValue) -> union {
        CheckedFunctionCall,
        CompileTimeValue,
    } {
    #partial outer: switch func_value in func {
    case StructTypeInitFunc:
        comptime_args := make([]CompileTimeValue, len(args))
        for arg, i in args {
            comptime, is_comptime := arg.(CompileTimeValue)
            if is_comptime == false {
                break outer
            }
            comptime_args[i] = comptime
        }
        return CompileTimeValue(CompileTimeStructInitialisation{func_value, comptime_args})
    }
    return CheckedFunctionCall{new_clone(func), args}
}

iterate_array :: proc(
    loop_index: uint,
    index_variable: VariableRef,
    value_variable: VariableRef,
    body: ^DoubleDynamic(CheckedStatement),
    body_variables: []Type,
    array_value: CheckedValue,
    array_type: ArrayType,
) -> CheckedLoop {
    loop_enter := make([]CheckedStatement, 1)
    loop_enter[0] = CheckedMutation{index_variable, CompileTimeValue(NumberValue{int_zero})}

    if_block := make([]CheckedStatement, 1)
    if_block[0] = BreakLoop{loop_index}
    insert(
        body,
        CheckedIf {
            create_joined_values(
                .IsGreaterThanOrEqual,
                index_variable,
                length_of_array(array_type, array_value),
            ),
            CheckedBlock{nil, if_block},
            CheckedBlock{},
        },
        CheckedMutation {
            value_variable,
            CheckedArrayAccess{new_clone(array_value), new_clone(CheckedValue(index_variable))},
        },
    )
    continue_code := make([]CheckedStatement, 1)
    continue_code[0] = CheckedMutation {
        index_variable,
        create_joined_values(
            .Addition,
            index_variable,
            CompileTimeValue(NumberValue{big_int_from_i64(1)}),
        ),
    }
    return CheckedLoop {
        loop_index,
        body_variables,
        loop_enter,
        continue_code,
        dynamic_to_fixed(body^),
    }
}

iterate_start_end_step :: proc(
    loop_index: uint,
    index_variable: VariableRef,
    type: NumericIteratorType,
    start: CheckedValue,
    end: CheckedValue,
    step: CheckedValue,
    body: ^DoubleDynamic(CheckedStatement),
    body_variables: []Type,
) -> CheckedLoop {
    // TODO: Handle when `step` is negative
    loop_enter := make([]CheckedStatement, 1)
    loop_enter[0] = CheckedMutation{index_variable, start}
    if_block := make([]CheckedStatement, 1)
    if_block[0] = BreakLoop{loop_index}
    insert(
        body,
        CheckedIf {
            create_joined_values(
                type == .IncludeEndValue ? .IsGreaterThan : .IsGreaterThanOrEqual,
                index_variable,
                end,
            ),
            CheckedBlock{nil, if_block},
            CheckedBlock{},
        },
    )
    loop_continue := make([]CheckedStatement, 1)
    loop_continue[0] = CheckedMutation {
        index_variable,
        create_joined_values(.Addition, index_variable, step),
    }
    return CheckedLoop {
        loop_index,
        body_variables,
        loop_enter,
        loop_continue,
        dynamic_to_fixed(body^),
    }
}

iterate_ordered_hash_map :: proc(
    loop_index: uint,
    hash_map: CheckedValue,
    index_variable: VariableRef,
    key_variable: VariableRef,
    value_variable: VariableRef,
    body: ^DoubleDynamic(CheckedStatement),
    body_variables: []Type,
) -> CheckedLoop {
    keys := KeysOfOrderedHashMapWithStringKey{new_clone(hash_map)} // TODO: Handle for I64 keys
    insert(
        body,
        CheckedMutation {
            value_variable,
            CheckedOrderedHashMapAccess {
                new_clone(hash_map),
                new_clone(CheckedValue(key_variable)),
            },
        },
    )
    return iterate_array(
        loop_index,
        index_variable,
        key_variable,
        body,
        body_variables,
        keys,
        ArrayType{0, string_type},
    )
}

