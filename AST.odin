package main

Import :: struct {
    components: []string,
}

Struct :: struct {
    fields: map[string]Type,
}

Function :: struct {
    inputs:  []Type,
    outputs: []Type,
}

TypeVariable :: distinct string
Array :: struct {
    length:    uint, // 0 means dynamic length
    item_type: ^Type,
}

SumTypeVariant :: struct {
    name: string,
    type: Type,
}

SumType :: struct {
    variants: []SumTypeVariant,
}

TypeValue :: union {
    Struct,
    Function,
    TypeVariable,
    Array,
    SumType,
}

Type :: struct {
    pos:  uint,
    type: TypeValue,
}

VariableReference :: distinct string

Number :: distinct string

String :: distinct string

Char :: distinct byte

ArrayAccess :: struct {
    array: ^Value,
    index: ^Value,
}

ValueInBrackets :: distinct ^Value

Value :: struct {
    pos:   uint,
    value: union {
        FunctionCall,
        JoinedValues,
        VariableReference,
        Number,
        String,
        Char,
        ArrayAccess,
        ValueInBrackets,
    },
}

ParsingValue :: struct {
    enclosed_in_brackets: bool,
    value:                Value,
}

ValueJoinMethod :: enum {
    // Prioraty 0
    BooleanAnd,
    BooleanOr,

    // Prioraty 1
    IsEqual,
    IsNotEqual,
    IsGreaterThan,
    IsLessThan,
    IsGreaterThanOrEqual,
    IsLessThanOrEqual,

    // Prioraty 2
    Multiplication,
    Division,

    // Prioraty 3
    Addition,
    Subtraction,
    Modulo,
}

// Operations with higher prioraty (prioraty 3 is the highest prioraty) are executed first
// See https://en.wikipedia.org/wiki/Order_of_operations#Programming_languages
get_prioraty :: proc(join_method: ValueJoinMethod) -> uint {
    switch join_method {
    case .BooleanAnd, .BooleanOr:
        return 0
    case .IsEqual,
         .IsNotEqual,
         .IsGreaterThan,
         .IsLessThan,
         .IsGreaterThanOrEqual,
         .IsLessThanOrEqual:
        return 1
    case .Division, .Multiplication:
        return 2
    case .Subtraction, .Addition, .Modulo:
        return 3
    }
    panic("Unreachable")
}

JoinedValues :: struct {
    join_method: ValueJoinMethod,
    val0:        ^Value,
    val1:        ^Value,
}

VariableDefinition :: struct {
    name:  string,
    type:  Type,
    value: Value,
}

VariableManagement :: struct {
    destination:   []NameAndType,
    value:         Value,
    mutation_type: MutationType,
}

FunctionCall :: struct {
    function: ^Value,
    args:     []Value, // TODO: Add named arguments
}

Iterator :: union {
    string, // Iterating over a variable
    NumericIterator,
}

NumericIteratorType :: enum {
    IncludeEndValue,
    ExcludeEndValue,
}

NumericIterator :: struct {
    start: string,
    end:   string,
    step:  string,
    type:  NumericIteratorType,
}

IdentAndPos :: struct {
    ident: string,
    pos:   uint,
}

ForInLoop :: struct {
    // At most there can be 3 variables:
    // - The iteration the for loop is on
    // - The key of the thing being iterated over
    // - The value of the thing being iterated over
    variables: [3]IdentAndPos,
    iterator:  Iterator,
    body:      []Statement,
}

IfElseStatement :: struct {
    condition:  Value,
    if_block:   []Statement,
    else_block: []Statement,
}

ReturnStatement :: distinct []Value
YieldStatement :: distinct []Value

Statement :: struct {
    position: uint,
    value:    union {
        VariableManagement,
        FunctionCall,
        ForInLoop,
        IfElseStatement,
        ReturnStatement,
        YieldStatement,
    },
}

FunctionArg :: struct {
    name:       IdentAndPos,
    value_type: Type,
    arg_type:   enum {
        Normal,
        Mutable,
        RemovedFromStack,
    },
}

NameAndType :: struct {
    name: string,
    type: Type,
}

FunctionDefinition :: struct {
    inputs:  []FunctionArg,
    outputs: []NameAndType,
    body:    []Statement,
}

ComponentDefinition :: struct {
    inputs: []NameAndType,
    body:   []Statement,
}

//File :: struct {
//    imports: []Import,
//    // TODO: Store the map order to maintain order when formatting is implemented
//    globals: map[string]Global,
//}

print_type :: proc(s: ^TreePrinterState, type: Type) {
    list_item(s, "Type at character index %d:", type.pos)
    print_type_value(s, type.type)
}

