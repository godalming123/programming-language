package main

import "core:fmt"
import "core:os/os2"
import "core:path/filepath"
import "core:testing"

RanExample :: struct {
    stdout: string,
    stderr: string,
    ok:     bool,
}

run_example :: proc(t: ^testing.T, relative_path: string) -> RanExample {
    base_dir, ok := filepath.abs(filepath.dir(os2.args[0]))
    if !ok {
        testing.fail_now(t, "Failed to make path absolute")
    }
    fullpath := fmt.aprintf("%s/%s", base_dir, relative_path)

    c_code := fmt.aprintf("%s.c", fullpath)
    executable := fmt.aprintf("%s.bin", fullpath)

    ok = build(fullpath)
    if !ok {
        testing.fail(t)
        return RanExample{"", "", false}
    }

    state, stdout, stderr, err := os2.process_exec(
        os2.Process_Desc{command = []string{"gcc", c_code, "-o", executable}},
        context.allocator,
    )
    if err != nil {
        testing.fail_now(t, fmt.aprintf("Failed to compile `%s`: %#v", c_code, err))
    }
    if state.exit_code != 0 {
        fmt.eprintfln(
            "Failed to compile `%s`:\nExit code: %d\nStderr:\n%s\nStdout:\n%s",
            c_code,
            state.exit_code,
            stdout,
            stderr,
        )
        testing.fail(t)
        return RanExample{"", "", false}
    }

    // TODO: Check for memory leaks when the process runs
    state, stdout, stderr, err = os2.process_exec(
        os2.Process_Desc{command = []string{executable}},
        context.allocator,
    )
    if err != nil {
        testing.fail_now(t, fmt.aprintf("Failed to run `%s`: %#v", executable, err))
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
        return RanExample{"", "", false}
    }
    return RanExample{string(stdout), string(stderr), true}
}

@(test)
fizzbuzz_example :: proc(t: ^testing.T) {
    ran := run_example(t, "examples/fizzbuzz.code")
    if !ran.ok {return}
    testing.expect(t, ran.stderr == "")
    testing.expect(
        t,
        ran.stdout ==
        "1\n2\nFizz\n4\nBuzz\nFizz\n7\n8\nFizz\nBuzz\n11\nFizz\n13\n14\nFizzbuzz\n16\n17\nFizz\n19\nBuzz\nFizz\n22\n23\nFizz\nBuzz\n26\nFizz\n28\n29\nFizzbuzz\n31\n32\nFizz\n34\nBuzz\nFizz\n37\n38\nFizz\nBuzz\n41\nFizz\n43\n44\nFizzbuzz\n46\n47\nFizz\n49\nBuzz\nFizz\n52\n53\nFizz\nBuzz\n56\nFizz\n58\n59\nFizzbuzz\n61\n62\nFizz\n64\nBuzz\nFizz\n67\n68\nFizz\nBuzz\n71\nFizz\n73\n74\nFizzbuzz\n76\n77\nFizz\n79\nBuzz\nFizz\n82\n83\nFizz\nBuzz\n86\nFizz\n88\n89\nFizzbuzz\n91\n92\nFizz\n94\nBuzz\nFizz\n97\n98\nFizz\nBuzz\n",
    )
}

@(test)
factorial_example :: proc(t: ^testing.T) {
    ran := run_example(t, "examples/factorial.code")
    if !ran.ok {return}
    testing.expect(t, ran.stderr == "")
    testing.expect(t, ran.stdout == "120\n")
}

//@(test)
//run_examples :: proc(t: ^testing.T) {
//    base_dir, ok := filepath.abs(filepath.dir(os2.args[0]))
//    if !ok {
//        testing.fail_now(t, "Failed to make path absolute")
//    }
//    examples_dir := fmt.aprintf("%s/examples", base_dir)
//
//    opened, err := os2.open(examples_dir)
//    if err != nil {
//        testing.fail_now(t, fmt.aprintf("Failed to open examples directory: %#v", err))
//    }
//
//    files: []os2.File_Info
//    files, err = os2.read_dir(opened, -1, context.allocator)
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

