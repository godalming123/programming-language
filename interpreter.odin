package main

// This file is mostly AI generated
// TODO: Proper memory management (garbage collector?)

import "base:runtime"
import "core:bufio"
import "core:fmt"
import "core:net"
import "core:os"
import "core:path/filepath"
import "core:slice"
import "core:strings"
import "webserver"

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
    RuntimeString,
    RuntimeArray,
    RuntimeStringOrderedHashMap,
    RuntimeStringOrderedHashMapInitFunc,
    RuntimeI64OrderedHashMap,
    RuntimeI64OrderedHashMapInitFunc,
    RuntimeStruct,
    RuntimeStructTypeInitFunc,
    RuntimeSumType,
    RuntimeSumTypeInitFunc,
    CheckedFuncRef,
    BuiltinFunction,
    SetHttpServerHandler,
    HttpServerListenAndServe,
}

RuntimeSumTypeInitFunc :: struct {
    variant_index: uint,
}

SetHttpServerHandler :: struct {
    server: uint,
}

HttpServerListenAndServe :: struct {
    server: uint,
}

RuntimeString :: struct {
    needs_freeing: bool,
    value:         string,
}

RuntimeArray :: struct {
    needs_freeing: bool,
    elems:         [dynamic]RuntimeValue,
}

RuntimeStringOrderedHashMap :: struct {
    needs_freeing: bool,
    hashmap:       map[string]RuntimeValue,
    order:         [dynamic]string,
}
RuntimeI64OrderedHashMap :: struct {
    needs_freeing: bool,
    hashmap:       map[i64]RuntimeValue,
    order:         [dynamic]i64,
}
RuntimeStringOrderedHashMapInitFunc :: struct {}
RuntimeI64OrderedHashMapInitFunc :: struct {}
RuntimeStruct :: struct {
    needs_freeing: bool,
    field_values:  []RuntimeValue,
}
RuntimeStructTypeInitFunc :: struct {}
RuntimeSumType :: struct {
    needs_freeing: bool,
    variant_index: uint,
    payload:       []RuntimeValue,
}

Frame :: struct {
    func_index: uint,
    scopes:     [dynamic][]RuntimeValue,
}

BuiltinHandler :: struct {
    data:      rawptr,
    procedure: proc(state: ^InterpState, f: BuiltinFunction, args: []RuntimeValue) -> RuntimeValue,
}

ReturnFromFunction :: struct {
    value: RuntimeValue,
}

ControlFlowOperation :: union {
    ContinueLoop,
    BreakLoop,
    ReturnFromFunction,
}

HttpServer :: struct {
    socket:  net.TCP_Socket,
    handler: CheckedFuncRef,
}

InterpState :: struct {
    types:           Types,
    checked_funcs:   []CheckedFunction,
    builtin_handler: BuiltinHandler,
    frames:          [dynamic]Frame,
    current_loop:    uint,
    control_flow_op: ControlFlowOperation,
    http_servers:    [dynamic]HttpServer,
}

/*
interpret :: proc(
    c: Checked,
    builtin_handler: BuiltinHandler,
    entry_func_ref: CheckedFuncRef,
) -> RuntimeValue {
    state := InterpState {
        c               = c,
        frames          = make([dynamic]Frame),
        builtin_handler = builtin_handler,
    }

    result := interp_execute_function2(&state, entry_func_ref, nil)
    assert(len(state.frames) == 0)
    delete(state.frames)
    return result
}
*/

