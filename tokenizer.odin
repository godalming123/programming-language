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
AtToken :: struct {} // @
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
ContinueToken :: struct {} // continue
UnreachableToken :: struct {} // unreachable
AndToken :: struct {} // and
OrToken :: struct {} // or
MatchToken :: struct {} // match
MutToken :: struct {} // mut
CommentToken :: distinct string

// Escapes that were in the string are removed by the tokenizer
// For example, the string literal `"\"hello"` would be tokenized into `"hello`
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
    AtToken,
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
    ContinueToken,
    UnreachableToken,
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

token_formatter :: proc(fi: ^fmt.Info, arg: any, verb: rune) -> bool {
    if verb != 'v' {
        return false
    }
    token := cast(^TokenContents)arg.data
    switch value in token {
    case Error:
        fmt.wprintf(fi.writer, "the tokenizer error \"%s\"", value)
    case NewlineToken:
        fmt.wprint(fi.writer, "a newline")
    case OpenBracketToken:
        fmt.wprint(fi.writer, "an open bracket (`(`)")
    case CloseBracketToken:
        fmt.wprint(fi.writer, "a close bracket (`)`)")
    case OpenSquareBracketToken:
        fmt.wprint(fi.writer, "an open square bracket (`[`)")
    case CloseSquareBracketToken:
        fmt.wprint(fi.writer, "a close square bracket (`]`)")
    case OpenAngleBracketToken:
        fmt.wprint(fi.writer, "an open angle bracket (`<`)")
    case LessThanOrEqualToken:
        fmt.wprint(fi.writer, "an less than or equal sign (`<=`)")
    case CloseAngleBracketToken:
        fmt.wprint(fi.writer, "a close angle bracket (`>`)")
    case GreaterThanOrEqualToken:
        fmt.wprint(fi.writer, "a greater than or equal sign (`>=`)")
    case CommaToken:
        fmt.wprint(fi.writer, "a comma (`,`)")
    case AtToken:
        fmt.wprint(fi.writer, "an at sign (`@`)")
    case ColonToken:
        fmt.wprint(fi.writer, "`:`")
    case ColonColonToken:
        fmt.wprint(fi.writer, "`::`")
    case SemiColonToken:
        fmt.wprint(fi.writer, "`;`")
    case BarToken:
        fmt.wprint(fi.writer, "`|`")
    case PipeToken:
        fmt.wprint(fi.writer, "`|>`")
    case OpenBraceToken:
        fmt.wprint(fi.writer, "an open brace (`{`)")
    case CloseBraceToken:
        fmt.wprint(fi.writer, "a close brace (`}`)")
    case SymbolsToken:
        fmt.wprintf(fi.writer, "the symbols `%s`", value)
    case ArrowToken:
        fmt.wprint(fi.writer, "`->`")
    case AssignToken:
        fmt.wprint(fi.writer, "`=`")
    case DigitsToken:
        fmt.wprintf(fi.writer, "the digits `%s`", value)
    case IdentToken:
        fmt.wprintf(
            fi.writer,
            "the identifier `%s` (which has %d segments)",
            strings.join(value.ident[:len(value)], "."),
            len(value),
        )
    case MarkerToken:
        fmt.wprintf(fi.writer, "the marker `#%s`", value)
    case TrueToken:
        fmt.wprint(fi.writer, "the keyword `true`")
    case FalseToken:
        fmt.wprint(fi.writer, "the keyword `false`")
    case InToken:
        fmt.wprint(fi.writer, "the keyword `in`")
    case StepToken:
        fmt.wprint(fi.writer, "the keyword `step`")
    case ForToken:
        fmt.wprint(fi.writer, "the keyword `for`")
    case DoToken:
        fmt.wprint(fi.writer, "the keyword `do`")
    case WhileToken:
        fmt.wprint(fi.writer, "the keyword `while`")
    case IfToken:
        fmt.wprint(fi.writer, "the keyword `if`")
    case ElseToken:
        fmt.wprint(fi.writer, "the keyword `else`")
    case ImportToken:
        fmt.wprint(fi.writer, "the keyword `import`")
    case ReturnToken:
        fmt.wprint(fi.writer, "the keyword `return`")
    case YieldToken:
        fmt.wprint(fi.writer, "the keyword `yield`")
    case ContinueToken:
        fmt.wprint(fi.writer, "the keyword `continue`")
    case UnreachableToken:
        fmt.wprint(fi.writer, "the keyword `unreachable`")
    case AndToken:
        fmt.wprint(fi.writer, "the keyword `and`")
    case OrToken:
        fmt.wprint(fi.writer, "the keyword `or`")
    case MatchToken:
        fmt.wprint(fi.writer, "the keyword `match`")
    case MutToken:
        fmt.wprint(fi.writer, "the keyword `mut`")
    case CommentToken:
        fmt.wprint(fi.writer, "a comment")
    case StringToken:
        fmt.wprintf(fi.writer, "the string literal `%s`", value)
    case CharToken:
        // TODO: Properly format character literals that use escapes
        fmt.wprintf(fi.writer, "the character literal '%c'", value)
    case EndOfFileToken:
        fmt.wprint(fi.writer, "the end of the file")
    case:
        panic("got nil")
    }
    return true
}

