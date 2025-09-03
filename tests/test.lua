local tlc = require("the-tiny-lua-compiler")

--[[
  ============================================================================
                            (•_•) GLOBAL CONSTANTS
                          The Rulebook for the Arena
  ============================================================================
--]]

-- Safety Limit for Infinite Loop Detection.
-- We use Lua's debug hook (`debug.sethook`) to count executed instructions
-- during each test run. If a test exceeds this limit, we assume it's stuck
-- in an infinite loop and terminate it with an error.
--
-- 15 million instructions is a high threshold, unlikely to be hit by correct,
-- non-trivial code within a reasonable time (~4 seconds processing time),
-- but low enough to catch runaway loops.
local INFINITE_LOOP_LIMIT = 15000000

-- A lookup table to convert non-printable escape characters back into their
-- readable '\\' + character form for clear error messages.
local ESCAPED_CHARACTER_CONVERSIONS = {
  ["\a"]  = "a",  -- Bell (alert sound)
  ["\b"]  = "b",  -- Backspace
  ["\f"]  = "f",  -- Form feed (printer page eject)
  ["\n"]  = "n",  -- New line
  ["\r"]  = "r",  -- Carriage return
  ["\t"]  = "t",  -- Horizontal tab
  ["\v"]  = "v",  -- Vertical tab
}

--[[
  ============================================================================
                                 (•_•)⊃━☆ﾟ.*･｡ﾟ
                                UTILITY BELT HELPERS
  ============================================================================
--]]

-- Cleans up a string for printing by replacing invisible control characters
-- (like newline, tab) with their visible escaped representation (e.g., "\n", "\t").
-- This ensures that diffs in test output are easy to read.
local function sanitizeString(str)
  return (str:gsub("[\a\b\f\n\r\t\v]", function(escapeChar)
    return "\\".. ESCAPED_CHARACTER_CONVERSIONS[escapeChar]
  end))
end

local function shallowCopy(original)
  if type(original) ~= "table" then
    return original
  end

  local copy = {}
  for i, v in pairs(original) do
    copy[i] = v
  end

  return copy
end

local function deepcompare(table1, table2, seen)
  seen = seen or {}
  if table1 == table2 then return true end
  if type(table1) ~= "table" or type(table2) ~= "table" then return false end
  if seen[table1] or seen[table2] then
    return seen[table1] == table2 or seen[table2] == table1
  end

  seen[table1] = table2
  seen[table2] = table1

  for i, v1 in pairs(table1) do
    local v2 = table2[i]
    if v2 == nil or not deepcompare(v1, v2, seen) then
      return false
    end
  end
  for i, _ in pairs(table2) do
    if table1[i] == nil then
      return false
    end
  end

  return true
end

local function tableTostring(tbl)
  local parts = {}
  for i, v in pairs(tbl) do
    table.insert(parts, tostring(i).." = "..tostring(v))
  end

  return "{" .. table.concat(parts, ", ") .. "}"
end

-- TEST HARNESS SETUP --
local TLCTest = {}
TLCTest.__index = TLCTest

function TLCTest.new()
  local self = setmetatable({}, TLCTest)
  self.ranTests = {}
  self.groups   = {}

  return self
end

function TLCTest:_getTestPath(name)
  local path = table.concat(self.groups, "->")
  path = (path == "" and path) or path .. "->"

  -- Colorize the path
  path = "\27[90m" .. path .. "\27[0m"
  return path .. name
end

function TLCTest:describe(name, func)
  table.insert(self.groups, name)
  func()
  table.remove(self.groups)
end

function TLCTest:it(name, func)
  local errorTable = nil
  local failed     = false

  do -- Hook prep + error handling
    local function unhook() debug.sethook() end
    local function terminateInfiniteLoop()
      unhook()
      return error("TLCTest: Infinite loop detected after " .. INFINITE_LOOP_LIMIT .. " instructions")
    end

    debug.sethook(terminateInfiniteLoop, "", INFINITE_LOOP_LIMIT)
    xpcall(func, function(err)
      local message = err
      local traceback = debug.traceback("", 2):sub(2)

      failed = true
      errorTable = {
        message   = message,
        traceback = traceback
      }
    end)
    unhook()
  end

  -- Print test result --
  local path = self:_getTestPath(name)

  if failed then
    -- Something went wrong, test failed.
    io.write("\27[41m\27[30m FAIL \27[0m ")
    table.insert(self.ranTests, { status = "FAIL",
      name  = name,
      path  = path,
      error = errorTable
    })
  elseif not failed then
    -- No error occurred, test passed.
    io.write("\27[42m\27[30m PASS \27[0m ")
    table.insert(self.ranTests, { status = "PASS",
      name = name,
      path = path
    })
  end

  print(path)
