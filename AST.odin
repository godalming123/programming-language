package main

StructField :: struct(T: typeid) {
    name: IdentAndPos,
    type: T,
}

Struct :: struct(T: typeid, ExtraData: typeid) {
    extra_data: ExtraData,

    // Stored this way to preserve the order
    fields_map: map[string]uint, // An index into `fields`
    fields:     #soa[]StructField(T),
}

SumTypeVariant :: struct(Payload: typeid) {
    name:    IdentAndPos,
    payload: Payload,
}

SumType :: struct(VariantPayload: typeid) {
    // Stored this way to preserve the order
    variants_map: map[string]uint, // An index into `variants`
    variants:     #soa[]SumTypeVariant(VariantPayload),
}

Ident :: struct {
    segments: #soa[]IdentAndPos,
}

/*
make_ident :: proc(token: IdentToken, file: FileRef) -> Ident {
    // TODO: Do not copy the token
    out := make(#soa[]IdentAndPos, len(token))
    for segment, i in token {
        out[i] = IdentAndPos{segment.ident, Pos{segment.index, file}}
    }
    return Ident{out}
}
*/

Number :: struct {
    is_negated:      bool,
    absolute_digits: string,
}

String :: distinct []string

Char :: distinct byte

Bool :: distinct bool

MarkedUnit :: struct {
    value:   ^Unit,
    markers: []IdentAndPos,
}

Tuple :: struct {
    elements: []Unit,
}

FuncDefinitionRef :: struct {
    // an index into:
    // - `ParserState.function_defs`
    // - `ParsedProject.function_defs`
    index: uint,
}

CheckedFuncRef :: struct {
    // An index into:
    // - `Checked.checked_funcs`
    // - `CheckerState.checked_functions`
    index: uint,
}

// - A unit is a value or a type
// - There is no distinction between a value and a type in the AST because
//   there are cases where the parser cannot tell whether something is a value
//   or a type
// - For example, something like `HtmlElem[State].Text("hello world")`, where
//   `HtmlElem[State]` could be either:
//   - A value with a type like `{ Text: (String) -> I64 }`, or;
//   - A sum type like `< Text{contents: String} >`

/*
InitialUnit :: union {
    Struct(Unit),
    SumType(Unit, struct {}),
    Tuple,
    FuncDefinitionRef,
    Ident,
    Number,
    String,
    Char,
    Bool,
    Import,
}
*/

UnitWithoutPos :: union {
    Struct(Unit, struct {}),
    SumType(Struct(Unit, struct {})),
    Tuple,
    FuncDefinitionRef,
    CallWithBrackets,
    CallWithSquareBrackets,
    CallWithFrontedSquareBrackets,
    JoinedUnits,
    Ident,
    Number,
    String,
    Char,
    Bool,
    MarkedUnit,
    Import,
}

Unit :: struct {
    pos:   Pos,
    value: UnitWithoutPos,
}

ParsingValue :: struct {
    enclosed_in_brackets: bool,
    value:                Unit,
}

UnitJoinMethod :: enum {
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
    In,

    // Prioraty 3
    Append, // ::
    Concat, // ++
    StringConcat, // &
    Colon, // Used for array indexing (for example `my_array[start_index:end_index]`)
    Arrow, // Used for function types (for example `(String) -> U64`)

    // Prioraty 4
    Addition,
    Subtraction,
    Modulo,

    // Prioraty 5
    Multiplication,
    Division,
}

// Operations with higher prioraty (prioraty 5 is the highest prioraty) are executed first
// See https://en.wikipedia.org/wiki/Order_of_operations#Programming_languages
get_prioraty :: proc(join_method: UnitJoinMethod) -> uint {
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
    case .In:
        return 2
    case .Append, .Concat, .StringConcat, .Colon, .Arrow:
        return 3
    case .Subtraction, .Addition, .Modulo:
        return 4
    case .Division, .Multiplication:
        return 5
    }
    panic("Unreachable")
}

JoinedUnits :: struct {
    join_method: UnitJoinMethod,
    unit0:       ^Unit,
    unit1:       ^Unit,
}

VariableDefinition :: struct {
    name:  string,
    type:  Unit,
    value: Unit,
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
    name: IdentAndPos,
    type: VariableDestType,

    // The unit in square brackets
    // nil if there isn't a key
    key:  ^Unit,
}

MutationType :: enum {
    IncrementBy,
    DecrementBy,
    MultiplyBy,
    DivideBy,
    SetTo,
}

VariableManagement :: struct {
    value:         Unit,
    destination:   []VariableDest,
    mutation_type: MutationType,
}

Call :: struct {
    unit_being_called: ^Unit,
    args:              []Unit, // TODO: Add named arguments
}

