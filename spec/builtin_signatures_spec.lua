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
