local jsonata = require("jsonata")
local parser = require("jsonata.parser")

local function run(src, input)
  return jsonata.compile(src):evaluate(input)
end

describe("parent %: parsing", function()
  it("parses % as a parent node in prefix position", function()
    local raw = parser.parse_raw("a.%")
    assert.are.equal("binary", raw.type)
    assert.are.equal("parent", raw.rhs.type)
  end)

  it("keeps infix modulo intact", function()
    assert.are.equal(1, run("a % b", { a = 7, b = 3 }))
  end)
end)
