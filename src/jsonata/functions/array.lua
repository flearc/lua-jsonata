local V = require("jsonata.value")
local H = require("jsonata.functions.helpers")

local R = {}

local function as_list(x)
  if V.is_nothing(x) then
    return {}
  end
  if V.is_array(x) then
    local t = {}
    for i = 1, #x do
      t[i] = x[i]
    end
    return t
  end
  return { x }
end

R.count = H.def(function(x)
  if V.is_nothing(x) then
    return 0
  end
  if V.is_array(x) then
    return #x
  end
  return 1
end, 1)

R.append = H.def(function(a, b)
  if V.is_nothing(a) then
    return b
  end
  if V.is_nothing(b) then
    return a
  end
  local out = V.array({})
  for _, v in ipairs(as_list(a)) do
    out[#out + 1] = v
  end
  for _, v in ipairs(as_list(b)) do
    out[#out + 1] = v
  end
  return out
end, 2)

R.reverse = H.def(function(x)
  if V.is_nothing(x) then
    return V.NOTHING
  end
  local list = as_list(x)
  local out = V.array({})
  for i = #list, 1, -1 do
    out[#out + 1] = list[i]
  end
  return out
end, 1)

R.distinct = H.def(function(x)
  if V.is_nothing(x) then
    return V.NOTHING
  end
  if not V.is_array(x) then
    return x
  end
  local out = V.array({})
  for i = 1, #x do
    local seen = false
    for j = 1, #out do
      if H.deep_equal(x[i], out[j]) then
        seen = true
        break
      end
    end
    if not seen then
      out[#out + 1] = x[i]
    end
  end
  return out
end, 1)

R.shuffle = H.def(function(x)
  if V.is_nothing(x) then
    return V.NOTHING
  end
  local list = as_list(x)
  for i = #list, 2, -1 do
    local j = math.random(i)
    list[i], list[j] = list[j], list[i]
  end
  local out = V.array({})
  for _, v in ipairs(list) do
    out[#out + 1] = v
  end
  return out
end, 1)

R.zip = H.def(function(...)
  local arrays = { ... }
  local n = select("#", ...)
  if n == 0 then
    return V.array({})
  end
  local minlen = math.huge
  for i = 1, n do
    minlen = math.min(minlen, #as_list(arrays[i]))
  end
  local out = V.array({})
  for i = 1, minlen do
    local tuple = V.array({})
    for k = 1, n do
      tuple[k] = as_list(arrays[k])[i]
    end
    out[i] = tuple
  end
  return out
end, nil)

return R
