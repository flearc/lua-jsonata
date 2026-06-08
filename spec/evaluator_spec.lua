local parser = require("jsonata.parser")
local Evaluator = require("jsonata.evaluator")
local Environment = require("jsonata.environment")
local V = require("jsonata.value")
local A = require("jsonata.adapter")
local functions = require("jsonata.functions")

local function make_env()
  local env = Environment.new()
  for name, fn in pairs(functions.registry) do
    env:bind(name, fn)
  end
  return env
end

local function eval_data(src, lua_data)
  local ast = parser.parse(src)
  local env = make_env()
  return Evaluator.evaluate(ast, A.from_lua(lua_data), env)
end

local function eval(src, input)
  local ast = parser.parse(src)
  local env = make_env()
  return Evaluator.evaluate(ast, input == nil and V.NOTHING or input, env)
end

describe("evaluator: literals and arithmetic", function()
  it("evaluates number/string/boolean/null literals", function()
    assert.are.equal(42, eval("42"))
    assert.are.equal("hi", eval([["hi"]]))
    assert.are.equal(true, eval("true"))
    assert.is_true(V.is_null(eval("null")))
  end)

  it("evaluates arithmetic with precedence", function()
    assert.are.equal(14, eval("2 + 3 * 4"))
    assert.are.equal(-5, eval("-5"))
    assert.are.equal(2, eval("8 % 3"))
  end)

  it("evaluates comparison and boolean", function()
    assert.are.equal(true, eval("3 > 2"))
    assert.are.equal(false, eval("3 = 2"))
    assert.are.equal(true, eval("true and true"))
    assert.are.equal(true, eval("false or true"))
  end)

  it("compares strings and raises structured error on mixed types", function()
    assert.are.equal(true, eval([["a" < "b"]]))
    local errs = require("jsonata.errors")
    local ok, err = pcall(eval, [[3 < "x"]])
    assert.is_false(ok)
    assert.is_true(errs.is_error(err))
  end)

  it("evaluates string concatenation coercing operands", function()
    assert.are.equal("a1", eval([["a" & 1]]))
  end)

  it("evaluates conditional, choosing branch by truthiness", function()
    assert.are.equal("yes", eval([[1 ? "yes" : "no"]]))
    assert.are.equal("no", eval([["" ? "yes" : "no"]]))
  end)

  it("evaluates a block returning the last expression", function()
    assert.are.equal(3, eval("($a := 1; $a + 2)"))
  end)
end)

describe("evaluator: names and paths", function()
  it("selects a field by name", function()
    assert.are.equal("Bob", eval_data("name", { name = "Bob" }))
  end)

  it("navigates nested paths", function()
    assert.are.equal(10, eval_data("a.b.c", { a = { b = { c = 10 } } }))
  end)

  it("returns NOTHING for missing fields", function()
    assert.is_true(V.is_nothing(eval_data("missing", { name = "Bob" })))
  end)

  it("flattens arrays along a path and unwraps multi-results to a sequence", function()
    local data = { Order = { { p = 1 }, { p = 2 }, { p = 3 } } }
    local r = eval_data("Order.p", data)
    assert.is_true(V.is_array(r))
    assert.are.same({ 1, 2, 3 }, { r[1], r[2], r[3] })
  end)

  it("unwraps a single match to a scalar", function()
    local data = { Order = { { p = 7 } } }
    assert.are.equal(7, eval_data("Order.p", data))
  end)

  it("applies a numeric predicate (0-based index)", function()
    assert.are.equal(20, eval_data("items[1]", { items = { 10, 20, 30 } }))
  end)

  it("applies a boolean predicate filter", function()
    local data = { n = { 1, 2, 3, 4 } }
    local r = eval_data("n[$ > 2]", data)
    assert.are.same({ 3, 4 }, { r[1], r[2] })
  end)

  it("applies an array-of-indices predicate", function()
    local r = eval_data("items[[0, 2]]", { items = { 10, 20, 30 } })
    assert.are.same({ 10, 30 }, { r[1], r[2] })
  end)
end)

describe("evaluator: constructors and function calls", function()
  it("builds an array (not flattened)", function()
    local r = eval("[1, 2, 3]")
    assert.is_true(V.is_array(r))
    assert.are.same({ 1, 2, 3 }, { r[1], r[2], r[3] })
  end)

  it("builds an object preserving key order", function()
    local r = eval([[{"b": 1, "a": 2}]])
    assert.is_true(V.is_object(r))
    assert.are.same({ "b", "a" }, V.obj_keys(r))
  end)

  it("calls a builtin function", function()
    assert.are.equal("5", eval("$string(5)"))
    assert.are.equal(3, eval_data("$count(items)", { items = { 1, 2, 3 } }))
  end)

  it("errors when invoking a non-function", function()
    local errs = require("jsonata.errors")
    local ok, err = pcall(eval, "$x()")
    assert.is_false(ok)
    assert.is_true(errs.is_error(err))
  end)
end)

describe("evaluator: lambdas", function()
  it("defines and applies a lambda", function()
    assert.are.equal(6, eval("function($x){ $x + 1 }(5)"))
  end)

  it("lambda bound to a variable", function()
    assert.are.equal(7, eval("($double := function($x){ $x * 2 }; $double(3) + 1)"))
  end)

  it("lambda is a closure capturing its environment", function()
    assert.are.equal(15, eval("($a := 10; function($x){ $x + $a })(5)"))
  end)

  it("missing lambda args bind to nothing", function()
    local V = require("jsonata.value")
    assert.is_true(V.is_nothing(eval("function($x){ $x }()")))
  end)
end)

describe("evaluator: apply operator ~>", function()
  it("applies a function to the LHS", function()
    assert.are.equal("5", eval("5 ~> $string"))
  end)

  it("chains left to right", function()
    assert.are.equal(1, eval("5 ~> $string ~> $length"))
  end)

  it("prepends the LHS as the first arg when RHS is a call", function()
    assert.are.equal("he", eval([["hello" ~> $substring(0, 2)]]))
  end)

  it("applies a lambda via ~>", function()
    assert.are.equal(6, eval("5 ~> function($x){ $x + 1 }"))
  end)
end)
