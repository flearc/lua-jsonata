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
