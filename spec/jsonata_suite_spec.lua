-- Guards the official suite inside the normal busted run / pre-push hook:
-- fails only if a previously-passing case regresses.
local core = require("support.suite_core")

describe("official jsonata test-suite", function()
  it("has zero regressions vs baseline", function()
    local r = core.run({})
    assert.are.equal(0, #r.regressions, "Regressions: " .. table.concat(r.regressions, ", "))
  end)
end)
