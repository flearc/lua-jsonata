local sort = require("jsonata.sort")

describe("jsonata.sort.stable_sort", function()
  -- comp_after(a, b) returns true when a should sort AFTER b
  local function asc(a, b)
    return a > b
  end

  it("sorts ascending with a comparator", function()
    assert.are.same({ 1, 2, 3 }, sort.stable_sort({ 3, 1, 2 }, asc))
  end)

  it("handles length 0 and 1", function()
    assert.are.same({}, sort.stable_sort({}, asc))
    assert.are.same({ 5 }, sort.stable_sort({ 5 }, asc))
  end)

  it("is stable: equal keys keep original order", function()
    local function by_key(a, b)
      return a.k > b.k
    end
    local out = sort.stable_sort({ { k = 1, id = "a" }, { k = 1, id = "b" }, { k = 0, id = "c" } }, by_key)
    assert.are.same({ "c", "a", "b" }, { out[1].id, out[2].id, out[3].id })
  end)
end)
