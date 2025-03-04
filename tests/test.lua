--[[
  The Tiny Lua Compiler Test Suite [TLCTS]
--]]

local tlc = require("the-tiny-lua-compiler")

-- Constants --
local MAX_PATH_LENGTH = 80

-- Used for printing escaped characters in strings
local ESCAPED_CHARS = {
  ["\a"] = "\\a",
  ["\b"] = "\\b",
  ["\f"] = "\\f",
  ["\n"] = "\\n",
  ["\r"] = "\\r",
  ["\t"] = "\\t",
  ["\v"] = "\\v"
}

-- Local functions --
local function escapeString(str)
  return str:gsub(".", function(c)
    return ESCAPED_CHARS[c] or c
  end)
end

-- TEST HARNESS SETUP --
local TLCTest = {}
TLCTest.__index = TLCTest

function TLCTest.new(name)
  local self = setmetatable({}, TLCTest)
  self.ranTests = {}
  self.groups = {}

  return self
end

function TLCTest:describe(name, func)
  table.insert(self.groups, name)
  func()
  table.remove(self.groups)
end

function TLCTest:getTestPath(name)
  local path = table.concat(self.groups, "->")
  path = (path == "" and path) or path .. "->"

  if #path > MAX_PATH_LENGTH then
    path = path:sub(1, MAX_PATH_LENGTH - 5) .. "...->"
  end

  -- Colorize the path
  path = "\27[90m" .. path .. "\27[0m"
  return path .. name
end

function TLCTest:it(name, func)
  local errorTable = nil
  local status, result = xpcall(func, function(err)
    local message = err
    local traceback = debug.traceback("", 2):sub(2)

    errorTable = {
      message   = message,
      traceback = traceback
    }
  end)

  -- Print test result --
  local path = self:getTestPath(name)

  if not errorTable then
    io.write("\27[42m\27[30m PASS \27[0m ")
    table.insert(self.ranTests, { status = "PASS",
      name = name,
      path = path
    })
  else
    io.write("\27[41m\27[30m FAIL \27[0m ")
    table.insert(self.ranTests, { status = "FAIL",
      name  = name,
      path  = path,
      error = errorTable
    })
  end

  print(path)
end

-- TLCTest assertions --
function TLCTest:assertEqual(a, b)
  if a ~= b then
    return error(("Expected %s, got %s"):format(tostring(a), tostring(b)))
  end
end

-- TLCTest summary --
function TLCTest:summary()
  local pass, fail = 0, 0
  local errors = {}

  for _, test in ipairs(self.ranTests) do
    if test.status == "PASS" then
      pass = pass + 1
    else
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
    for _, err in ipairs(errors) do
      print((" \27[1m%s\27[0m"):format(err.path))
      print(("  \27[31m%s\27[0m"):format(err.error.message))
      print(("  \27[90m%s\27[0m"):format(err.error.traceback))
    end
  end

  os.exit((fail == 0 and 0) or 1)
end

-- COMPILER HELPER --
local function compileAndRun(code)
  local tokens = tlc.Tokenizer.new(code):tokenize()
  local ast = tlc.Parser.new(tokens):parse()
  local proto = tlc.CodeGenerator.new(ast):generate()
  local bytecode = tlc.Compiler.new(proto):compile()
  return loadstring(bytecode)()
end

-- TEST SUITE --
suite = TLCTest.new()

suite:describe("Lexical Conventions", function()
  suite:it("String delimiters", function()
    suite:assertEqual(compileAndRun([==[
      return "double" .. 'single' .. [[
        multi-line]] .. [=[nested]=]
    ]==]), "doublesingle\n        multi-linenested")
  end)

  suite:it("String escape sequences", function()
    -- Numeric escapes
    suite:assertEqual(compileAndRun([[
      return "\9\99\101"
    ]]), "\tce")

    -- Control characters
    suite:assertEqual(compileAndRun([[
      return "\a\b\f\n\r\t\v"
    ]]), "\a\b\f\n\r\t\v")
  end)

  suite:it("Number formats", function()
    suite:assertEqual(compileAndRun([[
      return 123 + 0xA2 + 0X1F + 0.5 + .25 + 1e2
    ]]), 123 + 0xA2 + 0X1F + 0.5 + .25 + 1e2)
  end)
end)

