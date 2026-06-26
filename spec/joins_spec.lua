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

local cjson = require("cjson")
local function dataset(name)
  local f = assert(io.open("spec/jsonata-suite/datasets/" .. name .. ".json"))
  local raw = f:read("a")
  f:close()
  return cjson.decode(raw)
end

describe("M6d: tuple-stream group-by (the reduce half)", function()
  local EMP = dataset("employees")

  it("binding-in-value: { $e.FirstName: $join($c.Phone.number, ', ') }", function()
    local res = run("Employee@$e.Contact@$c[$c.ssn = $e.SSN]{ $e.FirstName: $join($c.Phone.number, ', ') }", EMP)
    assert.are.same({
      Fred = "0203 544 1234, 01962 001234, 077 7700 1234",
      Darren = "3146458343, 315 782 9279",
      Hugh = "0280 564 6543, 0280 864 8643, 07735 853535",
    }, res)
  end)

  it("context-in-value: { $e.FirstName: $c.Phone.number } accumulates per group", function()
    local res = run("Employee@$e.Contact@$c[$c.ssn = $e.SSN]{ $e.FirstName: $c.Phone.number }", EMP)
    assert.are.same({
      Fred = { "0203 544 1234", "01962 001234", "077 7700 1234" },
      Darren = { "3146458343", "315 782 9279" },
      Hugh = { "0280 564 6543", "0280 864 8643", "07735 853535" },
    }, res)
  end)

  it("index group-by: Account.Order#$i.Product{ $string(ProductID): $i }", function()
    local res = run("Account.Order#$i.Product{ $string(ProductID): $i }", dataset("dataset5"))
    assert.are.same({
      ["345664"] = 1,
      ["858236"] = 0,
      ["858383"] = { 0, 1 },
    }, res)
  end)

  it("non-tuple group-by is unchanged (regression)", function()
    local DATA = {
      Order = {
        { type = "a", v = 1 },
        { type = "b", v = 2 },
        { type = "a", v = 3 },
      },
    }
    assert.are.same({ a = { 1, 3 }, b = 2 }, run("Order{ type: v }", DATA))
  end)

  it("tuple group-by D1009: same key from two different pairs raises", function()
    local ok, err = pcall(run, "Employee@$e.Contact@$c[$c.ssn = $e.SSN]{ 'k': $e.FirstName, 'k': $c.ssn }", EMP)
    assert.is_false(ok)
    assert.are.equal("D1009", err.code)
  end)
end)

describe("M6e: nested tuple-stream detection (focus under sort/predicate)", function()
  local EMP = dataset("employees")

  -- ^(sort) nests the focus step into a sub-path; predicate nests Contact@$c.
  -- The path's tuple steps are all nested, so detection must recurse.
  it("sort-on-focus-step join: ^($e.Surname) (employee-map-reduce case7)", function()
    assert.are.same({
      { name = "Cruse", phone = { "3146458343", "315 782 9279" } },
      { name = "Jones", phone = "0280 564 6543" },
      { name = "Jones", phone = "0280 864 8643" },
      { name = "Jones", phone = "07735 853535" },
      { name = "Smith", phone = { "0203 544 1234", "01962 001234", "077 7700 1234" } },
    }, run("Employee@$e^($e.Surname).Contact@$c[$e.SSN=$c.ssn].{ 'name': $e.Surname, 'phone': $c.Phone.number }", EMP))
  end)

  it("sort-on-focus-step join: ^($e.FirstName) (employee-map-reduce case8)", function()
    assert.are.same({
      { name = "Cruse", phone = { "3146458343", "315 782 9279" } },
      { name = "Smith", phone = { "0203 544 1234", "01962 001234", "077 7700 1234" } },
      { name = "Jones", phone = "0280 564 6543" },
      { name = "Jones", phone = "0280 864 8643" },
      { name = "Jones", phone = "07735 853535" },
    }, run("Employee@$e^($e.FirstName).Contact@$c[$e.SSN=$c.ssn].{ 'name': $e.Surname, 'phone': $c.Phone.number }", EMP))
  end)

  it("index then sort then map carries $o (sorting case020)", function()
    assert.are.same({
      { Product = "Cloak", ["Order Index"] = 1 },
      { Product = "Trilby hat", ["Order Index"] = 0 },
      { Product = "Bowler Hat", ["Order Index"] = 0 },
      { Product = "Bowler Hat", ["Order Index"] = 1 },
    }, run("Account.Order#$o.Product^(ProductID).{ 'Product': `Product Name`, 'Order Index': $o }", dataset("dataset5")))
  end)
end)

