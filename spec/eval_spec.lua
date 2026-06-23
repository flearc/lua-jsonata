local errors = require("jsonata.errors")

describe("M5c: D3120/D3121 error templates", function()
  it("defines D3120 and D3121 with interpolatable {{value}}", function()
    local ok1, e1 = pcall(errors.raise, "D3120", { value = "boom" })
    assert.is_false(ok1)
    assert.are.equal("D3120", e1.code)
    assert.is_not_nil(e1.message:find("eval", 1, true))
    assert.is_nil(e1.message:find("{{", 1, true)) -- {{value}} interpolated

    local ok2, e2 = pcall(errors.raise, "D3121", { value = "boom" })
    assert.is_false(ok2)
    assert.are.equal("D3121", e2.code)
    assert.is_nil(e2.message:find("{{", 1, true))
  end)
end)

describe("M5c: M.apply wants_env hook", function()
  local E = require("jsonata.evaluator")
  local Environment = require("jsonata.environment")

  it("passes (env, input, ...args) to a wants_env builtin", function()
    local seen = {}
    local proc = {
      _jsonata_function = true,
      wants_env = true,
      impl = function(env, input, a)
        seen.env, seen.input, seen.a = env, input, a
        return a
      end,
    }
    local env = Environment.new()
    local r = E.apply(proc, { 42 }, "INPUT", env)
    assert.are.equal(42, r)
    assert.are.equal("INPUT", seen.input)
    assert.are.equal(env, seen.env)
    assert.are.equal(42, seen.a)
  end)

  it("a normal builtin gets only its args (no env/input prefix)", function()
    local seen = {}
    local proc = {
      _jsonata_function = true,
      impl = function(a, b)
        seen.a, seen.b = a, b
        return a
      end,
    }
    E.apply(proc, { 7, 8 }, "INPUT", Environment.new())
    assert.are.equal(7, seen.a)
    assert.are.equal(8, seen.b) -- NOT shifted by an env/input prefix
  end)
end)
