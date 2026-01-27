> [!NOTE]
> This programming language is pre-alpha, and almost everything may change as the language is developed.

# The two types of type

- For simple types, the compiler knows the maximum possible amount of memory that the type can use at compiler time
- For complex types, the compiler does not know this

# The two stacks

Most programming languages have one stack, but this one has two:

| Compiler managed stack (CMS)                                                                                     | Programmer manager stack (PMS)                                                |
| ---------------------------------------------------------------------------------------------------------------- | ----------------------------------------------------------------------------- |
| When a function returns, the CMS must have the same variables on it as it had on it when the function was called | Can grow and shrink independently of functions being called and returned from |
| Can cause a stack overflow                                                                                       | Can expand to fill all of the systems available memory                        |
| Only uses a system call to exit the program if the CMS overflows                                                 | May use a system call to resize the PMS when it grows and shrinks             |
| Data stored on the CMS cannot be resized                                                                         | Data stored on the PMS can be resized if it is the last thing on the PMS      |
