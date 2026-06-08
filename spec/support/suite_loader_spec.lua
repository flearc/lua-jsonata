local loader = require("support.suite_loader")

local DIR = "spec/support/fixtures_suite"

local function by_id(cases)
  local m = {}
  for _, c in ipairs(cases) do
    m[c.id] = c
  end
  return m
end

describe("suite_loader", function()
  it("discovers all case files with stable ids", function()
    local cases = loader.load_all(DIR)
    local m = by_id(cases)
    assert.is_not_nil(m["g1/case000"])
    assert.is_not_nil(m["g1/case005"])
    assert.are.equal(6, #cases)
  end)

  it("resolves inline expr + dataset + result", function()
    local c = by_id(loader.load_all(DIR))["g1/case000"]
    assert.are.equal("name", c.expr)
    assert.are.equal("Bob", c.input.name)
    assert.are.equal("result", c.expect.kind)
    assert.are.equal("Bob", c.expect.value)
  end)

  it("resolves dataset:null (no input) and bindings", function()
    local c = by_id(loader.load_all(DIR))["g1/case001"]
    assert.is_nil(c.input)
    assert.are.equal(4, c.bindings.x)
  end)

  it("flags undefinedResult", function()
    local c = by_id(loader.load_all(DIR))["g1/case002"]
    assert.are.equal("undefined", c.expect.kind)
  end)

  it("resolves expr-file", function()
    local c = by_id(loader.load_all(DIR))["g1/case003"]
    assert.are.equal("$count(items)", (c.expr:gsub("%s+$", "")))
  end)

  it("carries the unordered flag", function()
    local c = by_id(loader.load_all(DIR))["g1/case004"]
    assert.is_true(c.unordered)
  end)

  it("marks timelimit/depth cases as skip", function()
    local c = by_id(loader.load_all(DIR))["g1/case005"]
    assert.is_true(c.skip)
  end)
end)

describe("suite_loader case-file shapes", function()
  local LDIR = "spec/support/fixtures_loader"

  it("reads an inline data field (C1)", function()
    local c = by_id(loader.load_all(LDIR))["gx/inline"]
    assert.are.equal("Ann", c.input.name)
    assert.are.equal("Ann", c.expect.value)
  end)

  it("recognizes a nested error.code expectation (C3)", function()
    local c = by_id(loader.load_all(LDIR))["gx/errfield"]
    assert.are.equal("error", c.expect.kind)
    assert.are.equal("T2001", c.expect.code)
  end)

  it("expands an array-of-cases file into sub-descriptors (C2)", function()
    local m = by_id(loader.load_all(LDIR))
    assert.is_not_nil(m["gx/multi/0"])
    assert.is_not_nil(m["gx/multi/2"])
    assert.are.equal(1, m["gx/multi/0"].expect.value)
    assert.are.equal(3, m["gx/multi/2"].expect.value)
  end)
end)