interp_execute_function :: proc(s: ^InterpState, c: CheckedFunctionCall) -> RuntimeValue {
    fn_val := interp_eval_value(s, c.function^)
    args := make([]RuntimeValue, len(c.args))
    for arg_val, i in c.args {
        args[i] = interp_clone_value(interp_eval_value(s, arg_val))
    }

    if _, is_struct_init_func := fn_val.(RuntimeStructTypeInitFunc); is_struct_init_func {
        return RuntimeStruct{true, args}
    }

    if init_func, is_sum_type_init_func := fn_val.(RuntimeSumTypeInitFunc); is_sum_type_init_func {
        return RuntimeSumType{true, init_func.variant_index, args}
    }

    defer {
        for &arg in args {
            interp_destroy_value(&arg)
        }
        delete(args)
    }

    #partial switch val in fn_val {
    case BuiltinFunction:
        return s.builtin_handler.procedure(s, val, args)
    case CheckedFuncRef:
        return interp_execute_function2(s, val, args)
    case RuntimeI64OrderedHashMapInitFunc:
        assert(len(args) == 0)
        return RuntimeI64OrderedHashMap{}
    case RuntimeStringOrderedHashMapInitFunc:
        assert(len(args) == 0)
        return RuntimeStringOrderedHashMap{}
    case SetHttpServerHandler:
        assert(len(args) == 1)
        s.http_servers[val.server].handler = args[0].(CheckedFuncRef)
        return nil
    case HttpServerListenAndServe:
        assert(len(args) == 0)
        server := s.http_servers[val.server]
        if server.handler.index == max(uint) {
            panic("`listen_and_serve` called when handler has not been set")
        }
        buf: [65536]byte
        for {
            client, _, accept_err := net.accept_tcp(server.socket)
            if accept_err != nil {
                // TODO: Better error handling
                panic(fmt.aprintf("Accept error: %v", accept_err))
            }
            defer net.close(client)

            n, receive_err := net.recv_tcp(client, buf[:])
            if receive_err != nil {
                // TODO: Better error handling
                panic(fmt.aprintf("Receive error: %v", receive_err))
            }

            data := buf[:n]

            if webserver.is_websocket_upgrade_request(data) {
                panic("TODO")
            } else {
                request, ok := webserver.parse_http_request(data)
                if !ok {
                    webserver.send_error(client, 400, "Bad Request")
                    continue
                }
                defer delete(request.headers)

                req_fields := make([]RuntimeValue, 2)
                req_fields[0] = RuntimeString{false, request.path}
                req_fields[1] = RuntimeString{false, request.method}

                handler_args := make([]RuntimeValue, 1)
                handler_args[0] = RuntimeStruct{true, req_fields}

                response := interp_execute_function2(
                    s,
                    server.handler,
                    handler_args,
                ).(RuntimeSumType)

                webserver.send_response(
                    client,
                    200,
                    "OK",
                    response_type_variant_index_to_content_type(response.variant_index),
                    transmute([]byte)(response.payload[0].(RuntimeString).value),
                )
            }
        }
        return nil
    case:
        panic("Unreachable")
    }
}

interp_execute_function2 :: proc(
    state: ^InterpState,
    func_ref: CheckedFuncRef,
    args: []RuntimeValue,
) -> RuntimeValue {
    checked_func := state.checked_funcs[func_ref.index]

    frame := Frame {
        func_index = func_ref.index,
        scopes     = make([dynamic][]RuntimeValue),
    }
    append_elem(&frame.scopes, args)

    append_elem(&frame.scopes, make([]RuntimeValue, len(checked_func.variables)))
    // for var_type, i in checked_func.variables {
    // frame.scopes[1][i] = interp_default_value(state, var_type)
    // }

    append_elem(&state.frames, frame)

    assert(state.control_flow_op == nil)
    interp_exec_block(state, checked_func.body)
    f := pop(&state.frames)
    assert(len(f.scopes) == 2)
    for &v in f.scopes[1] {
        interp_destroy_value(&v)
    }
    delete(f.scopes[1])
    delete(f.scopes)

    if return_data, returning := state.control_flow_op.(ReturnFromFunction); returning {
        state.control_flow_op = nil
        return return_data.value
    } else {
        assert(state.control_flow_op == nil)
        return nil
    }
}

