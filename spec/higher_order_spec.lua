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

describe("higher-order: $single", function()
  it("returns the single matching element", function()
    assert.are.equal(3, run("$single([1,2,3,4], function($x){ $x = 3 })"))
  end)

  it("raises D3138 when more than one element matches", function()
    local ok, err = pcall(run, "$single([1,2,3,4], function($x){ $x > 2 })")
    assert.is_false(ok)
    assert.are.equal("D3138", err.code)
  end)

  it("raises D3139 when no element matches", function()
    local ok, err = pcall(run, "$single([1,2,3], function($x){ $x > 9 })")
    assert.is_false(ok)
    assert.are.equal("D3139", err.code)
  end)

  it("treats a missing predicate as always-true", function()
    assert.are.equal(42, run("$single([42])"))
  end)

  it("passes value/index/array to a three-arg predicate", function()
    assert.are.equal("one", run([[$single(["zero","one","two"], function($v,$i,$a){ $i = 1 })]]))
  end)
end)

describe("higher-order: $sift / $each", function()
  it("$sift keeps key/value pairs whose value is truthy", function()
    assert.are.same({ a = 1 }, run([[$sift({"a": 1, "b": 0}, $boolean)]]))
  end)

  it("$sift passes (value, key) to a two-arg callback", function()
    assert.are.same({ Age = 28 }, run([[$sift({"Age": 28, "Name": "x"}, function($v, $k){ $k = "Age" })]]))
  end)

  it("$sift injects the current input when called with only the function", function()
    assert.are.same({ keep = "x" }, run([[$sift(function($v){ $v = "x" })]], { keep = "x", drop = "y" }))
  end)

  it("$sift returns nothing when nothing is kept", function()
    assert.is_nil(run([[$sift({"a": 0}, $boolean)]]))
  end)

  it("$each collects callback results over key/value pairs in order", function()
    assert.are.same({ "HELLO", "WORLD" }, run([[$each({"a": "hello", "b": "world"}, $uppercase)]]))
  end)

  it("$each passes (value, key) to a two-arg callback", function()
    assert.are.same({ "a1", "b2" }, run([[$each({"a": 1, "b": 2}, function($v, $k){ $k & $v })]]))
  end)

  it("$sift returns nothing (no crash) when the object arg is not an object", function()
    assert.is_nil(run("$sift(missing, $boolean)", {}))
  end)

  it("$each returns nothing (no crash) when the object arg is not an object", function()
    assert.is_nil(run("$each(missing, $uppercase)", {}))
  end)
end)

describe("higher-order: $sort", function()
  it("sorts numbers ascending (numeric, not lexicographic)", function()
    assert.are.same({ 1, 2, 3 }, run("$sort([1,3,2])"))
    assert.are.same({ 1, 3, 11, 22 }, run("$sort([1,3,22,11])"))
  end)

  it("$sort does not mutate the context array", function()
    assert.are.same({ { 1, 3, 2 }, { 1, 2, 3 }, { 1, 3, 2 } }, run("[[$], [$sort($)], [$]]", { 1, 3, 2 }))
  end)

  it("sorts strings ascending", function()
    assert.are.same({ "apple", "banana", "cherry" }, run([[$sort(["banana","apple","cherry"])]]))
  end)

  it("wraps a scalar and returns an array (no singleton unwrap)", function()
    assert.are.same({ 1 }, run("$sort(1)"))
  end)

  it("returns nothing for an absent array", function()
    assert.is_nil(run("$sort(missing)", {}))
  end)

  it("raises D3070 for an array of objects with no comparator", function()
    local ok, err = pcall(run, [[$sort([{"a":1},{"a":2}])]])
    assert.is_false(ok)
    assert.are.equal("D3070", err.code)
  end)

  it("raises D3070 for a mixed number/string array with no comparator", function()
    local ok, err = pcall(run, [[$sort([1,"x"])]])
    assert.is_false(ok)
    assert.are.equal("D3070", err.code)
  end)

  it("sorts ascending/descending with a comparator", function()
    assert.are.same({ 1, 2, 3 }, run("$sort([3,1,2], function($a,$b){ $a > $b })"))
    assert.are.same({ 3, 2, 1 }, run("$sort([3,1,2], function($a,$b){ $a < $b })"))
  end)

  it("sorts objects by a key via a comparator", function()
    assert.are.same({ 1, 3 }, run([[$sort([{"p":3},{"p":1}], function($a,$b){ $a.p > $b.p }).p]]))
  end)

  it("is stable: equal keys keep their original order", function()
    assert.are.same({ "c", "a", "b" }, run([[$sort([{"k":1,"id":"a"},{"k":1,"id":"b"},{"k":0,"id":"c"}], function($a,$b){ $a.k > $b.k }).id]]))
  end)
end)
