local V = require("jsonata.value")
local H = require("jsonata.functions.helpers")

local R = {}

-- M1 scalar $string (container serialization added in Task 7).
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
    return H.num_to_str(x)
  end
  H.err("D3001", { value = x, message = "$string of array/object not yet supported" })
end
R._to_string = to_string

R.string = H.def(function(x)
  return to_string(x)
end, 1)

local function nothing_guard(x)
  return V.is_nothing(x)
end

-- Raise T0410 if x is not a string (and not NOTHING).
local function require_string(x, fname, pos)
  if V.is_nothing(x) then
    return false -- caller should return NOTHING
  end
  if V.typeof(x) ~= "string" then
    H.err("T0410", { name = fname, position = pos or 1, value = x })
  end
  return true
end

-- Raise T0410 if x is not a number (and not NOTHING/nil).
local function require_number(x, fname, pos)
  if x == nil or V.is_nothing(x) then
    return false
  end
  if V.typeof(x) ~= "number" then
    H.err("T0410", { name = fname, position = pos or 2, value = x })
  end
  return true
end

R.length = H.def(function(s)
  if not require_string(s, "length", 1) then
    return V.NOTHING
  end
  return H.utf8_len(s)
end, 1)

R.substring = H.def(function(s, start, length)
  if not require_string(s, "substring", 1) then
    return V.NOTHING
  end
  require_number(start, "substring", 2)
  require_number(length, "substring", 3)
  local chars = H.utf8_chars(s)
  local n = #chars
  start = math.floor(start)
  if start < 0 then
    start = math.max(n + start, 0)
  end
  local stop
  if length == nil then
    stop = n
  else
    stop = math.min(start + math.max(math.floor(length), 0), n)
  end
  local out = {}
  for i = start + 1, stop do
    out[#out + 1] = chars[i]
  end
  return table.concat(out)
end, 3)

R.substringBefore = H.def(function(s, pattern)
  if not require_string(s, "substringBefore", 1) then
    return V.NOTHING
  end
  require_string(pattern, "substringBefore", 2)
  local idx = string.find(s, pattern, 1, true)
  if not idx then
    return s
  end
  return s:sub(1, idx - 1)
end, 2)

R.substringAfter = H.def(function(s, pattern)
  if not require_string(s, "substringAfter", 1) then
    return V.NOTHING
  end
  require_string(pattern, "substringAfter", 2)
  local idx = string.find(s, pattern, 1, true)
  if not idx then
    return s
  end
  return s:sub(idx + #pattern)
end, 2)

R.uppercase = H.def(function(s)
  if not require_string(s, "uppercase", 1) then
    return V.NOTHING
  end
  return string.upper(s)
end, 1)

R.lowercase = H.def(function(s)
  if not require_string(s, "lowercase", 1) then
    return V.NOTHING
  end
  return string.lower(s)
end, 1)

R.trim = H.def(function(s)
  if not require_string(s, "trim", 1) then
    return V.NOTHING
  end
  s = s:gsub("%s+", " ")
  s = s:gsub("^ ", ""):gsub(" $", "")
  return s
end, 1)

R.pad = H.def(function(s, width, char)
  if not require_string(s, "pad", 1) then
    return V.NOTHING
  end
  require_number(width, "pad", 2)
  char = (char == nil or char == "") and " " or char
  width = math.floor(width)
  local len = H.utf8_len(s)
  local need = math.abs(width) - len
  if need <= 0 then
    return s
  end
  local padding = string.rep(char, need)
  if width < 0 then
    return padding .. s
  end
  return s .. padding
end, 3)

R.contains = H.def(function(s, sub)
  if not require_string(s, "contains", 1) then
    return V.NOTHING
  end
  require_string(sub, "contains", 2)
  return string.find(s, sub, 1, true) ~= nil
end, 2)

R.split = H.def(function(s, sep, limit)
  if not require_string(s, "split", 1) then
    return V.NOTHING
  end
  if limit ~= nil then
    if V.typeof(limit) ~= "number" then
      H.err("T0410", { name = "split", position = 3, value = limit })
    end
    if limit < 0 then
      H.err("D3020", { name = "split", position = 3, value = limit })
    end
  end
  local result = V.array({})
  if sep == "" then
    for _, ch in ipairs(H.utf8_chars(s)) do
      result[#result + 1] = ch
    end
  else
    local pos = 1
    while true do
      local i = string.find(s, sep, pos, true)
      if not i then
        result[#result + 1] = s:sub(pos)
        break
      end
      result[#result + 1] = s:sub(pos, i - 1)
      pos = i + #sep
    end
  end
  if limit ~= nil then
    local trimmed = V.array({})
    for i = 1, math.min(#result, math.floor(limit)) do
      trimmed[i] = result[i]
    end
    return trimmed
  end
  return result
end, 3)

R.join = H.def(function(arr, sep)
  if nothing_guard(arr) then
    return V.NOTHING
  end
  if not V.is_array(arr) then
    H.err("T0412", { name = "join", position = 1, value = arr })
  end
  -- All elements must be strings
  for i = 1, #arr do
    if V.typeof(arr[i]) ~= "string" then
      H.err("T0412", { name = "join", position = 1, value = arr })
    end
  end
  if sep ~= nil and V.typeof(sep) ~= "string" then
    H.err("T0410", { name = "join", position = 2, value = sep })
  end
  sep = sep or ""
  local parts = {}
  for i = 1, #arr do
    parts[i] = arr[i]
  end
  return table.concat(parts, sep)
end, 2)

return R
