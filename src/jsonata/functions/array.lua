local V = require("jsonata.value")
local H = require("jsonata.functions.helpers")

local R = {}

R.count = H.def(function(x)
  if V.is_nothing(x) then
    return 0
  end
  if V.is_array(x) then
    return #x
  end
  return 1
end, 1)

return R
