package main

// Handles namespace operations. Namespace operations are all handled in the
// same file to maintain a consistent set of builtins which cannot be overridden.

import "core:fmt"
import "core:strings"

builtins_err :: "`%s` is a builtin\nCannot override builtins"

// function_todo1 :: "TODO: Handle function calls where the function isn't a variable reference"
// function_todo2 :: "TODO: Handle function calls where `len(function_name_segments) > 2`"
// function_err1 :: "Compiler functions can only be called in function definitions which are marked with `#comptime`"
// function_err2 :: "Within unmarked function, cannot call `#comptime` function"
// function_err3 :: "In 2 segment function call that is used as a %s where the first segment is `compiler`\nExpected the second segment to be either %s\nGot `%s`"
// function_err4 :: "This function returns a value, so it cannot be used this as a statement"
// function_err5 :: "This function does not return a value, so it cannot be used as a value"
// function_err6 :: "First segment of a 2 segment function call that is used as a statement must be `compiler`\nGot `%s`"
// function_err7 :: "First segment of a 2 segment function call that is used as a value must be either `compiler` or ``\nGot `%s`"

builtin_print :: 0
builtin_println :: 1
builtin_readline :: 2
builtin_read_file :: 3
builtin_write_file :: 4
builtin_clear :: 5
builtin_run_executable :: 6
builtin_exit :: 7
builtin_get_os_args :: 8 // TODO

get_builtin_func_from_name :: proc(s: ^CheckerState, name: string) -> (u32, ExactCheckedType) {
    switch name {
    case "print":
        return builtin_print, s.string_to_nil_type
    case "println":
        return builtin_println, s.string_to_nil_type
    case "readline":
        return builtin_readline, s.string_to_string_type
    case "read_file":
        return builtin_read_file, s.string_to_string_type
    case "write_file":
        return builtin_write_file, s.string_string_to_nil_type
    case "clear":
        return builtin_clear, s.no_args_to_nil_type
    case "run_executable":
        return builtin_run_executable, s.array_of_strings_to_nil_type
    case "exit":
        return builtin_exit, s.i64_to_nil_type
    case:
        return max(u32), nil
    }
}

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

