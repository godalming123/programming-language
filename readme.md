# Programming language

The second programming language that I've developed, after [common assembly](https://github.com/godalming123/common-assembly).

# Compiling from source

```sh
odin build .
```

# Compiling and executing the fizzbuzz example

```sh
./programming_language build examples/fizzbuzz.code
gcc examples/fizzbuzz.code.c -o fizzbuzz
./fizzbuzz
```

# Running tests

```sh
odin test .
```

# Todo

- Choose a name
- Remove unnecersarry array copies from the C backend
  - Once this is done, arrays should grow by a multiple of 2 when they overflow rather than growing the minimum amount to be able to fit their new contents
- Add modules and namespaces
- Add garbage collection to the emitted C code to stop it from leaking memory
- Do not leak memory in the compiler
- Replace a couple of the compiler functions with functions in the standard library:
  - `compiler.write_file`
  - `compiler.run_executable`
  - `compiler.read_file`
- Tell the c compiler the type of the number literals that are emitted
- Check that number literals aren't too big or small for their type
- Implement parsing boolean not
- Implement more types:
  - Numbers of types other than `i64`
  - Structs
  - Enums
  - Unions
  - Dynamically sized arrays
- Design and implement memory management
- Implement string interpolation
- Add support for `yield` in if statements (should `yield`ing from a loop be supported?)
- Implement defer
- Use single statement switch in `odinfmt.json` when [this issue](https://github.com/DanielGavin/ols/issues/1255) is fixed
- Figure out if/how you represent a function causing side affects:
  - IMO computationally pure functions are important for the testing and predictability of a codebase
  - But, there are plenty of algorithms where you should create a side affect while an otherwise pure function is running
  - For example, in a compiler, your main compilation code should cause side affects because it should output errors and warnings as soon as they are found rather than waiting for that compilation stage to finish
  - Ways of describing side affects in other languages:
    - All functions are pure and just use monads to cause side affects (like [haskell](https://www.haskell.org/))
    - The side affects that a function may cause are described in the type signature (like [koka](https://koka-lang.github.io/koka/doc/index.html))
    - The type of a function describes whether it may cause affects (like [roc](https://www.roc-lang.org/))
- Add a better way of initialising arrays with lots of elements:
  - For example an array of 100 booleans where the first 50 are `true`, the next is `false`, and the rest are `true`
  - This could be something like `[100]Bool<50 x true, false, 49 x true>`
    - In this example, the numbers would be compile-time known constants to avoid the length mismatching
  - Zig handles this by supporting repeating arrays and appending arrays at compile-time
  - Maybe you should have to explicitly set the initial value of every element in an array rather than being able to implicitly initialise a fixed size array with something like `[100]Bool<>`
- Update some of the syntax (see [the syntax](#the-syntax))
- Implement data structures
  - Arena backed array with an embedded freelist
  - Tree
  - Hash based data structures:
    - Hash map
    - Hash set
    - Ordered hash map
    - Ordered hash set
    - Should there be an efficient way to store a reference to a particulair item in one of these data structures?
  - Arena backed buffer with an embedded freelist?
  - Arena backed malloc/free/free_all implementation?
- Implement generic types
- Deduplicate PMS resize operations
- Support length based strings as well as null terminated strings
- Always output error messages and warnings in the order that they appear in the program, rather than a somewhat random order

# Stuff that may be added

- A compiler function to minify JS
  - Simplifies build process as you can create minified JS code without needing a separate JS minifier, and the JS minifier would probably need a JS package manager
- Some kind of backwards pipe operator like [gleam's use expression](https://tour.gleam.run/advanced-features/use/)
  - Something like:
    ```
    main = || {
      use name = Input("What is your name?") // Alternative syntax: `name <- Input("What is your name?")`
      use Println("Hello ${name}") // Alternative syntax: `<- Println("Hello ${name}")`
      Exit(0)
    }
    ```
  - Would desugar to:
    ```
    main = || {
      Input("What is your name?", |name| {
        Prinln("Hello ${name}", || {
          Exit(0)
        })
      })
    }
    ```
  - (When I say "closure" here, I just mean a function that is defined inside another function)
  - This isn't really useful without closures that can access variables from the function where the closure was defined
    - You can maintain performance while also having closures that can access variables from the function where the closure was defined if you have linear types and 2 types of closure:
      - Closures where the type has `->` can be ran any number of times, and cannot access variables from the function where the closure was defined
      - Closures where the type has `=>` have to be ran exactly once, and can access variables from the function where the closure was defined
- Some kind of `loop` syntax sugar:
  ```
  sum = loop |n: I64 = 1, sum = 0| -> I64 {
    if n > 100 {
      return sum
    }
    return continue(n + 1, sum + n)
  }
  ```
  - This could also be done using a pipe operator that takes a tuple and passes all of the values in the tuple into the function as arguments:
    ```
    (1, 0) |> |n: I64, sum: I64| {
      if n > 100 {
        return sum
      }
      return self(n + 1, sum + n)
    }
    ```

# The syntax

- Instead of `<>`, I would rather use `[]` for union/sum types, but that conflicts with array types
- Instead of `[]Type(elem1, elem2, ...)`, I would rather use `[elem1, elem2, ...]` for array literals, but that is harder to type check
- Instead of `|args| -> ReturnType {...}`, I would rather use `(args) -> ReturnType {}` for function definitions, but that syntax conflicts with order of operations grouping
- Notes on the syntax for the payload of struct literals, tagged union literals, and array literals:
  - Syntaxes that can be used:
    - Just `()` (the current syntax)
    - `={}`
  - Syntaxes that can't easily be used:
    - Just `{}`, because then you can't distinguish between an identifier value followed by a block and a struct literal
      - This lack of clarity comes up with `for` loops, for example in `for i in ident {...}`, you can't tell if the value being iterated over `ident {...}` or if the `...` is the body of the for loop
    - Just `[]`, because then if you have something like `ident[0]`, then you can't tell if this is a struct literal of type `ident`, or if it is accessing the index `0` of the array `ident`
    - Just `<>`, because then if you have something like `MyStructType<1, 2>3`, you cannot easily tell whether `2>3` is a boolean comparison or if that code is the value `MyStructType<1, 2>`, and the `3` is a typo
  - Most of the syntaxes that can't be used could be used if there was a distinction in the tokenizer between `CamalCase` identifiers (which would be used for types) and `snake_case` identifiers (which would be used for variables)
  - I'm not sure if adding that distinction is worth the trade off in the quality of the parser's error messages
  - You also can't tell whether something like `JS` is a `CamalCase` or `snake_case` identifier

# Current Roadmap

- v0.1.0: Implement any language features for writing interactive user interfaces, and a UI library to do so:
  - Features of the UI system:
    - Functional, elm-like reactivity
    - Can compile to several different artifacts, all of which can seamlessly work together in the same website:
      - Static HTML, with client side reactivity
      - An executable for a server to handle requests
      - JS code that could run on the edge
  - Metaprogramming:
    - It could be nice to be able to define a couple different `build` functions in the standard library for different types of website, and have that be sufficient for building 99%+ of websites
    - There could be a different `build` function for:
      - Static site generation
      - Generating an executable for a server which implements a simple server+client model
      - Generating some JS code which could run on the edge
    - For this to be possible, you need some way to define that a particulair function/constant specifies the metadata/interactivity for one of the pages on the website
      - Maybe this could be done with tags, for example:
        ```
        CounterState : {
          count: I64,
        }

        #page={
          output_path = "counter.html",
          initial_state = CounterState={1},
        }
        counter = |s: CounterState| -> []Html(CounterState) {
          return []Html={
            button(
              "The count is ${s.count}",
              |s: CounterState| -> CounterState {return CounterState={s.count + 1}},
            ),
          }
        }
        ```
      - And then the build function would be implemented something like:
        ```
        import compiler
        output_page = |function, tag_arguments| {...}
        build = || {
          compiler.get_all_globals(with_tag = #page)
          |> compiler.expect_types(($State) -> []Html($State))
          |> map(output_page)
        }
        ```
- v0.2.0: Quality of life improvements:
  - LSP
    - A code action to reorder fields in a struct
    - A code action to rename
    - I think that the LSP code actions should also be accessible through a CLI
  - Formatter
  - Automatically generate documentation from code comments
  - Nice quality of life features for print debugging:
    - Although using a debugger is probably better, the combination of a couple of language features can create a really nice print debugging experience:
      - Compile-time constant booleans for whether to debug some information + `when` statements to only include some code to debug that info when the flag is enabled (like in odin)
      - `deferred_in_out` to visualise function calls with nested debug messages (like in odin)
      - Being able to convert any arbitrary type to a string without writing any extra code (like in odin)
  - Type inference?
- v0.3.0: Investigate [constraints](#what-i-mean-by-constraints)
- v0.4.0: Mostly stabilize a lower level memory model
- v0.5.0: Implement a backend that goes all the way to assembly code

# Potential zen of this programming language

I don't think that finalizing a set of design principles before designing a programming language is useful. It's just far better to refine a design principle by testing it in practise than to refine the principle by writing it down and thinking about it. When thinking of design principles without prototyping possible designs, I find that the principles either become vague and obvious, or fall-flat in the real world. For example, in common assembly there was [this design principle](https://github.com/godalming123/common-assembly/blob/1e9dfd7123ca2876e5312cc519d1a657d1e6533e/design.md?plain=1#L42) to "Create a syntax that shows the programmer how their code is slow", with the idea that the programmer would than be able to better optimize their code than an optimizing backend, which prototyping revealed to have many caveats:

- For a programmer that does not care about performance, a good optimizing backend compiling higher-level code produces faster machine code than a simple backed compiling low-level code
- General algorithms are more important than specific optimizations for performance, so a lower-level language design can cause slower code to be written because the language design induces too much friction when the programmer tries to improve the general algorithm
- For different architectures and runtimes, code is slow in different ways

Even for principles like "don't repeat yourself", real-world experience caveats this to "only repeat yourself a few times for small sections of code", with some experienced programmers [not including the rule](https://users.ece.utexas.edu/~adnan/pike.html) in their rules of programming.

Considering all of this, these design principles are tentative and subject to change. I think of them more as a hypothesis which I'm recording now for the curiosity of finding out if they hold up in the real world than some permanent decree.

- It's better to have a feature that covers 90% of it's potential use cases with 10% of the complexity than a feature that covers 99.9% of it's potential use cases with 100% of the complexity

# Programming language memory model

## Criteria for a memory model

- Safety:
  - No dereferencing invalid pointers:
    - No use after free
    - No null pointer dereference
  - No double free
  - Unused objects are forced to be cleaned up, so that memory leaks are not possible:
    - Free pointers
    - Close files
  - Thread safe code
- Simplicity
- Conciseness
- Performance

## Levels of performance for a memory model

1. Every piece of data is stored on either registers, or the CMS, or the PMS
2. Most data is stored on registers or the stack, some data is stored on the heap and managed manually
3. Most data is stored on registers or the stack, some data is stored on the heap and managed using reference counting
4. Most data is stored on registers or the stack, some data is stored on the heap and managed using garbage collection
5. Data is unnecessarily copied

## Other memory models

- Borrow checker (like in rust)
- Linear types (like in austral)
  - Linear types mean that each variable is used exactly once
- Mutable value semantics (like in hylo)
- Reference counting (like in swift)
- Garbage collection (like in go)
- Stack based memory management

# What I mean by "constraints"

> [!NOTE]
> This seems a lot like [idris](https://www.idris-lang.org/), however idris seems to only be able to prove constraints for functional programs (programs without mutation and loops), and I find functional code unreadable, so I don't think a constraints system like that is worth it given the reduction in readability.

I think there are only 3 reasons for programming languages to have type systems.

Reason 1: knowing the shape of the data that you're dealing with. For me, this feels really important for both allowing me to know what code I want to write, and allowing my LSP to autocomplete code, but given that languages like [Elixir](https://elixir-lang.org/) are [so admired](https://survey.stackoverflow.co/2025/technology#admired-and-desired), this reason might not apply to me if I get used to dynamically typed languages.

Reason 2: reducing the surface area of bugs. By this, I mean that in a language without types, if there is a runtime error, the programmer has no idea which part of their code is causing the issue, since the function where the runtime error occurs could have been passed invalid input data. Whereas, in a typed language, the types can usually guarantee that a function's arguments are valid input data, so if there is a runtime error in that function, the programmer knows that the code in that function is at fault. Additionally, what was a runtime error in a language without types, can become a compile time error in a language with types.

Reason 3: being able to more easily generate more efficient machine code. This reason is largely an implementation detail, which can be ignored when designing programming languages for the 99%+ of programs where the performance bottleneck is the programmer rather than the programming language.

The question "why can't the type system **always** guarantee that a function's arguments are valid input data?" stems from reason 2, and from this question the idea of constraints comes about.

Constraints could also be used for things like:

- The compiler being able to prove that an assert will always be true at compile time
- Disciminating the type of a union
  - This could replace the `match` statement
- Disciminating the size of an array
- Creating SOA arrays, for example:

  ```
  my_soa_array_type = {
    length: uint,
    names: []string,
    ages: []string,
  } where (.length == .names.len and .length == .ages.len)
  ```
