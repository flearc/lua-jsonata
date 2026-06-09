local jsonata = require("jsonata")

local function run(src, input)
  return jsonata.compile(src):evaluate(input)
end

describe("group-by {}", function()
  it("maps a bare name over an array input (prerequisite)", function()
    assert.are.same({ 1, 2 }, run("a", { { a = 1 }, { a = 2 } }))
  end)

  it("groups by key; value maps over multi-item groups", function()
    local data = { { id = "x", v = 1 }, { id = "y", v = 2 }, { id = "x", v = 3 } }
    assert.are.same({ x = { 1, 3 }, y = 2 }, run("${id: v}", data))
  end)

  it("aggregates per group", function()
    local data = { { k = "a", v = 10 }, { k = "b", v = 20 }, { k = "a", v = 5 } }
    assert.are.same({ a = 15, b = 20 }, run("${k: $sum(v)}", data))
  end)

  it("merges multiple key:value pairs into one object", function()
    local data = { { k1 = "a", k2 = "x", v = 1 }, { k1 = "b", k2 = "y", v = 2 } }
    assert.are.same({ a = 1, b = 2, x = 1, y = 2 }, run("${k1: v, k2: v}", data))
  end)

  it("groups a path lhs", function()
    local data = { orders = { { oid = "o1", amt = 10 }, { oid = "o2", amt = 20 }, { oid = "o1", amt = 5 } } }
    assert.are.same({ o1 = 15, o2 = 20 }, run("orders{oid: $sum(amt)}", data))
  end)

  it("raises T1003 when a key is not a string", function()
    local ok, err = pcall(run, "${n: v}", { { n = 5, v = 1 } })
    assert.is_false(ok)
    assert.are.equal("T1003", err.code)
  end)

  it("raises D1009 when two pairs evaluate to the same key", function()
    local ok, err = pcall(run, "${k: v, k: v}", { { k = "a", v = 1 } })
    assert.is_false(ok)
    assert.are.equal("D1009", err.code)
  end)
end)
