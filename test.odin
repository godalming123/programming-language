package main

// TODO: Implement some stuff so that all examples work in the interpreter and
//       the C emitter
// TODO: Check that the interpreter, the JS emitter, and the C emitter all have
//       the same behavior in all the tests

import "core:fmt"
import "core:os"
import "core:path/filepath"
import "core:testing"

Pipe :: struct(T: typeid) {
    stdout: T,
    stderr: T,
}

CompilationFailed :: struct {
    compiler: Pipe(string),
    status:   int,
}

CompilationSuccessful :: struct {
    compiler: Pipe(string),
    program:  Pipe(string),
}

RanExampleViaC :: union {
    CompilationFailed,
    CompilationSuccessful,
}

InterpretedExample :: struct {
    compiler:  Pipe(string),
    program:   Pipe(string),
    exit_code: int,
}

run_example_via_c :: proc(
    t: ^testing.T,
    absolute_path: string,
    stdin_to_send: string,
) -> RanExampleViaC {
    compiler_writer, compiler_builder := pipe_mock()
    executable: string
    status := compile(
        FunctionRef{absolute_path, "main"},
        compiler_writer,
        BuildC{&executable},
        NeverExitEarly{},
    )
    compiler := get_output(compiler_builder)
    if status != 0 {
        return CompilationFailed{compiler, status}
    }
    if executable == "" {
        testing.fail(t)
        return nil
    }

    stdin_reader, stdin_writer, err := os.pipe()
    if err != nil {
        testing.fail_now(t, fmt.aprintf("Failed to create pipe: %#v", err))
    }
    defer os.close(stdin_reader)

    _, err2 := os.write(stdin_writer, transmute([]u8)stdin_to_send)
    if err2 != nil {
        os.close(stdin_writer)
        testing.fail_now(t, fmt.aprintf("Failed to write to pipe: %#v", err2))
    }

    os.close(stdin_writer)

    // TODO: Check for memory leaks when the process runs
    state, stdout, stderr, err3 := os.process_exec(
        os.Process_Desc{command = []string{executable}, stdin = stdin_reader},
        context.allocator,
    )
    if err3 != nil {
        testing.fail_now(t, fmt.aprintf("Failed to run `%s`: %#v", executable, err3))
    }

    if state.exit_code != 0 {
        fmt.eprintfln(
            "Failed to run `%s`:\nExit code: %d\nStderr:\n%s\nStdout:\n%s",
            executable,
            state.exit_code,
            stdout,
            stderr,
        )
        testing.fail(t)
        return nil
    }
    return CompilationSuccessful{compiler, Pipe(string){string(stdout), string(stderr)}}
}

interpret_example :: proc(t: ^testing.T, func: FunctionRef) -> InterpretedExample {
    compiler_pipe, compiler_builder := pipe_mock()
    program_pipe, program_builder := pipe_mock()
    status := compile(
        func,
        compiler_pipe,
        Run{program_pipe, new(LongLivedInterpState)},
        NeverExitEarly{},
    )
    return InterpretedExample{get_output(compiler_builder), get_output(program_builder), status}
}

