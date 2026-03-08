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

    executable, build_ok := build(fullpath)
    if !build_ok {
        testing.fail(t)
        return RanExample{"", "", false}
    }

    // TODO: Check for memory leaks when the process runs
    state, stdout, stderr, err := os2.process_exec(
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

@(test)
primes_example :: proc(t: ^testing.T) {
    ran := run_example(t, "examples/primes.code")
    if !ran.ok {return}
    testing.expect(t, ran.stderr == "")
    testing.expect(
        t,
        ran.stdout ==
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
comptime_fibonacci_example :: proc(t: ^testing.T) {
    ran := run_example(t, "examples/comptime_fibonacci.code")
    if !ran.ok {return}
    testing.expect(t, ran.stderr == "")
    testing.expect(t, ran.stdout == "")
    file :: "fibonacci.txt"
    data, err := os2.read_entire_file(file, context.allocator)
    if err != nil {
        testing.fail_now(t, fmt.aprintf("Failed to read `%s`: %#v", file, err))
    }
    defer delete(data, context.allocator)
    testing.expect(t, string(data) == "1597")
}

@(test)
linked_list_example :: proc(t: ^testing.T) {
    ran := run_example(t, "examples/linked_list.code")
    if !ran.ok {return}
    testing.expect(t, ran.stderr == "")
    testing.expect(t, ran.stdout == "1\n2\n3\n")
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

