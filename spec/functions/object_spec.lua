local F = require("jsonata.functions")
local V = require("jsonata.value")

local function obj(pairs)
  local o = V.object()
  for _, kv in ipairs(pairs) do
    V.obj_set(o, kv[1], kv[2])
  end
  return o
end

describe("object functions", function()
  it("$keys returns keys in order", function()
    local r = F.keys.impl(obj({ { "b", 1 }, { "a", 2 } }))
    assert.are.same({ "b", "a" }, { r[1], r[2] })
  end)

  it("$lookup fetches a key", function()
    assert.are.equal(2, F.lookup.impl(obj({ { "a", 2 } }), "a"))
    assert.is_true(V.is_nothing(F.lookup.impl(obj({ { "a", 2 } }), "z")))
  end)

  it("$merge merges objects, later wins, order preserved", function()
    local merged = F.merge.impl(V.array({ obj({ { "a", 1 } }), obj({ { "b", 2 }, { "a", 9 } }) }))
    assert.are.same({ "a", "b" }, V.obj_keys(merged))
    assert.are.equal(9, V.obj_get(merged, "a"))
  end)

  it("$type classifies values", function()
    assert.are.equal("string", F.type.impl("s"))
    assert.are.equal("number", F.type.impl(3))
    assert.are.equal("array", F.type.impl(V.array({})))
    assert.are.equal("null", F.type.impl(V.NULL))
  end)

  it("$string serializes containers", function()
    assert.are.equal("[1,2]", F.string.impl(V.array({ 1, 2 })))
    assert.are.equal('{"a":1}', F.string.impl(obj({ { "a", 1 } })))
  end)
end)