/*
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
        return RuntimeString{false, ""}
    case:
        type_val := get_type(state.types, t)
        switch v in type_val {
        case OrderedHashMapTypeWithStringKey:
            return RuntimeStringOrderedHashMap{}
        case OrderedHashMapTypeWithI64Key:
            return RuntimeI64OrderedHashMap{}
        case ArrayType:
            return RuntimeArray{true, make([dynamic]RuntimeValue)}
        case Struct(Type, Type):
            fields := make([]RuntimeValue, len(v.fields))
            for field_type, i in v.fields {
                fields[i] = interp_default_value(state, field_type.type)
            }
            return RuntimeStruct{true, fields}
        case SumType(Type):
            payload := interp_default_value(state, v.variants[0].payload)
            return RuntimeSumType{true, 0, new_clone(payload)}
        case FuncType, GenericTypeValue:
            return i64(0)
        }
        return i64(0)
    }
}
*/

interp_exec_block :: proc(state: ^InterpState, body: []CheckedStatement) {
    for stmt in body {
        if state.control_flow_op != nil {
            return
        }
        interp_exec_statement(state, stmt)
    }
}

interp_push_scope :: proc(state: ^InterpState, variable_types: []Type) {
    scope := make([]RuntimeValue, len(variable_types))
    append_elem(&state.frames[len(state.frames) - 1].scopes, scope)
}

interp_pop_scope :: proc(state: ^InterpState, loc := #caller_location) {
    when debug_interpreter {
        print_call(loc, "interp_pop_scope")
    }
    frame := &state.frames[len(state.frames) - 1]
    scope := pop(&frame.scopes)
    for &val in scope {
        interp_destroy_value(&val)
    }
    delete(scope)
}

interp_destroy_value :: proc(val: ^RuntimeValue, loc := #caller_location) {
    /*
    when debug_interpreter {
        print_call(loc, "interp_destroy_value")
    }
    switch &v in val {
    case RuntimeStringOrderedHashMap:
        if v.needs_freeing {
            for _, &value in v.hashmap {
                interp_destroy_value(&value)
            }
            delete(v.hashmap)
            delete(v.order)
            v.needs_freeing = false
        }
    case RuntimeI64OrderedHashMap:
        if v.needs_freeing {
            for _, &value in v.hashmap {
                interp_destroy_value(&value)
            }
            delete(v.hashmap)
            delete(v.order)
            v.needs_freeing = false
        }
    case RuntimeArray:
        if v.needs_freeing {
            for &elem in v.elems {
                interp_destroy_value(&elem)
            }
            // TODO: Proper memory management
            // delete(v.elems)
            v.needs_freeing = false
        }
    case RuntimeStruct:
        if v.needs_freeing {
            for &field in v.field_values {
                interp_destroy_value(&field)
            }
            delete(v.field_values)
            v.needs_freeing = false
        }
    case RuntimeSumType:
        if v.needs_freeing {
            for &value in v.payload {
                interp_destroy_value(&value)
            }
            delete(v.payload)
            v.needs_freeing = false
        }
    case RuntimeString:
        if v.needs_freeing {
            delete(v.value)
            v.needs_freeing = false
        }
    case nil,
         i64,
         i32,
         i16,
         i8,
         u64,
         u32,
         u16,
         u8,
         bool,
         FuncDefinitionRef,
         BuiltinFunction,
         RuntimeStructTypeInitFunc,
         SumTypeInitFunc,
         RuntimeStringOrderedHashMapInitFunc,
         RuntimeI64OrderedHashMapInitFunc:
    }
    */
}

