local jsonata = require("jsonata")
local parser = require("jsonata.parser")

describe("M6c parser: @ / # bind focus/index on the last flat step", function()
  it("a@$x.b flattens to [a(focus x), b] with tuple set", function()
    local ast = parser.parse("a@$x.b")
    assert.are.equal("path", ast.type)
    assert.are.equal("x", ast.steps[1].focus)
    assert.is_true(ast.steps[1].tuple)
    assert.are.equal("b", ast.steps[2].value)
    assert.is_nil(ast.steps[2].focus)
  end)

  it("$#$pos wraps a single step with index set", function()
    local ast = parser.parse("$#$pos")
    assert.are.equal("path", ast.type)
    assert.are.equal("pos", ast.steps[1].index)
    assert.is_true(ast.steps[1].tuple)
  end)

  it("a.b@$l.c@$m keeps a flat 3-step path with two focuses", function()
    local ast = parser.parse("a.b@$l.c@$m")
    assert.are.equal(3, #ast.steps)
    assert.are.equal("l", ast.steps[2].focus)
    assert.are.equal("m", ast.steps[3].focus)
  end)
end)

describe("M6c parser: validation errors", function()
  it("@ with a non-variable rhs raises S0214 (token @)", function()
    local ok, err = pcall(parser.parse, "Account.Order@o.Product")
    assert.is_false(ok)
    assert.are.equal("S0214", err.code)
    assert.are.equal("@", err.token)
  end)

  it("# with a non-variable rhs raises S0214 (token #)", function()
    local ok, err = pcall(parser.parse, "Account.Order@$o#i.Product")
    assert.is_false(ok)
    assert.are.equal("S0214", err.code)
    assert.are.equal("#", err.token)
  end)

  it("@ after a predicate raises S0215", function()
    local ok, err = pcall(parser.parse, "Account.Order[1]@$o.Product")
    assert.is_false(ok)
    assert.are.equal("S0215", err.code)
  end)

  it("@ after a sort raises S0216", function()
    local ok, err = pcall(parser.parse, "Account.Order^(>OrderID)@$o.Product")
    assert.is_false(ok)
    assert.are.equal("S0216", err.code)
  end)

  it("# after a sort/filter does NOT raise (it indexes the step)", function()
    assert.has_no.errors(function()
      parser.parse("$^($)#$pos")
    end)
    assert.has_no.errors(function()
      parser.parse("$[[1..4]]#$pos")
    end)
  end)
end)

local function run(src, input)
  return jsonata.compile(src):evaluate(input)
end

describe("M6c eval: #$v index binding (0-based, natural order)", function()
  local NUMS = { 3, 1, 4, 1, 5, 9 }

  it("$#$pos[$pos<3] keeps the first three (0-based index)", function()
    assert.are.same({ 3, 1, 4 }, run("$#$pos[$pos<3]", NUMS))
  end)

  it("$#$pos[$pos<3][1] then positionally indexes the survivors", function()
    assert.are.equal(1, run("$#$pos[$pos<3][1]", NUMS))
  end)

  it("$#$pos[$pos<3]^($)[-1] sorts the survivors and takes the last", function()
    assert.are.equal(4, run("$#$pos[$pos<3]^($)[-1]", NUMS))
  end)

  it("index carries through a following step (per input item, 0-based)", function()
    local DATA = {
      Account = {
        Order = {
          { OrderID = "o1", Product = { { pid = 1 }, { pid = 2 } } },
          { OrderID = "o2", Product = { { pid = 3 } } },
        },
      },
    }
    local res = run("Account.Order#$o.Product.{ 'pid': pid, 'oi': $o }", DATA)
    assert.are.same({
      { pid = 1, oi = 0 },
      { pid = 2, oi = 0 },
      { pid = 3, oi = 1 },
    }, res)
  end)
end)

describe("M6c eval: @$v focus binding (cross-product join)", function()
  local DATA = {
    order = { { oid = "A", pid = 1 }, { oid = "B", pid = 2 } },
    product = {
      { pid = 1, name = "Hat" },
      { pid = 2, name = "Shoe" },
      { pid = 1, name = "Cap" },
    },
  }

  it("order@$o.product@$p[$o.pid=$p.pid] joins on pid", function()
    local res = run("order@$o.product@$p[$o.pid=$p.pid].{ 'order': $o.oid, 'name': $p.name }", DATA)
    assert.are.same({
      { order = "A", name = "Hat" },
      { order = "A", name = "Cap" },
      { order = "B", name = "Shoe" },
    }, res)
  end)

  it("focus does NOT advance @: product still evaluates from the root", function()
    local res = run("order@$o.product@$p.{ 'o': $o.oid, 'p': $p.name }", DATA)
    assert.are.equal(6, #res)
  end)
end)

describe("M6c eval: deferred reorder cases don't crash (red is OK)", function()
  it("$[[1..4]]#$pos[$pos>=2] evaluates to a structured value", function()
    assert.has_no.errors(function()
      run("$[[1..4]]#$pos[$pos>=2]", { 3, 1, 4, 1, 5, 9 })
    end)
  end)
  it("$^($)#$pos[$pos<3] evaluates to a structured value", function()
    assert.has_no.errors(function()
      run("$^($)#$pos[$pos<3]", { 3, 1, 4, 1, 5, 9 })
    end)
  end)
end)

describe("M6c eval: % parent + plain paths still work (regression)", function()
  it("a.b.%.c resolves the ancestor unchanged", function()
    assert.are.equal(7, run("a.b.%.c", { a = { b = 1, c = 7 } }))
  end)
end)
