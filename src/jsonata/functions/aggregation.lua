local V = require("jsonata.value")
local H = require("jsonata.functions.helpers")

local R = {}

-- Coerce the argument to a Lua list of numbers, or raise D3047.
local function numbers(x)
  if V.is_nothing(x) then
    return nil
  end
  local items
  if V.is_array(x) then
    items = {}
    for i = 1, #x do
      items[i] = x[i]
    end
  else
    items = { x }
  end
  for _, v in ipairs(items) do
    if V.typeof(v) ~= "number" then
      H.err("D3047", { value = v, message = "aggregate of a non-number" })
    end
  end
  return items
end

R.sum = H.def(function(x)
  local nums = numbers(x)
  if nums == nil then
    return V.NOTHING
  end
  local total = 0
  for _, v in ipairs(nums) do
    total = total + v
  end
  return total
end, 1, 1, "<a<n>:n>")

R.max = H.def(function(x)
  local nums = numbers(x)
  if nums == nil or #nums == 0 then
    return V.NOTHING
  end
  local m = nums[1]
  for i = 2, #nums do
    if nums[i] > m then
      m = nums[i]
    end
  end
  return m
end, 1, 1, "<a<n>:n>")

R.min = H.def(function(x)
  local nums = numbers(x)
  if nums == nil or #nums == 0 then
    return V.NOTHING
  end
  local m = nums[1]
  for i = 2, #nums do
    if nums[i] < m then
      m = nums[i]
    end
  end
  return m
end, 1, 1, "<a<n>:n>")

R.average = H.def(function(x)
  local nums = numbers(x)
  if nums == nil or #nums == 0 then
    return V.NOTHING
  end
  local total = 0
  for _, v in ipairs(nums) do
    total = total + v
  end
  return total / #nums
end, 1, 1, "<a<n>:n>")

return R
