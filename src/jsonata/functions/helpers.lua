local V = require("jsonata.value")
local errors = require("jsonata.errors")

local H = {}

-- Lazily reach the evaluator's apply (avoids a load-time require cycle:
-- evaluator -> functions -> helpers -> evaluator). Memoized, so cheap.
local eval
function H.apply(proc, args, context)
  eval = eval or require("jsonata.evaluator")
  return eval.apply(proc, args, context)
end

-- A regex literal evaluates to a callable function value tagged `regex = true`.
function H.is_regex(x)
  return type(x) == "table" and x._jsonata_function and x.regex or false
end

-- def(impl)            -> any number of args
-- def(impl, n)         -> exactly n          (max defaults to min)
-- def(impl, min, max)  -> between min and max (inclusive)
-- arity = number of REQUIRED args (= min); nil means unconstrained/variadic.
-- Mirrors jsonata getFunctionArity (implementation.length). HOFs read this to
-- decide how many of (value,index,array) to pass a callback.
function H.def(impl, min, max, sig)
  local signature = sig and require("jsonata.signature").parse(sig) or nil
  if min == nil then
    return { _jsonata_function = true, impl = impl, arity = nil, signature = signature }
  end
  max = max or min
  local checked = function(...)
    local n = select("#", ...)
    if n < min or n > max then
      errors.raise("T0410", { value = n })
    end
    return impl(...)
  end
  return { _jsonata_function = true, impl = checked, arity = min, signature = signature }
end

-- JSONata truthiness (migrated unchanged from M1 functions.lua).
local function truthy(x)
  if type(x) == "table" and (x._jsonata_lambda or x._jsonata_function) then
    return false
  end
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

-- UTF-8 decode a single-codepoint character string -> codepoint number.
function H.codepoint(ch)
  local b1 = ch:byte(1)
  if not b1 then
    return nil
  end
  if b1 < 0x80 then
    return b1
  elseif b1 < 0xE0 then
    return (b1 - 0xC0) * 0x40 + (ch:byte(2) - 0x80)
  elseif b1 < 0xF0 then
    return (b1 - 0xE0) * 0x1000 + (ch:byte(2) - 0x80) * 0x40 + (ch:byte(3) - 0x80)
  else
    return (b1 - 0xF0) * 0x40000 + (ch:byte(2) - 0x80) * 0x1000 + (ch:byte(3) - 0x80) * 0x40 + (ch:byte(4) - 0x80)
  end
end

-- UTF-8 encode a codepoint number -> string.
function H.from_codepoint(cp)
  if cp < 0x80 then
    return string.char(cp)
  elseif cp < 0x800 then
    return string.char(0xC0 + math.floor(cp / 0x40), 0x80 + (cp % 0x40))
  elseif cp < 0x10000 then
    return string.char(0xE0 + math.floor(cp / 0x1000), 0x80 + (math.floor(cp / 0x40) % 0x40), 0x80 + (cp % 0x40))
  else
    return string.char(0xF0 + math.floor(cp / 0x40000), 0x80 + (math.floor(cp / 0x1000) % 0x40), 0x80 + (math.floor(cp / 0x40) % 0x40), 0x80 + (cp % 0x40))
  end
end

-- Raise a JSONata runtime error.
function H.err(code, info)
  errors.raise(code, info or {})
end

-- Half-to-even (banker's) rounding with optional decimal precision. Faithful
-- port of jsonata's round() (jsonata.js:2658): shift the decimal place via a
-- STRING (never multiply by 10^p, which injects float error and used to drop
-- significant digits), round half-up to nearest integer, then correct exact
-- ties to even. Shared by $round, $formatBase, $formatNumber.
local function shift_decimal(x, by)
  -- mimic JS: x.toString().split('e'); +(mantissa + 'e' + (exp + by))
  local s = tostring(x)
  local mant, exp = s:match("^([^eE]+)[eE]([%+%-]?%d+)$")
  if mant then
    return tonumber(mant .. "e" .. (tonumber(exp) + by))
  end
  return tonumber(s .. "e" .. by)
end

function H.round_half_even(x, precision)
  precision = precision or 0
  local arg = x
  if precision ~= 0 then
    arg = shift_decimal(arg, precision)
  end
  -- Math.round: round half toward +infinity (frac-based so large integers,
  -- where x + 0.5 is unrepresentable, are returned exactly).
  local f = math.floor(arg)
  local result = (arg - f < 0.5) and f or (f + 1)
  -- ties-to-even: if we rounded exactly 0.5 the wrong way, step to even
  local diff = result - arg
  if math.abs(diff) == 0.5 and math.abs(result % 2) == 1 then
    result = result - 1
  end
  if precision ~= 0 then
    result = shift_decimal(result, -precision)
  end
  if result == 0 then -- normalize -0.0 to 0
    result = 0
  end
  return result
end

-- Structural equality over internal values (numbers/strings/booleans exact;
-- arrays elementwise; objects key-set + recursive; null/nothing by identity).
function H.deep_equal(a, b)
  if a == b then
    return true
  end
  local V = require("jsonata.value")
  local ta, tb = V.typeof(a), V.typeof(b)
  if ta ~= tb then
    return false
  end
  if ta == "array" then
    if #a ~= #b then
      return false
    end
    for i = 1, #a do
      if not H.deep_equal(a[i], b[i]) then
        return false
      end
    end
    return true
  elseif ta == "object" then
    local ka = V.obj_keys(a)
    if #ka ~= #V.obj_keys(b) then
      return false
    end
    for _, k in ipairs(ka) do
      if not H.deep_equal(V.obj_get(a, k), V.obj_get(b, k)) then
        return false
      end
    end
    return true
  end
  return false
end

local function json_escape(s)
  return (
    s:gsub('[%z\1-\31\\"]', function(c)
      local map = { ['"'] = '\\"', ["\\"] = "\\\\", ["\n"] = "\\n", ["\r"] = "\\r", ["\t"] = "\\t" }
      return map[c] or string.format("\\u%04x", string.byte(c))
    end)
  )
end

function H.serialize(x)
  local V = require("jsonata.value")
  if type(x) == "table" and (x._jsonata_function or x._jsonata_lambda) then
    return ""
  end
  if V.is_null(x) then
    return "null"
  end
  if V.is_nothing(x) then
    return ""
  end
  local t = V.typeof(x)
  if t == "string" then
    return '"' .. json_escape(x) .. '"'
  elseif t == "number" then
    if x == math.huge or x == -math.huge or x ~= x then
      H.err("D1001", { value = x })
    end
    return H.num_to_str(x)
  elseif t == "boolean" then
    return x and "true" or "false"
  elseif t == "array" then
    local parts = {}
    for i = 1, #x do
      parts[i] = H.serialize(x[i])
    end
    return "[" .. table.concat(parts, ",") .. "]"
  elseif t == "object" then
    local parts = {}
    for _, k in ipairs(V.obj_keys(x)) do
      local val = V.obj_get(x, k)
      local is_fn = type(val) == "table" and (val._jsonata_function or val._jsonata_lambda)
      if not is_fn and not V.is_nothing(val) then
        parts[#parts + 1] = '"' .. json_escape(k) .. '":' .. H.serialize(val)
      end
    end
    return "{" .. table.concat(parts, ",") .. "}"
  end
  return ""
end

return H