@(test)
example_00_fizzbuzz :: proc(t: ^testing.T) {
    ran := run_example_via_c(t, #directory + "examples/00_fizzbuzz.code", "")
    if ran == nil {return}
    out := ran.(CompilationSuccessful)
    testing.expect(t, out.compiler.stderr == "")
    testing.expect(t, out.program.stderr == "")
    testing.expect(
        t,
        out.program.stdout ==
        "1\n2\nFizz\n4\nBuzz\nFizz\n7\n8\nFizz\nBuzz\n11\nFizz\n13\n14\nFizzbuzz\n16\n17\nFizz\n19\nBuzz\nFizz\n22\n23\nFizz\nBuzz\n26\nFizz\n28\n29\nFizzbuzz\n31\n32\nFizz\n34\nBuzz\nFizz\n37\n38\nFizz\nBuzz\n41\nFizz\n43\n44\nFizzbuzz\n46\n47\nFizz\n49\nBuzz\nFizz\n52\n53\nFizz\nBuzz\n56\nFizz\n58\n59\nFizzbuzz\n61\n62\nFizz\n64\nBuzz\nFizz\n67\n68\nFizz\nBuzz\n71\nFizz\n73\n74\nFizzbuzz\n76\n77\nFizz\n79\nBuzz\nFizz\n82\n83\nFizz\nBuzz\n86\nFizz\n88\n89\nFizzbuzz\n91\n92\nFizz\n94\nBuzz\nFizz\n97\n98\nFizz\nBuzz\n",
    )
}

@(test)
example_01_factorial :: proc(t: ^testing.T) {
    ran := run_example_via_c(t, #directory + "examples/01_factorial.code", "")
    if ran == nil {return}
    out := ran.(CompilationSuccessful)
    testing.expect(t, out.compiler.stderr == "")
    testing.expect(t, out.program.stderr == "")
    testing.expect(t, out.program.stdout == "120\n")
}

@(test)
example_02_primes :: proc(t: ^testing.T) {
    ran := run_example_via_c(t, #directory + "examples/02_primes.code", "")
    if ran == nil {return}
    out := ran.(CompilationSuccessful)
    // testing.expect(t, out.compiler.stderr == "") // TODO: Implement array bounds checking so this line can be uncommented
    testing.expect(t, out.program.stderr == "")
    testing.expect(
        t,
        out.program.stdout ==
        `The number 1 is not prime
The number 2 is prime
The number 3 is prime
The number 4 is not prime
The number 5 is prime
The number 6 is not prime
The number 7 is prime
The number 8 is not prime
The number 9 is not prime
The number 10 is not prime
The number 11 is prime
The number 12 is not prime
The number 13 is prime
The number 14 is not prime
The number 15 is not prime
The number 16 is not prime
The number 17 is prime
The number 18 is not prime
The number 19 is prime
The number 20 is not prime
The number 21 is not prime
The number 22 is not prime
The number 23 is prime
The number 24 is not prime
The number 25 is not prime
The number 26 is not prime
The number 27 is not prime
The number 28 is not prime
The number 29 is prime
The number 30 is not prime
The number 31 is prime
The number 32 is not prime
The number 33 is not prime
The number 34 is not prime
The number 35 is not prime
The number 36 is not prime
The number 37 is prime
The number 38 is not prime
The number 39 is not prime
The number 40 is not prime
The number 41 is prime
The number 42 is not prime
The number 43 is prime
The number 44 is not prime
The number 45 is not prime
The number 46 is not prime
The number 47 is prime
The number 48 is not prime
The number 49 is not prime
The number 50 is not prime
The number 51 is not prime
The number 52 is not prime
The number 53 is prime
The number 54 is not prime
The number 55 is not prime
The number 56 is not prime
The number 57 is not prime
The number 58 is not prime
The number 59 is prime
The number 60 is not prime
The number 61 is prime
The number 62 is not prime
The number 63 is not prime
The number 64 is not prime
The number 65 is not prime
The number 66 is not prime
The number 67 is prime
The number 68 is not prime
The number 69 is not prime
The number 70 is not prime
The number 71 is prime
The number 72 is not prime
The number 73 is prime
The number 74 is not prime
The number 75 is not prime
The number 76 is not prime
The number 77 is not prime
The number 78 is not prime
The number 79 is prime
The number 80 is not prime
The number 81 is not prime
The number 82 is not prime
The number 83 is prime
The number 84 is not prime
The number 85 is not prime
The number 86 is not prime
The number 87 is not prime
The number 88 is not prime
The number 89 is prime
The number 90 is not prime
The number 91 is not prime
The number 92 is not prime
The number 93 is not prime
The number 94 is not prime
The number 95 is not prime
The number 96 is not prime
The number 97 is prime
The number 98 is not prime
The number 99 is not prime
The number 100 is not prime
`,
    )
}

@(test)
example_03_fibonacci :: proc(t: ^testing.T) {
    file :: #directory + "examples/fibonacci.txt"
    err := os.remove_all(file)
    testing.expect(t, err == nil || err.(os.General_Error) == .Not_Exist)

    ran := interpret_example(t, FunctionRef{#directory + "examples/03_fibonacci.code", "main"})
    testing.expect(t, ran.exit_code == 0)
    // testing.expect(ran.compiler_stderr == "") // TODO: Implement array bounds checking so this line can be uncommented

    data, err2 := os.read_entire_file(file, context.allocator)
    if err2 != nil {
        testing.fail_now(t, fmt.aprintf("Failed to read `%s`: %#v", file, err2))
    }
    defer delete(data, context.allocator)
    testing.expect(t, string(data) == "1597")
}

@(test)
example_04_linked_list :: proc(t: ^testing.T) {
    ran := run_example_via_c(t, #directory + "examples/04_linked_list.code", "")
    if ran == nil {return}
    out := ran.(CompilationSuccessful)
    testing.expect(t, out.compiler.stderr == "")
    testing.expect(t, out.program.stderr == "")
    testing.expect(t, out.program.stdout == "1\n2\n3\nReversed:\n3\n2\n1\n")
}

expect_ui_render :: proc(
    t: ^TestingTextExpecter,
    text: string,
    focused_button_num: int,
    pos := #caller_location,
) {
    expect_string(t, ansi_clear + "- ", pos)
    expect_string(t, text, pos)
    expect_string(t, "\n", pos)
    for i in 1 ..= 3 {
        expect_string(t, i == focused_button_num ? "- Focused button\n" : "- Button\n", pos)
        expect_string(t, "  - Text ", pos)
        expect_string(t, fmt.aprintf("%d", i), pos)
        expect_string(t, "\n", pos)
    }
    expect_string(t, "Enter either `next`, `prev`, `click`, or `quit`: ", pos)
}

@(test)
example_05_ui :: proc(t: ^testing.T) {
    ran := run_example_via_c(
        t,
        #directory + "examples/05_ui.code",
        "next\nclick\nprev\nprev\nclick\nnext\nnext\nnext\nclick\nquit\n",
    )
    if ran == nil {return}
    out := ran.(CompilationSuccessful)
    testing.expect(t, out.compiler.stderr == "")
    testing.expect(t, out.program.stderr == "")

    text_expecter := TestingTextExpecter{0, out.program.stdout, t}
    expect_ui_render(&text_expecter, "Initial text", 1)
    expect_ui_render(&text_expecter, "Initial text", 2) // After next
    expect_ui_render(&text_expecter, "Text 2", 2) // After click
    expect_ui_render(&text_expecter, "Text 2", 1) // After prev
    expect_ui_render(&text_expecter, "Text 2", 1) // After prev
    expect_ui_render(&text_expecter, "Text 1", 1) // After click
    expect_ui_render(&text_expecter, "Text 1", 2) // After next
    expect_ui_render(&text_expecter, "Text 1", 3) // After next
    expect_ui_render(&text_expecter, "Text 1", 3) // After next
    expect_ui_render(&text_expecter, "Text 3", 3) // After click
    expect_string(&text_expecter, ansi_clear)
    expect_finished(&text_expecter)
}

/*
// OLD(METAPROGRAM_IN_C)
@(test)
buffered_pipe_test :: proc(t: ^testing.T) {
    str :: "Hello world\n"
    pipe, err := create_buffered_pipe()
    testing.expect(t, err == nil)
    defer close_buffered_pipe(pipe)
    os.write_string(pipe.writer, str)
    read_str, err2 := bufio.reader_read_string(pipe.bufio_reader, '\n')
    testing.expect(t, err2 == nil)
    if str != read_str {
        testing.fail_now(t, fmt.aprintf("Expected %q, got %q", str, read_str))
    }
}
*/

// TODO: Mock a browser to test the counter and conways game of life

@(test)
example_06_counter :: proc(t: ^testing.T) {
    file :: #directory + "examples/counter.html"
    err := os.remove_all(file)
    testing.expect(t, err == nil || err.(os.General_Error) == .Not_Exist)

    ran := interpret_example(t, FunctionRef{#directory + "examples/06_counter.code", "build"})
    testing.expect(t, ran.exit_code == 0)
    testing.expect(t, ran.compiler.stderr == "")
    testing.expect(t, os.exists(file))
}

@(test)
example_07_conways_game_of_life :: proc(t: ^testing.T) {
    file :: #directory + "examples/conways_game_of_life.html"
    err := os.remove_all(file)
    testing.expect(t, err == nil || err.(os.General_Error) == .Not_Exist)

    ran := interpret_example(
        t,
        FunctionRef{#directory + "examples/07_conways_game_of_life.code", "build"},
    )
    testing.expect(t, ran.exit_code == 0)
    // testing.expect(t, ran.compiler_stderr == "") // TODO: Implement array bounds checking so this line can be uncommented
    testing.expect(t, os.exists(file))
}

@(test)
basic_fuzz_test :: proc(t: ^testing.T) {
    tmp_dir, err := os.temp_directory(context.allocator)
    if err != nil {
        testing.fail_now(t, "err != nil")
    }

    tmp_file, err2 := filepath.join([]string{tmp_dir, "fuzz.code"}, context.allocator)
    if err2 != nil {
        testing.fail_now(t, "err2 != nil")
    }


    for _ in 0 ..< 100 {
        code := random_string(800)

        // `%q` rather then `%s` to escape invalid runes and ANSI terminal escape codes
        fmt.printfln("Randomly generated code is:\n%q", code)

        err3 := os.write_entire_file(tmp_file, transmute([]u8)code)
        if err3 != nil {
            testing.fail_now(t, "err3 != nil")
        }

        pipe, _ := pipe_mock()
        compile(FunctionRef{tmp_file, "main"}, pipe, BuildC{}, NeverExitEarly{})
    }
}

@(test)
basic_type_system_test :: proc(t: ^testing.T) {
    types: Types
    generic_args0 := make([]Type, 1)
    generic_args0[0] = string_type
    generic_args1 := make([]Type, 1)
    generic_args1[0] = bool_type
    generic0 := create_type(&types, GenericTypeValue{GlobalValueWithGenericRef{7}, generic_args0})
    generic1 := create_type(&types, GenericTypeValue{GlobalValueWithGenericRef{7}, generic_args0})
    types.values[generic1.type.index].value.type = i64_type
    generic2 := create_type(&types, GenericTypeValue{GlobalValueWithGenericRef{7}, generic_args1})
    testing.expect(t, generic0.type == generic1.type)
    generic0_initialised := get_type(types, generic0.type).value.type
    testing.expect(t, generic0_initialised == i64_type)
    testing.expect(t, generic0.type != generic2.type)
}

@(test)
example_08_result :: proc(t: ^testing.T) {
    // TODO: Test inputs other than `dog`
    ran := run_example_via_c(t, #directory + "examples/08_result.code", "dog\n")
    if ran == nil {return}
    out := ran.(CompilationSuccessful)
    testing.expect(t, out.compiler.stderr == "")
    testing.expect(t, out.program.stderr == "")
    if out.program.stdout != "Enter the name of an animal: You entered the animal dog\n" {
        testing.fail_now(t, fmt.aprintf("Got the stdout `%s`", out.program.stdout))
    }
}

/*
// TODO:
// - Add support for hashmaps to the C backend so that 09_hashmap.code can be tested with the C backend
// - Add support for testing with the interpreter so that 09_hashmap.code can be tested with the interpreter
@(test)
example_09_hashmap :: proc(t: ^testing.T) {
    ran := run_normal_example(
        t,
        "examples/09_hashmap.code",
        "add\nbanana\nadd\napple\nadd\nbanana\nremove\napple\nexit\n",
    )
    if !ran.ok {return}
    testing.expect(t, ran.stderr == "")
    // TODO: Implement the test
}
*/

@(test)
example_10_geometry :: proc(t: ^testing.T) {
    ran := run_example_via_c(t, #directory + "examples/10_geometry.code", "")
    if ran == nil {return}
    out := ran.(CompilationSuccessful)
    testing.expect(t, out.compiler.stderr == "")
    testing.expect(t, out.program.stderr == "")
    e := TestingTextExpecter{0, out.program.stdout, t}
    expect_string(&e, "                              cc                              \n")
    expect_string(&e, "                    cccccccccccccccccccccc                    \n")
    expect_string(&e, "                cccc                      cccc                \n")
    expect_string(&e, "            cccc                              cccc            \n")
    expect_string(&e, "          cccc                                  cccc          \n")
    expect_string(&e, "        cccc                                      cccc        \n")
    expect_string(&e, "      cccc                                          cccc      \n")
    expect_string(&e, "      cc                                              cc      \n")
    expect_string(&e, "    cc                                                  cc    \n")
    expect_string(&e, "    cc                                                  cc    \n")
    expect_string(&e, "  cc                                                      cc  \n")
    expect_string(&e, "  cc                                                      cc  \n")
    expect_string(&e, "  cc                                                      cc  \n")
    expect_string(&e, "  cc                                                      cc  \n")
    expect_string(&e, "  cc                                                      cc  \n")
    expect_string(&e, "cccc                                                      cccc\n")
    expect_string(&e, "  cc                                                      cctt\n")
    expect_string(&e, "  cc                                                      tttt\n")
    expect_string(&e, "  cc                                                    tttttt\n")
    expect_string(&e, "  cc                                                  tttttttt\n")
    expect_string(&e, "  cc                                                tttttttttt\n")
    expect_string(&e, "    cc                                            tttttttttttt\n")
    expect_string(&e, "    cc                                          tttttttttttttt\n")
    expect_string(&e, "      cc                                      tttttttttttttttt\n")
    expect_string(&e, "      cccc                                  tttttttttttttttttt\n")
    expect_string(&e, "        cccc                              tttttttttttttttttttt\n")
    expect_string(&e, "          cccc                          tttttttttttttttttttttt\n")
    expect_string(&e, "            cccc                      tttttttttttttttttttttttt\n")
    expect_string(&e, "                cccc                tttttttttttttttttttttttttt\n")
    expect_string(&e, "                    cccccccccccccctttttttttttttttttttttttttttt\n")
    expect_string(&e, "                              cctttttttttttttttttttttttttttttt\n")
    expect_finished(&e)
}

@(test)
invalid_example_00_uninitialised_global_value_with_generics :: proc(t: ^testing.T) {
    ran := run_example_via_c(
        t,
        #directory + "examples/invalid/00_uninitialised_global_value_with_generics.code",
        "",
    )
    if ran == nil {return}
    out := ran.(CompilationFailed)
    e := TestingTextExpecter{0, out.compiler.stderr, t}
    expect_string(&e, "\n")
    expect_string(
        &e,
        "Error compiling `" +
        #directory +
        "examples/invalid/00_uninitialised_global_value_with_generics.code` (15:13)\n",
    )
    expect_string(
        &e,
        "Expected a func type, but got an uninitialised global value with generics\n",
    )
    expect_string(&e, "Hint: Try initialising the global value with something like `debug[T]`\n")
    expect_string(&e, "\n")
    expect_string(&e, "Erroneously checked with 1 error and 0 warnings in ")
    expect_digits(&e)
    expect_string(&e, ".")
    expect_digits(&e)
    expect_string(&e, " ms\n")
    expect_finished(&e)
}

@(test)
invalid_example_01_wrong_identifier_casing :: proc(t: ^testing.T) {
    file :: #directory + "examples/invalid/01_wrong_identifier_casing.code"
    ran := run_example_via_c(t, file, "")
    if ran == nil {return}
    out := ran.(CompilationSuccessful)
    testing.expect(t, out.program.stderr == "")
    testing.expect(t, out.program.stdout == "Hello world\n")
    testing.expect(t, out.compiler.stderr == "")
    e := TestingTextExpecter{0, out.compiler.stdout, t}
    fmt.println(out.compiler.stdout)
    expect_string(&e, "Reading `" + file + "`...\n")
    expect_string(&e, "Checking...\n")
    expect_string(&e, "\n")
    expect_string(&e, "Warning compiling `" + #directory)
    expect_string(&e, "examples/invalid/01_wrong_identifier_casing.code` (7:8)\n")
    expect_string(&e, "Expected generic names to be `CamelCase`, got `ok`\n")
    expect_string(&e, "First character in a camel case identifier must be an uppercase letter\n")
    expect_string(&e, "Got 'o'\n")
    expect_string(&e, "\n")
    expect_string(&e, "Warning compiling `" + #directory)
    expect_string(&e, "examples/invalid/01_wrong_identifier_casing.code` (7:12)\n")
    expect_string(&e, "Expected generic names to be `CamelCase`, got `err`\n")
    expect_string(&e, "First character in a camel case identifier must be an uppercase letter\n")
    expect_string(&e, "Got 'e'\n")
    expect_string(&e, "\n")
    expect_string(&e, "Successfully checked with 0 errors and 2 warnings in ")
    expect_digits(&e)
    expect_string(&e, ".")
    expect_digits(&e)
    expect_string(&e, " ms\n")
    expect_string(&e, "Emitting C code...\n")
    expect_done_message(&e)
    expect_finished(&e)
}

@(test)
invalid_example_02_wrong_main_function_type :: proc(t: ^testing.T) {
    file :: #directory + "examples/invalid/02_wrong_main_function_type.code"
    ran := run_example_via_c(t, file, "")
    if ran == nil {return}
    out := ran.(CompilationFailed)

    testing.expect(t, out.status == 1)

    e := TestingTextExpecter{0, out.compiler.stdout, t}
    expect_string(&e, "Reading `" + file + "`...\n")
    expect_string(&e, "Checking...\n")
    expect_done_message(&e)
    expect_finished(&e)

    e = TestingTextExpecter{0, out.compiler.stderr, t}
    expect_string(&e, "\n")
    expect_string(&e, "Error compiling\n")
    expect_string(&e, "Got the type `(String, I64) -> I64`\n")
    expect_string(&e, "Expected the type `() -> I64`\n")
    expect_string(&e, "\n")
    expect_string(&e, "Erroneously checked with 1 error and 0 warnings in ")
    expect_digits(&e)
    expect_string(&e, ".")
    expect_digits(&e)
    expect_string(&e, " ms\n")
    expect_finished(&e)
}

// TODO: Add a fuzz test where the code that gets compiled never has any syntax errors

// TODO: Add a fuzz test where the code that gets compiled has no invalid utf8 runes

// TODO: Test big numbers implementation

//@(test)
//run_examples :: proc(t: ^testing.T) {
//    examples_dir := fmt.aprintf("%s/examples", #directory)
//
//    opened, err := os.open(examples_dir)
//    if err != nil {
//        testing.fail_now(t, fmt.aprintf("Failed to open examples directory: %#v", err))
//    }
//
//    files: []os.File_Info
//    files, err = os.read_dir(opened, -1, context.allocator)
//    if err != nil {
//        testing.fail_now(t, fmt.aprintf("Failed to read examples directory: %#v", err))
//    }
//
//    for file in files {
//        if strings.ends_with(file.fullpath, ".code") {
//            run_example(t, file.fullpath)
//        }
//    }
//}

