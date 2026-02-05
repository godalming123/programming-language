package main

import "core:fmt"
import "core:slice"
import "core:strings"

// Things that might need adding in the future:
// - Handle numbers with decimals and + and - as one token
// - Handle character literals that use `'` for example 'a'
// - Create separate tokens for each possible combination of symbols that is valid

Error :: distinct string
NewlineToken :: struct {}
OpenBracketToken :: struct {} // (
CloseBracketToken :: struct {} // )
OpenSquareBracketToken :: struct {} // [
CloseSquareBracketToken :: struct {} // ]
OpenAngleBracketToken :: struct {} // <
CloseAngleBracketToken :: struct {} // >
OpenBraceToken :: struct {} // {
CloseBraceToken :: struct {} // }
CommaToken :: struct {} // ,
ColonToken :: struct {} // :
ArrowToken :: struct {} // ->
SymbolsToken :: distinct string
DigitsToken :: distinct string
IdentToken :: distinct string
InToken :: struct {} // in
StepToken :: struct {} // step
ForToken :: struct {} // for
IfToken :: struct {} // if
ElseToken :: struct {} // else
StructToken :: struct {} // struct
SumToken :: struct {} // sum
ImportToken :: struct {} // import
ReturnToken :: struct {} // return
YieldToken :: struct {} // yield
AndToken :: struct {} // and
OrToken :: struct {} // or
CommentToken :: distinct string
StringToken :: distinct string
CharToken :: distinct byte
EndOfFileToken :: struct {}

TokenContents :: union {
    Error,
    NewlineToken,
    OpenBracketToken,
    CloseBracketToken,
    OpenSquareBracketToken,
    CloseSquareBracketToken,
    OpenAngleBracketToken,
    CloseAngleBracketToken,
    OpenBraceToken,
    CloseBraceToken,
    CommaToken,
    ColonToken,
    SymbolsToken,
    ArrowToken,
    DigitsToken,
    IdentToken,
    InToken,
    StepToken,
    ForToken,
    IfToken,
    ElseToken,
    StructToken,
    SumToken,
    ImportToken,
    ReturnToken,
    YieldToken,
    AndToken,
    OrToken,
    CommentToken,
    StringToken,
    CharToken,
    EndOfFileToken,
}

token_contents_to_string :: proc(token: TokenContents) -> string {
    switch value in token {
    case Error:
        return fmt.aprintf("the tokenizer error \"%s\"", value)
    case NewlineToken:
        return "a newline"
    case OpenBracketToken:
        return "an open bracket (`(`)"
    case CloseBracketToken:
        return "a close bracket (`)`)"
    case OpenSquareBracketToken:
        return "an open square bracket (`[`)"
    case CloseSquareBracketToken:
        return "a close square bracket (`]`)"
    case OpenAngleBracketToken:
        return "an open angle bracket (`<`)"
    case CloseAngleBracketToken:
        return "a close angle bracket (`>`)"
    case CommaToken:
        return "a comma (`,`)"
    case ColonToken:
        return "`:`"
    case OpenBraceToken:
        return "an open brace (`{`)"
    case CloseBraceToken:
        return "a close brace (`}`)"
    case SymbolsToken:
        return fmt.aprintf("the symbols `%s`", value)
    case ArrowToken:
        return "`->`"
    case DigitsToken:
        return fmt.aprintf("the digits `%s`", value)
    case IdentToken:
        return fmt.aprintf("the identifier `%s`", value)
    case InToken:
        return "the keyword `in`"
    case StepToken:
        return "the keyword `step`"
    case ForToken:
        return "the keyword `for`"
    case IfToken:
        return "the keyword `if`"
    case ElseToken:
        return "the keyword `else`"
    case StructToken:
        return "the keyword `struct`"
    case SumToken:
        return "the keyword `sum`"
    case ImportToken:
        return "the keyword `import`"
    case ReturnToken:
        return "the keyword `return`"
    case YieldToken:
        return "the keyword `yield`"
    case AndToken:
        return "the keyword `and`"
    case OrToken:
        return "the keyword `or`"
    case CommentToken:
        return "a comment"
    case StringToken:
        return fmt.aprintf("the string literal `%s`", value)
    case CharToken:
        // TODO: Properly format character literals that use escapes
        return fmt.aprintf("the character literal '%c'", value)
    case EndOfFileToken:
        return "the end of the file"
    case:
        panic("got nil")
    }
}

