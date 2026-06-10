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

  it("resolves a %.% predicate strand through the enclosing path", function()
    -- the %.% inside the predicate consumes one level in the filter context,
    -- the remaining level must escape the nested wrap and anchor on step b
    local ast = parser.parse("a.b.c[%.%.x = 1]")
    local b = ast.steps[2]
    assert.is_truthy(b.ancestor)
    assert.is_truthy(b.tuple)
  end)

  it("shares one label when two % anchor on the same step", function()
    -- (%.x + %.y) parses as a binary + node (not a block); each operand is a
    -- path whose first step is a parent node; both must share the label from b.
    local ast = parser.parse("a.b.(%.x + %.y)")
    local b = ast.steps[2]
    assert.is_truthy(b.ancestor)
    -- both parent nodes inside the block must resolve through the SAME label
    local plus = ast.steps[3] -- binary + (the parenthesised expression)
    local p1 = plus.lhs.steps[1]
    local p2 = plus.rhs.steps[1]
    assert.are.equal("parent", p1.type)
    assert.are.equal("parent", p2.type)
    assert.are.equal(p1.slot.label, p2.slot.label)
    assert.are.equal(b.ancestor.label, p1.slot.label)
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
