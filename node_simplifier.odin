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
         .StringConcat: // TODO
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
        flip_values = val0_is_comptime
    }
    if flip_values {
        return CheckedJoinedValues{method, new_clone(val1), new_clone(val0)}
    }
    return CheckedJoinedValues{method, new_clone(val0), new_clone(val1)}
}

