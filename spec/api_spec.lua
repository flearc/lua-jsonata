local jsonata = require("jsonata")

describe("public API", function()
  it("compiles and evaluates against plain Lua data", function()
    local expr = jsonata.compile("a.b")
    assert.are.equal(5, expr:evaluate({ a = { b = 5 } }))
  end)

  it("returns nil for no match", function()
    local expr = jsonata.compile("missing")
    assert.is_nil(expr:evaluate({ a = 1 }))
  end)

  it("returns plain Lua arrays/objects", function()
    local expr = jsonata.compile("items")
    assert.are.same({ 1, 2, 3 }, expr:evaluate({ items = { 1, 2, 3 } }))
  end)

  it("supports one-shot bindings", function()
    local expr = jsonata.compile("$factor * 2")
    assert.are.equal(6, expr:evaluate({}, { factor = 3 }))
  end)

  it("supports assign for permanent bindings", function()
    local expr = jsonata.compile("$tax")
    expr:assign("tax", 0.2)
    assert.are.equal(0.2, expr:evaluate({}))
  end)

  it("supports registerFunction with a sync Lua function", function()
    local expr = jsonata.compile("$double(21)")
    expr:registerFunction("double", function(x)
      return x * 2
    end)
    assert.are.equal(42, expr:evaluate({}))
  end)

  it("propagates structured parse errors", function()
    local errs = require("jsonata.errors")
    local ok, err = pcall(jsonata.compile, "1 +")
    assert.is_false(ok)
    assert.is_true(errs.is_error(err))
  end)
end)
