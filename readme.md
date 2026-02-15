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
  - Maybe you should have to explicitly set the initial value of every element in an array rather than being able to implicitly initialise a fixed size array with something like `[100]Bool<>`
- Automatically run the C compiler after C code is emitted
- Update the syntax:
  - Instead of `<>`, I would rather use `[]` for union/sum types, but that conflicts with array types
  - I don't like using `={}` for the payload of struct literals, tagged union literals, and array literals
    - I would rather use just `{}` but that means you can't distinguish between an identifier value followed by a block and a struct literal
      - This lack of clarity comes up with `for` loops, for example in `for i in ident {...}`, is the value being iterated over `ident {...}` or is the `...` the for loop's body
    - I can't use just `[]` because then if you have something like `ident[0]`, is this a struct literal of type `ident`, or is it accessing the index `0` of the array `ident`
    - I can't use just `<>` because then if you have something like `MyStructType<1, 2>3`, you cannot easily tell whether `2>3` is boolean comparison or if that code is the value `MyStructType<1, 2>`, and the `3` is a typo
  - Instead of `[]Type={elems}`, I would rather use `[elems]` for array literals, but that is harder to type check
  - Instead of `||`, I would rather use `()` for function definitions, but that conflicts with order of operations grouping
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

# Current Roadmap

- v0.1.0: Mostly stabilize memory model
- v0.2.0: Investigate [constraints](#what-i-mean-by-constraints)
- v0.3.0: Implement any language features for writing interactive user interfaces, and a UI library to do so
- v0.4.0: Implement a backend that goes all the way to assembly code
- v0.5.0: Quality of life improvements:
  - LSP
  - Formatter
  - Automatically generate documentation from code comments
  - Type inference?

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
- Disciminating the size of an array
- Creating SOA arrays, for example:

  ```
  my_soa_array_type = {
    length: uint,
    names: []string,
    ages: []string,
  } where (.length == .names.len and .length == .ages.len)
  ```
