package main

// Handles namespace operations. Namespace operations are all handled in the
// same file to maintain a consistent set of builtins which cannot be overridden.

import "core:fmt"
import "core:strings"

builtins_err :: "`%s` is a builtin\nCannot override builtins"

function_todo1 :: "TODO: Handle function calls where the function isn't a variable reference"
function_todo2 :: "TODO: Handle function calls where `len(function_name_segments) > 2`"
function_err1 :: "Compiler functions can only be called in function definitions which are marked with `#comptime`"
function_err2 :: "Within unmarked function, cannot call `#comptime` function"
function_err3 :: "In 2 segment function call that is used as a %s where the first segment is `compiler`\nExpected the second segment to be either %s\nGot `%s`"
function_err4 :: "This function returns a value, so it cannot be used this as a statement"
function_err5 :: "This function does not return a value, so it cannot be used as a value"
function_err6 :: "First segment of a 2 segment function call that is used as a statement must be `compiler`\nGot `%s`"
function_err7 :: "First segment of a 2 segment function call that is used as a value must be either `compiler` or ``\nGot `%s`"

argument_count_mismatch :: proc(
    s: ^CheckerState,
    pos: uint,
    num_provided: uint,
    num_expected: uint,
    func_name: ..string,
) {
    name := strings.join(func_name, ".")
    defer delete_string(name)
    num_to_str :: proc(num: uint) -> string {
        return num == 1 ? fmt.aprint("1 argument") : fmt.aprintf("%d arguments", num)
    }
    provided := num_to_str(num_provided)
    defer delete_string(provided)
    expected := num_to_str(num_expected)
    defer delete_string(expected)
    err(
        s,
        pos,
        "Argument count mismatch\nFunction call provides %s\nThe `%s` function expects %s",
        provided,
        name,
        expected,
    )
}

handle_user_defined_named_function_call :: proc(
    s: ^CheckerState,
    pos: uint,
    function_name: string,
    args: []Value,
    body: ^[dynamic]CheckedStatement,
) -> (
    CheckedFunctionCall,
    bool,
) {
    if is_builtin(function_name) {
        err(s, pos, "`%s` is a builtin, but it is not a function", function_name)
        return CheckedFunctionCall{}, false
    }

    func_index, exists := get_global_function(s, pos, function_name, "")
    if !exists {
        return CheckedFunctionCall{}, false
    }
    func_props := s.funcs_props[func_index]

    if s.func_type == .Normal && func_props.func_type == .ComptimeFunc {
        err(s, pos, function_err2)
        return CheckedFunctionCall{}, false
    }

    if len(args) != len(func_props.args) {
        argument_count_mismatch(s, pos, len(args), len(func_props.args), function_name)
        return CheckedFunctionCall{}, false
    }

    checked_args := make([]CheckedValue, len(args))
    for arg, i in args {
        value := check_value(s, arg, body, &func_props.args[i].type)
        if value == nil {
            return CheckedFunctionCall{}, false
        }

        checked_args[i] = value
    }

    return CheckedFunctionCall{func_index, checked_args}, true
}

