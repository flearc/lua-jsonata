local V = require("jsonata.value")
local errors = require("jsonata.errors")

local H = {}

function H.def(impl, arity)
  return { _jsonata_function = true, impl = impl, arity = arity }
end

-- JSONata truthiness (migrated unchanged from M1 functions.lua).
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
H.truthy = truthy

-- Render a JSON number the JSONata way: integer-valued -> no trailing ".0".
function H.num_to_str(x)
  if x == math.floor(x) and x == x and x ~= math.huge and x ~= -math.huge then
    return string.format("%d", x)
  end
  return tostring(x)
end

-- Split a UTF-8 string into an array of single-codepoint substrings.
function H.utf8_chars(s)
  local chars = {}
  local i, n = 1, #s
  while i <= n do
    local b = s:byte(i)
    local len = 1
    if b >= 0xF0 then
      len = 4
    elseif b >= 0xE0 then
      len = 3
    elseif b >= 0xC0 then
      len = 2
    end
    chars[#chars + 1] = s:sub(i, i + len - 1)
    i = i + len
  end
  return chars
end

function H.utf8_len(s)
  return #H.utf8_chars(s)
end

-- Raise a JSONata runtime error.
function H.err(code, info)
  errors.raise(code, info or {})
end

return H