interp_clone_value :: proc(val: RuntimeValue, loc := #caller_location) -> RuntimeValue {
    when debug_interpreter {
        print_call(loc, "interp_clone_value")
    }
    switch v in val {
    case nil:
        panic("Unreachable: Uninitialised")
    case RuntimeStringOrderedHashMap:
        out_hashmap := make(map[string]RuntimeValue, len(v.hashmap))
        for key, value in v.hashmap {
            out_hashmap[key] = interp_clone_value(value)
        }
        out_order := slice.clone_to_dynamic(v.order[:])
        return RuntimeStringOrderedHashMap{true, out_hashmap, out_order}
    case RuntimeI64OrderedHashMap:
        out_hashmap := make(map[i64]RuntimeValue, len(v.hashmap))
        for key, value in v.hashmap {
            out_hashmap[key] = interp_clone_value(value)
        }
        out_order := slice.clone_to_dynamic(v.order[:])
        return RuntimeI64OrderedHashMap{true, out_hashmap, out_order}
    case RuntimeArray:
        new_elems := make([dynamic]RuntimeValue, len(v.elems))
        for elem, i in v.elems {
            new_elems[i] = interp_clone_value(elem)
        }
        return RuntimeArray{true, new_elems}
    case RuntimeStruct:
        new_fields := make([]RuntimeValue, len(v.field_values))
        for field, i in v.field_values {
            new_fields[i] = interp_clone_value(field)
        }
        return RuntimeStruct{true, new_fields}
    case RuntimeSumType:
        payload := make([]RuntimeValue, len(v.payload))
        for value, i in v.payload {
            payload[i] = interp_clone_value(value)
        }
        return RuntimeSumType{true, v.variant_index, payload}
    case RuntimeString:
        return RuntimeString{true, strings.clone(v.value)}
    case i64,
         i32,
         i16,
         i8,
         u64,
         u32,
         u16,
         u8,
         bool,
         CheckedFuncRef,
         BuiltinFunction,
         RuntimeStructTypeInitFunc,
         RuntimeSumTypeInitFunc,
         RuntimeStringOrderedHashMapInitFunc,
         RuntimeI64OrderedHashMapInitFunc,
         HttpServerListenAndServe,
         SetHttpServerHandler:
        return val
    }
    return RuntimeValue{}
}

interp_exec_statement :: proc(state: ^InterpState, stmt: CheckedStatement) {
    switch s in stmt {
    case UnreachableStatement:
        panic("Reached unreachable code")

    case CheckedReturn:
        if s.value != nil {
            state.control_flow_op = ReturnFromFunction {
                interp_clone_value(interp_eval_value(state, s.value)),
            }
        } else {
            state.control_flow_op = ReturnFromFunction{nil}
        }
        when debug_interpreter {
            debug("state.control_flow_op set to %v", state.control_flow_op)
        }

    case CheckedIf:
        cond := interp_eval_value(state, s.condition)
        cond_bool, cond_ok := cond.(bool)
        if !cond_ok {
            panic("Expected bool in if condition")
        }
        if cond_bool {
            interp_push_scope(state, s.if_block.variables)
            interp_exec_block(state, s.if_block.body)
            interp_pop_scope(state)
        } else {
            interp_push_scope(state, s.else_block.variables)
            interp_exec_block(state, s.else_block.body)
            interp_pop_scope(state)
        }

    case CheckedLoop:
        loop_index := s.loop_index
        interp_push_scope(state, s.variables)
        interp_exec_block(state, s.enter)
        outer: for {
            if state.control_flow_op != nil do break

            old_loop := state.current_loop
            state.current_loop = loop_index
            interp_exec_block(state, s.body)
            state.current_loop = old_loop

            switch op in state.control_flow_op {
            case ReturnFromFunction:
                break outer
            case BreakLoop:
                if op.loop_index == loop_index {
                    state.control_flow_op = nil
                    break outer
                }
            case ContinueLoop:
                if op.loop_index == loop_index {
                    state.control_flow_op = nil
                }
            }

            interp_exec_block(state, s.continue_code)
        }
        interp_pop_scope(state)

    case ContinueLoop:
        assert(state.control_flow_op == nil)
        state.control_flow_op = ContinueLoop{s.loop_index}

    case BreakLoop:
        assert(state.control_flow_op == nil)
        state.control_flow_op = BreakLoop{s.loop_index}

    case CheckedMutation:
        get_mutable_value :: proc(
            s: ^InterpState,
            value: CheckedValue,
            loc := #caller_location,
        ) -> ^RuntimeValue {
            when debug_interpreter {
                print_call(loc, "get_mutable_value")
            }
            #partial switch v in value {
            case CheckedArrayAccess:
                array := get_mutable_value(s, v.array^).(RuntimeArray)
                return &array.elems[interp_eval_value(s, v.index^).(i64)]
            case VariableRef:
                return &s.frames[len(s.frames) - 1].scopes[v.nesting_level][v.index]
            case CheckedOrderedHashMapAccess:
                key := interp_eval_value(s, v.key^)
                #partial switch &hash_map_value in get_mutable_value(s, v.hash_map^) {
                case RuntimeStringOrderedHashMap:
                    key_string := key.(RuntimeString).value
                    if !(key_string in hash_map_value.hashmap) {
                        hash_map_value.hashmap[key_string] = nil
                        append_elem(&hash_map_value.order, key_string)
                    }
                    return &hash_map_value.hashmap[key_string]
                case RuntimeI64OrderedHashMap:
                    return &hash_map_value.hashmap[key.(i64)]
                }
                panic("Unreachable")
            case:
                panic("Unreachable")
            }
        }
        mutable_value := get_mutable_value(state, s.destination)
        interp_destroy_value(mutable_value)
        mutable_value^ = interp_clone_value(interp_eval_value(state, s.value))

    case CheckedArrayMutation:
        old_value :=
            state.frames[len(state.frames) - 1].scopes[s.variable.nesting_level][s.variable.index]
        arr, old_value_is_array := old_value.(RuntimeArray)
        if old_value_is_array {
            clear(&arr.elems)
        } else {
            arr = RuntimeArray{true, make([dynamic]RuntimeValue)}
        }
        for segment in s.segments {
            switch seg in segment {
            case SingleElemSegment:
                val := interp_eval_value(state, seg.elem)
                append_elem(&arr.elems, interp_clone_value(val))
            case InlineArraySegment:
                src := interp_eval_value(state, seg.array)
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
        assert(interp_execute_function(state, s) == nil)

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
                    RuntimeStruct{false, sum_val.payload}
            }
            interp_exec_block(state, branch.block.body)
            interp_pop_scope(state)
        }

    }
}

