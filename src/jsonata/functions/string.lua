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
  -- arrays/objects: JSON serialization
  return H.serialize(x)
end
R._to_string = to_string

R.string = H.def(function(x, prettify)
  if V.is_nothing(x) then
    return V.NOTHING
  end
  return to_string(x)
end, 1, 2, "<x-b?:s>")

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
  if V.is_nothing(s) then
    return V.NOTHING
  end
  return H.utf8_len(s)
end, 1, 1, "<s-:n>")

R.substring = H.def(function(s, start, length)
  if V.is_nothing(s) then
    return V.NOTHING
  end
  local chars = H.utf8_chars(s)
  local n = #chars
  start = math.floor(start)
  if start < 0 then
    start = math.max(n + start, 0)
  end
  local stop
  if length == nil or V.is_nothing(length) then
    stop = n
  else
    stop = math.min(start + math.max(math.floor(length), 0), n)
  end
  local out = {}
  for i = start + 1, stop do
    out[#out + 1] = chars[i]
  end
  return table.concat(out)
end, 2, 3, "<s-nn?:s>")

R.substringBefore = H.def(function(s, pattern)
  if V.is_nothing(s) then
    return V.NOTHING
  end
  local idx = string.find(s, pattern, 1, true)
  if not idx then
    return s
  end
  return s:sub(1, idx - 1)
end, 2, 2, "<s-s:s>")

R.substringAfter = H.def(function(s, pattern)
  if V.is_nothing(s) then
    return V.NOTHING
  end
  local idx = string.find(s, pattern, 1, true)
  if not idx then
    return s
  end
  return s:sub(idx + #pattern)
end, 2, 2, "<s-s:s>")

R.uppercase = H.def(function(s)
  if V.is_nothing(s) then
    return V.NOTHING
  end
  return string.upper(s)
end, 1, 1, "<s-:s>")

R.lowercase = H.def(function(s)
  if V.is_nothing(s) then
    return V.NOTHING
  end
  return string.lower(s)
end, 1, 1, "<s-:s>")

R.trim = H.def(function(s)
  if V.is_nothing(s) then
    return V.NOTHING
  end
  s = s:gsub("%s+", " ")
  s = s:gsub("^ ", ""):gsub(" $", "")
  return s
end, 1, 1, "<s-:s>")

R.pad = H.def(function(s, width, char)
  if nothing_guard(s) then
    return V.NOTHING
  end
  char = (char == nil or V.is_nothing(char) or char == "") and " " or char
  width = math.floor(width)
  local len = H.utf8_len(s)
  local need = math.abs(width) - len
  if need <= 0 then
    return s
  end
  local pad_chars = H.utf8_chars(char)
  local built = {}
  for k = 1, need do
    built[k] = pad_chars[((k - 1) % #pad_chars) + 1]
  end
  local padding = table.concat(built)
  if width < 0 then
    return padding .. s
  end
  return s .. padding
end, 2, 3, "<s-ns?:s>")

R.contains = H.def(function(s, sub)
  if not require_string(s, "contains", 1) then
    return V.NOTHING
  end
  if H.is_regex(sub) then
    return not V.is_nothing(H.apply(sub, { s }))
  end
  require_string(sub, "contains", 2)
  return string.find(s, sub, 1, true) ~= nil
end, 2, 2, "<s-(sf):b>")

R.split = H.def(function(s, sep, limit)
  if not require_string(s, "split", 1) then
    return V.NOTHING
  end
  if limit == nil or V.is_nothing(limit) then
    limit = nil
  else
    if V.typeof(limit) ~= "number" then
      H.err("T0410", { name = "split", position = 3, value = limit })
    end
    if limit < 0 then
      H.err("D3020", { name = "split", position = 3, value = limit })
    end
  end
  local result = V.array({})
  if H.is_regex(sep) then
    local pos = 0 -- 0-based char index into s
    while true do
      local m = H.apply(sep, { string.sub(s, pos + 1) })
      if V.is_nothing(m) then
        break
      end
      local mstart = pos + V.obj_get(m, "start")
      local mend = pos + V.obj_get(m, "end")
      result[#result + 1] = string.sub(s, pos + 1, mstart)
      pos = mend
      if mend == mstart then -- zero-width match guard
        pos = pos + 1
      end
    end
    result[#result + 1] = string.sub(s, pos + 1)
  else
    if sep ~= nil and V.typeof(sep) ~= "string" then
      H.err("T0410", { name = "split", position = 2, value = sep })
    end
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
  end
  if limit ~= nil then
    local trimmed = V.array({})
    for i = 1, math.min(#result, math.floor(limit)) do
      trimmed[i] = result[i]
    end
    return trimmed
  end
  return result
end, 2, 3, "<s-(sf)n?:a<s>>")

R.match = H.def(function(s, regex, limit)
  if not require_string(s, "match", 1) then
    return V.NOTHING
  end
  if not (limit == nil or V.is_nothing(limit)) and limit < 0 then
    H.err("D3040", { name = "match", position = 3, value = limit })
  end
  local result = V.array({})
  if limit == nil or V.is_nothing(limit) or limit > 0 then
    local count = 0
    local m = H.apply(regex, { s })
    while not V.is_nothing(m) and (limit == nil or V.is_nothing(limit) or count < limit) do
      local obj = V.object()
      V.obj_set(obj, "match", V.obj_get(m, "match"))
      V.obj_set(obj, "index", V.obj_get(m, "start"))
      V.obj_set(obj, "groups", V.obj_get(m, "groups"))
      result[#result + 1] = obj
      m = H.apply(V.obj_get(m, "next"), {})
      count = count + 1
    end
  end
  -- jsonata returns a sequence: 0 -> undefined, 1 -> the bare object, N -> array
  if #result == 0 then
    return V.NOTHING
  elseif #result == 1 then
    return result[1]
  end
  return result
end, 2, 3, "<s-f<s:o>n?:a<o>>")

R.join = H.def(function(arr, sep)
  if nothing_guard(arr) then
    return V.NOTHING
  end
  if V.is_nothing(sep) then
    sep = ""
  end
  local parts = {}
  for i = 1, #arr do
    parts[i] = arr[i]
  end
  return table.concat(parts, sep)
end, 1, 2, "<a<s>s?:s>")

-- Percent-encode every byte not in `unreserved`.
local function percent_encode(s, unreserved)
  return (s:gsub("[^" .. unreserved .. "]", function(c)
    return string.format("%%%02X", string.byte(c))
  end))
end

local function percent_decode(s)
  return (s:gsub("%%(%x%x)", function(hex)
    return string.char(tonumber(hex, 16))
  end))
end

-- Component: encode everything except RFC3986 unreserved.
local COMPONENT_UNRESERVED = "%w%-%_%.%!%~%*%'%(%)"
-- Full URL: also keep reserved/delimiter chars.
local URL_UNRESERVED = COMPONENT_UNRESERVED .. "%;%,%/%?%:%@%&%=%+%$%#%[%]"

R.encodeUrlComponent = H.def(function(s)
  if V.is_nothing(s) then
    return V.NOTHING
  end
  return percent_encode(s, COMPONENT_UNRESERVED)
end, 1, 1, "<s-:s>")

R.encodeUrl = H.def(function(s)
  if V.is_nothing(s) then
    return V.NOTHING
  end
  return percent_encode(s, URL_UNRESERVED)
end, 1, 1, "<s-:s>")

R.decodeUrlComponent = H.def(function(s)
  if V.is_nothing(s) then
    return V.NOTHING
  end
  return percent_decode(s)
end, 1, 1, "<s-:s>")

R.decodeUrl = H.def(function(s)
  if V.is_nothing(s) then
    return V.NOTHING
  end
  return percent_decode(s)
end, 1, 1, "<s-:s>")

return R
