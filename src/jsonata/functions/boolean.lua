local V = require("jsonata.value")
local H = require("jsonata.functions.helpers")

local R = {}

R.boolean = H.def(function(x)
  return H.truthy(x)
end, 1)

R["not"] = H.def(function(x)
  return not H.truthy(x)
end, 1)

R.exists = H.def(function(x)
  return not V.is_nothing(x)
end, 1)

return R
