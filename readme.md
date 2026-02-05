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
- Implement creating and mutating variables with function calls
- Implement more types:
  - Numbers of types other than `i64`
  - Structs
  - Enums
  - Unions
  - Arrays
- Design and implement memory management
- Implement being able to use a functions argument in its body
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
    - The type of a function describes wether it may cause affects (like [roc](https://www.roc-lang.org/))
- Implement features until the tests pass

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

# What I mean by "constraints"

I think there are only 3 reasons for programming languages to have type systems.

Reason 1: knowing the shape of the data that you're dealing with. For me, this feels really important for both allowing me to know what code I want to write, and allowing my LSP to autocomplete code, but given that languages like [Elixir](https://elixir-lang.org/) are [so admired](https://survey.stackoverflow.co/2025/technology#admired-and-desired), this reason might not apply to me if I get used to dynamically typed langauges.

Reason 2: reducing the surface area of bugs. By this, I mean that in a language without types, if there is a runtime error, the programmer has no idea which part of their code is causing the issue, since the function where the runtime error occurs could have been passed invalid input data. Whereas, in a typed language, the types can usually garuntee that a function's arguments are valid input data, so if there is a runtime error in that function, the programmer knows that the code in that function is at fault. Additionally, what was a runtime error in a language without types, can become a compile time error in a langauge with types.

Reason 3: being able to more easily generate more efficient machine code. This reason is largely an implementation detail, which can be ignored when designing programming languages for the 99%+ of programs where the performance bottleneck is the programmer rather than the programming language.

The question "why can't the type system **always** garuntee that a function's arguments are valid input data?" stems from reason 2, and from this question the idea of constraints comes about.

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
