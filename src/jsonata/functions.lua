local V = require("jsonata.value")
local errors = require("jsonata.errors")

local M = {}

local function def(impl, arity)
  return { _jsonata_function = true, impl = impl, arity = arity }
end

-- JSONata truthiness rules.
local function truthy(x)
  if V.is_nothing(x) then
    return false
  end
  local t = V.typeof(x)
  if t == "boolean" then
    return x
  elseif t == "string" then
    return #x > 0
  elseif t == "number" then
    return x ~= 0
  elseif t == "null" then
    return false
  elseif t == "array" then
    if #x == 0 then
      return false
    end
    for i = 1, #x do
      if truthy(x[i]) then
        return true
      end
    end
    return false
  elseif t == "object" then
    return #V.obj_keys(x) > 0
  end
  return false
end
M.truthy = truthy

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
    -- Integers render without a trailing .0
    if x == math.floor(x) and x == x and x ~= math.huge and x ~= -math.huge then
      return string.format("%d", x)
    end
    return tostring(x)
  end
  if t == "array" or t == "object" then
    errors.raise("D3001", { value = x, message = "$string of array/object is not supported in M1" })
  end
  return tostring(x)
end

M.string = def(function(x)
  return to_string(x)
end, 1)

M.number = def(function(x)
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

M.boolean = def(function(x)
  return truthy(x)
end, 1)

M["not"] = def(function(x)
  return not truthy(x)
end, 1)

M.exists = def(function(x)
  return not V.is_nothing(x)
end, 1)

M.count = def(function(x)
  if V.is_nothing(x) then
    return 0
  end
  if V.is_array(x) then
    return #x
  end
  return 1
end, 1)

-- Registry name -> def, used by environment to populate the static frame.
M.registry = {
  string = M.string,
  number = M.number,
  boolean = M.boolean,
  ["not"] = M["not"],
  exists = M.exists,
  count = M.count,
}

return M