end

function TLCTest:assertEqual(b, a, message)
  if a ~= b then
    local msg = ("Expected %s, got %s"):format(tostring(a), tostring(b))
    if message then msg = message .. " - " .. msg end
    return error(msg, 0)
  end
end

function TLCTest:assertDeepEqual(expected, actual, message)
  if deepcompare(expected, actual) then return true end

  local actualString = type(actual) == "table" and tableTostring(actual) or tostring(actual)
  local expectedString = type(expected) == "table" and tableTostring(expected) or tostring(expected)

  error("Expected returns do not match actual returns.\n" ..
        "    Expected: \t '" .. sanitizeString(expectedString) .. "'\n" ..
        "    Actual: \t '"   .. sanitizeString(actualString)   .. "'",
        0)

  if message then
    message = message .. " - " .. message
  end

  return error(message, 0)
end

function TLCTest:assertTrue(condition, message)
  if not condition then
    local msg = "Expected condition to be true, but got false"
    if message then msg = message .. " - " .. msg end
    return error(msg, 0)
  end
end

function TLCTest:assertFalse(condition, message)
  if condition then
    local msg = "Expected condition to be false, but got true"
    if message then msg = message .. " - " .. msg end
    return error(msg, 0)
  end
end

-- COMPILER HELPERS --

--// Sandboxed Execution //--

-- Runs a chunk of code in an isolated environment to prevent side effects.
-- NOTE: It does not prevent global table environment pollution, for example,
--       `math.var = 42` will still create a global variable `math.var`.
function TLCTest:runSandboxed(code)
  local func, err = loadstring(code)
  if not func then
    return false, tostring(err) -- Return error if code fails to load.
  end

  -- Create a new, clean environment for the function by making a shallow copy
  -- of the global environment. This gives it access to standard functions
  -- like `ipairs` and `tostring` but ensures any *new* globals it creates
  -- will not pollute the main test suite's environment.
  local newEnvironment = shallowCopy(_G)
  setfenv(func, newEnvironment)

  -- Execute the function in its new, sandboxed environment.
  return func()
end

--// The Full TLC Pipeline //--

-- Takes a string of Lua code, runs it through the entire Tiny Lua Compiler
-- toolchain, and then executes the resulting bytecode in a sandbox.
function TLCTest:compileAndRun(code)
  local tokens    = tlc.Tokenizer.new(code):tokenize()
  local ast       = tlc.Parser.new(tokens):parse()
  local proto     = tlc.CodeGenerator.new(ast):generate()
  local bytecode  = tlc.Compiler.new(proto):compile()

  return self:runSandboxed(bytecode)
end

-- This is the most important function in the suite. It orchestrates the "duel"
-- between the standard Lua interpreter and our own compiler.
function TLCTest:compileAndRunChecked(code)
  local expectedReturns = { xpcall(
    function()    return self:runSandboxed(code) end,
    function(err) return err .. debug.traceback("", 2) end)
  }

  local actualReturns = { xpcall(
    function()    return self:compileAndRun(code) end,
    function(err) return err .. debug.traceback("", 2) end)
  }

  -- The first element of it is the success status (true/false).
  local expectedResult, actualResult = table.remove(expectedReturns, 1),
                                       table.remove(actualReturns, 1)

  -- Check if one run failed while the other succeeded.
  if not expectedResult or not actualResult then
    local errMsg = "Execution success status mismatch: "
    if not expectedResult then
      errMsg = errMsg .. "Standard Lua failed with: " .. tostring(expectedReturns[1])
    else
      errMsg = errMsg .. "TLC-compiled code failed with: " .. tostring(actualReturns[1])
    end
    error(errMsg, 0)
  end

  -- The Verdict: If both succeeded (or both failed), we do a deep comparison
  -- of their return values (or their error messages) to ensure they are identical.
  return self:assertDeepEqual(expectedReturns, actualReturns)
end


