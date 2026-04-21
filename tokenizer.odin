package main

import "core:fmt"
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
LessThanOrEqualToken :: struct {} // <=
CloseAngleBracketToken :: struct {} // >
GreaterThanOrEqualToken :: struct {} // >=
OpenBraceToken :: struct {} // {
CloseBraceToken :: struct {} // }
CommaToken :: struct {} // ,
ColonToken :: struct {} // :
ColonColonToken :: struct {} // ::
SemiColonToken :: struct {} // ;
BarToken :: struct {} // |
PipeToken :: struct {} // |>
ArrowToken :: struct {} // ->
AssignToken :: struct {} // =
SymbolsToken :: distinct string
DigitsToken :: distinct string
IdentToken :: #soa[]IdentAndPos // A list of the segments in the identifier, where each segment is separated by `.`
MarkerToken :: distinct string
TrueToken :: struct {} // true
FalseToken :: struct {} // false
InToken :: struct {} // in
StepToken :: struct {} // step
DoToken :: struct {} // do
ForToken :: struct {} // for
WhileToken :: struct {} // while
IfToken :: struct {} // if
ElseToken :: struct {} // else
ImportToken :: struct {} // import
ReturnToken :: struct {} // return
YieldToken :: struct {} // yield
AndToken :: struct {} // and
OrToken :: struct {} // or
MatchToken :: struct {} // match
MutToken :: struct {} // mut
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
    LessThanOrEqualToken,
    CloseAngleBracketToken,
    GreaterThanOrEqualToken,
    OpenBraceToken,
    CloseBraceToken,
    CommaToken,
    ColonToken,
    ColonColonToken,
    SemiColonToken,
    BarToken,
    PipeToken,
    SymbolsToken,
    ArrowToken,
    AssignToken,
    DigitsToken,
    IdentToken,
    MarkerToken,
    TrueToken,
    FalseToken,
    InToken,
    StepToken,
    DoToken,
    ForToken,
    WhileToken,
    IfToken,
    ElseToken,
    ImportToken,
    ReturnToken,
    YieldToken,
    AndToken,
    OrToken,
    MatchToken,
    MutToken,
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
    case LessThanOrEqualToken:
        return "an less than or equal sign (`<=`)"
    case CloseAngleBracketToken:
        return "a close angle bracket (`>`)"
    case GreaterThanOrEqualToken:
        return "a greater than or equal sign (`>=`)"
    case CommaToken:
        return "a comma (`,`)"
    case ColonToken:
        return "`:`"
    case ColonColonToken:
        return "`::`"
    case SemiColonToken:
        return "`;`"
    case BarToken:
        return "`|`"
    case PipeToken:
        return "`|>`"
    case OpenBraceToken:
        return "an open brace (`{`)"
    case CloseBraceToken:
        return "a close brace (`}`)"
    case SymbolsToken:
        return fmt.aprintf("the symbols `%s`", value)
    case ArrowToken:
        return "`->`"
    case AssignToken:
        return "`=`"
    case DigitsToken:
        return fmt.aprintf("the digits `%s`", value)
    case IdentToken:
        return fmt.aprintf(
            "the identifier `%s` (which has %d segments)",
            strings.join(value.ident[:len(value)], "."),
            len(value),
        )
    case MarkerToken:
        return fmt.aprintf("the marker `#%s`", value)
    case TrueToken:
        return "the keyword `true`"
    case FalseToken:
        return "the keyword `false`"
    case InToken:
        return "the keyword `in`"
    case StepToken:
        return "the keyword `step`"
    case ForToken:
        return "the keyword `for`"
    case DoToken:
        return "the keyword `do`"
    case WhileToken:
        return "the keyword `while`"
    case IfToken:
        return "the keyword `if`"
    case ElseToken:
        return "the keyword `else`"
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
    case MatchToken:
        return "the keyword `match`"
    case MutToken:
        return "the keyword `mut`"
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
    index:              uint,
    using file:         CompilerFile,
    last_token_pos:     uint,
    last_token:         TokenContents,
    last_token_skipped: bool,
}

is_nothing_char :: proc(c: byte) -> bool {
    return c == ' ' || c == '\t'
}

is_alphanumeric_char :: proc(c: byte) -> bool {
    return c == '_' || ('a' <= c && c <= 'z') || ('A' <= c && c <= 'Z') || ('0' <= c && c <= '9')
}

