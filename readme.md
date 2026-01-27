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
- v0.2.0: Investigate using constraints for things like:
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
- v0.3.0: Implement any language features for writing interactive user interfaces, and a UI library to do so
- v0.4.0: Implement a backend that goes all the way to assembly code