is_close_brace :: proc(t: TokenContents) -> bool {
    _, is_close_brace := t.(CloseBraceToken)
    return is_close_brace
}

is_close_bracket :: proc(t: TokenContents) -> bool {
    _, is_close_bracket := t.(CloseBracketToken)
    return is_close_bracket
}

is_close_square_bracket :: proc(t: TokenContents) -> bool {
    _, is_close_square_bracket := t.(CloseSquareBracketToken)
    return is_close_square_bracket
}

CompilerFile :: struct {
    code:      string,
    file_path: string,
    dir_path:  string,
}

TokenizerState :: struct {
    file_ref:                                         ^CompilerFile,
    index:                                            uint,
    last_token_pos:                                   uint,
    last_token:                                       TokenContents,
    last_token_descriptions_of_other_possible_tokens: []string,
    last_token_skipped:                               bool,
}

is_nothing_char :: proc(c: byte) -> bool {
    return c == ' ' || c == '\t'
}

// TODO: Dry
is_alphanumeric_char :: proc(c: byte) -> bool {
    return c == '_' || ('a' <= c && c <= 'z') || ('A' <= c && c <= 'Z') || ('0' <= c && c <= '9')
}
is_alphanumeric_char_rune :: proc(c: rune) -> bool {
    return c == '_' || ('a' <= c && c <= 'z') || ('A' <= c && c <= 'Z') || ('0' <= c && c <= '9')
}

is_digit_char :: proc(c: byte) -> bool {
    return '0' <= c && c <= '9'
}

is_symbol_char :: proc(c: byte) -> bool {
    switch c {
    case '=', '+', '-', '*', '/', '.', '<', '>', '%', '~', '&':
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
        if s.index >= len(s.file_ref.code) {
            return SkipperResult{true, true}
        }
        if !should_continue(s.file_ref.code[s.index]) {
            return SkipperResult{false, true}
        }
    }
}

skip :: proc(s: ^TokenizerState, should_continue: proc(_: byte) -> bool) -> SkipperResult {
    if s.index >= len(s.file_ref.code) {
        return SkipperResult{true, false}
    }
    if !should_continue(s.file_ref.code[s.index]) {
        return SkipperResult{false, false}
    }
    return skip_ignore_first(s, should_continue)
}