suite:describe("Expressions and Operators", function()
  suite:it("Operator precedence", function()
    suite:assertEqual(compileAndRun([[
      return 2 + 3 * 4 ^ 2 / 2
    ]]), 2 + 3 * 4 ^ 2 / 2)
  end)

  suite:it("Relational operators", function()
    suite:assertEqual(compileAndRun([[
      return (3 < 5) and (5 <= 5) and (7 > 3) and
             (7 >= 7) and (5 ~= 3) and (5 == 5)
    ]]), (3 < 5) and (5 <= 5) and (7 > 3) and
         (7 >= 7) and (5 ~= 3) and (5 == 5)
    )
  end)

  suite:it("Logical operators", function()
    suite:assertEqual(compileAndRun([[
      return (true and false) or (true and 1 or 5) or (nil and 3)
    ]]), (true and false) or (true and 1 or 5) or (nil and 3))
  end)
end)

suite:describe("Statements", function()
  suite:it("Chained assignments", function()
    suite:assertEqual(compileAndRun([[
      local a, b, c = 1, 2, 3
      a, b = b, a
      c = a + b
      return c
    ]]), 3)

    suite:assertEqual(compileAndRun([[
      local a, b = {}, {}
      a.x, b.x = 1, 2
      return a.x + b.x
    ]]), 3)

    suite:assertEqual(compileAndRun([[
      local a = {}
      local b = a

      a.x, a = 1, {x = 4}

      return b.x + a.x
    ]]), 5)
  end)

  suite:it("Multiple returns", function()
    local a, b, c = compileAndRun([[
      return 1, 2, 3
    ]])
    suite:assertEqual(a, 1)
    suite:assertEqual(b, 2)
    suite:assertEqual(c, 3)
  end)
end)

suite:describe("Loop Constructs", function()
  suite:it("Numeric for loops", function()
    -- Basic numeric for
    suite:assertEqual(compileAndRun([[
      local sum = 0
      for i = 1, 5 do sum = sum + i end
      return sum
    ]]), 15)

    -- With step value
    suite:assertEqual(compileAndRun([[
      local sum = 0
      for i = 10, 1, -2 do sum = sum + i end
      return sum
    ]]), 30)

    -- Floating point range
    suite:assertEqual(compileAndRun([[
      local sum = 0
      for i = 0.5, 2.5, 0.5 do sum = sum + i end
      return sum
    ]]), 7.5)
  end)

  suite:it("Generic for loops", function()
    -- ipairs style
    suite:assertEqual(compileAndRun([[
      local sum = 0
      for _, v in ipairs({5, 4, 3}) do
        sum = sum + v
      end
      return sum
    ]]), 12)

    -- pairs style
    suite:assertEqual(compileAndRun([[
      local t = {a=1, b=2}
      local sum = 0
      for k, v in pairs(t) do
        sum = sum + v
      end
      return sum
    ]]), 3)

    -- Custom iterator
    suite:assertEqual(compileAndRun([[
      local sum = 0
      for v in function()
        local n = 0
        return function()
          n = n + 1
          return n <= 3 and n*3 or nil
        end
      end() do
        sum = sum + v
      end
      return sum
    ]]), 18)
  end)

  suite:it("Repeat-until loops", function()
    suite:assertEqual(compileAndRun([[
      local i = 5
      repeat i = i - 1 until i <= 0
      return i
    ]]), 0)
  end)

  suite:it("Break statement", function()
    -- Numeric for loop
    suite:assertEqual(compileAndRun([[
      local sum = 0
      for i = 1, 10 do
        sum = sum + i
        if i == 5 then
          break
        end
      end
      return sum
    ]]), 15)

    -- Generic for loop
    suite:assertEqual(compileAndRun([[
      local sum = 0
      for _, v in ipairs({1, 2, 3, 4, 5, 6, 7, 8, 9, 10}) do
        sum = sum + v
        if v == 5 then
          break
        end
      end
      return sum
    ]]), 15)

    -- While loop
    suite:assertEqual(compileAndRun([[
      local sum = 0
      while true do
        sum = sum + 1
        if sum == 5 then
          break
        end
      end
      return sum
    ]]), 5)

    -- Repeat loop
    suite:assertEqual(compileAndRun([[
      local sum = 0
      repeat
        sum = sum + 1
        if sum == 5 then
          break
        end
      until false
      return sum
    ]]), 5)
  end)
end)

