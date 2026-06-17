local V = require("jsonata.value")
local H = require("jsonata.functions.helpers")

local R = {}

R.boolean = H.def(function(x)
  return H.truthy(x)
end, 1, 1, "<x-:b>")

R["not"] = H.def(function(x)
  if V.is_nothing(x) then
    return V.NOTHING
  end
  return not H.truthy(x)
end, 1, 1, "<x-:b>")

R.exists = H.def(function(x)
  return not V.is_nothing(x)
end, 1)

return R