check_call_statement :: proc(
    s: ^CheckerState,
    pos: uint,
    call: FunctionCall,
    body: ^[dynamic]CheckedStatement,
    loc := #caller_location,
) -> bool {
    when debug_checker {
        print_call(loc, "check call statement")
    }

    function_segments, is_var_ref := call.function.value.(VariableReference)
    if !is_var_ref {
        err(s, pos, function_todo1)
        return false
    }

    switch len(function_segments) {
    case:
        err(s, pos, function_todo2)
        return false
    case 1:
        func_name := function_segments[0].ident
        switch func_name {
        case "print", "println":
            // Any -> ()
            if len(call.args) < 1 {
                err(s, pos, "Print function must have at least one argument")
                return false
            }
            if len(call.args) > 1 {
                err(s, pos, "TODO: Handle print function with more than one arguments")
                return false
            }
            val, ok := to_str(s, body, call.args[0], func_name == "println")
            if !ok {
                return false
            }
            append_elem(body, CheckedPrint(val))
            return true
        case:
            call, ok := handle_user_defined_named_function_call(s, pos, func_name, call.args, body)
            if !ok {
                return false
            }
            if s.funcs_props[call.index].return_type != nil {
                err(s, pos, function_err4)
                return false
            }
            append_elem(body, call)
            return true
        }
    case 2:
        if function_segments[0].ident != "compiler" {
            err(s, function_segments[0].pos, function_err6, function_segments[0].ident)
            return false
        }
        if s.func_type != .ComptimeFunc {
            err(s, pos, function_err1)
            return false
        }
        switch function_segments[1].ident {
        case "run_executable":
            // (String, []String) -> ()
            err(s, pos, "TODO: Implement run_executable")
            return false
        case "write_file":
            // (String, String) -> ()
            if len(call.args) != 2 {
                argument_count_mismatch(s, pos, len(call.args), 2, "compiler.write_file")
                return false
            }
            expected_type: CheckedType = StringType{}
            name_value := check_value(s, call.args[0], body, &expected_type)
            text_value := check_value(s, call.args[1], body, &expected_type)
            if name_value == nil || text_value == nil {
                return false
            }
            append_elem(body, CheckedWriteFile{name_value, text_value})
            return true
        case:
            err(
                s,
                function_segments[1].pos,
                function_err3,
                "statement",
                "`write_file`, or `run_executable`",
                function_segments[1].ident,
            )
            return false
        }
    }
}

