local V = require("jsonata.value")
local H = require("jsonata.functions.helpers")

local R = {}

local function num_guard(x)
  return V.is_nothing(x)
end

-- Parse a string to a number, supporting 0x/0o/0b radix prefixes per the
-- JSONata spec (LuaJIT's tonumber accepts 0b but not 0o; parse explicitly).
local function parse_number_string(s)
  local sign, prefix, digits = s:match("^([%+%-]?)0([xXoObB])([0-9A-Fa-f]+)$")
  if prefix then
    local base = (prefix == "x" or prefix == "X") and 16 or (prefix == "o" or prefix == "O") and 8 or 2
    local n = tonumber(digits, base)
    if n ~= nil and sign == "-" then
      n = -n
    end
    return n
  end
  return tonumber(s)
end

R.number = H.def(function(x)
  local t = V.typeof(x)
  if t == "number" then
    return x
  elseif t == "string" then
    local n = parse_number_string(x)
    if n == nil or n ~= n or n == math.huge or n == -math.huge then
      H.err("D3030", { value = x })
    end
    return n
  elseif t == "boolean" then
    return x and 1 or 0
  end
  return V.NOTHING
end, 1, 1, "<(nsb)-:n>")

R.abs = H.def(function(x)
  if num_guard(x) then
    return V.NOTHING
  end
  return math.abs(x)
end, 1, 1, "<n-:n>")

R.floor = H.def(function(x)
  if num_guard(x) then
    return V.NOTHING
  end
  return math.floor(x)
end, 1, 1, "<n-:n>")

R.ceil = H.def(function(x)
  if num_guard(x) then
    return V.NOTHING
  end
  return math.ceil(x)
end, 1, 1, "<n-:n>")

-- Round half to even (banker's rounding), with optional decimal precision.
R.round = H.def(function(x, precision)
  if num_guard(x) then
    return V.NOTHING
  end
  precision = (precision == nil or V.is_nothing(precision)) and 0 or math.floor(precision)
  local factor = 10 ^ precision
  local scaled = x * factor
  -- correct binary-float representation error before the half-even test
  scaled = tonumber(string.format("%.12g", scaled)) or scaled
  local floored = math.floor(scaled)
  local diff = scaled - floored
  local rounded
  if diff < 0.5 then
    rounded = floored
  elseif diff > 0.5 then
    rounded = floored + 1
  else
    rounded = (floored % 2 == 0) and floored or floored + 1
  end
  return rounded / factor
end, 1, 2, "<n-n?:n>")

R.power = H.def(function(base, exp)
  if num_guard(base) or num_guard(exp) then
    return V.NOTHING
  end
  return base ^ exp
end, 2, 2, "<n-n:n>")

R.sqrt = H.def(function(x)
  if num_guard(x) then
    return V.NOTHING
  end
  if x < 0 then
    H.err("D3060", { value = x, message = "$sqrt of a negative number" })
  end
  return math.sqrt(x)
end, 1, 1, "<n-:n>")

local DIGITS = "0123456789abcdefghijklmnopqrstuvwxyz"
R.formatBase = H.def(function(x, radix)
  if num_guard(x) then
    return V.NOTHING
  end
  radix = (radix == nil or V.is_nothing(radix)) and 10 or math.floor(radix)
  if radix < 2 or radix > 36 then
    H.err("D3100", { value = radix, message = "$formatBase radix out of range" })
  end
  local n = math.floor(math.abs(x))
  if n == 0 then
    return "0"
  end
  local out = {}
  while n > 0 do
    local d = n % radix
    out[#out + 1] = DIGITS:sub(d + 1, d + 1)
    n = math.floor(n / radix)
  end
  local s = string.reverse(table.concat(out))
  if x < 0 then
    s = "-" .. s
  end
  return s
end, 1, 2, "<n-n?:s>")

return R
