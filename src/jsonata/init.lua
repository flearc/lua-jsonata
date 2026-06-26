local parser = require("jsonata.parser")
local Evaluator = require("jsonata.evaluator")
local Environment = require("jsonata.environment")
local functions = require("jsonata.functions")
local adapter = require("jsonata.adapter")

local M = {}
M._VERSION = "0.0.1-m1"

local Expression = {}
Expression.__index = Expression

-- Build the static frame pre-populated with builtins.
local function make_static_frame()
  local env = Environment.new()
  for name, def in pairs(functions.registry) do
    env:bind(name, def)
  end
  return env
end

local function wrap_lua_function(fn)
  return {
    _jsonata_function = true,
    arity = nil, -- M1: no arity enforcement on user functions
    impl = function(...)
      local n = select("#", ...)
      local converted = {}
      for i = 1, n do
        converted[i] = adapter.from_lua((select(i, ...)))
      end
      -- User function sees plain Lua values, returns a plain Lua value.
      local lua_args = {}
      for i = 1, n do
        lua_args[i] = adapter.to_lua(converted[i])
      end
      local result = fn((table.unpack or unpack)(lua_args, 1, n))
      return adapter.from_lua(result)
    end,
  }
end

function M.compile(source)
  local ast = parser.parse(source)
  return setmetatable({ ast = ast, assigned = {} }, Expression)
end

function Expression:assign(name, value)
  self.assigned[name] = adapter.from_lua(value)
  return self
end

function Expression:registerFunction(name, fn)
  self.assigned[name] = wrap_lua_function(fn)
  return self
end

function Expression:evaluate(input, bindings)
  local env = make_static_frame():create_frame()
  env.timestamp = os.time() * 1000 -- fixed per evaluation: $now/$millis/$toMillis now-fill share it
  for name, value in pairs(self.assigned) do
    env:bind(name, value)
  end
  if bindings then
    for name, value in pairs(bindings) do
      env:bind(name, adapter.from_lua(value))
    end
  end
  if self._explain_hook then
    env:bind("__explain_hook", self._explain_hook)
  end
  local internal_input = adapter.from_lua(input)
  env:bind("$", internal_input)
  local result = Evaluator.evaluate(self.ast, internal_input, env)
  return adapter.to_lua(result)
end

function M.explain(source, input, stage)
  return require("jsonata.explain").explain(source, input, stage)
end

return M
