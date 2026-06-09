local jsonata = require("jsonata")

local function run(src, input)
  return jsonata.compile(src):evaluate(input)
end

describe("transform ~> |...|", function()
  it("merges an update object into matched nodes", function()
    assert.are.same({ a = { y = 1, x = 99 } }, run([[$ ~> |a|{"x": 99}|]], { a = { y = 1 } }))
  end)

  it("deletes a single key", function()
    assert.are.same({ a = { z = 2 } }, run([[$ ~> |a|{},"y"|]], { a = { y = 1, z = 2 } }))
  end)

  it("deletes multiple keys", function()
    assert.are.same({ a = { w = 3 } }, run([[$ ~> |a|{},["y","z"]|]], { a = { y = 1, z = 2, w = 3 } }))
  end)

  it("computes the update value in the matched node's context", function()
    assert.are.same({ items = { price = 3, qty = 4, total = 12 } }, run([[$ ~> |items|{"total": price * qty}|]], { items = { price = 3, qty = 4 } }))
  end)

  it("applies to every node when the pattern matches an array", function()
    assert.are.same({ list = { { n = 1, tag = "x" }, { n = 2, tag = "x" } } }, run([[$ ~> |list|{"tag": "x"}|]], { list = { { n = 1 }, { n = 2 } } }))
  end)

  it("raises T2011 when the update is not an object", function()
    local ok, err = pcall(run, [[$ ~> |a|5|]], { a = {} })
    assert.is_false(ok)
    assert.are.equal("T2011", err.code)
  end)

  it("raises T2012 when the delete is not an array of strings", function()
    local ok, err = pcall(run, [[$ ~> |a|{},5|]], { a = {} })
    assert.is_false(ok)
    assert.are.equal("T2012", err.code)
  end)

  it("returns the clone unchanged when the pattern matches nothing", function()
    assert.are.same({ a = 1 }, run([[$ ~> |nope|{"x": 1}|]], { a = 1 }))
  end)

  it("returns nothing when the input is undefined", function()
    assert.is_nil(run([[missing ~> |a|{"x": 1}|]], {}))
  end)
end)
