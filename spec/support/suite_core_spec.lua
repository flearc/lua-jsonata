local core = require("support.suite_core")

local DIR = "spec/support/fixtures_suite"

describe("suite_core", function()
  local r
  setup(function()
    r = core.run({ suite_dir = DIR, baseline_path = DIR .. "/baseline.lua" })
  end)

  it("counts and categorizes cases", function()
    assert.are.equal(6, r.total)
    assert.are.equal(1, r.skipped) -- case005 timelimit/depth
    assert.are.equal(5, r.passed)
    assert.are.equal(0, r.errored)
  end)

  it("records per-group pass/total", function()
    assert.are.equal(5, r.by_group["g1"].pass)
    assert.are.equal(6, r.by_group["g1"].total)
  end)

  it("detects regressions (baseline case now missing from passes)", function()
    local set = {}
    for _, id in ipairs(r.regressions) do
      set[id] = true
    end
    assert.is_true(set["g1/case999_gone"])
  end)

  it("detects surprise passes (passing but not in baseline)", function()
    local set = {}
    for _, id in ipairs(r.surprises) do
      set[id] = true
    end
    assert.is_true(set["g1/case002"])
  end)

  it("can write and reload a baseline from current passes", function()
    local tmp = os.tmpname()
    core.write_baseline(tmp, r.pass_set)
    local reloaded = core.load_baseline(tmp)
    assert.is_true(reloaded["g1/case000"])
    assert.is_nil(reloaded["g1/case999_gone"])
    os.remove(tmp)
  end)
end)