print_type_value :: proc(s: ^TreePrinterState, type: TypeValue) {
    list_item(s, "todo")
}

print_name_and_type_list :: proc(s: ^TreePrinterState, label: string, list: []NameAndType) {
    list_item(s, label)
    for name_and_type, index in list {
        list_item(s, "`%s`:", name_and_type.name)
        print_type(s, name_and_type.type)
    }
}

print_argument_list :: proc(s: ^TreePrinterState, label: string, list: []FunctionArg) {
    list_item(s, label)
    for arg, index in list {
        list_item(s, "`%s`:", arg.name)
        switch arg.arg_type {
        case .Normal:
            list_item(s, "normal type")
        case .Mutable:
            list_item(s, "mutable type")
        case .RemovedFromStack:
            list_item(s, "removed from stack type")
        }
        print_type(s, arg.value_type)
    }
}

print_value :: proc(s: ^TreePrinterState, value: Value, label_fmt: string, args: ..any) {
    list_item(s, label_fmt, ..args)
    list_item(s, "value at character index %d", value.pos)
    switch v in value.value {
    case ValueInBrackets:
        print_value(s, v^, "value in brackets")
    case ArrayAccess:
        list_item(s, "array access:")
        print_value(s, v.array^, "array:")
        print_value(s, v.index^, "index:")
    case Number:
        list_item(s, "number: %s", v)
    case FunctionCall:
        list_item(s, "function call")
        print_value(s, v.function^, "function value")
        for arg, index in v.args {
            print_value(s, arg, "value %d", index)
        }
    case JoinedValues:
        list_item(s, "joined values:")
        {list_item(s, "join method: %v", v.join_method)}
        print_value(s, v.val0^, "val0:")
        print_value(s, v.val1^, "val1:")
    case VariableReference:
        list_item(s, "variable: %s", v)
    case String:
        list_item(s, "string: %s", v)
    case Char:
        list_item(s, "character: %c", v)
    }
}

print_block :: proc(s: ^TreePrinterState, label: string, block: []Statement) {
    list_item(s, label)
    for statement, index in block {
        list_item(s, "statement %d at character index %d", index, statement.position)
        #partial switch v in statement.value {
        case ForInLoop:
            list_item(s, "for in loop:")
            {
                list_item(s, "variables:")
                print_variable :: proc(s: ^TreePrinterState, var: IdentAndPos) {
                    list_item(s, "`%s` at character index %d", var.ident, var.pos)
                }
                print_variable(s, v.variables[0])
                print_variable(s, v.variables[1])
                print_variable(s, v.variables[2])
            }
            switch iter in v.iterator {
            case NumericIterator:
                list_item(s, "numeric iterator:")
                {list_item(s, "type: %v", iter.type)}
                {list_item(s, "start: %v", iter.start)}
                {list_item(s, "end: %v", iter.end)}
                {list_item(s, "step: %v", iter.step)}
            case string:
                list_item(s, "string iterator `%s`", iter)
            }
            print_block(s, "body", v.body)
        case ReturnStatement:
            list_item(s, "return statement")
            for v, i in v {
                print_value(s, v, "value %d:", i)
            }
        case YieldStatement:
            list_item(s, "yield statement")
            for v, i in v {
                print_value(s, v, "value %d:", i)
            }
        case IfElseStatement:
            list_item(s, "if else statement")
            print_value(s, v.condition, "condition:")
            print_block(s, "if block:", v.if_block)
            print_block(s, "else block:", v.else_block)
        case FunctionCall:
            list_item(s, "function call")
            print_value(s, v.function^, "function value")
            for arg, index in v.args {
                print_value(s, arg, "value %d", index)
            }
        case:
            list_item(s, "todo")

        }
    }
}

print_ast :: proc(
    imports: []Import,
    globals: map[string]ParsedGlobal,
    global_functions: []FunctionDefinition,
    global_types: []TypeValue,
) {
    s: TreePrinterState

    {
        list_item(&s, "%d imports:", len(imports))
        for i, index in imports {
            list_item(&s, "import %d", index)
            for component, index in i.components {
                list_item(&s, "component %d: %s", index, component)
            }
        }
    }

    {
        list_item(&s, "%d globals:", len(globals))
        for name, global in globals {
            list_item(&s, "global called `%s` at character index %d:", name, global.pos)
            switch global.kind {
            case .Type:
                list_item(&s, "value is a type:")
                print_type_value(&s, global_types[global.index])
            case .Function:
                list_item(&s, "value is a function definition:")
                print_argument_list(&s, "inputs:", global_functions[global.index].inputs)
                print_name_and_type_list(&s, "outputs:", global_functions[global.index].outputs)
                print_block(&s, "body:", global_functions[global.index].body)
            }
        }
    }
}