/*
// The `ExactCheckedType` returned is the return type of the function
// The `CheckedValue` returned is always either `nil`, `CheckedFunctionCall` or `CheckedStructTypeInitialisation`
handle_user_defined_named_function_call :: proc(
    s: ^CheckerState,
    pos: uint,
    function_name: string,
    args: []Value,
    body: ^[dynamic]CheckedStatement,
    loc := #caller_location,
) -> (
    CheckedValue,
    ExactCheckedType,
) {
    when debug_checker {
        print_call(loc, "handle_user_defined_named_function_call")
    }

    if is_builtin(function_name) {
        err(s, pos, "`%s` is a builtin, but it is not a function", function_name)
        return nil, nil
    }

    global_props, exists := s.globals[function_name]
    if !exists {
        err(s, pos, "The global `%s` is not defined", function_name)
        return nil, nil
    }

    switch value in global_props.value {
    case Value:
        func_index, is_func := value.value.(uint)
        if !is_func {
            err(
                s,
                pos,
                "TODO: The global value `%s` is not a function and so cannot be called",
                function_name,
            )
            return nil, nil
        }
        func_props, _ := get_info(s.func_types[:], func_index)

        if s.func_type == .Normal && func_props.type == .ComptimeFunc {
            err(s, pos, function_err2)
            return nil, nil
        }

        checked_args, ok := check_args(s, pos, function_name, args, func_props.args, body)
        if !ok {
            return nil, nil
        }

        return CheckedFunctionCall{func_index, checked_args},
            func_props.return_type == nil ? nil : func_props.return_type^

    case GlobalTypeWithGenericRef:
        err(s, pos, "No generic type argument passed to generic type")
        return nil, nil

    case GlobalTypeWithoutGenericRef:
        global := s.checked_global_types_without_generics[value.index]
        struct_type, struct_type_ok := get_struct_type(s, pos, global)
        if !struct_type_ok {
            return nil, nil
        }

        arg_types := struct_type.fields.type[:len(struct_type.fields)]
        checked_args, ok := check_args(s, pos, function_name, args, arg_types, body)
        if !ok {
            return nil, nil
        }

        return CheckedStructTypeInitialisation{value, checked_args}, value

    case nil:
        panic("Unreachable")

    case:
        panic("Unreachable")
    }
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
            call, return_type := handle_user_defined_named_function_call(
                s,
                pos,
                func_name,
                call.args,
                body,
            )
            if call == nil {
                return false
            }
            if return_type != nil {
                err(s, pos, function_err4)
                return false
            }
            append_elem(body, call.(CheckedFunctionCall))
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
            expected_type: ExactCheckedType = StringType{}
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
    type: ^ExactCheckedType,
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
            array_type: ExactCheckedType = nil
            item_type: ExactCheckedType = nil
            array := check_value(s, call.args[0], body, &array_type)
            item := check_value(s, call.args[1], body, &item_type)
            if array == nil || item == nil {
                return nil
            }
            array_length, exact_array_type, array_item_type := check_array(
                s,
                call.args[0].pos,
                array,
                array_type,
                "Expected an array type\nGot the type `%s`",
            )
            if array_length == nil {
                return nil
            }
            types_ok := expect_type(s, call.args[1].pos, array_item_type, item_type, "")
            if !types_ok {
                return nil
            }
            segments := make([]ArraySegment, 2)
            segments[0] = InlineArraySegment{array, array_length}
            segments[1] = SingleElemSegment{item}
            return_type := ArrayType(u32){0, exact_array_type.item_type} // TODO: Maybe `append` should be able to output fixed size arrays
            s.array_type_initialisations[combine_u32(return_type.length, return_type.item_type)] =
                struct{}{}
            array_ref := add_unnamed_variable(s, return_type, false)
            append_elem(body, CheckedArrayMutation{array_ref, return_type, segments})
            return finish_checking_value(s, pos, array_ref, return_type, type)
        case "readline":
            // (String) -> String
            if len(call.args) != 1 {
                argument_count_mismatch(s, pos, len(call.args), 1, "readline")
                return nil
            }
            expected_type: ExactCheckedType = StringType{}
            prompt_value := check_value(s, call.args[0], body, &expected_type)
            if prompt_value == nil {
                return nil
            }
            out := CheckedReadLine{new_clone(prompt_value)}
            return finish_checking_value(s, pos, out, StringType{}, type)
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
            value_type: ExactCheckedType = nil
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
            call, return_type := handle_user_defined_named_function_call(
                s,
                pos,
                func_name,
                call.args,
                body,
            )
            if call == nil {
                return nil
            }
            if return_type == nil {
                err(s, pos, function_err5)
                return nil
            }
            return finish_checking_value(s, pos, call, return_type, type)
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
                // (Any) -> String
                err(s, pos, "TODO: Implement emit_js_value")
                return nil
            case "emit_c_code":
                // (() -> I64) -> String
                err(s, pos, "TODO: Implement emit_c_code")
                return nil
            case "read_file":
                // (String) -> String
                if len(call.args) != 1 {
                    argument_count_mismatch(s, pos, len(call.args), 1, "compiler.read_file")
                    return false
                }
                expected_type: ExactCheckedType = StringType{}
                name_value := check_value(s, call.args[0], body, &expected_type)
                if name_value == nil {
                    return false
                }
                out := CheckedReadFile{new_clone(name_value)}
                return finish_checking_value(s, pos, out, StringType{}, type)
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
                when debug_checker {
                    debug("expected_type is %#v", expected_type)
                }
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
*/