interp_is_equal :: proc(s: ^InterpState, lhs: RuntimeValue, val1: CheckedValue) -> bool {
    rhs := interp_eval_value(s, val1)
    a_i64, a_is_i64 := lhs.(i64)
    if a_is_i64 {
        return a_i64 == rhs.(i64)
    }
    a_bool, a_is_bool := lhs.(bool)
    if a_is_bool {
        return a_bool == rhs.(bool)
    }
    panic("Unreachable")
}

interp_eval_comptime_value :: proc(s: ^InterpState, value: CompileTimeValue) -> RuntimeValue {
    switch comptime in value {
    case CompileTimeStructInitialisation:
        out_args := make([]RuntimeValue, len(comptime.args))
        for arg, i in comptime.args {
            out_args[i] = interp_eval_comptime_value(s, arg)
        }
        return RuntimeStruct{true, out_args}
    case CheckedFuncRef:
        return comptime
    case StringLiteralValue:
        return RuntimeString{false, string(comptime)}
    case NumberValue:
        as_u64, ok := big_uint_to_u64(comptime.value.absolute_value)
        assert(ok)
        if comptime.value.is_negated {
            return -i64(as_u64)
        }
        return i64(as_u64)
    case BoolValue:
        return bool(comptime)
    case Type, GlobalValueWithGenericRef, UninitialisedOrderedHashMapType, Import:
        panic("Unreachable")
    case:
        panic("Unreachable")
    }
}

