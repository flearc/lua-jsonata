-- JSON wrapper for the test harness.
-- Normalizes JSON null to the library's own public NULL marker so decoded
-- values flow correctly through jsonata.evaluate and compare against results.
local dkjson = require("dkjson")
local jsonata = require("jsonata")

local M = {}

-- Obtain the library's public null marker via the public API only
-- (jsonata.compile("null"):evaluate(nil) returns the adapter NULL marker).
M.NULL = jsonata.compile("null"):evaluate(nil)

local function ordered_object_newindex(t, k, v)
  local mt = getmetatable(t)
  if not mt.__jsonata_key_order then
    mt = {
      __jsontype = "object",
      __newindex = ordered_object_newindex,
      __jsonata_key_order = {},
    }
    setmetatable(t, mt)
  end
  local order = getmetatable(t).__jsonata_key_order
  order[#order + 1] = k
  rawset(t, k, v)
end

local OBJECT_META = {
  __jsontype = "object",
  __newindex = ordered_object_newindex,
}

local ARRAY_META = {
  __jsontype = "array",
}

local function replace_nulls(v)
  if v == dkjson.null then
    return M.NULL
  end
  if type(v) == "table" then
    for k, val in pairs(v) do
      v[k] = replace_nulls(val)
    end
  end
  return v
end

-- Decode a JSON string; JSON null becomes M.NULL throughout.
function M.decode(str)
  local value, _, err = dkjson.decode(str, 1, dkjson.null, OBJECT_META, ARRAY_META)
  if err then
    error(err, 2)
  end
  return replace_nulls(value)
end

return M
