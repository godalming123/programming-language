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

get_builtin_func_from_name :: proc(s: ^CheckerState, name: string) -> (u32, ExactCheckedType) {
    switch name {
    case "print":
        return builtin_print, s.string_to_nil_type
    case "println":
        return builtin_println, s.string_to_nil_type
    case "eprint":
        return builtin_eprint, s.string_to_nil_type
    case "eprintln":
        return builtin_eprintln, s.string_to_nil_type
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

// Returns nil if there are errors in the named type
handle_named_type :: proc(
    s: ^CheckerState,
    pos: uint,
    type_segments: Ident,
    generic_args: []Unit,
    generic_arg_name: string,
) -> GenericCheckedType {
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
            if len(generic_args) != 0 {
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

        if len(generic_args) == 0 {
            ref, is_type_without_generic := global.value.(GlobalTypeWithoutGenericRef)
            if !is_type_without_generic {
                err(s, pos, "The global `%s` is not a type without a generic arg", name)
                return nil
            }
            return GlobalTypeWithoutGenericRef{ref.index}
        } else if len(generic_args) != 1 {
            err(s, pos, "TODO: Support types with more than 1 generic argument")
            return nil
        } else {
            ref, is_type_with_generic := global.value.(GlobalTypeWithGenericRef)
            if !is_type_with_generic {
                err(s, pos, "The global `%s` is not a type with a generic arg", name)
                return nil
            }
            checked_generic_arg := check_type(s, generic_args[0], generic_arg_name)
            if checked_generic_arg == nil {
                return nil
            }
            return GenericType(^GenericCheckedType){ref.index, new_clone(checked_generic_arg)}
        }
    }
    if len(generic_args) != 0 {
        err(s, pos, "The builtin type `%s` cannot have a generic argument", name)
        return nil
    }
    return builtin_type
}

to_str :: proc(
    s: ^CheckerState,
    pos: uint,
    val: CheckedValue,
    type: ExactCheckedType,
) -> CheckedValue {
    from_type: ToStringFromType = ---
    switch _ in type {
    case BoolType:
        from_type = .BoolType
    case StringType:
        return val
    case I64Type:
        from_type = .I64Type
    case I32Type:
        from_type = .I32Type
    case I16Type:
        from_type = .I16Type
    case I8Type:
        from_type = .I8Type
    case U64Type:
        from_type = .U64Type
    case U32Type:
        from_type = .U32Type
    case U16Type:
        from_type = .U16Type
    case U8Type:
        from_type = .U8Type
    case ArrayType(u32):
        err(s, pos, "Cannot convert array to string")
        return nil
    case FuncTypeRef:
        err(s, pos, "Cannot convert function to string")
        return nil
    case GenericType(u32):
        err(s, pos, "Cannot convert generic type to string")
        return nil
    case GlobalTypeWithoutGenericRef:
        err(s, pos, "Cannot convert global type to string")
        return nil
    case Struct(ExactCheckedType):
        err(s, pos, "Cannot convert struct type to string")
        return nil
    case SumType(ExactCheckedType, FuncTypeRef):
        err(s, pos, "Cannot convert sum type to string")
        return nil
    case SumVariant(^ExactCheckedType):
        err(s, pos, "Cannot convert sum type variant to string")
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