interp_eval_value :: proc(s: ^InterpState, v: CheckedValue) -> RuntimeValue {
    switch value in v {
    case OrderedHashMapInitFunc:
        #partial switch type in get_type(s.types, value.type) {
        case OrderedHashMapTypeWithStringKey:
            return RuntimeStringOrderedHashMapInitFunc{}
        case OrderedHashMapTypeWithI64Key:
            return RuntimeI64OrderedHashMapInitFunc{}
        }
        panic("Unreachable")
    case CheckedOrderedHashMapAccess:
        hash_map := interp_eval_value(s, value.hash_map^)
        key := interp_eval_value(s, value.key^)
        #partial switch hash_map_value in hash_map {
        case RuntimeStringOrderedHashMap:
            return hash_map_value.hashmap[key.(RuntimeString).value]
        case RuntimeI64OrderedHashMap:
            return hash_map_value.hashmap[key.(i64)]
        }
        panic("Unreachable")
    case KeysOfOrderedHashMapWithStringKey:
        keys := interp_eval_value(s, value.hash_map^).(RuntimeStringOrderedHashMap).order
        out := make([dynamic]RuntimeValue, len(keys))
        for key, i in keys {
            out[i] = RuntimeString{false, key}
        }
        return RuntimeArray{true, out}
    case KeysOfOrderedHashMapWithI64Key:
        keys := interp_eval_value(s, value.hash_map^).(RuntimeI64OrderedHashMap).order
        out := make([dynamic]RuntimeValue, len(keys))
        for key, i in keys {
            out[i] = key
        }
        return RuntimeArray{true, out}

    case CompileTimeValue:
        return interp_eval_comptime_value(s, value)

    case ToString:
        inner := interp_eval_value(s, value.value^)
        switch inner_val in inner {
        case nil:
            panic("Unreachable: Uninitialised")
        case i64:
            return RuntimeString{true, fmt.aprintf("%d", inner_val)}
        case i32:
            return RuntimeString{true, fmt.aprintf("%d", inner_val)}
        case i16:
            return RuntimeString{true, fmt.aprintf("%d", inner_val)}
        case i8:
            return RuntimeString{true, fmt.aprintf("%d", inner_val)}
        case u64:
            return RuntimeString{true, fmt.aprintf("%d", inner_val)}
        case u32:
            return RuntimeString{true, fmt.aprintf("%d", inner_val)}
        case u16:
            return RuntimeString{true, fmt.aprintf("%d", inner_val)}
        case u8:
            return RuntimeString{true, fmt.aprintf("%d", inner_val)}
        case bool:
            return RuntimeString{false, inner_val ? "true" : "false"}
        case RuntimeString:
            return inner_val
        case RuntimeArray,
             RuntimeStruct,
             RuntimeSumType,
             CheckedFuncRef,
             BuiltinFunction,
             RuntimeStringOrderedHashMap,
             RuntimeI64OrderedHashMap,
             RuntimeStructTypeInitFunc,
             RuntimeSumTypeInitFunc,
             RuntimeStringOrderedHashMapInitFunc,
             RuntimeI64OrderedHashMapInitFunc,
             HttpServerListenAndServe,
             SetHttpServerHandler:
            panic("Unreachable")
        }

    case VariableRef:
        return s.frames[len(s.frames) - 1].scopes[value.nesting_level][value.index]

    case BooleanNotValue:
        inner := interp_eval_value(s, value^)
        return !inner.(bool)

    case CheckedJoinedValues:
        lhs := interp_eval_value(s, value.val0^)

        switch value.join_method {

        case .In:
            #partial switch b in interp_eval_value(s, value.val1^) {
            case RuntimeStringOrderedHashMap:
                return lhs.(RuntimeString).value in b.hashmap
            case RuntimeI64OrderedHashMap:
                return lhs.(i64) in b.hashmap
            }
            panic("Unreachable")

        case .Addition:
            return lhs.(i64) + interp_eval_value(s, value.val1^).(i64)

        case .Subtraction:
            return lhs.(i64) - interp_eval_value(s, value.val1^).(i64)

        case .Multiplication:
            return lhs.(i64) * interp_eval_value(s, value.val1^).(i64)

        case .Division:
            return lhs.(i64) / interp_eval_value(s, value.val1^).(i64)

        case .Modulo:
            return lhs.(i64) % interp_eval_value(s, value.val1^).(i64)

        case .IsEqual:
            return interp_is_equal(s, lhs, value.val1^)

        case .IsNotEqual:
            return !interp_is_equal(s, lhs, value.val1^)

        case .IsLessThan:
            return lhs.(i64) < interp_eval_value(s, value.val1^).(i64)

        case .IsLessThanOrEqual:
            return lhs.(i64) <= interp_eval_value(s, value.val1^).(i64)

        case .IsGreaterThan:
            return lhs.(i64) > interp_eval_value(s, value.val1^).(i64)

        case .IsGreaterThanOrEqual:
            return lhs.(i64) >= interp_eval_value(s, value.val1^).(i64)

        case .BooleanAnd:
            if lhs.(bool) == false {
                return false
            }
            return interp_eval_value(s, value.val1^).(bool)

        case .BooleanOr:
            if lhs.(bool) == true {
                return true
            }
            return interp_eval_value(s, value.val1^).(bool)

        case .StringConcat:
            return RuntimeString {
                true,
                strings.concatenate(
                    []string {
                        lhs.(RuntimeString).value,
                        interp_eval_value(s, value.val1^).(RuntimeString).value,
                    },
                ),
            }

        case .Append, .Concat, .Colon, .Arrow:
            panic("Unreachable")
        }

    case CheckedFunctionCall:
        return interp_execute_function(s, value)

    case StructTypeInitFunc:
        // struct_type := get_type(state.checked.types, value.type).(Struct(Type, Type))
        // fields := make([dynamic]RuntimeValue, len(struct_type.fields))
        // for field_type, i in struct_type.fields {
        // fields[i] = interp_default_value(state, field_type.type)
        // }
        // return RuntimeStruct{fields}
        return RuntimeStructTypeInitFunc{}

    case SumTypeInitFunc:
        return RuntimeSumTypeInitFunc{value.variant_index}

    case CheckedArrayAccess:
        arr_val := interp_eval_value(s, value.array^)
        index_val := interp_eval_value(s, value.index^)
        arr, arr_ok := arr_val.(RuntimeArray)
        if !arr_ok {panic("Expected array for array access")}
        idx, idx_ok := index_val.(i64)
        if !idx_ok {panic("Expected i64 for array index")}
        return arr.elems[idx]

    case CheckedFieldAccess:
        struct_val := interp_eval_value(s, value.value^)
        s, s_ok := struct_val.(RuntimeStruct)
        if !s_ok {panic("Expected struct for field access")}
        return s.field_values[value.field_index]

    case LengthOfArray:
        arr := interp_eval_value(s, value.array^).(RuntimeArray)
        return i64(len(arr.elems))

    case LengthOfOrderedHashMapWithStringKey:
        hash_map := interp_eval_value(s, value.hash_map^)
        return i64(len(hash_map.(RuntimeStringOrderedHashMap).order))

    case LengthOfOrderedHashMapWithI64Key:
        hash_map := interp_eval_value(s, value.hash_map^)
        return i64(len(hash_map.(RuntimeI64OrderedHashMap).order))

    case StringsAreEqual:
        str0 := interp_eval_value(s, value.str0^)
        str1 := interp_eval_value(s, value.str1^)
        return str0.(RuntimeString).value == str1.(RuntimeString).value

    case BuiltinFunction:
        return value

    }
    panic("Unreachable")
}

