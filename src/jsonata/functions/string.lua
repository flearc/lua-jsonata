local V = require("jsonata.value")
local H = require("jsonata.functions.helpers")

local R = {}

-- M1 scalar $string (container serialization added in Task 7).
local function to_string(x)
  if V.is_nothing(x) then
    return ""
  end
  if V.is_null(x) then
    return "null"
  end
  local t = V.typeof(x)
  if t == "string" then
    return x
  elseif t == "boolean" then
    return x and "true" or "false"
  elseif t == "number" then
    return H.num_to_str(x)
  end
  H.err("D3001", { value = x, message = "$string of array/object not yet supported" })
end
R._to_string = to_string

R.string = H.def(function(x)
  return to_string(x)
end, 1)

return R
