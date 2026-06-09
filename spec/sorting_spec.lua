local jsonata = require("jsonata")

local function run(src, input)
  return jsonata.compile(src):evaluate(input)
end

describe("order-by ^", function()
  it("sorts by self ascending and descending", function()
    assert.are.same({ 1, 2, 3 }, run("$^($)", { 3, 1, 2 }))
    assert.are.same({ 3, 2, 1 }, run("$^(>$)", { 3, 1, 2 }))
  end)

  it("sorts objects by a field, then navigates (path integration)", function()
    local data = { { name = "Bill", age = 35 }, { name = "Sally", age = 33 }, { name = "Jim", age = 99 } }
    assert.are.same({ "Sally", "Bill", "Jim" }, run("$^(age).name", data))
  end)

  it("sorts by multiple keys (ties broken by 2nd key)", function()
    local data = { { id = "a", k1 = 1, k2 = 2 }, { id = "b", k1 = 1, k2 = 1 }, { id = "c", k1 = 0, k2 = 9 } }
    assert.are.same({ "c", "b", "a" }, run("$^(k1, k2).id", data))
  end)

  it("supports per-key direction", function()
    local data = { { id = "a", k1 = 1, k2 = 2 }, { id = "b", k1 = 1, k2 = 1 }, { id = "c", k1 = 0, k2 = 9 } }
    assert.are.same({ "c", "a", "b" }, run("$^(k1, >k2).id", data))
  end)

  it("sorts by an expression key", function()
    local data = { { id = "a", p = 3, q = 2 }, { id = "b", p = 2, q = 2 }, { id = "c", p = 1, q = 5 } }
    assert.are.same({ "b", "c", "a" }, run("$^(p*q).id", data))
  end)

  it("singleton-unwraps a single-element result", function()
    local data = { { name = "Bill", age = 35 }, { name = "Sally", age = 33 } }
    assert.are.same({ name = "Bill", age = 35 }, run("$[0]^(age)", data))
  end)

  it("raises T2008 when a sort key is not a number or string", function()
    local ok, err = pcall(run, "$^($)", { { a = 1 }, { a = 2 } })
    assert.is_false(ok)
    assert.are.equal("T2008", err.code)
  end)

  it("raises T2007 when keys have mismatched types", function()
    local ok, err = pcall(run, "$^(k)", { { k = 1 }, { k = "x" } })
    assert.is_false(ok)
    assert.are.equal("T2007", err.code)
  end)
end)
