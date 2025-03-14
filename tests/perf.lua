--[[
  The Tiny Lua Compiler Performance Test Suite
--]]

--* Imports *--
local tlc = require("the-tiny-lua-compiler")

-- Constants --
local ITERATIONS = 100
local TLC_CODE = io.open("the-tiny-lua-compiler.lua"):read("*a")

--* Functions *--
local function compile(code)
  local tokens   = tlc.Tokenizer.new(code):tokenize()
  local ast      = tlc.Parser.new(tokens):parse()
  local proto    = tlc.CodeGenerator.new(ast):generate()
  local bytecode = tlc.Compiler.new(proto):compile()
  return bytecode
end

local function benchmark()
  local start = os.clock()
  for _ = 1, ITERATIONS do
    compile(TLC_CODE)
  end
  local elapsed = os.clock() - start

  print(string.format("Compiled %d times in %.2f seconds", ITERATIONS, elapsed))
end

--* Main *--
benchmark()