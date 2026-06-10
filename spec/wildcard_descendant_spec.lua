local jsonata = require("jsonata")

local function run(src, input)
  return jsonata.compile(src):evaluate(input)
end

-- Dataset with a nested object inside an array field, so descendant recursion
-- and array-value flattening are both exercised. `blah` is a Lua array, so the
-- order of descendant `fud` values (hello, world) is deterministic.
local DATA = {
  foo = {
    bar = 42,
    blah = {
      { baz = { fud = "hello" } },
      { baz = { fud = "world" } },
      { bazz = "gotcha" },
    },
    ["blah.baz"] = "here",
  },
  bar = 98,
}

describe("wildcard *", function()
  it("returns the elements of an array input (bare *)", function()
    assert.are.same({ 10, 20, 30 }, run("*", { 10, 20, 30 }))
  end)

  it("recursively flattens nested array values", function()
    assert.are.same({ 1, 2, 3, 4 }, run("*", { { 1, 2 }, { 3, 4 } }))
  end)

  it("returns all the values of an object (order-independent)", function()
    assert.are.equal(6, run("$sum(*)", { a = 1, b = 2, c = 3 }))
    assert.are.equal(3, run("$count(*)", { a = 1, b = 2, c = 3 }))
  end)

  it("flattens an array-typed field into the result", function()
    -- foo has 4 keys; blah is a 3-element array that flattens in -> 5 values
    assert.are.equal(5, run("$count(foo.*)", DATA))
  end)

  it("composes with a predicate", function()
    assert.are.equal(5, run("$sum(*[$ > 1])", { a = 1, b = 2, c = 3 }))
  end)

  it("unwraps a singleton result to a scalar", function()
    assert.are.equal(42, run("*", { a = 42 }))
  end)

  it("as the first path step over array input runs once (spreads elements)", function()
    -- must apply to the whole array (its elements), not descend per-element
    assert.are.same({ 2, 4 }, run("*.b", { { a = 1, b = 2 }, { a = 3, b = 4 } }))
    assert.are.same({ 2, 3 }, run("*[$ > 1]", { 1, 2, 3 }))
  end)

  it("yields nothing for a non-object/non-array input", function()
    assert.is_nil(run("foo.bar.*", DATA)) -- bar is 42, a scalar
    assert.is_nil(run("$sum.*", {})) -- a function value
  end)

  it("does not break infix multiply", function()
    assert.are.equal(42, run("a * b", { a = 6, b = 7 }))
    assert.are.equal(20, run("x * 4", { x = 5 }))
  end)

  it("does not break named selectors", function()
    assert.are.equal(42, run("foo.bar", DATA))
  end)
end)

describe("descendant **", function()
  it("collects descendant values at any depth", function()
    assert.are.same({ "hello", "world" }, run("foo.**.fud", DATA))
    assert.are.same({ "hello", "world" }, run("**.fud", DATA))
    assert.are.same({ "hello", "world" }, run("foo.*.**.fud", DATA))
  end)

  it("indexes into the descendant result", function()
    assert.are.equal("hello", run("(**.fud)[0]", DATA))
  end)

  it("unwraps a single descendant to a scalar", function()
    assert.are.equal(5, run("a.**", { a = 5 }))
  end)

  it("on a leaf scalar yields the scalar itself", function()
    assert.are.equal(7, run("**", 7))
  end)
end)