suite:describe("Variable Scoping", function()
  suite:it("Basic lexical scoping", function()
    suite:assertEqual(compileAndRun([[
      local x = 10
      do
        local x = 20
        x = x + 5
      end
      return x
    ]]), 10)
  end)

  suite:it("Function upvalue capture", function()
    suite:assertEqual(compileAndRun([[
      local function outer()
        local x = 5
        return function() return x end
      end
      local inner = outer()
      return inner()
    ]]), 5)
  end)

  suite:it("Function upvalue modification", function()
    suite:assertEqual(compileAndRun([[
      local function outer()
        local x = 5
        return function() x = x + 1; return x end
      end
      local inner = outer()
      inner()
      return inner()
    ]]), 7)
  end)

  suite:it("Nested function scoping", function()
    suite:assertEqual(compileAndRun([[
      local function outer()
        local x = 10
        local function inner()
          return x + 5
        end
        return inner()
      end
      return outer()
    ]]), 15)
  end)

  suite:it("Multi-level closures", function()
    suite:assertEqual(compileAndRun([[
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
    ]]), 3)
  end)

  suite:it("Repeated local declarations", function()
    suite:assertEqual(compileAndRun([[
      local x = 1
      local x = 2
      do
        local x = 3
      end
      return x
    ]]), 2)
  end)

  suite:it("Deeply nested scopes", function()
    suite:assertEqual(compileAndRun([[
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
    ]]), 6)
  end)
end)

suite:describe("Function Definitions", function()
  suite:it("Function syntax variants", function()
    -- Empty parameter list
    suite:assertEqual(compileAndRun([[
      local f = function()
        return 42
      end
      return f()
    ]]), 42)

    -- Varargs
    suite:assertEqual(compileAndRun([[
      local sum = function(...)
        local s = 0
        for _, n in ipairs{...} do
          s = s + n
        end
        return s
      end

      return sum(1, 2, 3)
    ]]), 6)
  end)
end)

suite:describe("Table Constructors", function()
  suite:it("Array-style tables", function()
    suite:assertEqual(compileAndRun([[
      return {1, 2, 3, [4] = 4}[4]
    ]]), 4)
  end)

  suite:it("Hash-style tables", function()
    suite:assertEqual(compileAndRun([[
      return {a = 1, ["b"] = 2, [3] = 3}["b"]
    ]]), 2)
  end)

  suite:it("Nested tables", function()
    suite:assertEqual(compileAndRun([[
      return { {1}, {a = {b = 2}} }[2].a.b
    ]]), 2)
  end)
end)

suite:describe("Error Handling", function()
  suite:it("Syntax error detection", function()
    local status = pcall(compileAndRun, "return 1 + + 2")
    suite:assertEqual(status, false)
  end)
end)

suite:describe("Comments", function()
  suite:it("Single-line comments", function()
    suite:assertEqual(compileAndRun([[
      return 42 -- This is a comment
    ]]), 42)
  end)

  suite:it("Multi-line comments", function()
    suite:assertEqual(compileAndRun([==[
      --[[
        This is a multi-line comment
        It can span multiple lines
        FALSE ENDING] ]=]
      ]]
      return 42
    ]==]), 42)

    suite:assertEqual(compileAndRun([===[
      --[=[
        This is a nested multi-line comment
        It can span multiple lines
        FALSE ENDING]] ]= ]==]
      ]=]
      return 42
    ]===]), 42)
  end)
end)

suite:describe("Miscellaneous", function()
  suite:it("Parenthesis-less function calls", function()
    suite:assertEqual(compileAndRun([[
      local function f(x) return x end
      local value1 = #f"hello"
      local value2 = f{b = 10}.b
      return value1 + value2
    ]]), 15)
  end)
end)

