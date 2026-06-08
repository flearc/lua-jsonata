-- cjson wrapper for the test harness.
-- Normalizes JSON null to the library's own public NULL marker so decoded
-- values flow correctly through jsonata.evaluate and compare against results.
local cjson = require("cjson")
local jsonata = require("jsonata")

local M = {}

-- Obtain the library's public null marker via the public API only
-- (jsonata.compile("null"):evaluate(nil) returns the adapter NULL marker).
M.NULL = jsonata.compile("null"):evaluate(nil)

local function replace_nulls(v)
  if v == cjson.null then
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
  return replace_nulls(cjson.decode(str))
end

return M
