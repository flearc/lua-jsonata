local errors = require("jsonata.errors")

describe("M5c: D3120/D3121 error templates", function()
  it("defines D3120 and D3121 with interpolatable {{value}}", function()
    local ok1, e1 = pcall(errors.raise, "D3120", { value = "boom" })
    assert.is_false(ok1)
    assert.are.equal("D3120", e1.code)
    assert.is_not_nil(e1.message:find("eval", 1, true))
    assert.is_nil(e1.message:find("{{", 1, true)) -- {{value}} interpolated

    local ok2, e2 = pcall(errors.raise, "D3121", { value = "boom" })
    assert.is_false(ok2)
    assert.are.equal("D3121", e2.code)
    assert.is_nil(e2.message:find("{{", 1, true))
  end)
end)
