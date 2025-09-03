<div align="center">

![The Tiny Lua Compiler (TLC)](https://github.com/ByteXenon/TinyLua/assets/125568681/41cf5285-e31d-4b27-a8a8-ee83a7300f1f)

**A minimal, educational Lua 5.1 compiler written in Lua**

_Inspired by [Jamie Kyle's The Super Tiny Compiler](https://github.com/jamiebuilds/the-super-tiny-compiler) written in JavaScript_

</div>

## Features

- **Heavily Commented & Educational**: The code is written to be read, with over 50% of the file dedicated to comments explaining the what, how, and why of each step.
- [**Self-compiling**](<https://en.wikipedia.org/wiki/Self-hosting_(compilers)>): TLC is powerful enough to compile its own source code, producing a new, fully-functional version of itself. This is the final milestone in compiler design, demonstrating that the compiler can handle the complexities of its own syntax and semantics.
- **Zero dependencies**: Written in standard Lua 5.1 with no external libraries. Just one file and the Lua interpreter are all you need.
- **Speed**: While education is the priority, the tokenizer uses optimized lookups and the compiler is designed efficiently, making it quite fast for a compiler written in a high-level language.
- **100% test coverage**: TLC has a test suite that covers 100% of the code. Want to see it in action? Run `lua tests/test.lua` in your terminal.

### [Want to jump into the code? Click here](https://github.com/bytexenon/The-Tiny-Lua-Compiler/blob/main/the-tiny-lua-compiler.lua)

---

### Why should I care?

That's fair, most people don't really have to think about compilers in their day
jobs. However, compilers are all around you, tons of the tools you use are based
on concepts borrowed from compilers.

### Why Lua?

Lua is a simple programming language that is easy to learn and use. It doesn't
have complex syntax or a lot of features, which makes it a great language to
make a compiler for.

### But compilers are scary!

Yes, they are. But that's our fault (the people who write compilers), we've
taken something that is reasonably straightforward and made it so scary that
most think of it as this totally unapproachable thing that only the nerdiest of
the nerds are able to understand.

### Example usage?

The compiler is written in a way that it can be used as a library.
Here is an example of how you can use it:

```lua
--[[
  EXAMPLE: COMPILE AND EXECUTE LUA CODE WITH TLC
  ----------------------------------------------
  Demonstrates the full compilation pipeline from
  source code to execution.
--]]

local tlc = require("the-tiny-lua-compiler")

-- 1. Source code to compile
local source = [[
  for i = 1, 3 do
    print("Hello from TLC! " .. i)
  end
]]

-- 2. Compilation Pipeline
-- -----------------------

-- Alternatively, you can use `tlc.fullCompile(source)` to do all of the steps in one go.
-- The `fullCompile` function is a stable entry point that ensures future compatibility.
-- It handles the entire compilation process, so you don't have to worry about the
-- internal steps changing in future versions of TLC.

-- Tokenize: Raw text -> Stream of tokens
local tokens    = tlc.Tokenizer.new(source):tokenize()

-- Parse: Stream of tokens -> Abstract Syntax Tree (AST)
local ast       = tlc.Parser.new(tokens):parse()

-- Generate Code: AST -> Function Prototype (Intermediate Representation)
local proto     = tlc.CodeGenerator.new(ast):generate()

-- Compile: Function Prototype -> Final Lua Bytecode String
local bytecode  = tlc.Compiler.new(proto):compile()

-- 3. Execution
-- ------------
-- NOTE: Requires Lua 5.1 to run the bytecode.
local compiledFunction = loadstring(bytecode)
compiledFunction() -- Execute the compiled bytecode

--[[
  EXPECTED OUTPUT:
  Hello from TLC! 1
  Hello from TLC! 2
  Hello from TLC! 3
--]]
```

<sup><sub>
`loadstring` can be used not only to load and execute Lua 5.1 *human-readable code*, but it also supports loading Lua 5.1 *bytecode* - which is exactly what TLC generates. This means you can run code compiled by TLC directly with `loadstring`. Alternatively, you can write the bytecode to a file and execute it with `lua <filename>`.
</sub></sup>

### Okay so where do I begin?

Awesome! Head on over to the [the-tiny-lua-compiler.lua](https://github.com/bytexenon/The-Tiny-Lua-Compiler/blob/main/the-tiny-lua-compiler.lua) file.

### Tests

Run the test suite with:

```bash
lua tests/test.lua
```

### Support The Tiny Lua Compiler (TLC)

I don't take donations, but you can support TLC by starring the repository and sharing it with others.
If you find a bug or have a feature request, feel free to open an issue or submit a pull request.

---

[![cc-by-4.0](https://licensebuttons.net/l/by/4.0/80x15.png)](http://creativecommons.org/licenses/by/4.0/)