describe("M6f: ordered stages on root/sort tuple steps", function()
  local NUMS = { 3, 1, 4, 1, 5, 9 }

  it("filter before #: $[[1..4]]#$pos[$pos>=2] re-indexes the survivors", function()
    assert.are.same({ 1, 5 }, run("$[[1..4]]#$pos[$pos>=2]", NUMS))
  end)

  it("sort before #: $^($)#$pos[$pos<3] indexes the sorted sequence", function()
    assert.are.same({ 1, 1, 3 }, run("$^($)#$pos[$pos<3]", NUMS))
  end)

  it("intermediate: $[[1..4]]#$pos collapses to the filtered values", function()
    assert.are.same({ 1, 4, 1, 5 }, run("$[[1..4]]#$pos", NUMS))
  end)

  it("intermediate: $^($)#$pos collapses to the sorted values", function()
    assert.are.same({ 1, 1, 3, 4, 5, 9 }, run("$^($)#$pos", NUMS))
  end)

  it("regression: natural-order $#$pos[$pos<3] still keeps the first three", function()
    assert.are.same({ 3, 1, 4 }, run("$#$pos[$pos<3]", NUMS))
  end)
end)

describe("M6g: flat tuple-stage library joins", function()
  local LIBRARY = dataset("library")

  it("library-joins/7 indexes the global matched join stream", function()
    local res = run(
      [[
library.loans@$l#$il.books@$b#$ib[$l.isbn=$b.isbn]#$ib2.customers@$c#$ic[$l.customer=$c.id].{
  'title': $b.title,
  'customer': $l.customer,
  'name': $c.name,
  'loan-index': $il,
  'book-index': $ib,
  'customer-index': $ic,
  'ib2': $ib2
}
]],
      LIBRARY
    )

    assert.are.same({
      {
        title = "Structure and Interpretation of Computer Programs",
        customer = "10001",
        name = "Joe Doe",
        ["loan-index"] = 0,
        ["book-index"] = 0,
        ["customer-index"] = 0,
        ib2 = 0,
      },
      {
        title = "Compilers: Principles, Techniques, and Tools",
        customer = "10003",
        name = "Jason Arthur",
        ["loan-index"] = 1,
        ["book-index"] = 3,
        ["customer-index"] = 2,
        ib2 = 1,
      },
      {
        title = "Structure and Interpretation of Computer Programs",
        customer = "10003",
        name = "Jason Arthur",
        ["loan-index"] = 2,
        ["book-index"] = 0,
        ["customer-index"] = 2,
        ib2 = 2,
      },
    }, res)
  end)

  it("library-joins/8 applies [1] to the global matched join stream", function()
    local res = run(
      [[
library.loans@$l.books@$b[$l.isbn=$b.isbn][1].{
  'title': $b.title,
  'customer': $l.customer
}
]],
      LIBRARY
    )

    assert.are.same({
      title = "Compilers: Principles, Techniques, and Tools",
      customer = "10003",
    }, res)
  end)

  it("library-joins/10 applies [1][] to the global matched join stream", function()
    local res = run(
      [[
library.loans@$l.books@$b[$l.isbn=$b.isbn][1][].{
  'title': $b.title,
  'customer': $l.customer
}
]],
      LIBRARY
    )

    assert.are.same({
      {
        title = "Compilers: Principles, Techniques, and Tools",
        customer = "10003",
      },
    }, res)
  end)
end)

describe("M6f: sort index binds only on a raw (not tuple-bound) stream", function()
  local NUMS = { 3, 1, 4, 1, 5, 9 }
  it("sort-on-raw binds the index (index/6 still works)", function()
    assert.are.same({ 1, 1, 3 }, run("$^($)#$pos[$pos<3]", NUMS))
  end)
  it("sort after a prior #-binding does NOT bind (double-index → undefined)", function()
    assert.is_nil(run("$#$a^($)#$b[$b<2]", NUMS))
  end)
end)