suite:describe("Complex General Tests", function()
  suite:it("Factorial function", function()
    suite:assertEqual(compileAndRun([[
      local function factorial(n)
        if n == 0 then
          return 1
        else
          return n * factorial(n - 1)
        end
      end

      return factorial(5)
    ]]), 120)
  end)

  suite:it("Fibonacci sequence", function()
    suite:assertEqual(compileAndRun([[
      local function fib(n)
        if n <= 1 then
          return n
        else
          return fib(n - 1) + fib(n - 2)
        end
      end

      return fib(10)
    ]]), 55)
  end)

  suite:it("Quicksort algorithm", function()
    suite:assertEqual(compileAndRun([[
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

      return table.concat(
        quicksort({5, 3, 8, 2, 9, 1, 6, 0, 7, 4}),
        ", "
      )
    ]]), "0, 1, 2, 3, 4, 5, 6, 7, 8, 9")
  end)

  suite:it("Game of Life simulation", function()
    suite:assertEqual(compileAndRun([=[
      local function T2D(w, h)
        local t = {}
        for y = 1, h do
          t[y] = {}
          for x = 1, w do t[y][x] = 0 end
        end
        return t
      end

      local Life = {
        new = function(self, w, h)
          return setmetatable({
              w = w,
              h = h,
              gen = 1,
              curr = T2D(w, h),
              next = T2D(w, h)
            }, { __index = self })
        end,
        set = function(self, coords)
          for i = 1, #coords, 2 do
            self.curr[coords[i + 1]][coords[i]] = 1
          end
        end,
        step = function(self)
          local curr, next = self.curr, self.next
          local ym1, y, yp1 = self.h - 1, self.h, 1
          for i = 1, self.h do
            local xm1, x, xp1 = self.w - 1, self.w, 1
            for j = 1, self.w do
              local sum = curr[ym1][xm1] + curr[ym1][x] + curr[ym1][xp1] +
                  curr[y][xm1] + curr[y][xp1] +
                  curr[yp1][xm1] + curr[yp1][x] + curr[yp1][xp1]
              next[y][x] = ((sum == 2) and curr[y][x]) or ((sum == 3) and 1) or 0
              xm1, x, xp1 = x, xp1, xp1 + 1
            end
            ym1, y, yp1 = y, yp1, yp1 + 1
          end
          self.curr, self.next, self.gen = self.next, self.curr, self.gen + 1
        end,
        evolve = function(self, times)
          times = times or 1
          for i = 1, times do self:step() end
        end,
        render = function(self)
          local output = {}
          for y = 1, self.h do
            for x = 1, self.w do
              table.insert(output, self.curr[y][x] == 0 and "□ " or "■ ")
            end
            table.insert(output, "\n")
          end
          return table.concat(output)
        end
      }

      local life = Life:new(5, 5)
      life:set({ 2, 1, 3, 2, 1, 3, 2, 3, 3, 3 })
      life:evolve(3)
      return life:render()
    ]=]), "□ □ □ □ □ \n□ ■ □ □ □ \n□ □ ■ ■ □ \n□ ■ ■ □ □ \n□ □ □ □ □ \n")
  end)

  suite:it("Self-compilation", function()
    -- Might take a while to run

    local testCode = [[
      local code = io.open("the-tiny-lua-compiler.lua"):read("*a")
      local tlc  = compileAndRun(code)

      local code = "return 2 * 10 + (function() return 2 * 5 end)()"

      local tokens   = tlc.Tokenizer.new(code):tokenize()
      local ast      = tlc.Parser.new(tokens):parse()
      local proto    = tlc.CodeGenerator.new(ast):generate()
      local bytecode = tlc.Compiler.new(proto):compile()
      local result   = loadstring(bytecode)()

      return result
    ]]

    _G.compileAndRun = compileAndRun
    suite:assertEqual(compileAndRun(testCode), 30)
    _G.compileAndRun = nil
  end)
end)

return suite:summary()