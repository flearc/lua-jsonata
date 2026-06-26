local H = require("jsonata.functions.helpers")
local jsonata = require("jsonata")
local function run(src, input)
  return jsonata.compile(src):evaluate(input)
end

describe("num_to_str: ECMAScript Number->String", function()
  local cases = {
    { 0, "0" },
    { -0.0, "0" },
    { 123, "123" },
    { -12.34, "-12.34" },
    { 1.5, "1.5" },
    { 100000, "100000" },
    { 0.3, "0.3" },
    { 1e20, "100000000000000000000" },
    { 1e21, "1e+21" },
    { 1e100, "1e+100" },
    { 1e308, "1e+308" },
    { 1e-6, "0.000001" },
    { 1e-7, "1e-7" },
    { 5e-324, "5e-324" },
    { 123456789012345680, "123456789012345680" },
  }
  for _, c in ipairs(cases) do
    it("formats " .. tostring(c[2]), function()
      assert.are.equal(c[2], H.num_to_str(c[1]))
    end)
  end
end)

describe("$string number formatting (thresholds)", function()
  it("exponential thresholds + plain integers", function()
    assert.are.equal("1e+21", run("$string(1e21)"))
    assert.are.equal("100000000000000000000", run("$string(1e20)"))
    assert.are.equal("0.000001", run("$string(1e-6)"))
    assert.are.equal("1e-7", run("$string(1e-7)"))
    assert.are.equal("1e+100", run("$string(1e100)"))
  end)
end)
