package main

import "core:fmt"

// Handles namespace operations. Namespace operations are all handled in the
// same file to maintain a consistent set of builtins which cannot be overridden.

argument_count_mismatch :: proc(
    s: ^CheckerState,
    pos: uint,
    func_name: string,
    num_provided: uint,
    num_expected: uint,
) {
    num_to_str :: proc(num: uint) -> string {
        return num == 1 ? fmt.aprint("1 argument") : fmt.aprint("%d arguments", num)
    }
    provided := num_to_str(num_provided)
    defer free(&provided)
    expected := num_to_str(num_expected)
    defer free(&expected)
    err(
        s,
        pos,
        "Argument count mismatch\nFunction call provides %s\nThe `%s` function expects %s\n",
        provided,
        func_name,
        expected,
    )
}

// - The `bool` returned is whether the function call was parsed successfully
// - If the `CheckedValue` returned is `nil` and the `bool` returned is `true`,
//   then the function call can only be used as a statement
// - If the `CheckedValue` returned is not `nil` and the `bool` returned is
//   `true`, then the function call can only be used as a value
handle_named_function_call :: proc(
    s: ^CheckerState,
    pos: uint,
    function_name_segments: []string,
    args: []Value,
    body: ^[dynamic]CheckedStatement,
    loc := #caller_location,
) -> (
    CheckedValue,
    bool,
) {
    when debug_checker {
        print_call(loc, "handle named function call")
    }
    if len(function_name_segments) != 1 {
        if len(function_name_segments) > 2 {
            err(s, pos, "TODO: Handle function calls where `len(function_name_segments) > 2`")
            return nil, false
        }
        switch function_name_segments[0] {
        case "compiler":
            if s.func_type != .ComptimeFunc {
                err(
                    s,
                    pos,
                    "Compiler functions can only be called in function definitions which are marked with `#comptime`",
                )
                return nil, false
            }
            switch function_name_segments[1] {
            case "emit_js_value":
                // Any -> String
                err(s, pos, "TODO: Implement emit_js_value")
                return nil, false
            case "emit_c_code":
                // (() -> I64) -> String
                err(s, pos, "TODO: Implement emit_c_code")
                return nil, false
            case "run_executable":
                // (String, []String) -> ()
                err(s, pos, "TODO: Implement run_executable")
                return nil, false
            case "write_file":
                // (String, String) -> ()
                if len(args) != 2 {
                    argument_count_mismatch(s, pos, "compiler.write_file", len(args), 2)
                    return nil, false
                }
                name_value := check_value(s, args[0], body)
                if name_value != nil {
                    name_type := get_type(s, name_value)
                    if !expect_type(s, args[0].pos, StringType{}, name_type, "") {
                        name_value = nil
                    }
                }
                text_value := check_value(s, args[1], body)
                if text_value != nil {
                    text_type := get_type(s, text_value)
                    if !expect_type(s, args[1].pos, StringType{}, text_type, "") {
                        text_value = nil
                    }
                }
                if name_value == nil || text_value == nil {
                    return nil, false
                }
                append_elem(body, CheckedWriteFile{name_value, text_value})
                return nil, true
            case "read_file":
                // (String) -> String
                err(s, pos, "TODO: Implement read_file")
                return nil, false
            case:
                err(
                    s,
                    pos,
                    "Expected second segment of multi-segment function call where first segment is `compiler` to be either `emit_js_function_body`, `write_file`, `emit_c_code`, or `run_executable`\nGot `%s`",
                    function_name_segments[1],
                )
                return nil, false
            }
        //case "js":
        //    if s.func_type != .JsFunc {
        //        err_ok(
        //            s.file,
        //            pos,
        //            "JS functions can only be called in function definitions which are marked with `#js`",
        //        )
        //        return nil
        //    }
        //    first_args := check_inline_js_first_args(s, pos, args)
        //    switch function_name_segments[1] {
        //    case "call":
        //        if !first_args.ok {
        //            return nil
        //        }
        //        args := make([]CheckedValue, len(first_args.args_left))
        //        ok := true
        //        for arg, index in first_args.args_left {
        //            arg_value, arg_ok := check_value(s, arg)
        //            if !arg_ok {
        //                ok = false
        //                continue
        //            }
        //            if !expect_type(s, arg.pos, JsObjectType{}, get_type(s, arg_value), "") {
        //                ok = false
        //                continue
        //            }
        //            args[index] = arg_value
        //        }
        //        if !ok {
        //            return nil
        //        }
        //        return CheckedJsFunctionCall{first_args.value, args}
        //    case "assign":
        //        if !first_args.ok {
        //            return nil
        //        }
        //        if len(first_args.args_left) != 1 {
        //            err_ok(
        //                s.file,
        //                pos,
        //                "After first arguments, expected exactly one argument for `js.assign`\nGot %d arguments",
        //                len(first_args.args_left),
        //            )
        //            return nil
        //        }
        //        value, ok := check_value(s, first_args.args_left[0])
        //        if !ok {
        //            return nil
        //        }
        //        if !expect_type(
        //            s,
        //            first_args.args_left[0].pos,
        //            JsObjectType{},
        //            get_type(s, value),
        //            "",
        //        ) {
        //            return nil
        //        }
        //        return CheckedJsAssignment{first_args.value, value}
        //    case:
        //        err_ok(
        //            s.file,
        //            pos,
        //            "Expected second segment of multi-segment function call where first segment is `js` to be either `call` or `assign`\nGot `%s`",
        //            function_name_segments[1],
        //        )
        //        return nil
        //    }
        case:
            err(
                s,
                pos,
                "Expected first segment of multi-segment function call to be `compiler`\nGot `%s`",
                function_name_segments[0],
            )
            return nil, false
        }
    }
    function_name := function_name_segments[0]
    switch function_name {
    // TODO: If you append or concatenate fixed size arrays, that should return a fixed size array
    case "append":
        // ([]$T, $T) -> []$T
        if len(args) != 2 {
            argument_count_mismatch(s, pos, "append", len(args), 2)
            return nil, false
        }
        array := check_value(s, args[0], body)
        item := check_value(s, args[1], body)
        if array == nil || item == nil {
            return nil, false
        }
        array_length, array_type_ref, array_type := check_array(
            s,
            args[0].pos,
            array,
            "Expected an array type\nGot the type `%s`",
        )
        if array_length == nil {
            return nil, false
        }
        types_ok := expect_type(s, args[1].pos, array_type.item_type, get_type(s, item), "")
        if !types_ok {
            return nil, false
        }
        segments := make([]ArraySegment, 2)
        segments[0] = InlineArraySegment{array, array_length}
        segments[1] = SingleElemSegment{item}
        array_ref: VariableRef
        if array_type.length == 0 {
            array_ref = add_unnamed_variable(s, array_type_ref, false)
        } else {
            // If the input array is not dynamic, create a new type for the output array that is dynamic
            ref := ArrayRef(len(s.array_types))
            append_elem(&s.array_types, ArrayType{0, array_type.item_type})
            array_ref = add_unnamed_variable(s, ref, false)
        }
        append_elem(
            body,
            CheckedArrayMutation{array_ref, ArrayType{0, array_type.item_type}, segments},
        )
        return array_ref, true
    case "concat":
        // ([]$T, []$T) -> []$T
        err(s, pos, "TODO: Handle array concatenation")
        return nil, false
    case "print", "println":
        // Any -> ()
        if len(args) < 1 {
            err(s, pos, "Print function must have at least one argument")
            return nil, false
        }
        if len(args) > 1 {
            err(s, pos, "TODO: Handle print function with more than one arguments")
            return nil, false
        }
        val, ok := to_str(s, body, args[0], function_name == "println")
        if !ok {
            return nil, false
        }
        append_elem(body, CheckedPrint(val))
        return nil, true
    case "to_str":
        if len(args) != 1 {
            argument_count_mismatch(s, pos, "to_str", len(args), 1)
            return nil, false
        }
        value, ok := to_str(s, body, args[0], false)
        if !ok {
            return nil, false
        }
        return value, true
    case "len":
        // []$T -> I64
        if len(args) != 1 {
            argument_count_mismatch(s, pos, "len", len(args), 1)
            return nil, false
        }
        value := check_value(s, args[0], body)
        if value == nil {
            return nil, false
        }
        array_length, _, _ := check_array(
            s,
            pos,
            value,
            "Expected an array type\nGot the type `%s`\nThe argument to the `len` function must be an array",
        )
        if array_length == nil {
            return nil, false
        }
        return array_length, true
    }
    is_builtin := err_if_builtin(
        s,
        function_name,
        pos,
        "`%s` is a builtin, but it is not a function",
        function_name,
    )
    if is_builtin {
        return nil, false
    }
    func_index, exists := get_global_function(s, pos, function_name, "")
    if !exists {
        return nil, false
    }
    func_props := s.funcs_props[func_index]

    // if s.func_type == .Normal && func_props.func_type == .JsFunc {
    //     err_ok(s.file, pos, "Within unmarked function, cannot call `#js` function")
    //     return nil
    // }
    if s.func_type == .Normal && func_props.func_type == .ComptimeFunc {
        err(s, pos, "Within unmarked function, cannot call `#comptime` function")
        return nil, false
    }
    //if s.func_type == .JsFunc && func_props.func_type == .ComptimeFunc {
    //    err_ok(s.file, pos, "Within `#js` function, cannot call `#comptime` function")
    //    return nil
    //}
    //if s.func_type == .ComptimeFunc && func_props.func_type == .JsFunc {
    //    err_ok(s.file, pos, "Within `#comptime` function, cannot call `#js` function")
    //    return nil
    //}

    if len(args) != len(func_props.args) {
        argument_count_mismatch(s, pos, function_name, len(args), len(func_props.args))
        return nil, false
    }

    checked_args := make([]CheckedValue, len(args))
    for arg, i in args {
        value := check_value(s, arg, body)
        if value == nil {
            return nil, false
        }

        type := get_type(s, value)
        ok := expect_type(s, arg.pos, func_props.args[i].type, type, "")
        if !ok {
            return nil, false
        }

        checked_args[i] = value
    }

    call := CheckedFunctionCall{func_index, checked_args}
    if func_props.return_type == nil {
        append_elem(body, call)
        return nil, true
    }
    return call, true
}

