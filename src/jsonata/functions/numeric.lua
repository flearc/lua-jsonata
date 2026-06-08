local V = require("jsonata.value")
local H = require("jsonata.functions.helpers")

local R = {}

R.number = H.def(function(x)
  local t = V.typeof(x)
  if t == "number" then
    return x
  elseif t == "string" then
    local n = tonumber(x)
    if n == nil then
      return V.NOTHING
    end
    return n
  elseif t == "boolean" then
    return x and 1 or 0
  end
  return V.NOTHING
end, 1)

return R
