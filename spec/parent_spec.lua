local jsonata = require("jsonata")
local parser = require("jsonata.parser")

local function run(src, input)
  return jsonata.compile(src):evaluate(input)
end

local ORDERS = {
  Account = {
    Order = {
      {
        OrderID = "order103",
        Product = {
          { ProductID = 1, Price = 10, Quantity = 2 },
          { ProductID = 2, Price = 20, Quantity = 1 },
        },
      },
      {
        OrderID = "order104",
        Product = {
          { ProductID = 3, Price = 30, Quantity = 4 },
        },
      },
    },
  },
}

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

describe("parent %: evaluation core", function()
  it("binds each item's own parent under fan-out (constructor step)", function()
    assert.are.same({
      { pid = 1, oid = "order103" },
      { pid = 2, oid = "order103" },
      { pid = 3, oid = "order104" },
    }, run("Account.Order.Product.{ 'pid': ProductID, 'oid': %.OrderID }", ORDERS))
  end)

  it("supports %.% chains across two levels", function()
    local data = { a = { name = "A", b = { name = "B", c = { 1, 2 } } } }
    assert.are.same({
      { v = 1, pb = "B", pa = "A" },
      { v = 2, pb = "B", pa = "A" },
    }, run("a.b.c.{ 'v': $, 'pb': %.name, 'pa': %.%.name }", data))
  end)

  it("evaluates % as a path step (navigate back up)", function()
    assert.are.same({ b = { x = 1 } }, run("a.b.%", { a = { b = { x = 1 } } }))
  end)

  it("works inside a block with a variable binding", function()
    assert.are.same({ "order103", "order103", "order104" }, run("Account.Order.Product.( $p := %; $p.OrderID )", ORDERS))
    assert.are.same({ "order103", "order103", "order104" }, run("Account.Order.Product.( $x := 1; %.OrderID )", ORDERS))
  end)

  it("returns nothing when % is invoked as a function (then T1006)", function()
    local ok, err = pcall(run, "a.( %() )", { a = { b = 1 } })
    assert.is_false(ok)
    assert.are.equal("T1006", err.code)
  end)
end)