check_call_value :: proc(
    s: ^CheckerState,
    pos: uint,
    call: FunctionCall,
    body: ^[dynamic]CheckedStatement,
    type: ^CheckedType, // TODO: Check type of function return is this type
    loc := #caller_location,
) -> CheckedValue {
    when debug_checker {
        print_call(loc, "check call value")
    }

    function_segments, is_var_ref := call.function.value.(VariableReference)
    if !is_var_ref {
        err(s, pos, function_todo1)
        return nil
    }
    switch len(function_segments) {
    case:
        err(s, pos, function_todo2)
        return nil
    case 1:
        func_name := function_segments[0].ident
        switch func_name {
        case "append":
            // ([]$T, $T) -> []$T
            if len(call.args) != 2 {
                argument_count_mismatch(s, pos, len(call.args), 2, "append")
                return nil
            }
            array_type: CheckedType = nil
            item_type: CheckedType = nil
            array := check_value(s, call.args[0], body, &array_type)
            item := check_value(s, call.args[1], body, &item_type)
            if array == nil || item == nil {
                return nil
            }
            array_length, array_type_ref, array_type_info := check_array(
                s,
                call.args[0].pos,
                array,
                array_type,
                "Expected an array type\nGot the type `%s`",
            )
            if array_length == nil {
                return nil
            }
            types_ok := expect_type(s, call.args[1].pos, array_type_info.item_type, item_type, "")
            if !types_ok {
                return nil
            }
            segments := make([]ArraySegment, 2)
            segments[0] = InlineArraySegment{array, array_length}
            segments[1] = SingleElemSegment{item}
            array_ref_type: CheckedType = ---
            if array_type_info.length == 0 {
                array_ref_type = array_type_ref
            } else {
                // If the input array is not dynamic, create a new type for the output array that is dynamic
                array_ref_type := ArrayRef(len(s.array_types))
                append_elem(&s.array_types, ArrayType{0, array_type_info.item_type})
            }
            array_ref := add_unnamed_variable(s, array_ref_type, false)
            append_elem(
                body,
                CheckedArrayMutation{array_ref, ArrayType{0, array_type_info.item_type}, segments},
            )
            return finish_checking_value(s, pos, array_ref, array_ref_type, type)
        case "concat":
            // ([]$T, []$T) -> []$T
            err(s, pos, "TODO: Handle array concatenation")
            return nil
        case "to_str":
            if len(call.args) != 1 {
                argument_count_mismatch(s, pos, len(call.args), 1, "to_str")
                return nil
            }
            value, ok := to_str(s, body, call.args[0], false)
            if !ok {
                return nil
            }
            return finish_checking_value(s, pos, value, StringType{}, type)
        case "len":
            // []$T -> I64
            if len(call.args) != 1 {
                argument_count_mismatch(s, pos, len(call.args), 1, "len")
                return nil
            }
            value_type: CheckedType = nil
            value := check_value(s, call.args[0], body, &value_type)
            if value == nil {
                return nil
            }
            array_length, _, _ := check_array(
                s,
                pos,
                value,
                value_type,
                "Expected an array type\nGot the type `%s`\nThe argument to the `len` function must be an array",
            )
            if array_length == nil {
                return nil
            }
            return finish_checking_value(s, pos, array_length, I64Type{}, type)
        case:
            call, ok := handle_user_defined_named_function_call(s, pos, func_name, call.args, body)
            if !ok {
                return nil
            }
            func_props := s.funcs_props[call.index]
            if func_props.return_type == nil {
                err(s, pos, function_err5)
                return nil
            }
            return finish_checking_value(s, pos, call, func_props.return_type, type)
        }
    case 2:
        switch function_segments[0].ident {
        case "compiler":
            if s.func_type != .ComptimeFunc {
                err(s, pos, function_err1)
                return nil
            }
            switch function_segments[1].ident {
            case "emit_js_value":
                // Any -> String
                err(s, pos, "TODO: Implement emit_js_value")
                return nil
            case "emit_c_code":
                // (() -> I64) -> String
                err(s, pos, "TODO: Implement emit_c_code")
                return nil
            case "read_file":
                // (String) -> String
                err(s, pos, "TODO: Implement read_file")
                return nil
            case:
                err(
                    s,
                    function_segments[1].pos,
                    function_err3,
                    "value",
                    "`emit_js_value`, `emit_c_code`, or `read_file`",
                    function_segments[1].ident,
                )
                return nil
            }
        case "":
            if type^ == nil {
                err(s, pos, "Cannot determine the sum type of this value")
                return nil
            }
            sum_type, sum_type_ok := get_sum_type(s, pos, type^)
            if !sum_type_ok {
                return nil
            }

            variant_index, exists := sum_type.variants_map[function_segments[1].ident]
            if !exists {
                err(
                    s,
                    pos,
                    "The sum type `%s` does not have a variant called `%s`",
                    type_to_string(s, type^),
                    function_segments[1].ident,
                )
                return nil
            }
            variant := sum_type.variants[variant_index].payload

            if len(variant.fields) != len(call.args) {
                argument_count_mismatch(
                    s,
                    pos,
                    len(call.args),
                    len(variant.fields),
                    ..function_segments.ident[:len(function_segments)],
                )
                return nil
            }

            checked_args := make([]CheckedValue, len(call.args))
            args_ok := true
            for arg, i in call.args {
                expected_type := variant.fields[i].type
                checked_args[i] = check_value(s, arg, body, &expected_type)
                if checked_args[i] == nil {
                    args_ok = false
                }
            }
            if !args_ok {
                return nil
            }
            dest := add_unnamed_variable(s, type^, false)
            append_elem(
                body,
                CheckedSumTypeInitialisation{dest, type^, variant_index, checked_args},
            )
            return dest
        case:
            err(s, function_segments[0].pos, function_err7, function_segments[0].ident)
            return nil
        }
    }
}