is_digit_char :: proc(c: byte) -> bool {
    return '0' <= c && c <= '9'
}

is_symbol_char :: proc(c: byte) -> bool {
    switch c {
    case '=', '+', '-', '*', '/', '.', '<', '>', '%', '~':
        return true
    case:
        return false
    }
}

SkipperResult :: struct {
    reached_end_of_file:      bool,
    skipped_atleast_one_char: bool,
}

skip_ignore_first :: proc(
    s: ^TokenizerState,
    should_continue: proc(_: byte) -> bool,
) -> SkipperResult {
    for {
        s.index += 1
        if s.index >= len(s.code) {
            return SkipperResult{true, true}
        }
        if !should_continue(s.code[s.index]) {
            return SkipperResult{false, true}
        }
    }
}

skip :: proc(s: ^TokenizerState, should_continue: proc(_: byte) -> bool) -> SkipperResult {
    if s.index >= len(s.code) {
        return SkipperResult{true, false}
    }
    if !should_continue(s.code[s.index]) {
        return SkipperResult{false, false}
    }
    return skip_ignore_first(s, should_continue)
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

wrong_token_err :: proc(
    state: ^TokenizerState,
    expected_possibilities: []string,
    infos: ..string,
) {
    expected_bytes: []byte
    defer delete(expected_bytes)
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
    info_len := len(infos)
    for info in infos {
        info_len += len(info)
    }
    info_bytes := make([]byte, info_len)
    defer delete(info_bytes)
    i := 0
    for info in infos {
        i += copy(info_bytes[i:], info)
        info_bytes[i] = '\n'
        i += 1
    }
    diagnostic(
        state.file,
        state.last_token_pos,
        "%sExpected%s\nGot %s",
        string(info_bytes),
        string(expected_bytes),
        token_contents_to_string(state.last_token),
    )
}

tokenize_segmented_identifier :: proc(s: ^TokenizerState, first_ident: string) {
    segments := make(#soa[dynamic]IdentAndPos, 1)
    segments[0] = IdentAndPos{first_ident, s.last_token_pos}
    for s.index < len(s.code) && s.code[s.index] == '.' {
        s.index += 1
        segment_start := s.index
        skipper_result := skip(s, is_alphanumeric_char)
        if skipper_result.skipped_atleast_one_char {
            append_soa_elem(&segments, IdentAndPos{s.code[segment_start:s.index], segment_start})
        } else {
            if skipper_result.reached_end_of_file {
                s.last_token = Error(
                    "While tokenizing segmented identifier\nExpected an alphanumeric\nGot the end of the file",
                )
            } else {
                s.last_token = Error(
                    fmt.aprintf(
                        "While tokenizing segmented identifier\nExpected an alphanumeric\nGot `%c`",
                        s.code[s.index],
                    ),
                )
            }
            return
        }
    }
    s.last_token = segments[:]
}

get_next_token :: proc(
    state: ^TokenizerState,
    skip_newlines_and_comments_and_semicolons: bool,
    loc := #caller_location,
) {
    when debug_tokenizer {
        print_call(loc, "get next token")
        defer {
            debug("last token set to %s", token_contents_to_string(state.last_token))
        }
    }
    if skip(state, is_nothing_char).reached_end_of_file {
        state.last_token_pos = len(state.code)
        state.last_token = EndOfFileToken{}
        return
    }
    state.last_token_pos = state.index
    state.last_token_skipped = false
    char := state.code[state.index]
    switch char {
    case '\n':
        state.index += 1
        if skip_newlines_and_comments_and_semicolons {
            get_next_token(state, skip_newlines_and_comments_and_semicolons)
            state.last_token_skipped = true
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
        if state.index < len(state.code) && state.code[state.index] == ':' {
            state.index += 1
            state.last_token = ColonColonToken{}
        } else {
            state.last_token = ColonToken{}
        }

    case '<':
        state.index += 1
        if state.index < len(state.code) && state.code[state.index] == '=' {
            state.index += 1
            state.last_token = LessThanOrEqualToken{}
        } else {
            state.last_token = OpenAngleBracketToken{}
        }

    case '>':
        state.index += 1
        if state.index < len(state.code) && state.code[state.index] == '=' {
            state.index += 1
            state.last_token = GreaterThanOrEqualToken{}
        } else {
            state.last_token = CloseAngleBracketToken{}
        }

    case ';':
        state.index += 1
        if skip_newlines_and_comments_and_semicolons {
            get_next_token(state, skip_newlines_and_comments_and_semicolons)
            state.last_token_skipped = true
        } else {
            state.last_token = SemiColonToken{}
        }

    case '|':
        state.index += 1
        if state.index < len(state.code) && state.code[state.index] == '>' {
            state.index += 1
            state.last_token = PipeToken{}
        } else {
            state.last_token = BarToken{}
        }

    case '0' ..< '9':
        skip_ignore_first(state, is_digit_char)
        state.last_token = DigitsToken(state.code[state.last_token_pos:state.index])

    case '#':
        state.index += 1
        skipper_result := skip(state, is_alphanumeric_char)
        if skipper_result.skipped_atleast_one_char {
            state.last_token = MarkerToken(state.code[state.last_token_pos + 1:state.index])
        } else if skipper_result.reached_end_of_file {
            state.last_token = Error(
                "While tokenizing marker\nExpected an alphanumeric\nGot the end of the file",
            )
        } else {
            state.last_token = Error(
                fmt.aprintf(
                    "While tokenizing marker\nExpected an alphanumeric\nGot `%c`",
                    state.code[state.index],
                ),
            )
        }

    case '_', 'a' ..< 'z', 'A' ..< 'Z':
        skip_ignore_first(state, is_alphanumeric_char)
        ident := state.code[state.last_token_pos:state.index]
        switch ident {
        case "in":
            state.last_token = InToken{}
        case "true":
            state.last_token = TrueToken{}
        case "false":
            state.last_token = FalseToken{}
        case "step":
            state.last_token = StepToken{}
        case "for":
            state.last_token = ForToken{}
        case "do":
            state.last_token = DoToken{}
        case "while":
            state.last_token = WhileToken{}
        case "if":
            state.last_token = IfToken{}
        case "else":
            state.last_token = ElseToken{}
        case "import":
            state.last_token = ImportToken{}
        case "return":
            state.last_token = ReturnToken{}
        case "yield":
            state.last_token = YieldToken{}
        case "and":
            state.last_token = AndToken{}
        case "or":
            state.last_token = OrToken{}
        case "match":
            state.last_token = MatchToken{}
        case "mut":
            state.last_token = MutToken{}
        case:
            tokenize_segmented_identifier(state, ident)
        }
    case '"':
        state.index += 1
        for {
            if state.index >= len(state.code) {
                state.last_token_pos = len(state.code)
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
        state.index += 1
        if state.index >= len(state.code) {
            state.last_token = Error(
                "While tokenizing character. Expected `'`. Got unexpected end of file.",
            )
            return
        }
        if state.code[state.index] != '\'' {
            state.last_token = Error(
                fmt.aprintf("Expected `'`, got `%c`", state.code[state.index]),
            )
            return
        }
        state.index += 1
    case '/':
        if state.index + 1 < len(state.code) && state.code[state.index + 1] == '/' {
            state.index += 2
            for state.index < len(state.code) && state.code[state.index] != '\n' {
                state.index += 1
            }
            state.index += 1
            if skip_newlines_and_comments_and_semicolons {
                get_next_token(state, skip_newlines_and_comments_and_semicolons)
                state.last_token_skipped = true
            } else {
                state.last_token = CommentToken(
                    strings.trim(state.code[state.last_token_pos:state.index - 1], " "),
                )
            }
        } else {
            skip_ignore_first(state, is_symbol_char)
            state.last_token = SymbolsToken(state.code[state.last_token_pos:state.index])
        }
    case '.':
        if state.index + 1 < len(state.code) && is_alphanumeric_char(state.code[state.index + 1]) {
            tokenize_segmented_identifier(state, "")
        } else {
            skip_ignore_first(state, is_symbol_char)
            state.last_token = SymbolsToken(state.code[state.last_token_pos:state.index])
        }
    case:
        if !is_symbol_char(char) {
            state.last_token = Error(fmt.aprintf("Unrecognized character `%c`", char))
            return
        }
        skip_ignore_first(state, is_symbol_char)
        symbols := state.code[state.last_token_pos:state.index]
        switch symbols {
        case "->":
            state.last_token = ArrowToken{}
        case "=":
            state.last_token = AssignToken{}
        case:
            state.last_token = SymbolsToken(symbols)
        }
    }
}

