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

describe("toPrecision(15) rounds half away from zero (JS), not half-even", function()
  local cases = {
    { "572242133073302.5", "572242133073303" },
    { "-800411785470156.5", "-800411785470157" },
    { "-28093361853.90625", "-28093361853.9063" },
    { "0.1+0.2", "0.3" }, -- still works (non-tie)
    { "22/7", "3.14285714285714" }, -- still works
    { "5e-324", "5e-324" }, -- denormal still works (no FP-scaling overflow)
  }
  for _, c in ipairs(cases) do
    it("$string(" .. c[1] .. ") = " .. c[2], function()
      assert.are.equal(c[2], run("$string(" .. c[1] .. ")"))
    end)
  end
end)

describe("$string non-finite + functions + embedded rounding", function()
  it("non-finite number -> D3001", function()
    local ok, err = pcall(run, "$string(1/0)")
    assert.is_false(ok)
    assert.are.equal("D3001", err.code)
  end)
  it("function/lambda -> empty string", function()
    assert.are.equal("", run("$string($sum)"))
    assert.are.equal("", run("$string(function($x){$x})"))
  end)
  it("compact object serialization rounds embedded non-integers", function()
    assert.are.equal(
      '{"string":"hello","number":39.4,"null":null,"boolean":false}',
      run('$string({ "string": "hello", "number": 78.8 / 2, "null": null, "boolean": false })')
    )
  end)
end)

describe("$string prettify (2-space indent)", function()
  it("objects + arrays", function()
    assert.are.equal('{\n  "string": "hello"\n}', run('$string({"string": "hello"}, true)'))
    assert.are.equal('[\n  "string",\n  5\n]', run('$string(["string", 5], true)'))
  end)
  it("nested + compact-when-false", function()
    assert.are.equal('{"a":[1,2]}', run('$string({"a":[1,2]})'))
    assert.are.equal('{\n  "a": [\n    1,\n    2\n  ]\n}', run('$string({"a":[1,2]}, true)'))
  end)
  it("empty object/array on one line", function()
    assert.are.equal("{}", run("$string({}, true)"))
    assert.are.equal("[]", run("$string([], true)"))
  end)
end)

describe("$string serializes function values as empty string (keep key)", function()
  it('object function members render as ""', function()
    assert.are.equal('{"a":""}', run("$string({'a': $sum})"))
    assert.are.equal('{"a":"","b":1}', run("$string({'a': function($x){$x}, 'b': 1})"))
    assert.are.equal('{"obj":{"f":""}}', run("$string({'obj': {'f': $sum}})"))
  end)
  it("undefined/nothing members are still dropped", function()
    assert.are.equal('{"b":1}', run("$string({'a': blah, 'b': 1})", {}))
  end)
end)
