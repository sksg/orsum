# My ∨∑ (orsum) toy-language

## Features

1. **Virtual Machine Implementation**:
   - A customizable virtual machine (`VirtualMachine`) with tracing modes for execution, stack, and input.

2. **Intermediate Representation**:
   - Support for creating registers and constants with debug information.
   - Provides operations for handling bytecode, constants, and instructions.

3. **Syntax Parsing**:
   - Recursive Descent Parser with tracing options for consumption, transition, production, and input handling.
   - Support for tokenization and parsing errors.

4. **Value Types**:
   - Supports various value types like integers, floating points, booleans, and strings.
   - Type checking and conversion utilities.

5. **Build System**:
   - Configurable build system using Zig's `std.Build` for creating executables.

6. **Testing Utilities**:
   - Functions for comparing slices and providing detailed differences.
   - Utility for rendering differences in control codes and binary data.

7. **Tracing Capabilities**:
   - Tracing for tokens, parsers, and virtual machine execution.

This repository demonstrates a toy-language implementation with various features to explore programming language concepts, virtual machine design, and testing practices.