// Returns nil if there are errors in the named type
handle_named_type :: proc(
    s: ^CheckerState,
    pos: uint,
    type_segments: IdentToken,
    generic_arg: ^Type,
    generic_arg_name: string,
) -> GenericCheckedType {
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
    builtin_type: GenericCheckedType = ---
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

        if generic_arg == nil {
            ref, is_type_without_generic := global.value.(GlobalTypeWithoutGenericRef)
            if !is_type_without_generic {
                err(s, pos, "The global `%s` is not a type without a generic arg", name)
                return nil
            }
            return GlobalTypeWithoutGenericRef{ref.index}
        } else {
            ref, is_type_with_generic := global.value.(GlobalTypeWithGenericRef)
            if !is_type_with_generic {
                err(s, pos, "The global `%s` is not a type with a generic arg", name)
                return nil
            }
            checked_generic_arg := check_type(s, generic_arg^, generic_arg_name)
            if checked_generic_arg == nil {
                return nil
            }
            return GenericType(^GenericCheckedType){ref.index, new_clone(checked_generic_arg)}
        }
    }
    if generic_arg != nil {
        err(s, pos, "The builtin type `%s` cannot have a generic argument", name)
        return nil
    }
    return builtin_type
}

to_str :: proc(
    s: ^CheckerState,
    pos: uint,
    body: ^[dynamic]CheckedStatement,
    val: CheckedValue,
    type: ExactCheckedType,
) -> (
    VariableRef,
    bool,
) {
    format: string
    // TODO: Rework to be able to emit JS code
    switch _ in type {
    case BoolType:
        format = "\"%b\""
    case StringType:
        format = "\"%s\""
    case I64Type:
        format = "\"%\" PRId64"
    case I32Type:
        format = "\"%\" PRId32"
    case I16Type:
        format = "\"%\" PRId16"
    case I8Type:
        format = "\"%\" PRId8"
    case U64Type:
        format = "\"%\" PRIu64"
    case U32Type:
        format = "\"%\" PRIu32"
    case U16Type:
        format = "\"%\" PRIu16"
    case U8Type:
        format = "\"%\" PRIu8"
    case ArrayType(u32):
        err(s, pos, "Cannot convert array to string")
        return VariableRef{}, false
    case FuncTypeRef:
        err(s, pos, "Cannot convert function to string")
        return VariableRef{}, false
    case GenericType(u32):
        err(s, pos, "Cannot convert generic type to string")
        return VariableRef{}, false
    case GlobalTypeWithoutGenericRef:
        err(s, pos, "Cannot convert global type to string")
        return VariableRef{}, false
    case Struct(ExactCheckedType):
        err(s, pos, "Cannot convert struct type to string")
        return VariableRef{}, false
    case SumType(ExactCheckedType, FuncTypeRef):
        err(s, pos, "Cannot convert sum type to string")
        return VariableRef{}, false
    case SumVariant(^ExactCheckedType):
        err(s, pos, "Cannot convert sum type variant to string")
        return VariableRef{}, false
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
         "readline",
         "read_file",
         "write_file",
         "clear",
         "run_executable",
         "exit",
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
         "to_str":
        return true
    case:
        return false
    }
}

add_unnamed_variable :: proc(
    s: ^CheckerState,
    variable_type: ExactCheckedType,
    variable_is_mut: bool,
    loc := #caller_location,
) -> VariableRef {
    when debug_checker {
        print_call(loc, "add_unnamed_variable")
    }
    assert(
        len(s.scopes[len(s.scopes) - 1].variable_is_muts) ==
        len(s.scopes[len(s.scopes) - 1].variable_types),
    )
    assert(variable_type != nil)
    var_ref := VariableRef{len(s.scopes) - 1, len(s.scopes[len(s.scopes) - 1].variable_is_muts)}
    append_elem(&s.scopes[len(s.scopes) - 1].variable_types, variable_type)
    append_elem(&s.scopes[len(s.scopes) - 1].variable_is_muts, variable_is_mut)
    return var_ref
}

// The boolean returned is whether there are errors
add_variable :: proc(
    s: ^CheckerState,
    variable_type: ExactCheckedType,
    variable_is_mut: bool,
    variable: IdentAndPos,
    loc := #caller_location,
) -> (
    VariableRef,
    bool,
) {
    when debug_checker {
        print_call(loc, "add_variable")
    }
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

