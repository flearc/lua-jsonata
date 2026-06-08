local jsonata = require("jsonata")

local function run(src, input)
  return jsonata.compile(src):evaluate(input)
end

describe("higher-order: $map / $filter", function()
  it("$map applies the callback to each element", function()
    assert.are.same({ 1, 4, 9 }, run("$map([1,2,3], function($x){ $x * $x })"))
  end)

  it("$map passes value and 0-based index to a two-arg callback", function()
    assert.are.same({ "0:a", "1:b" }, run([[$map(["a","b"], function($v, $i){ $i & ":" & $v })]]))
  end)

  it("$map with a builtin callback supplies only the value (arity introspection)", function()
    assert.are.same({ "1", "2", "3" }, run("$map([1,2,3], $string)"))
  end)

  it("$map drops nothing results, keeps surviving elements", function()
    assert.are.same({ 1, 2 }, run([[$map([{"v":1},{"v":2},{}], function($o){ $o.v })]]))
  end)

  it("$filter keeps the original element when the callback is truthy", function()
    assert.are.same({ 2, 3 }, run("$filter([0,1,2,3], function($x){ $x > 1 })"))
  end)

  it("$filter coerces a scalar to a singleton and unwraps the single result", function()
    assert.are.equal(5, run("$filter(5, function($x){ $x > 1 })"))
  end)

  it("$filter with $boolean drops falsy values", function()
    assert.are.same({ 1, 2 }, run("$filter([0,1,2], $boolean)"))
  end)

  it("$map coerces a scalar so the 3rd callback arg is a real array", function()
    assert.are.same({ 5, 99 }, run("$map(5, function($v, $i, $a){ $append($a, [99]) })"))
  end)
end)

describe("higher-order: $reduce", function()
  it("folds left with no initial value", function()
    assert.are.equal(15, run("$reduce([1,2,3,4,5], function($a,$b){ $a + $b })"))
  end)

  it("folds left with an initial value", function()
    assert.are.equal(17, run("$reduce([1,2,3,4,5], function($a,$b){ $a + $b }, 2)"))
  end)

  it("treats a scalar as a singleton sequence", function()
    assert.are.equal(1, run("$reduce(1, function($a,$b){ $a + $b })"))
  end)

  it("returns nothing for an absent sequence WITHOUT checking arity", function()
    assert.is_nil(run("$reduce(missing, function($a){ $a })", {}))
  end)

  it("raises D3050 when the reducer takes fewer than two arguments", function()
    local ok, err = pcall(run, "$reduce([1,2,3], function($a){ $a })")
    assert.is_false(ok)
    assert.are.equal("D3050", err.code)
  end)

  it("returns nothing for an empty array with no init", function()
    assert.is_nil(run("$reduce([], function($a,$b){ $a + $b })"))
  end)

  it("passes a 0-based index to a three-arg reducer", function()
    -- fold [10,20,30]: acc=10; +20+idx1=31; +30+idx2=63
    assert.are.equal(63, run("$reduce([10,20,30], function($acc,$v,$i){ $acc + $v + $i })"))
  end)
end)
