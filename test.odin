package main

import "core:fmt"
import "core:os/os2"
import "core:path/filepath"
import "core:strings"
import "core:testing"

@(test)
run_examples :: proc(t: ^testing.T) {
    base_dir, ok := filepath.abs(filepath.dir(os2.args[0]))
    if !ok {
        testing.fail_now(t, "Failed to make path absolute")
    }
    examples_dir := fmt.aprintf("%s/examples", base_dir)
    compiler_executable := fmt.aprintf("%s/programming_language", base_dir)
    fmt.println(examples_dir)

    opened, err := os2.open(examples_dir)
    if err != nil {
        testing.fail_now(t, fmt.aprintf("Failed to open examples directory: %#v", err))
    }

    files: []os2.File_Info
    files, err = os2.read_dir(opened, -1, context.allocator)
    if err != nil {
        testing.fail_now(t, fmt.aprintf("Failed to read examples directory: %#v", err))
    }

    for file in files {
        suffix :: ".code"
        if strings.ends_with(file.fullpath, suffix) {
            without_suffix := file.fullpath[0:len(file.fullpath) - len(suffix)]
            c_code := fmt.aprintf("%s.c", file.fullpath)
            executable := fmt.aprintf("%s.bin", without_suffix)

            ok := build(file.fullpath)
            if !ok {
                testing.fail(t)
                continue
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
                continue
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
                continue
            }
            // TODO: Compare stdout got and stdout expected
        }
    }
}