-- TLCTest summary --
function TLCTest:summary()
  local pass, fail = 0, 0
  local errors = {}

  for _, test in ipairs(self.ranTests) do
    if test.status == "PASS" then
      pass = pass + 1
    elseif test.status == "FAIL" then
      fail = fail + 1
      table.insert(errors, test)
    end
  end

  print("\n\27[1mTest Results:\27[0m")
  print(("Passed: \27[32m%d\27[0m"):format(pass))
  print(("Failed: \27[31m%d\27[0m"):format(fail))
  print(("Total:  %d"):format(pass + fail))

  if fail > 0 then
    print("\n\27[1mErrors:\27[0m")
    for i, err in ipairs(errors) do
      print(("\n%d) \27[1m%s\27[0m"):format(i, err.path))
      print(("   \27[31m%s\27[0m"):format(err.error.message))
      print(("   \27[90m%s\27[0m"):format(err.error.traceback))
    end
  end

  os.exit((fail == 0 and 0) or 1)
end

-- TEST SUITE --
local suite = TLCTest.new()

suite:describe("Lexical Conventions", function()
  suite:it("String delimiters", function()
    suite:compileAndRunChecked([==[
      return "double" .. 'single' .. [[
        multi-line]] .. [=[nested]=]
    ]==])
  end)

  suite:it("String escape sequences", function()
    -- Numeric escapes
    suite:compileAndRunChecked([[
      return "\9\99\101"
    ]])

    -- Escape characters
    suite:compileAndRunChecked([[
      return "\a\b\f\n\r\t\v"
    ]])
  end)

  suite:it("Number formats", function()
    suite:compileAndRunChecked([[
      return 123 + 0xA2 + 0X1F + 0.5 + .25 + 1e2
    ]])
  end)
end)

