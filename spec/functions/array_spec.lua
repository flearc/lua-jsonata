local F = require("jsonata.functions")
local V = require("jsonata.value")

local function arr(...)
  return V.array({ ... })
end

describe("array functions", function()
  it("$append joins arrays (and wraps scalars)", function()
    local r = F.append.impl(arr(1, 2), arr(3, 4))
    assert.are.same({ 1, 2, 3, 4 }, { r[1], r[2], r[3], r[4] })
    local r2 = F.append.impl(arr(1), 2)
    assert.are.same({ 1, 2 }, { r2[1], r2[2] })
  end)

  it("$reverse", function()
    local r = F.reverse.impl(arr(1, 2, 3))
    assert.are.same({ 3, 2, 1 }, { r[1], r[2], r[3] })
  end)

  it("$distinct dedupes by value, first-seen order", function()
    local r = F.distinct.impl(arr(1, 2, 1, 3, 2))
    assert.are.same({ 1, 2, 3 }, { r[1], r[2], r[3] })
  end)

  it("$zip pairs by shortest", function()
    local r = F.zip.impl(arr(1, 2, 3), arr("a", "b"))
    assert.are.equal(2, #r)
    assert.are.same({ 1, "a" }, { r[1][1], r[1][2] })
  end)
end)
