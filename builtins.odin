package main

// Handles namespace operations. Namespace operations are all handled in the
// same file to maintain a consistent set of builtins which cannot be overridden.

import "core:fmt"
import "core:strings"

builtins_err :: "`%s` is a builtin\nCannot override builtins"
function_err :: "Within unmarked function, cannot call `#comptime` function"

// function_todo1 :: "TODO: Handle function calls where the function isn't a variable reference"
// function_todo2 :: "TODO: Handle function calls where `len(function_name_segments) > 2`"
// function_err1 :: "Compiler functions can only be called in function definitions which are marked with `#comptime`"
// function_err3 :: "In 2 segment function call that is used as a %s where the first segment is `compiler`\nExpected the second segment to be either %s\nGot `%s`"
// function_err4 :: "This function returns a value, so it cannot be used this as a statement"
// function_err5 :: "This function does not return a value, so it cannot be used as a value"
// function_err6 :: "First segment of a 2 segment function call that is used as a statement must be `compiler`\nGot `%s`"
// function_err7 :: "First segment of a 2 segment function call that is used as a value must be either `compiler` or ``\nGot `%s`"

builtin_print :: 0
builtin_println :: 1
builtin_eprint :: 2
builtin_eprintln :: 3
builtin_readline :: 4
builtin_read_file :: 5
builtin_write_file :: 6
builtin_clear :: 7
builtin_run_executable :: 8
builtin_exit :: 9
builtin_get_os_args :: 10 // TODO
builtin_emit_js_code :: 11
builtin_string_repeat :: 12

get_builtin_func_from_name :: proc(name: string) -> (u32, Type) {
    switch name {
    case "print":
        return builtin_print, string_to_nil_type
    case "println":
        return builtin_println, string_to_nil_type
    case "eprint":
        return builtin_eprint, string_to_nil_type
    case "eprintln":
        return builtin_eprintln, string_to_nil_type
    case "readline":
        return builtin_readline, string_to_string_type
    case "read_file":
        return builtin_read_file, string_to_string_type
    case "write_file":
        return builtin_write_file, string_string_to_nil_type
    case "clear":
        return builtin_clear, no_args_to_nil_type
    case "run_executable":
        return builtin_run_executable, array_of_strings_to_nil_type
    case "exit":
        return builtin_exit, i64_to_nil_type
    case "string_repeat":
        return builtin_string_repeat, string_i64_to_string_type
    case:
        return max(u32), invalid_type
    }
}

get_builtin_type_from_name :: proc(name: string) -> Type {
    switch name {
    case "I64":
        return i64_type
    case "I32":
        return i32_type
    case "I16":
        return i16_type
    case "I8":
        return i8_type
    case "U64":
        return u64_type
    case "U32":
        return u32_type
    case "U16":
        return u16_type
    case "U8":
        return u8_type
    case "Bool":
        return bool_type
    case "String":
        return string_type
    case "Type":
        return type_type
    case:
        return unknown_type
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

to_str :: proc(s: ^CheckerState, pos: uint, val: CheckedValue, type: Type) -> CheckedValue {
    from_type: ToStringFromType = ---
    switch type {
    case bool_type:
        from_type = .BoolType
    case string_type:
        return val
    case i64_type:
        from_type = .I64Type
    case i32_type:
        from_type = .I32Type
    case i16_type:
        from_type = .I16Type
    case i8_type:
        from_type = .I8Type
    case u64_type:
        from_type = .U64Type
    case u32_type:
        from_type = .U32Type
    case u16_type:
        from_type = .U16Type
    case u8_type:
        from_type = .U8Type
    case:
        err(s, pos, "Cannot convert the type `%s` to `String`", type_to_string(s, type))
        return nil
    }
    return ToString{from_type, new_clone(val)}
}

// The boolean returned is whether the name is a builtin
is_builtin :: proc(name: string) -> bool {
    switch name {
    case "compiler",
         "print",
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
         "Type",
         "OrderedHashMap",
         "to_str",
         "string_repeat",
         "function_id":
        return true
    case:
        return false
    }
}

add_unnamed_variable :: proc(
    s: ^CheckerState,
    variable_type: Type,
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
    var_ref := VariableRef{len(s.scopes) - 1, len(s.scopes[len(s.scopes) - 1].variable_is_muts)}
    append_elem(&s.scopes[len(s.scopes) - 1].variable_types, variable_type)
    append_elem(&s.scopes[len(s.scopes) - 1].variable_is_muts, variable_is_mut)
    return var_ref
}

// The boolean returned is whether there are errors
add_variable :: proc(
    s: ^CheckerState,
    variable_type: Type,
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

