local compare = require("support.suite_compare")

local NULL = setmetatable({}, { __name = "test.null" })
local eq = compare.new(NULL)

describe("suite_compare", function()
  it("compares scalars exactly", function()
    assert.is_true(eq(5, 5, false))
    assert.is_true(eq("a", "a", false))
    assert.is_true(eq(true, true, false))
    assert.is_false(eq(5, 6, false))
    assert.is_false(eq(0.1 + 0.2, 0.3, false)) -- no epsilon: float noise is NOT equal
  end)

  it("treats the null marker by identity, distinct from empty containers", function()
    assert.is_true(eq(NULL, NULL, false))
    assert.is_false(eq(NULL, {}, false)) -- null is not an empty object
    assert.is_false(eq(NULL, 0, false))
  end)

  it("compares arrays elementwise (ordered)", function()
    assert.is_true(eq({ 1, 2, 3 }, { 1, 2, 3 }, false))
    assert.is_false(eq({ 1, 2, 3 }, { 1, 3, 2 }, false))
    assert.is_false(eq({ 1, 2 }, { 1, 2, 3 }, false))
  end)

  it("compares arrays as multisets when unordered", function()
    assert.is_true(eq({ 3, 1, 2 }, { 1, 2, 3 }, true))
    assert.is_true(eq({ { a = 1 }, { a = 2 } }, { { a = 2 }, { a = 1 } }, true))
    assert.is_false(eq({ 1, 1, 2 }, { 1, 2, 2 }, true)) -- multiset, not set
  end)

  it("compares objects order-independently and recursively", function()
    assert.is_true(eq({ a = 1, b = 2 }, { b = 2, a = 1 }, false))
    assert.is_true(eq({ a = { x = 1 } }, { a = { x = 1 } }, false))
    assert.is_false(eq({ a = 1 }, { a = 1, b = 2 }, false))
    assert.is_false(eq({ a = 1, b = 2 }, { a = 1 }, false))
  end)

  it("treats two empty containers as equal (documented limitation)", function()
    assert.is_true(eq({}, {}, false))
  end)

  it("distinguishes array vs non-empty object", function()
    assert.is_false(eq({ 1, 2 }, { a = 1 }, false))
  end)

  it("handles null nested inside structures", function()
    assert.is_true(eq({ a = NULL }, { a = NULL }, false))
    assert.is_false(eq({ a = NULL }, { a = 1 }, false))
  end)
end)