CallWithBrackets :: distinct Call // A(B, C, D)
CallWithSquareBrackets :: distinct Call // A[B, C, D]
CallWithFrontedSquareBrackets :: distinct Call // [B, C, D]A

Iterator :: union {
    Unit,
    NumericIterator,
}

NumericIteratorType :: enum {
    IncludeEndValue,
    ExcludeEndValue,
}

NumericIterator :: struct {
    start: Unit,
    end:   Unit,
    step:  ^Unit, // nil if the step is 1
    type:  NumericIteratorType,
}

Pos :: struct {
    index: uint,
    file:  FileRef,
}

unknown_pos :: Pos{max(uint), nil}

/*
IdentAndIndex :: struct {
    ident: string,
    index: uint,
}
*/

IdentAndPos :: struct {
    ident: string,
    pos:   Pos,
}

ConditionControlledLoop :: struct {
    type:      enum {
        WhileLoop,
        DoWhileLoop,
    },
    condition: Unit,
    body:      []Statement,
}

ForInLoop :: struct {
    label:     IdentAndPos,
    // At most there can be 3 variables:
    // - The iteration the for loop is on
    // - The key of the thing being iterated over
    // - The value of the thing being iterated over
    variables: [3]IdentAndPos,
    iterator:  Iterator,
    body:      []Statement,
}

IfElseStatement :: struct {
    condition:  Unit,
    if_block:   []Statement,
    else_block: []Statement,
}

MatchBranch :: struct {
    label: Unit,
    body:  []Statement,
}

MatchStatement :: struct {
    value:    Unit,
    branches: []MatchBranch,
}

ReturnStatement :: distinct []Unit
YieldStatement :: distinct []Unit
ContinueStatement :: struct {
    label: IdentAndPos,
}
UnreachableStatement :: struct {}

Statement :: struct {
    position: Pos,
    value:    union {
        VariableManagement,
        CallWithBrackets,
        ConditionControlledLoop,
        ForInLoop,
        IfElseStatement,
        ReturnStatement,
        YieldStatement,
        MatchStatement,
        ContinueStatement,
        UnreachableStatement,
    },
}

FunctionArg :: struct {
    name:       IdentAndPos,
    value_type: Unit,
    arg_type:   enum {
        Normal,
        Mutable,
        RemovedFromStack,
    },
}

FunctionDefinition :: struct {
    inputs: #soa[]FunctionArg,
    output: ^Unit, // if the function has no output, then `output` is `nil`
    body:   []Statement,
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
*/

debug_call :: proc(funcs: []FunctionDefinition, c: Call) {
    debug_nesting += 1
    debug_unit(funcs, c.unit_being_called^)
    for arg, i in c.args {
        debug("arg %d", i)
        debug_nesting += 1
        debug_unit(funcs, arg)
        debug_nesting -= 1
    }
    debug_nesting -= 1
}

debug_unit :: proc(funcs: []FunctionDefinition, unit: Unit) {
    debug("value at character index %d", unit.pos)
    debug_nesting += 1
    switch v in unit.value {
    case Struct(Unit, struct {}):
        panic("TODO")
    case SumType(Struct(Unit, struct {})):
        panic("TODO")
    case Number:
        debug("is_negated: %v", v.is_negated)
        debug("absolute_digits: %s", v.absolute_digits)
    case Char:
        panic("TODO")
    case MarkedUnit:
        panic("TODO")
    case Import:
        panic("TODO")
    case Bool:
        if v {
            debug("The boolean literal `true`")
        } else {
            debug("The boolean literal `false`")
        }
    case FuncDefinitionRef:
        debug("value is a function definition (TODO)")
    // print_argument_list(s, "inputs:", funcs[v].inputs)
    // print_output_list(s, "outputs:", funcs[v].outputs)
    // print_block(s, funcs, funcs[v].body, "body:")
    case Tuple:
        debug("tuple:")
        for elem in v.elements {
            debug_unit(funcs, elem)
        }
    case CallWithBrackets:
        debug("call with brackets")
        debug_call(funcs, Call(v))
    case CallWithSquareBrackets:
        debug("call with square brackets")
        debug_call(funcs, Call(v))
    case CallWithFrontedSquareBrackets:
        debug("call with fronted square brackets")
        debug_call(funcs, Call(v))
    case JoinedUnits:
        debug("joined units")
        debug_nesting += 1
        debug("join method: %v", v.join_method)
        debug_unit(funcs, v.unit0^)
        debug_unit(funcs, v.unit1^)
        debug_nesting -= 1
    case Ident:
        debug("ident")
        debug_nesting += 1
        for segment in v.segments {
            debug("%q", segment.ident)
        }
        debug_nesting -= 1
    case String:
        debug("string: %v", v)
    }
    debug_nesting -= 1
}

/*
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