suite:describe("Expressions and Operators", function()
  suite:it("Operator precedence", function()
    suite:compileAndRunChecked([[return 2 + 3 * 4 ^ 2 / 2 - 1]])
    suite:compileAndRunChecked([[return "a" .. "b" == "ab" and not (2 > 3 or 5 < 4)]])
  end)

  suite:it("Relational operators", function()
    suite:compileAndRunChecked([[return (3 < 5) and (5 <= 5) and (7 > 3) and (7 >= 7) and (5 ~= 3) and (5 == 5)]])
    suite:compileAndRunChecked([[return nil == nil]])
    suite:compileAndRunChecked([[return "a" > "b"]])
  end)

  suite:it("Logical operators with short-circuiting", function()
    suite:compileAndRunChecked([[return (true and false) or (true and 1 or 5) or (nil and 3)]])
    suite:compileAndRunChecked([[local x = 5; local y = (x > 10 and error("fail")) or 42; return y]])
  end)

  suite:it("Unary operators", function()
    suite:compileAndRunChecked([[return -10 + -(-5)]])
    suite:compileAndRunChecked([[return not (not true)]])
    suite:compileAndRunChecked([[return not nil]])
    suite:compileAndRunChecked([[local t = {1,2,3}; return #t .. #"abc"]])
  end)
end)

suite:describe("Statements", function()
  suite:it("Chained assignments", function()
    suite:compileAndRunChecked([[local a, b, c = 1, 2, 3; a, b = b, a; c = a + b; return c]])
    suite:compileAndRunChecked([[local a, b = {}, {}; a.x, b.x = 1, 2; return a.x + b.x]])
    suite:compileAndRunChecked([[local a = {}; local b = a; a.x, a = 1, {x = 4}; return b.x + a.x]])
  end)

  suite:it("Multiple returns", function()
    suite:compileAndRunChecked([[return 1, 2, 3]])
  end)

  suite:it("Single return from multi-return function", function()
    suite:compileAndRunChecked([[local function f() return 1, 2, 3 end; local a, b, c = (f()); return a, b, c]])
  end)
end)

suite:describe("Global Variables", function()
  suite:it("Can assign to and read from a global", function()
    suite:compileAndRunChecked([[x = 10; y = 20; return x + y]])
  end)

  suite:it("Can handle undeclared globals which are nil", function()
    suite:compileAndRunChecked([[return my_undeclared_global == nil]])
  end)
end)

suite:describe("Control Flow", function()
  suite:it("If-elseif-else statements", function()
    suite:compileAndRunChecked([[local x = 10; if x > 20 then return 1 elseif x > 5 then return 2 else return 3 end]])
    suite:compileAndRunChecked([[local x = 30; if x > 20 then return 1 elseif x > 5 then return 2 else return 3 end]])
    suite:compileAndRunChecked([[local x = 2; if x > 20 then return 1 elseif x > 5 then return 2 else return 3 end]])
    suite:compileAndRunChecked([[if false then return 1 end]])
  end)

  suite:it("While loops", function()
    suite:compileAndRunChecked([[local i = 5; local sum = 0; while i > 0 do sum = sum + i; i = i - 1 end; return sum]])
  end)

  suite:it("Return statement from inside a loop", function()
    suite:compileAndRunChecked([[for i = 1, 10 do if i == 5 then return i*2 end end]])
  end)
end)

suite:describe("Loop Constructs", function()
  suite:it("Numeric for loops", function()
    -- Basic numeric for
    suite:compileAndRunChecked([[
      local sum = 0
      for i = 1, 5 do sum = sum + i end
      return sum
    ]])

    -- With step value
    suite:compileAndRunChecked([[
      local sum = 0
      for i = 10, 1, -2 do sum = sum + i end
      return sum
    ]])

    -- Floating point range
    suite:compileAndRunChecked([[
      local sum = 0
      for i = 0.5, 2.5, 0.5 do sum = sum + i end
      return sum
    ]])
  end)

  suite:it("Generic for loops", function()
    -- ipairs style
    suite:compileAndRunChecked([[
      local sum = 0
      for _, v in ipairs({5, 4, 3}) do
        sum = sum + v
      end
      return sum
    ]])

    -- pairs style
    suite:compileAndRunChecked([[
      local t = {a=1, b=2}
      local sum = 0
      for k, v in pairs(t) do
        sum = sum + v
      end
      return sum
    ]])

    -- Custom iterator
    suite:compileAndRunChecked([[
      local sum = 0
      for v in (function()
          local n = 0
          return function()
            n = n + 1
            return n <= 3 and n*3 or nil
          end
        end)() do
        sum = sum + v
      end
      return sum
    ]])
  end)

  suite:it("Repeat-until loops", function()
    suite:compileAndRunChecked([[
      local i = 5
      repeat i = i - 1 until i <= 0
      return i
    ]])
  end)

  suite:it("Break statement", function()
    -- Numeric for loop
    suite:compileAndRunChecked([[
      local sum = 0
      for i = 1, 10 do
        sum = sum + i
        if i == 5 then
          break
        end
      end
      return sum
    ]])

    -- Generic for loop
    suite:compileAndRunChecked([[
      local sum = 0
      for _, v in ipairs({1, 2, 3, 4, 5, 6, 7, 8, 9, 10}) do
        sum = sum + v
        if v == 5 then
          break
        end
      end
      return sum
    ]])

    -- While loop
    suite:compileAndRunChecked([[
      local sum = 0
      while true do
        sum = sum + 1
        if sum == 5 then
          break
        end
      end
      return sum
    ]])

    -- Repeat loop
    suite:compileAndRunChecked([[
      local sum = 0
      repeat
        sum = sum + 1
        if sum == 5 then
          break
        end
      until false
      return sum
    ]])
  end)
end)

suite:describe("Variable Scoping", function()
  suite:it("Basic lexical scoping", function()
    suite:compileAndRunChecked([[
      local x = 10
      do
        local x = 20
        x = x + 5
      end
      return x
    ]])
  end)

  suite:it("Function upvalue capture", function()
    suite:compileAndRunChecked([[
      local function outer()
        local x = 5
        return function() return x end
      end
      local inner = outer()
      return inner()
    ]])
  end)

  suite:it("Function upvalue modification", function()
    suite:compileAndRunChecked([[
      local function outer()
        local x = 5
        return function() x = x + 1; return x end
      end
      local inner = outer()
      inner()
      return inner()
    ]])
  end)

  suite:it("Nested function scoping", function()
    suite:compileAndRunChecked([[
      local function outer()
        local x = 10
        local function inner()
          return x + 5
        end
        return inner()
      end
      return outer()
    ]])
  end)

  suite:it("Multi-level closures", function()
    suite:compileAndRunChecked([[
      local function level1()
        local a = 1
        return function()
          local b = 2
          return function()
            return a + b
          end
        end
      end
      return level1()()()
    ]])
  end)

  suite:it("Repeated local declarations", function()
    suite:compileAndRunChecked([[
      local x = 1
      local x = 2
      do
        local x = 3
      end
      return x
    ]])
  end)

  suite:it("Deeply nested scopes", function()
    suite:compileAndRunChecked([[
      local a = 1
      do
        local b = 2
        do
          local c = 3
          do
            return a + b + c
          end
        end
      end
    ]])
  end)
end)

suite:describe("Function Definitions", function()
  suite:it("Function syntax variants", function()
    -- Empty parameter list
    suite:compileAndRunChecked([[
      local f = function()
        return 42
      end
      return f()
    ]])

    -- Varargs
    suite:compileAndRunChecked([[
      local sum = function(...)
        local s = 0
        for _, n in ipairs{...} do
          s = s + n
        end
        return s
      end

      return sum(1, 2, 3)
    ]])

  end)
end)

suite:describe("Table Constructors", function()
  suite:it("Array-style tables", function()
    suite:compileAndRunChecked([[
      return ({1, 2, 3, [4] = 4})[4]
    ]])
  end)

  suite:it("Hash-style tables", function()
    suite:compileAndRunChecked([[
      return ({a = 1, ["b"] = 2, [3] = 3})["b"]
    ]])
  end)

  suite:it("Nested tables", function()
    suite:compileAndRunChecked([[
      return ({ {1}, {a = {b = 2}} })[2].a.b
    ]])
  end)
end)

suite:describe("Error Handling", function()
  suite:it("Syntax error detection", function()
    local status = pcall(suite.compileAndRun, suite, "return 1 + + 2")
    suite:assertEqual(status, false)
  end)
end)

suite:describe("Comments", function()
  suite:it("Single-line comments", function()
    suite:compileAndRunChecked([[
      return 42 -- This is a comment
    ]])
  end)

  suite:it("Multi-line comments", function()
    suite:compileAndRunChecked([==[
      --[[
        This is a multi-line comment
        It can span multiple lines
        FALSE ENDING] ]=]
      ]]
      return 42
    ]==])

    suite:compileAndRunChecked([===[
      --[=[
        This is a nested multi-line comment
        It can span multiple lines
        FALSE ENDING]] ]= ]==]
      ]=]

      return 42
    ]===])
  end)
