> [!NOTE]
> This programming language is pre-alpha, and almost everything may change as the language evolves.

# Markers

- When a function is marked with `#comptime`, it means that it can only be ran at compile time because it interacts with the compiler
- All `#comptime` functions either use another `#comptime` function or use a function in the `compiler` namespace
- You cannot call a `#comptime` function from a function that isn't marked with `#comptime`

<!--
- When a function is marked with `#comptime`, it means that it can only be ran at compile time because it interacts with the compiler
- When a function is marked with `#js`, it means that it cannot be transpiled to C nor ran at compile time because it uses JS code

- All `#comptime` functions either use another `#comptime` function or use a function in the `compiler` namespace
- All `#js` functions either use another `#js` function, or use a function in the `js` namespace
-->

# General

- `~` means that something is being mutated
- `+` means that something is being allocated onto the PCS
- `-` means that something is being deallocated from the PCS

# Variables

## Create constant

```
my_constant = "hello world"
```

## Create mutable

```
mut my_number = 10
```

## Update mutable

```
~my_number += 5
// OR
~my_number = my_number + 5
```

# The two types of type

- For normal types, the compiler knows the maximum possible amount of memory that the type can use at compiler time, so the type can be stored using just the CMS
- For dynamic types, the compiler does not know this, so part of the type has to be stored on the PMS[^3]

# The two stacks

Most programming languages have one stack, but this one has two:

| Compiler managed stack (CMS)                                                                                  | Programmer manager stack (PMS)                                                                                                                                                                                                                                            |
| ------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Can only store data where the maximum size of the data is known at compile time                               | Can store data with a conceptually infinite maximum size                                                                                                                                                                                                                  |
| The space used to store a piece of data is the maximum amount of space which that the piece of data could use | If the maximum size of a piece of data is known at compile time, that is the amount of space used to store that piece of data. Otherwise, the data can be resized if it is the last thing on the PMS, which updates the amount of space used to store that piece of data. |
| Can cause a stack overflow[^1]                                                                                | Can expand to fill all of the system's available memory[^2]                                                                                                                                                                                                               |
| Only uses a system call to exit the program if the CMS overflows[^1]                                          | May use a system call to resize the PMS when it grows and shrinks                                                                                                                                                                                                         |
| The compiler can optimize data which is stored in the CMS to be stored in a register instead                  | It is harder to implement a compiler optimization which stores data in registers rather than the PMS                                                                                                                                                                      |

# How to do memory management

If you're doing low-level memory management, and you add a way to represent a variable size array that is stored in a specific arena, then how do you represent an array of arrays? I think that you need to be able to represent that a piece of data uses a variable number of contiguous regions of memory.

This could be something like:

- Each type has a set of contiguous memory spaces which it uses to store data
- Each type has a specific range of the number of contiguous memory spaces that it uses to store data
  - `0` contiguous memory spaces -> only stored on CMS
  - `1` contiguous memory space -> partially stored on CMS, partially stored on PMS
  - `>1` contiguous memory spaces -> ?
- There are a couple data structures which use a contiguous memory space

```
String<A> : Array(U8)<A>

MathToken<A> : < // All of `A` stores part of `MathToken`
	Plus{pos: U64},
	Minus{pos: U64},
	Multiply{pos: U64},
	Divide{pos: U64},
	OpenBracket{pos: U64},
	CloseBracket{pos: U64},
	Integer{pos: U64, value: I64},
	Float{pos: U64, value: F64},
	Error{pos: U64, msg: String<A>},
>

ParsedMath<in A> : < // Part of `A` stores part of `ParsedMath`
	Addition{Pointer(ParsedMath)<in A, in A>, Pointer(ParsedMath)<in A, in A>},
	Subtraction{Pointer(ParsedMath)<in A, in A>, Pointer(ParsedMath)<in A, in A>},
	Multiplication{Pointer(ParsedMath)<in A, in A>, Pointer(ParsedMath)<in A, in A>},
	Division{Pointer(ParsedMath)<in A, in A>, Pointer(ParsedMath)<in A, in A>},
	Negation{Pointer(ParsedMath)<in A, in A>},
	Integer{I64},
	Float{F64},
>
```

# Footnotes

[^1]: Provided that recursion isn't used, the maximum size of the CMS could be calculated at compile time to make stack overflows impossible.

[^2]: In initial implementations, the maximum size of the PMS may be a fixed massive number like 64GB rather than being the size of system's memory.

[^3]: TODO: Add a way to create extra programmer controlled stacks which are implemented using arenas
