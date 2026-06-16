local jsonata = require("jsonata")

local function run(src, input)
  return jsonata.compile(src):evaluate(input)
end

describe("lambda: λ alias", function()
  it("λ is an alias for function", function()
    assert.are.equal(5, run("λ($x){$x}(5)"))
    assert.are.equal(8, run("λ($x, $y){$x + $y}(3, 5)"))
  end)
end)