wrong_token_err :: proc(
    state: ^ParserState,
    infos: ..string,
    loc := #caller_location,
) {
    expected_bytes: []byte
    defer delete(expected_bytes)
    if len(state.last_token_descriptions_of_other_possible_tokens) == 1 {
        expected_bytes = make([]byte, len(state.last_token_descriptions_of_other_possible_tokens[0]) + 1)
        expected_bytes[0] = ' '
        copy(expected_bytes[1:], state.last_token_descriptions_of_other_possible_tokens[0])
    } else {
        line_start :: "\n- "
        either :: " either:"
        length := len(either) + len(state.last_token_descriptions_of_other_possible_tokens) * len(line_start)
        for str in state.last_token_descriptions_of_other_possible_tokens {
            length += len(str)
        }
        expected_bytes = make([]byte, length)
        i := copy(expected_bytes, either)
        for str in state.last_token_descriptions_of_other_possible_tokens {
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
        &state.r,
        Pos{state.last_token_pos, state.file_ref},
        "%sExpected%s\nGot %v",
        string(info_bytes),
        string(expected_bytes),
        state.last_token,
        loc = loc,
    )
}

tokenize_segmented_identifier :: proc(s: ^TokenizerState, first_ident: string) {
    segments := make(#soa[dynamic]IdentAndPos, 1)
    segments[0] = IdentAndPos{first_ident, Pos{s.last_token_pos, s.file_ref}}
    for s.index < len(s.file_ref.code) && s.file_ref.code[s.index] == '.' {
        s.index += 1
        segment_start := s.index
        skipper_result := skip(s, is_alphanumeric_char)
        if skipper_result.skipped_atleast_one_char {
            append_soa_elem(
                &segments,
                IdentAndPos {
                    s.file_ref.code[segment_start:s.index],
                    Pos{segment_start, s.file_ref},
                },
            )
        } else {
            s.last_token = Error(
                skipper_result.reached_end_of_file ? "While tokenizing segmented identifier\nExpected an alphanumeric\nGot the end of the file" : fmt.aprintf("While tokenizing segmented identifier\nExpected an alphanumeric\nGot `%c`", s.file_ref.code[s.index]),
            )
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
    clear_dynamic(&state.last_token_descriptions_of_other_possible_tokens)
    if skip(state, is_nothing_char).reached_end_of_file {
        state.last_token_pos = len(state.file_ref.code)
        state.last_token = EndOfFileToken{}
        return
    }
    state.last_token_pos = state.index
    state.last_token_skipped = false
    char := state.file_ref.code[state.index]
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
    case '@':
        state.index += 1
        state.last_token = AtToken{}
    case ':':
        state.index += 1
        if state.index < len(state.file_ref.code) && state.file_ref.code[state.index] == ':' {
            state.index += 1
            state.last_token = ColonColonToken{}
        } else {
            state.last_token = ColonToken{}
        }

    case '<':
        state.index += 1
        if state.index < len(state.file_ref.code) && state.file_ref.code[state.index] == '=' {
            state.index += 1
            state.last_token = LessThanOrEqualToken{}
        } else {
            state.last_token = OpenAngleBracketToken{}
        }

    case '>':
        state.index += 1
        if state.index < len(state.file_ref.code) && state.file_ref.code[state.index] == '=' {
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
        if state.index < len(state.file_ref.code) && state.file_ref.code[state.index] == '>' {
            state.index += 1
            state.last_token = PipeToken{}
        } else {
            state.last_token = BarToken{}
        }

    case '0' ..< '9':
        skip_ignore_first(state, is_digit_char)
        state.last_token = DigitsToken(state.file_ref.code[state.last_token_pos:state.index])

    case '#':
        state.index += 1
        skipper_result := skip(state, is_alphanumeric_char)
        if skipper_result.skipped_atleast_one_char {
            state.last_token = MarkerToken(
                state.file_ref.code[state.last_token_pos + 1:state.index],
            )
        } else if skipper_result.reached_end_of_file {
            state.last_token = Error(
                "While tokenizing marker\nExpected an alphanumeric\nGot the end of the file",
            )
        } else {
            state.last_token = Error(
                fmt.aprintf(
                    "While tokenizing marker\nExpected an alphanumeric\nGot `%c`",
                    state.file_ref.code[state.index],
                ),
            )
        }

    case '_', 'a' ..< 'z', 'A' ..< 'Z':
        skip_ignore_first(state, is_alphanumeric_char)
        ident := state.file_ref.code[state.last_token_pos:state.index]
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
        case "continue":
            state.last_token = ContinueToken{}
        case "unreachable":
            state.last_token = UnreachableToken{}
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
        contents := make([dynamic]byte)
        for {
            if state.index >= len(state.file_ref.code) {
                state.last_token_pos = len(state.file_ref.code)
                state.last_token = Error("Unexpected end of file while tokenizing string")
                return
            }
            switch state.file_ref.code[state.index] {
            case '"':
                state.index += 1
                state.last_token = StringToken(contents[:])
                return
            case '\\':
                state.index += 1
                switch state.index >= len(state.file_ref.code) ? '?' : state.file_ref.code[state.index] {
                case 'n':
                    append_elem(&contents, '\n')
                case 't':
                    append_elem(&contents, '\t')
                case '"':
                    append_elem(&contents, '"')
                case '\\':
                    append_elem(&contents, '\\')
                case:
                    state.last_token_pos = state.index
                    state.last_token = Error(
                        "Invalid escape code (supported escape codes are `\\n`, `\\t`, `\\\"`, and `\\\\`)",
                    )
                    return
                }
            case:
                append_elem(&contents, state.file_ref.code[state.index])
            }
            state.index += 1
        }
    case '\'':
        state.index += 1
        if state.index >= len(state.file_ref.code) {
            state.last_token = Error("Unexpected end of file while tokenizing character")
            return
        }
        if state.file_ref.code[state.index] == '\\' {
            state.index += 1
            if state.index >= len(state.file_ref.code) {
                state.last_token = Error("Unexpected end of file while tokenizing character")
                return
            }
        }
        state.last_token = CharToken(state.file_ref.code[state.index])
        state.index += 1
        if state.index >= len(state.file_ref.code) {
            state.last_token = Error(
                "While tokenizing character. Expected `'`. Got unexpected end of file.",
            )
            return
        }
        if state.file_ref.code[state.index] != '\'' {
            state.last_token = Error(
                fmt.aprintf("Expected `'`, got `%c`", state.file_ref.code[state.index]),
            )
            return
        }
        state.index += 1
    case '/':
        if state.index + 1 < len(state.file_ref.code) &&
           state.file_ref.code[state.index + 1] == '/' {
            state.index += 2
            for state.index < len(state.file_ref.code) &&
                state.file_ref.code[state.index] != '\n' {
                state.index += 1
            }
            state.index += 1
            if skip_newlines_and_comments_and_semicolons {
                get_next_token(state, skip_newlines_and_comments_and_semicolons)
                state.last_token_skipped = true
            } else {
                state.last_token = CommentToken(
                    strings.trim(state.file_ref.code[state.last_token_pos:state.index - 1], " "),
                )
            }
        } else {
            skip_ignore_first(state, is_symbol_char)
            state.last_token = SymbolsToken(state.file_ref.code[state.last_token_pos:state.index])
        }
    case '.':
        if state.index + 1 < len(state.file_ref.code) &&
           is_alphanumeric_char(state.file_ref.code[state.index + 1]) {
            tokenize_segmented_identifier(state, "")
        } else {
            skip_ignore_first(state, is_symbol_char)
            state.last_token = SymbolsToken(state.file_ref.code[state.last_token_pos:state.index])
        }
    case:
        if !is_symbol_char(char) {
            state.last_token = Error(fmt.aprintf("Unrecognized character `%c`", char))
            return
        }
        skip_ignore_first(state, is_symbol_char)
        symbols := state.file_ref.code[state.last_token_pos:state.index]
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

