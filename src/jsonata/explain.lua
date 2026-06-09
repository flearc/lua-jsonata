local V = require("jsonata.value")

local M = {}

-- Render an INTERNAL tagged value to a compact one-line string.
-- Order matters: sentinels are tables, and empty seq/array/object are all empty
-- tables distinguished only by metatable, so check sentinels first and
-- sequence-before-array. Uses value.lua predicates (NOT adapter.to_lua) to
-- preserve null/nothing/seq-vs-array/object-order distinctions.
local function render_value(x, seen)
  if V.is_nothing(x) then
    return "*nothing*"
  end
  if V.is_null(x) then
    return "null"
  end
  local tx = type(x)
  if tx ~= "table" then
    if tx == "string" then
      return string.format("%q", x)
    end
    if tx == "number" then
      if x == x and x ~= math.huge and x ~= -math.huge and x == math.floor(x) then
        return string.format("%.0f", x)
      end
      return tostring(x)
    end
    return tostring(x) -- boolean / other
  end
  if x._jsonata_lambda then
    return "<lambda>"
  end
  if x._jsonata_function then
    return "<function>"
  end
  seen = seen or {}
  if seen[x] then
    return "<cycle>"
  end
  seen[x] = true
  local out
  if V.is_sequence(x) then
    local parts = {}
    for i = 1, #x do
      parts[i] = render_value(x[i], seen)
    end
    out = "<seq:[" .. table.concat(parts, ", ") .. "]>"
  elseif V.is_array(x) then
    local parts = {}
    for i = 1, #x do
      parts[i] = render_value(x[i], seen)
    end
    out = "[" .. table.concat(parts, ", ") .. "]"
  elseif V.is_object(x) then
    local parts = {}
    local keys = V.obj_keys(x)
    for i = 1, #keys do
      local k = keys[i]
      parts[i] = tostring(k) .. ": " .. render_value(x.map[k], seen)
    end
    out = "{" .. table.concat(parts, ", ") .. "}"
  else
    out = "<" .. tostring(x) .. ">"
  end
  seen[x] = nil
  return out
end

M._render_value = render_value

return M
