package main

// Handles namespace operations. Namespace operations are all handled in the
// same file to maintain a consistent set of builtins which cannot be overridden.

import "core:fmt"

// Returns nil if there are errors in the named function call
handle_named_function_call :: proc(
    s: ^CheckerState,
    pos: uint,
    function_name: string,
    args: []Value,
) -> union {
        CheckedPrint,
        CheckedFunctionCall,
        I64Value,
    } {
    switch function_name {
    case "print":
        stmt, ok := check_print(s, pos, args, false)
        if !ok {
            return nil
        }
        return stmt
    case "println":
        stmt, ok := check_print(s, pos, args, true)
        if !ok {
            return nil
        }
        return stmt
    case "len":
        if len(args) != 1 {
            err_ok(
                s.file,
                pos,
                "Argument count mismatch\nFunction call provides %d arguments\n`len` function expects 1 argument\n",
                len(args),
            )
            return nil
        }
        value, ok := check_value(s, args[0])
        if !ok {
            return nil
        }
        type := get_type(s, value)
        array_ref, is_array := type.(ArrayRef)
        if !is_array {
            err_ok(
                s.file,
                pos,
                "Expected an array type\nGot the type `%s`\nYou can only get the length of an array",
                type_to_string(s, type),
            )
            return nil
        }
        array := get_array_type(s.array_types[:], &array_ref)
        if array.length != 0 {
            return I64Value(fmt.aprint(array.length))
        }
        err_ok(s.file, pos, "TODO: Handle getting the length of a dynamic length array")
        return nil
    }
    is_builtin := err_if_builtin(
        s.file,
        function_name,
        pos,
        "`%s` is a builtin, but it is not a function",
        function_name,
    )
    if is_builtin {
        return nil
    }
    func_index, exists := get_global_function(s.file, s.globals, pos, function_name, "")
    if !exists {
        return nil
    }

    func_props := s.global_funcs_props[func_index]
    if len(args) != len(func_props.args) {
        err_ok(
            s.file,
            pos,
            "Argument count mismatch\nFunction call provides %d arguments\nFunction definition expects %d arguments",
            len(args),
            len(func_props.args),
        )
        return nil
    }

    checked_args := make([]CheckedValue, len(args))
    for arg, i in args {
        value, ok := check_value(s, arg)
        if !ok {
            return nil
        }

        type := get_type(s, value)
        ok = expect_type(s, arg.pos, func_props.args[i].type, type)
        if !ok {
            return nil
        }

        checked_args[i] = value
    }

    return CheckedFunctionCall{func_index, checked_args}
}

// Returns nil if there are errors in the named type
handle_named_type :: proc(file: CompilerFile, pos: uint, type_name: string) -> CheckedType {
    switch type_name {
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
        file,
        type_name,
        pos,
        "`%s` is a builtin, but it is not a type",
        type_name,
    )
    if is_builtin {
        return nil
    }
    err_ok(file, pos, "TODO: Support checking type variable")
    return nil
}

// The boolean returned is whether there are errors in the print statement
check_print :: proc(
    s: ^CheckerState,
    pos: uint,
    args: []Value,
    add_newline: bool,
) -> (
    CheckedPrint,
    bool,
) {
    if len(args) < 1 {
        err_ok(s.file, pos, "Print function must have atleast one argument")
        return CheckedPrint{}, false
    }
    if len(args) != 1 {
        err_ok(s.file, pos, "TODO: Handle print function with more than one arguments")
        return CheckedPrint{}, false
    }
    val, val_ok := check_value(s, args[0])
    if !val_ok {
        return CheckedPrint{}, false
    }
    type := get_type(s, val)
    format: string
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
        err_ok(s.file, pos, "Cannot print an array")
        return CheckedPrint{}, false
    }
    values := make([]CheckedValue, 1)
    values[0] = val
    return CheckedPrint{format, values}, true
}

// The boolean returned is whether the name is a builtin
err_if_builtin :: proc(
    file: CompilerFile,
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
         "len":
        err_ok(file, pos, msg, ..args)
        return true
    }
    return false
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
    assert(
        len(s.scopes[len(s.scopes) - 1].variable_is_muts) ==
        len(s.scopes[len(s.scopes) - 1].variable_types),
    )
    is_builtin := err_if_builtin(
        s.file,
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
    var_ref := VariableRef {
        len(s.scopes) - 1,
        uint(len(s.scopes[len(s.scopes) - 1].variable_is_muts)),
    }
    if variable.ident != "" {
        if variable.ident in s.variables_map {
            err_ok(s.file, variable.pos, "Redeclaration of variable `%s`", variable.ident)
            return VariableRef{}, false
        }
        s.variables_map[variable.ident] = var_ref
    }
    append_elem(&s.scopes[len(s.scopes) - 1].variable_types, variable_type)
    append_elem(&s.scopes[len(s.scopes) - 1].variable_is_muts, variable_is_mut)
    return var_ref, true
}

