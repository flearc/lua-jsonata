local jsonata = require("jsonata")
local parser = require("jsonata.parser")

local function run(src, input)
  return jsonata.compile(src):evaluate(input)
end

describe("parent %: ancestry wiring (process_ast)", function()
  it("anchors a parent slot onto the preceding step", function()
    local ast = parser.parse("a.b.%")
    assert.are.equal("path", ast.type)
    local b = ast.steps[2]
    assert.are.equal("name", b.type)
    assert.is_truthy(b.tuple)
    assert.is_truthy(b.ancestor)
    assert.are.equal(b.ancestor.label, ast.steps[3].slot.label)
  end)

  it("anchors %.% slots on the two preceding steps", function()
    local ast = parser.parse("a.b.c.{ 'x': %.%.name }")
    -- %.%.name inside the object step seeds two slots: level-1 anchors on c
    -- (whose step INPUT is b's value), level-2 anchors on b (whose step INPUT
    -- is a's value -- the value %.% ultimately resolves to at runtime).
    local b = ast.steps[2]
    local c = ast.steps[3]
    assert.is_truthy(c.ancestor)
    assert.is_truthy(c.tuple)
    assert.is_truthy(b.ancestor)
    assert.is_truthy(b.tuple)
  end)

  it("raises S0217 for a bare top-level %", function()
    local ok, err = pcall(parser.parse, "%")
    assert.is_false(ok)
    assert.are.equal("S0217", err.code)
  end)

  it("raises S0217 when % climbs above the root", function()
    local ok, err = pcall(parser.parse, "a.%.%")
    assert.is_false(ok)
    assert.are.equal("S0217", err.code)
  end)

  it("raises S0217 when the previous step cannot carry an ancestor", function()
    local ok, err = pcall(parser.parse, "$.%")
    assert.is_false(ok)
    assert.are.equal("S0217", err.code)
  end)
end)

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
