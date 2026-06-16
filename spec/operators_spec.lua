local jsonata = require("jsonata")
local adapter = require("jsonata.adapter")

local function run(src, input)
  return jsonata.compile(src):evaluate(input)
end

describe("in operator", function()
  it("tests membership in an array", function()
    assert.is_true(run("1 in [1, 2]"))
    assert.is_false(run("3 in [1, 2]"))
    assert.is_true(run('"world" in ["hello", "world"]'))
    assert.is_false(run('"x" in [1, 2]'))
  end)

  it("wraps a non-array rhs into a singleton", function()
    assert.is_true(run('"hello" in "hello"'))
    assert.is_false(run('"hello" in "world"'))
  end)

  it("returns false when either side is undefined", function()
    assert.is_false(run("miss in [1, 2]", {}))
    assert.is_false(run("1 in miss", {}))
  end)

  it("works inside a predicate", function()
    local data = { books = { { title = "A", tags = { "x", "y" } }, { title = "B", tags = { "z" } } } }
    -- single match: jsonata unwraps the 1-element sequence to a scalar
    assert.are.equal("A", run('books["x" in tags].title', data))
  end)

  it("composes with and (precedence)", function()
    assert.is_true(run("2 in [1, 2] and 3 in [3, 4]"))
  end)
end)

describe("conditional ? without else", function()
  it("returns the then-branch when the condition is truthy", function()
    assert.are.equal("y", run('true ? "y"'))
    assert.are.equal("cheap", run('5 < 30 ? "cheap"'))
  end)

  it("returns nothing when the condition is falsy and no else", function()
    assert.is_nil(run('false ? "y"'))
    assert.is_nil(run('30 < 5 ? "cheap"'))
  end)

  it("does not break the full ternary", function()
    assert.are.equal("y", run('true ? "y" : "n"'))
    assert.are.equal("n", run('false ? "y" : "n"'))
  end)
end)

describe("?? coalescing (undefined-coalesce)", function()
  it("keeps a defined left, even when falsy", function()
    assert.are.equal(0, run("0 ?? 42"))
    assert.is_false(run("false ?? 42"))
    assert.are.equal("", run('"" ?? 42'))
    assert.are.same({}, run("[] ?? 42"))
    assert.are.same({}, run("{} ?? 42"))
    assert.are.equal(adapter.NULL, run("null ?? 42"))
  end)

  it("falls back only when the left is undefined", function()
    assert.are.equal(42, run("miss ?? 42", {}))
    assert.are.equal(7, run("foo.bar ?? 7", { foo = {} }))
    assert.are.equal(5, run("foo.bar ?? 7", { foo = { bar = 5 } }))
  end)
end)

describe("?: default (falsy-default)", function()
  it("keeps a truthy left", function()
    assert.are.equal("hi", run('"hi" ?: 9'))
    assert.are.equal(-5, run("-5 ?: 9"))
    assert.are.same({ 1 }, run("[1] ?: 9"))
  end)

  it("falls back when the left is falsy", function()
    assert.are.equal(42, run("0 ?: 42"))
    assert.are.equal(42, run('"" ?: 42'))
    assert.are.equal(42, run("false ?: 42"))
    assert.are.equal(42, run("[] ?: 42"))
    assert.are.equal(42, run("{} ?: 42"))
    assert.are.equal(42, run("miss ?: 42", {}))
  end)
end)

describe("?? / ?: right-greedy RHS (matches jsonata expression(0))", function()
  -- The RHS must consume same-and-lower precedence operators, so e.g.
  -- `"a" ?? "b" = "a"` parses as `"a" ?? ("b" = "a")`, NOT `("a" ?? "b") = "a"`.
  it("?? RHS grabs a trailing comparison", function()
    assert.are.equal("a", run('"a" ?? "b" = "a"'))
  end)

  it("?: RHS grabs a trailing comparison", function()
    assert.are.equal("a", run('"a" ?: "b" = "a"'))
  end)

  it("?? RHS grabs a trailing boolean expression", function()
    assert.are.equal("val", run('"val" ?? false or true'))
  end)

  it("?? RHS grabs a trailing ternary", function()
    assert.are.equal(0, run('0 ?? "x" ? "b" : "c"'))
  end)
end)