end)

suite:describe("Miscellaneous", function()
  suite:it("Parenthesis-less function calls", function()
    suite:compileAndRunChecked([[
      local function f(x) return x end

      local value1 = #f"hello"
      local value2 = f{b = 10}.b
      return value1 + value2
    ]])
  end)
end)

suite:describe("Complex General Tests", function()
  suite:it("Factorial function", function()
    suite:compileAndRunChecked([[
      local function factorial(n)
        if n == 0 then
          return 1
        end

        return n * factorial(n - 1)
      end

      return factorial(10)
    ]])
  end)

  suite:it("Fibonacci sequence", function()
    suite:compileAndRunChecked([[
      local function fib(n)
        if n <= 1 then
          return n
        end

        return fib(n - 1) + fib(n - 2)
      end

      return fib(10)
    ]])
  end)

  suite:it("Quicksort algorithm", function()
    suite:compileAndRunChecked([[
      local function quicksort(t)
        if #t < 2 then return t end

        local pivot = t[1]
        local a, b, c = {}, {}, {}
        for _,v in ipairs(t) do
          if     v < pivot then a[#a + 1] = v
          elseif v > pivot then c[#c + 1] = v
          else                  b[#b + 1] = v
          end
        end

        a = quicksort(a)
        c = quicksort(c)
        for _, v in ipairs(b) do a[#a + 1] = v end
        for _, v in ipairs(c) do a[#a + 1] = v end
        return a
      end

      return unpack(quicksort({5, 3, 8, 2, 9, 1, 6, 0, 7, 4}))
    ]])
  end)

  suite:it("Self-compilation", function()
    -- NOTE: This test might take a while to run.

    local testCode = [[
      -- Test comment
      local code = io.open("the-tiny-lua-compiler.lua"):read("*a")
      local tlc  = suite:compileAndRun(code)

      -- This code should be just enough to test the compiler.
      -- Adding more complex logic would be redundant, as the most
      -- difficult part is (correctly) compiling the compiler itself.
      local code = "return 2 * 10 + (function() return 2 * 5 end)()"

      local tokens   = tlc.Tokenizer.new(code):tokenize()
      local ast      = tlc.Parser.new(tokens):parse()
      local proto    = tlc.CodeGenerator.new(ast):generate()
      local bytecode = tlc.Compiler.new(proto):compile()
      local func     = loadstring(bytecode)
      local result   = func()

      return result
    ]]

    -- Temporarily add the suite to the global environment.
    _G.suite = suite
    suite:assertEqual(suite:compileAndRun(testCode), 30)
    _G.suite = nil

  end)
end)

return suite:summary()