DefaultBuiltinHandlerData :: struct {
    working_dir: string,
    pipe:        Pipe(^os.File),
}

default_builtin_handler_procedure :: proc(
    state: ^InterpState,
    index: BuiltinFunction,
    args: []RuntimeValue,
) -> RuntimeValue {
    data := cast(^DefaultBuiltinHandlerData)state.builtin_handler.data
    // TODO: Maybe we should use the definitions in glue.c
    // https://odin-lang.org/news/binding-to-c/
    switch index {
    case .print:
        assert(len(args) == 1)
        fmt.fprint(data.pipe.stdout, args[0].(RuntimeString).value)
        return nil
    case .println:
        assert(len(args) == 1)
        fmt.fprintln(data.pipe.stdout, args[0].(RuntimeString).value)
        return nil
    case .eprint:
        assert(len(args) == 1)
        fmt.fprint(data.pipe.stderr, args[0].(RuntimeString).value)
        return nil
    case .eprintln:
        assert(len(args) == 1)
        fmt.fprintln(data.pipe.stderr, args[0].(RuntimeString).value)
        return nil
    case .readline:
        assert(len(args) == 1)
        fmt.print(args[0].(RuntimeString).value)
        scanner: bufio.Scanner
        bufio.scanner_init(&scanner, os.to_reader(os.stdin))
        assert(bufio.scan(&scanner))
        return RuntimeString{false, bufio.scanner_text(&scanner)}
    case .read_file:
        panic("TODO")
    case .write_file:
        assert(len(args) == 2)
        file_name := args[0].(RuntimeString).value
        path: string = ---
        defer delete(path)
        if filepath.is_abs(file_name) {
            path = strings.clone(file_name)
        } else {
            err: runtime.Allocator_Error = ---
            path, err = filepath.join([]string{data.working_dir, file_name})
            if err != nil {
                panic(fmt.aprintf("Failed to join path: %v", err))
            }
        }
        err2 := os.write_entire_file(path, transmute([]u8)args[1].(RuntimeString).value)
        if err2 != nil {
            panic(fmt.aprintf("Failed to write file at `%s`: %v", path, err2))
        }
        return nil
    case .clear:
        assert(len(args) == 0)
        fmt.print(ansi_clear)
        return nil
    case .run_executable:
        panic("TODO")
    case .exit:
        assert(len(args) == 1)
        os.exit(int(args[0].(i64)))
    case .get_os_args:
        panic("TODO")
    case .emit_js_code:
        // TODO: Tree shake globals which are not used by the globals in `globals_map`
        assert(len(args) == 2)
        globals_map := args[0].(RuntimeStringOrderedHashMap)
        glue := args[1].(RuntimeString)
        builder := emit_javascript(state.types, state.checked_funcs)
        for global_name in globals_map.order {
            strings.write_string(&builder, "let ")
            strings.write_string(&builder, global_name)
            strings.write_string(&builder, "=")
            emit_js_runtime_value(&builder, globals_map.hashmap[global_name])
            strings.write_string(&builder, ";")
        }
        strings.write_string(&builder, glue.value)
        return RuntimeString{true, strings.to_string(builder)}
    case .cache_contains:
        panic("TODO")
    case .cache_set:
        panic("TODO")
    case .cache_get:
        panic("TODO")
    case .init_http_server:
        assert(len(args) == 0)

        server_index: uint = len(state.http_servers)

        funcs := make([]RuntimeValue, 3)
        funcs[0] = SetHttpServerHandler{server_index}
        funcs[1] = HttpServerListenAndServe{server_index}

        endpoint := net.Endpoint{net.IP4_Address{0, 0, 0, 0}, 8080}
        // TODO: Implement upper limit on number of ports to try
        for {
            // TODO: Log that the port is being tried
            socket, err := net.listen_tcp(endpoint)
            if err == nil {
                funcs[2] = i64(endpoint.port)
                append(&state.http_servers, HttpServer{socket, CheckedFuncRef{max(uint)}})
                return RuntimeStruct{true, funcs}
            }
            if err != net.Bind_Error.Address_In_Use {
                // TODO: Better error reporting
                panic(fmt.aprintf("Failed create TCP socket and start listening: %v", err))
            }
            // TODO: Log that the port is already in use
            endpoint.port += 1
        }
    case .string_repeat:
        assert(len(args) == 2)
        return RuntimeString {
            true,
            strings.repeat(args[0].(RuntimeString).value, int(args[1].(i64))),
        }
    case .invalid_builtin:
        panic("Unreachable")
    case:
        panic(fmt.aprintf("Unreachable (index is %d)", index))
    }
}

