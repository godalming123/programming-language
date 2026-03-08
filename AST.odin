package main

Import :: struct {
    pos:        uint,
    components: IdentToken,
}

StructField :: struct {
    name: IdentAndPos,
    type: Type,
}

Struct :: struct {
    // Stored this way to preserve the order
    fields_map: map[string]uint, // An index into `fields`
    fields:     #soa[]StructField,
}

Function :: struct {
    inputs:  []Type,
    outputs: []Type,
}

TypeVariable :: struct {
    identifier:   IdentToken,
    generic_type: ^Type, // can be `nil`
}

Array :: struct {
    length:    uint, // 0 means dynamic length
    item_type: ^Type,
}

SumTypeVariant :: struct {
    name:    IdentAndPos,
    payload: Struct,
}

SumType :: struct {
    // Stored this way to preserve the order
    variants_map: map[string]uint, // An index into `variants`
    variants:     #soa[]SumTypeVariant,
}

// DynamicType :: distinct ^Type

TypeValue :: union {
    Struct,
    Function,
    TypeVariable,
    Array,
    SumType,
    // DynamicType,
}

Type :: struct {
    pos:  uint,
    type: TypeValue,
}

VariableReference :: distinct IdentToken

Number :: distinct string

String :: distinct []string

Char :: distinct byte

Bool :: distinct bool

SingleElemAccess :: distinct ^Value
RangedAccess :: struct {
    start: ^Value,
    end:   ^Value,
}

ArrayAccess :: struct {
    array:     ^Value,
    index_pos: uint,
    index:     union {
        SingleElemAccess,
        RangedAccess,
    },
}

TypeInitialisation :: struct {
    type: TypeValue,
    args: []Value,
}

ValueInBrackets :: distinct ^Value

MarkedValue :: struct {
    value:   ^ValueWithoutPos,
    markers: []IdentAndPos,
}

ValueWithoutPos :: union {
    uint, // an index into the function definitions
    FunctionCall,
    JoinedValues,
    VariableReference,
    Number,
    String,
    Char,
    Bool,
    ArrayAccess,
    ValueInBrackets,
    TypeInitialisation,
    MarkedValue,
}

