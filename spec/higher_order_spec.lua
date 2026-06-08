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