// Returns nil if there are errors in the named type
handle_named_type :: proc(
    s: ^CheckerState,
    pos: uint,
    type_segments: IdentToken,
    generic_arg: ^Type,
    generic_arg_name: string,
) -> CheckedType {
    //if len(type_segments) == 2 && type_segments[0] == "js" && type_segments[1] == "Object" {
    //    if func_type != .JsFunc {
    //        err_ok(
    //            file,
    //            pos,
    //            "Can only use the `js.Object` type within a function marked with `#js`",
    //        )
    //        return nil
    //    }
    //    return JsObjectType{}
    //}
    if len(type_segments) != 1 {
        err(s, pos, "TODO: Support compiling type references with `.` in them")
        return nil
    }
    name := type_segments[0].ident
    builtin_type: CheckedType = ---
    switch name {
    case "I64":
        builtin_type = I64Type{}
    case "I32":
        builtin_type = I32Type{}
    case "I16":
        builtin_type = I16Type{}
    case "I8":
        builtin_type = I8Type{}
    case "U64":
        builtin_type = U64Type{}
    case "U32":
        builtin_type = U32Type{}
    case "U16":
        builtin_type = U16Type{}
    case "U8":
        builtin_type = U8Type{}
    case "Bool":
        builtin_type = BoolType{}
    case "String":
        builtin_type = StringType{}
    case:
        if is_builtin(name) {
            err(s, pos, "`%s` is a builtin, but it is not a type", name)
            return nil
        }

        if name == generic_arg_name {
            if generic_arg != nil {
                err(s, pos, "TODO: Support generic args that are generic")
                return nil
            }
            return TypeOfGenericArg{}
        }

        global, exists := s.globals[name]
        if !exists {
            err(s, pos, "There is no global called `%s`", name)
            return nil
        }

        index, is_type := global.value.(uint)
        if !is_type {
            err(s, pos, "The global `%s` is not a type", name)
            return nil
        }

        type := s.global_types[index]
        if generic_arg == nil {
            if type.generic.ident != "" {
                err(s, pos, "The global type `%s` requires a generic argument", name)
                return nil
            }
            return TypeRef(index)
        } else {
            if type.generic.ident == "" {
                err(s, pos, "The global type `%s` does not accept a generic argument", name)
                return nil
            }
            checked_generic_arg := check_type(s, generic_arg^, generic_arg_name)
            if checked_generic_arg == nil {
                return nil
            }
            _, is_type_of_generic_arg := checked_generic_arg.(TypeOfGenericArg)
            if is_type_of_generic_arg {
                return GenericTypeWhereArgIsTypeOfGenericArg{index}
            }
            return create_generic_type(s, index, checked_generic_arg)
        }
    }
    if generic_arg != nil {
        err(s, pos, "The builtin type `%s` cannot have a generic argument", name)
        return nil
    }
    return builtin_type
}

// CheckInlineJsFirstArgsOutput :: struct {
//     ok:        bool,
//     args_left: []Value,
//     value:     JsValue,
// }

// check_inline_js_first_args :: proc(
//     s: ^CheckerState,
//     pos: uint,
//     args: []Value,
// ) -> CheckInlineJsFirstArgsOutput {
//     first_args_msg :: "Expected first arguments to be either just a string literal or a variable reference followed by a string literal"
//     if len(args) == 0 {
//         err_ok(s.file, pos, first_args_msg + "\nGot no arguments")
//         return CheckInlineJsFirstArgsOutput{ok = false}
//     }
//     value, ok := check_value(s, args[0])
//     if !ok {
//         return CheckInlineJsFirstArgsOutput{ok = false}
//     }
//     if str, is_str := value.(StringValue); is_str {
//         return CheckInlineJsFirstArgsOutput{true, args[1:], JsValue{nil, string(str)}}
//     }
//     if !expect_type(s, args[0].pos, JsObjectType{}, get_type(s, value), first_args_msg) {
//         return CheckInlineJsFirstArgsOutput{ok = false}
//     }
//     if len(args) <= 1 {
//         err_ok(
//             s.file,
//             args[0].pos,
//             first_args_msg + "\nExpected additional string literal argument",
//         )
//         return CheckInlineJsFirstArgsOutput{ok = false}
//     }
//     if str, is_str := args[1].value.(String); is_str {
//         return CheckInlineJsFirstArgsOutput {
//             true,
//             args[2:],
//             JsValue{new_clone(value), strings.join(([]string)(str), "")},
//         }
//     }
//     err_ok(s.file, args[1].pos, "After value, expected string literal\n" + first_args_msg)
//     return CheckInlineJsFirstArgsOutput{ok = false}
// }

