local V = require("jsonata.value")

local M = {}

-- Public NULL marker returned to callers (distinct, inspectable table).
M.NULL = setmetatable({}, {
  __name = "jsonata.output.null",
  __tostring = function()
    return "null"
  end,
})

local function is_array_shape(t)
  local count = 0
  for k in pairs(t) do
    if type(k) ~= "number" then
      return false
    end
    count = count + 1
  end
  if count == 0 then
    return false -- empty table defaults to object
  end
  for i = 1, count do
    if t[i] == nil then
      return false
    end
  end
  return true
end

local function lua_key_order(t)
  local mt = getmetatable(t)
  return mt and mt.__jsonata_key_order or nil
end

function M.from_lua(x)
  if x == nil then
    return V.NOTHING
  end
  local t = type(x)
  if t ~= "table" then
    return x -- number/string/boolean unchanged
  end
  if x == M.NULL then
    return V.NULL
  end
  -- Already an internal value: pass through.
  if V.is_array(x) or V.is_object(x) or V.is_null(x) or V.is_nothing(x) then
    return x
  end
  if is_array_shape(x) then
    local arr = V.array({})
    for i = 1, #x do
      arr[i] = M.from_lua(x[i])
    end
    return arr
  end
  local obj = V.object()
  local order = lua_key_order(x)
  local seen = {}
  if order then
    for _, k in ipairs(order) do
      if x[k] ~= nil then
        seen[k] = true
        V.obj_set(obj, k, M.from_lua(x[k]))
      end
    end
  end
  for k, val in pairs(x) do
    if not seen[k] then
      V.obj_set(obj, k, M.from_lua(val))
    end
  end
  return obj
end

function M.to_lua(x)
  if V.is_nothing(x) then
    return nil
  end
  if V.is_null(x) then
    return M.NULL
  end
  if V.is_array(x) then
    local out = {}
    for i = 1, #x do
      out[i] = M.to_lua(x[i])
    end
    return out
  end
  if V.is_object(x) then
    local out = {}
    for _, k in ipairs(V.obj_keys(x)) do
      out[k] = M.to_lua(V.obj_get(x, k))
    end
    return out
  end
  return x
end

return M
