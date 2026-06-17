local jsonata = require("jsonata")

local function run(src, input)
  return jsonata.compile(src):evaluate(input)
end

describe("builtin signatures: chokepoint wiring (no signatures yet)", function()
  it("unsigned builtins still work through M.apply", function()
    assert.are.equal(6, run("$sum([1,2,3])"))
    assert.are.equal("HELLO", run('$uppercase("hello")'))
    assert.are.equal(3, run("$count([1,2,3])"))
  end)

  it("H.def still attaches a signature field when given one", function()
    local H = require("jsonata.functions.helpers")
    local def = H.def(function(x)
      return x
    end, 1, 1, "<n:n>")
    assert.is_not_nil(def.signature)
    assert.is_function(def.signature.validate)
    local plain = H.def(function(x)
      return x
    end, 1)
    assert.is_nil(plain.signature)
  end)
end)

describe("builtin signatures: $sift / $each context injection via '-'", function()
  it("$sift bare form injects the context object", function()
    local data = { a = 1, b = 2, c = 3 }
    local r = run("$sift(λ($v)<n:b>{$v > 1})", data)
    assert.are.equal(2, r.b)
    assert.are.equal(3, r.c)
    assert.is_nil(r.a)
  end)

  it("$sift explicit form still works", function()
    local data = { o = { a = 1, b = 2 } }
    local r = run("$sift(o, λ($v)<n:b>{$v > 1})", data)
    assert.are.equal(2, r.b)
  end)

  it("$each bare form injects the context object", function()
    local data = { a = 1, b = 2 }
    assert.are.same({ 1, 2 }, run("$sort($each(λ($v)<n:n>{$v}))", data))
  end)

  it("$sift on a non-object context raises T0411", function()
    local ok, err = pcall(run, "$sift(λ($v)<n:b>{true})", 5)
    assert.is_false(ok)
    assert.are.equal("T0411", err.code)
  end)
end)

describe("builtin signatures: '-' string/URL", function()
  local function code(src)
    local ok, err = pcall(run, src)
    assert.is_false(ok)
    return err.code
  end

  it("rejects a wrong-typed arg with T0410", function()
    assert.are.equal("T0410", code("$uppercase(5)"))
    assert.are.equal("T0410", code("$length([1,2])"))
    assert.are.equal("T0410", code('$substring("abc", "x")'))
    assert.are.equal("T0410", code('$pad("x", "y")'))
    assert.are.equal("T0410", code("$encodeUrl(5)"))
  end)

  it("injects the context for a '-' first param", function()
    assert.are.equal("HELLO", run("$uppercase()", "hello"))
    assert.are.equal(5, run("$length()", "hello"))
    assert.are.equal("ell", run("$substring(1, 3)", "hello"))
  end)

  it("raises T0411 when the context is the wrong type", function()
    local ok, err = pcall(run, "$uppercase()", 5)
    assert.is_false(ok)
    assert.are.equal("T0411", err.code)
  end)

  it("propagates undefined (NOTHING in -> NOTHING out)", function()
    assert.is_nil(run("nope.$uppercase()", {}))
    assert.is_nil(run("$string(nope)", {}))
  end)

  it("still computes normally", function()
    assert.are.equal("HI", run('$uppercase("hi")'))
    assert.are.equal(" xx", run('$pad("xx", -3)'))
    assert.are.equal("a%20b", run('$encodeUrl("a b")'))
  end)
end)

describe("builtin signatures: '-' numeric + object/boolean", function()
  local function code(src, input)
    local ok, err = pcall(run, src, input)
    assert.is_false(ok)
    return err.code
  end

  it("numeric builtins reject non-numbers with T0410", function()
    assert.are.equal("T0410", code('$abs("x")'))
    assert.are.equal("T0410", code('$floor("x")'))
    assert.are.equal("T0410", code('$power("x", 2)'))
    assert.are.equal("T0410", code("$number([1,2])"))
  end)

  it("numeric builtins inject context + propagate undefined", function()
    assert.are.equal(5, run("$abs()", -5))
    assert.is_nil(run("nope.$abs()", {}))
  end)

  it("$number coerces a string/boolean and the context", function()
    assert.are.equal(42, run('$number("42")'))
    assert.are.equal(1, run("$number(true)"))
    assert.are.equal(7, run("$number()", "7"))
  end)

  it("$lookup requires a string key (T0410)", function()
    assert.are.equal("T0410", code("$lookup({}, 5)"))
  end)

  it("$keys injects the context object", function()
    assert.are.same({ "a", "b" }, run("$sort($keys())", { a = 1, b = 2 }))
  end)

  it("$not returns undefined on undefined (not true)", function()
    assert.is_nil(run("$not(nope)", {}))
    assert.is_true(run("$not(false)"))
  end)
end)

describe("builtin signatures: non-'-' subtypes", function()
  local function code(src)
    local ok, err = pcall(run, src)
    assert.is_false(ok)
    return err.code
  end

  it("aggregates raise T0412 on a non-number element", function()
    assert.are.equal("T0412", code('$sum([1, "x"])'))
    assert.are.equal("T0412", code('$max([1, "x"])'))
  end)

  it("aggregates still compute (incl. scalar coercion)", function()
    assert.are.equal(6, run("$sum([1,2,3])"))
    assert.are.equal(5, run("$sum(5)"))
    assert.are.equal(3, run("$max([1,2,3])"))
  end)

  it("$join requires an array of strings (T0412)", function()
    assert.are.equal("T0412", code("$join([1,2])"))
  end)

  it("$join treats an undefined separator as empty (case011/012)", function()
    assert.are.equal("ab", run('$join(["a","b"])'))
    assert.are.equal("ab", run('λ($a,$sep)<a<s>s?:s>{$join($a,$sep)}(["a","b"])'))
  end)

  it("$merge requires an array of objects", function()
    local r = run('$merge([{"a":1},{"b":2}])')
    assert.are.equal(1, r.a)
    assert.are.equal(2, r.b)
    assert.are.equal("T0412", code("$merge([1,2])"))
  end)

  it("$assert rejects a non-boolean condition with T0410", function()
    assert.are.equal("T0410", code('$assert(5, "msg")'))
  end)

  it("$exists works with its signature", function()
    assert.is_true(run("$exists(foo)", { foo = 1 }))
    assert.is_false(run("$exists(foo)", {}))
  end)
end)