to_str :: proc(
    s: ^CheckerState,
    body: ^[dynamic]CheckedStatement,
    value: Value,
    add_newline: bool,
) -> (
    VariableRef,
    bool,
) {
    type: CheckedType = nil
    val := check_value(s, value, body, &type)
    if val == nil {
        return VariableRef{}, false
    }
    format: string
    // TODO: Rework to be able to emit JS code
    switch _ in type {
    case BoolType:
        format = add_newline ? "\"%b\\n\"" : "\"%b\""
    case StringType:
        format = add_newline ? "\"%s\\n\"" : "\"%s\""
    case I64Type:
        format = add_newline ? "\"%\" PRId64 \"\\n\"" : "\"%\" PRId64"
    case I32Type:
        format = add_newline ? "\"%\" PRId32 \"\\n\"" : "\"%\" PRId32"
    case I16Type:
        format = add_newline ? "\"%\" PRId16 \"\\n\"" : "\"%\" PRId16"
    case I8Type:
        format = add_newline ? "\"%\" PRId8 \"\\n\"" : "\"%\" PRId8"
    case U64Type:
        format = add_newline ? "\"%\" PRIu64 \"\\n\"" : "\"%\" PRIu64"
    case U32Type:
        format = add_newline ? "\"%\" PRIu32 \"\\n\"" : "\"%\" PRIu32"
    case U16Type:
        format = add_newline ? "\"%\" PRIu16 \"\\n\"" : "\"%\" PRIu16"
    case U8Type:
        format = add_newline ? "\"%\" PRIu8 \"\\n\"" : "\"%\" PRIu8"
    case ArrayRef:
        err(s, value.pos, "Cannot convert array to string")
        return VariableRef{}, false
    case FuncType:
        err(s, value.pos, "Cannot convert function to string")
        return VariableRef{}, false
    case GenericTypeRef:
        err(s, value.pos, "Cannot convert generic type to string")
        return VariableRef{}, false
    case TypeRef:
        err(s, value.pos, "Cannot convert global type to string")
        return VariableRef{}, false
    case CheckedStructType:
        err(s, value.pos, "Cannot convert struct type to string")
        return VariableRef{}, false
    case CheckedSumType:
        err(s, value.pos, "Cannot convert sum type to string")
        return VariableRef{}, false
    case SumVariant:
        err(s, value.pos, "Cannot convert sum type variant to string")
        return VariableRef{}, false
    case TypeOfGenericArg, GenericTypeWhereArgIsTypeOfGenericArg:
        panic("Unreachable")
    }
    variable := add_unnamed_variable(s, StringType{}, false)
    string_conversion_values := make([]CheckedValue, 1)
    string_conversion_values[0] = val
    append_elem(body, StringInterpolation{variable, format, string_conversion_values})
    return variable, true
}

// The boolean returned is whether the name is a builtin
is_builtin :: proc(name: string) -> bool {
    switch name {
    case "print",
         "println",
         "I64",
         "I32",
         "I16",
         "I8",
         "U64",
         "U32",
         "U16",
         "U8",
         "Bool",
         "String",
         "compiler",
         "append",
         "concat",
         "to_str",
         // "js",
         "len":
        return true
    case:
        return false
    }
}

add_unnamed_variable :: proc(
    s: ^CheckerState,
    variable_type: CheckedType,
    variable_is_mut: bool,
) -> VariableRef {
    assert(
        len(s.scopes[len(s.scopes) - 1].variable_is_muts) ==
        len(s.scopes[len(s.scopes) - 1].variable_types),
    )
    var_ref := VariableRef{len(s.scopes) - 1, len(s.scopes[len(s.scopes) - 1].variable_is_muts)}
    append_elem(&s.scopes[len(s.scopes) - 1].variable_types, variable_type)
    append_elem(&s.scopes[len(s.scopes) - 1].variable_is_muts, variable_is_mut)
    return var_ref
}

// The boolean returned is whether there are errors
add_variable :: proc(
    s: ^CheckerState,
    variable_type: CheckedType,
    variable_is_mut: bool,
    variable: IdentAndPos,
) -> (
    VariableRef,
    bool,
) {
    // TODO: Add a warning for unused variables
    expect_snake_case(s, "variable names", variable)
    if is_builtin(variable.ident) {
        err(s, variable.pos, builtins_err, variable.ident)
        return VariableRef{}, false
    }
    if variable.ident in s.variables_map {
        err(s, variable.pos, "Redeclaration of variable `%s`", variable.ident)
        return VariableRef{}, false
    }
    var_ref := add_unnamed_variable(s, variable_type, variable_is_mut)
    s.variables_map[variable.ident] = var_ref
    return var_ref, true
}