CompilerFile :: struct {
    code:      string,
    file_name: string,
}

TokenizerState :: struct {
    index:          uint,
    using file:     CompilerFile,
    last_token_pos: uint,
    last_token:     TokenContents,
}

// Returns whether the tokenizer has reached the end of the file
skip_nothing_tokens :: proc(state: ^TokenizerState) -> bool {
    for state.index < len(state.code) {
        if state.code[state.index] != ' ' && state.code[state.index] != '\t' {
            return false
        }
        state.index += 1
    }
    state.index = len(state.code) - 1 // Make sure that the index is valid
    return true
}

get_location :: proc(text: string, position: uint) -> (line := 1, column := 1) {
    for char in text[:position] {
        if char == '\n' {
            line += 1
            column = 1
        } else {
            column += 1
        }
    }
    return
}

// Set the position to max(uint) to not have a position for the error message
err_ok :: proc(file: CompilerFile, position: uint, message_fmt: string, message_args: ..any) {
    message := fmt.aprintf(message_fmt, ..message_args)
    defer delete(message)
    if position == max(uint) {
        fmt.eprintf("\nError compiling `%s`:\n%s\n", file.file_name, message)
    } else {
        line, column := get_location(file.code, position)
        fmt.eprintf(
            "\nError compiling `%s`:\nLine %d column %d:\n%s\n",
            file.file_name,
            line,
            column,
            message,
        )
    }
}

wrong_token_err :: proc(state: ^TokenizerState, expected_possibilities: []string) {
    expected_bytes: []byte
    if len(expected_possibilities) == 1 {
        expected_bytes = make([]byte, len(expected_possibilities[0]) + 1)
        expected_bytes[0] = ' '
        copy(expected_bytes[1:], expected_possibilities[0])
    } else {
        line_start :: "\n- "
        either :: " either:"
        length := len(either) + len(expected_possibilities) * len(line_start)
        for str in expected_possibilities {
            length += len(str)
        }
        expected_bytes = make([]byte, length)
        i := copy(expected_bytes, either)
        for str in expected_possibilities {
            i += copy(expected_bytes[i:], line_start)
            i += copy(expected_bytes[i:], str)
        }
    }
    err_ok(
        state.file,
        state.last_token_pos,
        "Expected%s\nGot %s",
        string(expected_bytes),
        token_contents_to_string(state.last_token),
    )
    delete(expected_bytes)
}

