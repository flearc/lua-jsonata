local errors = require("jsonata.errors")
local E = require("jsonata.evaluator")

describe("M5d: M.is_function + T2006", function()
  it("M.is_function recognizes lambdas and builtins, rejects data", function()
    assert.is_true(E.is_function({ _jsonata_lambda = true }))
    assert.is_true(E.is_function({ _jsonata_function = true }))
    assert.is_falsy(E.is_function(5))
    assert.is_falsy(E.is_function("x"))
    assert.is_falsy(E.is_function({ a = 1 }))
    assert.is_falsy(E.is_function(nil))
  end)

  it("defines the T2006 template", function()
    local ok, e = pcall(errors.raise, "T2006", { value = 3 })
    assert.is_false(ok)
    assert.are.equal("T2006", e.code)
    assert.is_not_nil(e.message:find("function application", 1, true))
  end)
end)

describe("M5d: ~> function composition", function()
  local jsonata = require("jsonata")
  local function run(src, input)
    return jsonata.compile(src):evaluate(input)
  end
  local function code(src, input)
    local ok, err = pcall(run, src, input)
    assert.is_false(ok)
    return err.code
  end

  it("composes two builtins, applied via ~>", function()
    assert.are.equal(225, run("($square := function($x){$x*$x}; $i := $sum ~> $square; [1..5] ~> $i())"))
  end)

  it("composes and is directly callable, left-to-right order", function()
    assert.are.equal("HELLO WORLD", run("($ut := $trim ~> $uppercase; $ut('   Hello    World   '))"))
  end)

  it("composes partially-applied functions (partial composition)", function()
    assert.are.equal(55, run("($square := function($x){$x*$x}; $ss := $map(?, $square) ~> $sum; [1..5] ~> $ss())"))
  end)

  it("re-composes (three-way, left-associative)", function()
    assert.are.equal(13, run("($inc := function($x){$x+1}; $dbl := function($x){$x*2}; $f := $inc ~> $dbl ~> $inc; $f(5))"))
  end)

  it("raises T2006 when the right side is not a function", function()
    assert.are.equal("T2006", code("42 ~> 'hello'"))
    assert.are.equal("T2006", code("($f := $sum; $f ~> 3)"))
  end)

  it("does not break the apply form (non-function lhs unchanged)", function()
    assert.are.equal("5", run("5 ~> $string"))
    assert.are.equal(6, run("[1,2,3] ~> $sum"))
    assert.are.equal("HI", run("'hi' ~> $uppercase"))
  end)
end)
