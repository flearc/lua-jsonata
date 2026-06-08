local F = require("jsonata.functions")
local V = require("jsonata.value")

describe("aggregation functions", function()
  local function arr(...)
    return V.array({ ... })
  end

  it("$sum/$max/$min/$average over an array", function()
    assert.are.equal(6, F.sum.impl(arr(1, 2, 3)))
    assert.are.equal(3, F.max.impl(arr(1, 3, 2)))
    assert.are.equal(1, F.min.impl(arr(1, 3, 2)))
    assert.are.equal(2, F.average.impl(arr(1, 2, 3)))
  end)

  it("treat a single number as a one-element sequence", function()
    assert.are.equal(5, F.sum.impl(5))
    assert.are.equal(5, F.max.impl(5))
  end)

  it("NOTHING input returns NOTHING", function()
    assert.is_true(V.is_nothing(F.sum.impl(V.NOTHING)))
  end)
end)
