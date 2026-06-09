local jsonata = require("jsonata")

local function run(src, input)
  return jsonata.compile(src):evaluate(input)
end

describe("range ..", function()
  it("builds an ascending integer range", function()
    assert.are.same({ 0, 1, 2, 3, 4, 5, 6, 7, 8, 9 }, run("[0..9]"))
    assert.are.same({ -2, -1, 0, 1, 2 }, run("[-2..2]"))
  end)

  it("is empty for a reverse range", function()
    assert.are.same({}, run("[5..2]"))
  end)

  it("spreads ranges among other array elements", function()
    assert.are.same({ 0, 4, 5, 6, 7, 8, 9, 20 }, run("[0, 4..9, 20]"))
    assert.are.same({ 2, 3, 4, 5 }, run("[5..2, 2..5]"))
  end)

  it("is empty when an endpoint is undefined", function()
    assert.are.same({}, run("[-2..blah]", {}))
  end)

  it("composes with a predicate and a map", function()
    assert.are.same({ 0, 2, 4, 6, 8 }, run("[0..9][$ % 2 = 0]"))
    assert.are.same({ 4, 1, 0, 1, 4 }, run("[-2..2].($ * $)"))
  end)

  it("raises T2003 when the left side is not an integer", function()
    local ok, err = pcall(run, "[1.1..5]")
    assert.is_false(ok)
    assert.are.equal("T2003", err.code)
  end)

  it("raises T2004 when the right side is not an integer", function()
    local ok, err = pcall(run, "[1..false]")
    assert.is_false(ok)
    assert.are.equal("T2004", err.code)
  end)

  it("raises D2014 when the range exceeds 1e7 elements", function()
    local ok, err = pcall(run, "[0..10000000]")
    assert.is_false(ok)
    assert.are.equal("D2014", err.code)
  end)

  it("keeps decimals working and a single range in []", function()
    assert.are.equal(5.5, run("5.5"))
    assert.are.same({ 1, 2, 3, 4, 5 }, run("[1..5]"))
  end)
end)
