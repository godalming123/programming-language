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

Type :: union {
    Struct,
    Function,
    TypeVariable,
    Array,
}

VariableReference :: distinct string

Number :: distinct string

String :: distinct string

Value :: struct {
    pos:   uint,
    value: union {
        FunctionCall,
        JoinedValues,
        VariableReference,
        Number,
        String,
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
    function_name: string,
    args:          []Value, // TODO: Add named arguments
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


NameAndType :: struct {
    name: string,
    type: Type,
}

FunctionDefinition :: struct {
    inputs:  []NameAndType,
    outputs: []NameAndType,
    body:    []Statement,
}

ComponentDefinition :: struct {
    inputs: []NameAndType,
    body:   []Statement,
}

Global :: struct {
    position: uint,
    value:    union {
        Type,
        FunctionDefinition,
    },
}

File :: struct {
    imports: []Import,
    // TODO: Store the map order to maintain order when formatting is implemented
    globals: map[string]Global,
}

print_type :: proc(s: ^TreePrinterState, type: Type) {
    list_item(s, "todo")
}

print_name_and_type_list :: proc(s: ^TreePrinterState, label: string, list: []NameAndType) {
    list_item(s, label)
    for name_and_type, index in list {
        list_item(s, "`%s`:", name_and_type.name)
        print_type(s, name_and_type.type)
    }
}

print_value :: proc(s: ^TreePrinterState, value: Value, label_fmt: string, args: ..any) {
    list_item(s, label_fmt, ..args)
    list_item(s, "value at character index %d", value.pos)
    switch v in value.value {
    case Number:
        list_item(s, "number: %s", v)
    case FunctionCall:
        list_item(s, "function call:")
        {list_item(s, "function name: %s", v.function_name)}
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
    }
}

print_block :: proc(s: ^TreePrinterState, label: string, block: []Statement) {
    list_item(s, label)
    for statement, index in block {
        list_item(s, "statement %d at character index %d", index, statement.position)
        #partial switch value in statement.value {
        case ForInLoop:
            list_item(s, "for in loop:")
            {
                list_item(s, "variables:")
                print_variable :: proc(s: ^TreePrinterState, var: IdentAndPos) {
                    list_item(s, "`%s` at character index %d", var.ident, var.pos)
                }
                print_variable(s, value.variables[0])
                print_variable(s, value.variables[1])
                print_variable(s, value.variables[2])
            }
            switch iter in value.iterator {
            case NumericIterator:
                list_item(s, "numeric iterator:")
                {list_item(s, "type: %v", iter.type)}
                {list_item(s, "start: %v", iter.start)}
                {list_item(s, "end: %v", iter.end)}
                {list_item(s, "step: %v", iter.step)}
            case string:
                list_item(s, "string iterator `%s`", iter)
            }
            print_block(s, "body", value.body)
        case ReturnStatement:
            list_item(s, "return statement")
            for v, i in value {
                print_value(s, v, "value %d:", i)
            }
        case YieldStatement:
            list_item(s, "yield statement")
            for v, i in value {
                print_value(s, v, "value %d:", i)
            }
        case IfElseStatement:
            list_item(s, "if else statement")
            print_value(s, value.condition, "condition:")
            print_block(s, "if block:", value.if_block)
            print_block(s, "else block:", value.else_block)
        case FunctionCall:
            list_item(s, "a function call")
            {list_item(s, "function name: %s", value.function_name)}
            for v, i in value.args {
                print_value(s, v, "arg %d:", i)
            }
        case:
            list_item(s, "todo")

        }
    }
}

print_ast :: proc(imports: []Import, globals: map[string]Global) {
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
            list_item(&s, "global called `%s` at character index %d:", name, global.position)
            switch value in global.value {
            case Type:
                list_item(&s, "value is a type:")
                print_type(&s, value)
            case FunctionDefinition:
                list_item(&s, "value is a function definition:")
                print_name_and_type_list(&s, "inputs:", value.inputs)
                print_name_and_type_list(&s, "outputs:", value.outputs)
                print_block(&s, "body:", value.body)
            }
        }
    }
}

