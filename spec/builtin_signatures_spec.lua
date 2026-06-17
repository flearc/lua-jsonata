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
