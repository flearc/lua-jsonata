local F = require("jsonata.functions")

describe("url functions", function()
  it("$encodeUrlComponent / $decodeUrlComponent round-trip", function()
    assert.are.equal("a%20b%2Fc", F.encodeUrlComponent.impl("a b/c"))
    assert.are.equal("a b/c", F.decodeUrlComponent.impl("a%20b%2Fc"))
  end)

  it("$encodeUrl keeps reserved chars, encodes spaces", function()
    assert.are.equal("http://x/a%20b", F.encodeUrl.impl("http://x/a b"))
    assert.are.equal("http://x/a b", F.decodeUrl.impl("http://x/a%20b"))
  end)
end)