Value :: struct {
    pos:   uint,
    value: ValueWithoutPos,
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

VariableDestType :: enum {
    // type // what goes before the identifier
    Constant, // nothing
    Mutable, // `mut`
    ConstantAddedToPcs, // `+`
    MutableAddedToPcs, // `mut +`
    Mutated, // `~`
}

VariableDest :: struct {
    name:        IdentAndPos,
    type:        VariableDestType,
    array_index: ^Value, // nil if there isn't an array index
}

VariableManagement :: struct {
    value:         Value,
    destination:   []VariableDest,
    mutation_type: MutationType,
}

FunctionCall :: struct {
    function: ^Value,
    args:     []Value, // TODO: Add named arguments
}

Iterator :: union {
    Value,
    NumericIterator,
}

NumericIteratorType :: enum {
    IncludeEndValue,
    ExcludeEndValue,
}

NumericIterator :: struct {
    start: Value,
    end:   Value,
    step:  ^Value, // nil if the step is 1
    type:  NumericIteratorType,
}

IdentAndPos :: struct {
    ident: string,
    pos:   uint,
}

ConditionControlledLoop :: struct {
    type:      enum {
        WhileLoop,
        DoWhileLoop,
    },
    condition: Value,
    body:      []Statement,
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

MatchBranch :: struct {
    name: IdentAndPos,
    type: Type,
    body: []Statement,
}

MatchStatement :: struct {
    value:    Value,
    branches: []MatchBranch,
}

ReturnStatement :: distinct []Value
YieldStatement :: distinct []Value

Statement :: struct {
    position: uint,
    value:    union {
        VariableManagement,
        FunctionCall,
        ConditionControlledLoop,
        ForInLoop,
        IfElseStatement,
        ReturnStatement,
        YieldStatement,
        MatchStatement,
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

FunctionOutput :: struct {
    name:        IdentAndPos,
    value_type:  Type,
    output_type: enum {
        Normal,
        AllocatedOntoStack,
    },
}

NameAndType :: struct {
    name: string,
    type: Type,
}

FunctionDefinition :: struct {
    inputs:  []FunctionArg,
    outputs: []FunctionOutput,
    body:    []Statement,
    markers: []IdentAndPos,
}

//ComponentDefinition :: struct {
//    inputs: []NameAndType,
//    body:   []Statement,
//}

//File :: struct {
//    imports: []Import,
//    // TODO: Store the map order to maintain order when formatting is implemented
//    globals: map[string]Global,
//}
/*
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

print_output_list :: proc(s: ^TreePrinterState, label: string, list: []FunctionOutput) {
    list_item(s, label)
    for output, index in list {
        list_item(s, "`%s`:", output.name)
        switch output.output_type {
        case .Normal:
            list_item(s, "normal type")
        case .AllocatedOntoStack:
            list_item(s, "allocated onto stack type")
        }
        print_type(s, output.value_type)
    }
}

print_value :: proc(
    s: ^TreePrinterState,
    funcs: []FunctionDefinition,
    value: Value,
    label_fmt: string,
    args: ..any,
) {
    list_item(s, label_fmt, ..args)
    list_item(s, "value at character index %d", value.pos)
    switch v in value.value {
    case Bool:
        if v {
            list_item(s, "The boolean literal `true`")
        } else {
            list_item(s, "The boolean literal `false`")
        }
    case uint:
        list_item(s, "value is a function definition:")
        print_argument_list(s, "inputs:", funcs[v].inputs)
        print_output_list(s, "outputs:", funcs[v].outputs)
        print_block(s, funcs, funcs[v].body, "body:")
    case TypeInitialisation:
        list_item(s, "type initialisation")
        list_item(s, "TODO: Handle printing this")
    case ValueInBrackets:
        print_value(s, funcs, v^, "value in brackets")
    case ArrayAccess:
        switch index in v.index {
        case SingleElemAccess:
            print_value(s, funcs, index^, "single elem array access:")
            print_value(s, funcs, v.array^, "array:")
        case RangedAccess:
            list_item(s, "ranged array access:")
            print_value(s, funcs, v.array^, "array:")
            print_value(s, funcs, index.start^, "start:")
            print_value(s, funcs, index.end^, "end:")
        }
    case Number:
        list_item(s, "number: %s", v)
    case FunctionCall:
        list_item(s, "function call")
        print_value(s, funcs, v.function^, "function value")
        for arg, index in v.args {
            print_value(s, funcs, arg, "value %d", index)
        }
    case JoinedValues:
        list_item(s, "joined values:")
        {list_item(s, "join method: %v", v.join_method)}
        print_value(s, funcs, v.val0^, "val0:")
        print_value(s, funcs, v.val1^, "val1:")
    case VariableReference:
        list_item(s, "variable: %s", v)
    case String:
        list_item(s, "string: %s", v)
    case Char:
        list_item(s, "character: %c", v)
    }
}

print_block :: proc(
    s: ^TreePrinterState,
    funcs: []FunctionDefinition,
    block: []Statement,
    label: string,
) {
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
            case Value:
                print_value(s, funcs, iter, "value iterator:")
            }
            print_block(s, funcs, v.body, "body")
        case DoWhileLoop:
            list_item(s, "Do while loop:")
            print_block(s, funcs, v.body, "loop body:")
            print_value(s, funcs, v.condition, "loop condition:")
        case WhileLoop:
            list_item(s, "While loop:")
            print_value(s, funcs, v.condition, "loop condition:")
            print_block(s, funcs, v.body, "loop body:")
        case ReturnStatement:
            list_item(s, "return statement")
            for v, i in v {
                print_value(s, funcs, v, "value %d:", i)
            }
        case YieldStatement:
            list_item(s, "yield statement")
            for v, i in v {
                print_value(s, funcs, v, "value %d:", i)
            }
        case IfElseStatement:
            list_item(s, "if else statement")
            print_value(s, funcs, v.condition, "condition:")
            print_block(s, funcs, v.if_block, "if block:")
            print_block(s, funcs, v.else_block, "else block:")
        case FunctionCall:
            list_item(s, "function call")
            print_value(s, funcs, v.function^, "function value")
            for arg, index in v.args {
                print_value(s, funcs, arg, "value %d", index)
            }
        case:
            list_item(s, "todo")

        }
    }
}

print_ast :: proc(
    imports: []Import,
    globals: map[string]ParsedGlobal,
    funcs: []FunctionDefinition,
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
            switch value in global.value {
            case uint:
                list_item(&s, "global type called `%s` at character index %d:", name, global.pos)
                print_type_value(&s, global_types[value])
            case Value:
                print_value(
                    &s,
                    funcs,
                    value,
                    "global value called `%s` at character index %d:",
                    name,
                    global.pos,
                )
            }
        }
    }
}

*/