// Returns nil if there are errors in the named type
handle_named_type :: proc(s: ^CheckerState, pos: uint, type_segments: []string) -> CheckedType {
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
    switch type_segments[0] {
    case "I64":
        return I64Type{}
    case "I32":
        return I32Type{}
    case "I16":
        return I16Type{}
    case "I8":
        return I8Type{}
    case "U64":
        return U64Type{}
    case "U32":
        return U32Type{}
    case "U16":
        return U16Type{}
    case "U8":
        return U8Type{}
    case "Bool":
        return BoolType{}
    case "String":
        return StringType{}
    }
    is_builtin := err_if_builtin(
        s,
        type_segments[0],
        pos,
        "`%s` is a builtin, but it is not a type",
        type_segments[0],
    )
    if is_builtin {
        return nil
    }
    err(s, pos, "TODO: Support checking type variable")
    return nil
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
    val := check_value(s, value, body)
    if val == nil {
        return VariableRef{}, false
    }
    type := get_type(s, val)
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
    }
    variable := add_unnamed_variable(s, StringType{}, false)
    string_conversion_values := make([]CheckedValue, 1)
    string_conversion_values[0] = val
    append_elem(body, StringInterpolation{variable, format, string_conversion_values})
    return variable, true
}

// The boolean returned is whether the name is a builtin
err_if_builtin :: proc(
    s: ^CheckerState,
    name: string,
    pos: uint,
    msg: string,
    args: ..any,
) -> bool {
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
        err(s, pos, msg, ..args)
        return true
    }
    return false
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
    is_builtin := err_if_builtin(
        s,
        variable.ident,
        variable.pos,
        "`%s` is a builtin\nCannot override builtins",
        variable.ident,
    )
    // TODO: Consider whether we should fail compilation when there is an incorrectly cased variable name
    expect_snake_case(s, "variable names", variable)
    if is_builtin {
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

