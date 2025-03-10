<div align="center">

![The Tiny Lua Compiler (TLC)](https://github.com/ByteXenon/TinyLua/assets/125568681/41cf5285-e31d-4b27-a8a8-ee83a7300f1f)

**A minimal, educational Lua 5.1 compiler written in Lua**

_Inspired by [Jamie Kyle's The Super Tiny Compiler](https://github.com/jamiebuilds/the-super-tiny-compiler) written in JavaScript_

</div>

## Features

- **Educational**: Reading through the guided code will help you learn about how _most_ compilers work from end to end.
- [**Self-compiling**](<https://en.wikipedia.org/wiki/Self-hosting_(compilers)>): This compiler can compile itself!
- **Zero dependencies**: This compiler is written in pure Lua and has no dependencies.
- **Speed**: Even though speed is not the main priority, the compiler is still pretty fast compared to other Lua compilers written in Lua.
- **100% test coverage**: TLC has a test suite that covers 100% of the code. Want to see it in action? Run `sh tests/test.sh` in your terminal.

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
local tlc = require("the-tiny-lua-compiler")

local code = [[
  for i = 1, 3 do
    print("Hello from TLC! " .. i)
  end
]]

-- Tokenize the code
local tokens = tlc.Tokenizer.new(code):tokenize()

-- Convert tokens into an Abstract Syntax Tree (AST)
local abstractSyntaxTree = tlc.Parser.new(tokens):parse()

-- Generate executable code
local prototype = tlc.CodeGenerator.new(abstractSyntaxTree):generate()
local bytecode = tlc.Compiler.new(prototype):compile()

-- Load and execute the compiled function.
-- Only works in Lua 5.1 (as it generates Lua 5.1 bytecode)
local compiledFunction = loadstring(bytecode)
compiledFunction()
```

### Okay so where do I begin?

Awesome! Head on over to the [the-tiny-lua-compiler.lua](https://github.com/bytexenon/The-Tiny-Lua-Compiler/blob/main/the-tiny-lua-compiler.lua) file.

### Tests

Run the test suite with:

```bash
sh tests/test.sh
```

### Support The Tiny Lua Compiler (TLC)

I don't take donations, but you can support TLC by starring the repository and sharing it with others.
If you find a bug or have a feature request, feel free to open an issue or submit a pull request.

---

[![cc-by-4.0](https://licensebuttons.net/l/by/4.0/80x15.png)](http://creativecommons.org/licenses/by/4.0/)