get_next_token :: proc(
    state: ^TokenizerState,
    skip_newlines_and_comments: bool,
    loc := #caller_location,
) {
    when debug {
        fmt.printfln(
            "Get next token called from file %s at line %d column %d",
            loc.file_path,
            loc.line,
            loc.column,
        )
    }
    if skip_nothing_tokens(state) {
        state.last_token_pos = state.index
        state.last_token = EndOfFileToken{}
        return
    }
    state.last_token_pos = state.index
    symbols :: []u8{'|', '=', '+', '-', '*', '/', '.', '<', '>', '%', '~'}
    char := state.code[state.index]
    switch char {
    case '\n':
        state.index += 1
        if skip_newlines_and_comments {
            get_next_token(state, skip_newlines_and_comments)
        } else {
            state.last_token = NewlineToken{}
        }
    case '(':
        state.index += 1
        state.last_token = OpenBracketToken{}
    case ')':
        state.index += 1
        state.last_token = CloseBracketToken{}
    case '[':
        state.index += 1
        state.last_token = OpenSquareBracketToken{}
    case ']':
        state.index += 1
        state.last_token = CloseSquareBracketToken{}
    case '{':
        state.index += 1
        state.last_token = OpenBraceToken{}
    case '}':
        state.index += 1
        state.last_token = CloseBraceToken{}
    case ',':
        state.index += 1
        state.last_token = CommaToken{}
    case ':':
        state.index += 1
        state.last_token = ColonToken{}
    case '0' ..< '9':
        for state.index < len(state.code) &&
            '0' <= state.code[state.index] &&
            state.code[state.index] <= '9' {
            state.index += 1
        }
        state.last_token = DigitsToken(state.code[state.last_token_pos:state.index])
    case '_', 'a' ..< 'z', 'A' ..< 'Z':
        for state.index < len(state.code) &&
            (state.code[state.index] == '_' ||
                    ('a' <= state.code[state.index] && state.code[state.index] <= 'z') ||
                    ('A' <= state.code[state.index] && state.code[state.index] <= 'Z') ||
                    ('0' <= state.code[state.index] && state.code[state.index] <= '9')) {
            state.index += 1
        }
        ident := state.code[state.last_token_pos:state.index]
        switch ident {
        case "in":
            state.last_token = InToken{}
        case "step":
            state.last_token = StepToken{}
        case "for":
            state.last_token = ForToken{}
        case "if":
            state.last_token = IfToken{}
        case "else":
            state.last_token = ElseToken{}
        case "struct":
            state.last_token = StructToken{}
        case "sum":
            state.last_token = SumToken{}
        case "import":
            state.last_token = ImportToken{}
        case "return":
            state.last_token = ReturnToken{}
        case "yield":
            state.last_token = YieldToken{}
        case:
            state.last_token = IdentToken(ident)
        }
    case '"':
        state.index += 1
        for {
            if state.index >= len(state.code) {
                state.last_token_pos = min(state.index, uint(len(state.code)) - 1)
                state.last_token = Error("Unexpected end of file while tokenizing string")
                return
            }
            switch state.code[state.index] {
            case '"':
                state.index += 1
                state.last_token = StringToken(
                    state.code[state.last_token_pos + 1:state.index - 1],
                )
                return
            case '\\':
                state.index += 2 // Avoid exiting string early for `\"` escapes
            case:
                state.index += 1
            }
        }
    case '\'':
        state.index += 1
        if state.index >= len(state.code) {
            state.last_token = Error("Unexpected end of file while tokenizing character")
            return
        }
        if state.code[state.index] == '\\' {
            state.index += 1
            if state.index >= len(state.code) {
                state.last_token = Error("Unexpected end of file while tokenizing character")
                return
            }
        }
        state.last_token = CharToken(state.code[state.index])
    case '/':
        if state.index + 1 < len(state.code) && state.code[state.index + 1] == '/' {
            state.index += 2
            for state.index < len(state.code) && state.code[state.index] != '\n' {
                state.index += 1
            }
            state.index += 1
            if skip_newlines_and_comments {
                get_next_token(state, skip_newlines_and_comments)
                return
            }
            state.last_token = CommentToken(
                strings.trim(state.code[state.last_token_pos:state.index - 1], " "),
            )
        }
        fallthrough
    case:
        if slice.contains(symbols, char) {
            for state.index < len(state.code) && slice.contains(symbols, state.code[state.index]) {
                state.index += 1
            }
            symbols := state.code[state.last_token_pos:state.index]
            switch symbols {
            case "->":
                state.last_token = ArrowToken{}
            case "<":
                state.last_token = OpenAngleBracketToken{}
            case ">":
                state.last_token = CloseAngleBracketToken{}
            case:
                state.last_token = SymbolsToken(symbols)
            }
        } else {
            state.last_token = Error(fmt.aprintf("Unrecognized character %c", char))
        }
    }
    when debug {
        // TODO: There are some cases where state.last_token is updated but this line of code in not ran
        fmt.printfln("Last token set to %s", token_contents_to_string(state.last_token))
    }
}

