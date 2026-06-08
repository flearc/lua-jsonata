-- Exact deep-equality for the test harness (jsonata-cpp philosophy: no epsilon).
-- new(null_marker) -> equal(actual, expected, unordered)
local M = {}

local function kind(t)
  local n = 0
  local has_string = false
  for k in pairs(t) do
    n = n + 1
    if type(k) ~= "number" then
      has_string = true
    end
  end
  if n == 0 then
    return "empty"
  end
  if has_string then
    return "object"
  end
  for i = 1, n do
    if t[i] == nil then
      return "object"
    end
  end
  return "array"
end

function M.new(null_marker)
  local equal
  equal = function(a, b, unordered)
    if a == b then
      return true
    end
    -- The null marker is an empty table; compare it by identity only so it is
    -- never confused with an empty container.
    if a == null_marker or b == null_marker then
      return false
    end
    if type(a) ~= "table" or type(b) ~= "table" then
      return false -- scalars: exact (== above), nothing else is equal
    end
    local ka, kb = kind(a), kind(b)
    if ka == "empty" or kb == "empty" then
      return ka == "empty" and kb == "empty" -- both empty: equal (documented limitation)
    end
    if ka ~= kb then
      return false
    end
    if ka == "array" then
      if #a ~= #b then
        return false
      end
      if unordered then
        local used = {}
        for i = 1, #a do
          local found = false
          for j = 1, #b do
            if not used[j] and equal(a[i], b[j], false) then
              used[j] = true
              found = true
              break
            end
          end
          if not found then
            return false
          end
        end
        return true
      end
      for i = 1, #a do
        if not equal(a[i], b[i], false) then
          return false
        end
      end
      return true
    end
    -- object: same key set, recursive (order-independent)
    for k, v in pairs(a) do
      if not equal(v, b[k], false) then
        return false
      end
    end
    for k in pairs(b) do
      if a[k] == nil then
        return false
      end
    end
    return true
  end
  return equal
end

return M
