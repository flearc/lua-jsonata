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

-- Format a (digits_str, exponent) pair using ECMAScript Number::toString thresholds.
-- digits is a string of significant digits with no trailing zeros; e10 is the
-- base-10 exponent of the leading digit (so the value is digits * 10^(e10-k+1)).
local function format_digits(digits, e10, neg)
  local k = #digits
  local n = e10 + 1
  local out
  if k <= n and n <= 21 then
    out = digits .. string.rep("0", n - k)
  elseif 0 < n and n <= 21 then
    out = digits:sub(1, n) .. "." .. digits:sub(n + 1)
  elseif -6 < n and n <= 0 then
    out = "0." .. string.rep("0", -n) .. digits
  else
    local m = digits:sub(1, 1)
    if k > 1 then
      m = m .. "." .. digits:sub(2)
    end
    local ee = n - 1
    out = m .. "e" .. (ee >= 0 and "+" or "-") .. math.abs(ee)
  end
  return neg and ("-" .. out) or out
end

-- Round a digit string (all significant digits, no trailing zeros) to 15 digits,
-- half-away-from-zero, using carry propagation. Returns (new_digits, new_exp).
-- exp is the base-10 exponent of the leading digit.
-- Only call when #digits > 15 (caller must ensure this).
local function round15_digits(digits, exp)
  local keep = digits:sub(1, 15)
  local d16 = tonumber(digits:sub(16, 16)) or 0
  if d16 >= 5 then
    -- Increment via carry propagation (pure digit-string, no float arithmetic)
    local chars = {}
    for i = 1, #keep do
      chars[i] = keep:byte(i) - 48
    end -- '0'=48
    local carry = 1
    for i = #chars, 1, -1 do
      local d = chars[i] + carry
      if d >= 10 then
        chars[i] = d - 10
        carry = 1
      else
        chars[i] = d
        carry = 0
        break
      end
    end
    local s = ""
    if carry == 1 then
      s = "1"
      exp = exp + 1
    end
    for i = 1, #chars do
      s = s .. chars[i]
    end
    keep = s
  end
  keep = keep:gsub("0+$", "")
  if keep == "" then
    keep = "0"
  end
  return keep, exp
end

-- Faithful port of the ECMAScript Number::toString algorithm: shortest round-trip
-- significant digits, then JS's fixed-vs-exponential thresholds (fixed when
-- -6 < n <= 21, else e+N/e-N). Non-integer values are first rounded to 15
-- significant digits (JS JSONata's toPrecision(15) step) to suppress FP noise
-- (e.g. $sum rounding errors), using half-away-from-zero (JS semantics, not C's
-- half-to-even). Integer-valued inputs bypass rounding so that
-- $formatInteger/$formatNumber/$formatBase/$round are unaffected.
function H.num_to_str(x)
  if x ~= x then
    return "NaN"
  end
  if x == math.huge then
    return "Infinity"
  end
  if x == -math.huge then
    return "-Infinity"
  end
  if x == 0 then
    return "0" -- also covers -0 (0 == -0 in Lua)
  end
  local neg = x < 0
  local a = math.abs(x)
  -- Find shortest round-trip digit string for a.
  local digits, e10
  for p = 0, 16 do
    local s = string.format("%." .. p .. "e", a)
    if tonumber(s) == a then
      local mant, exp = s:match("^(%d[%.%d]*)[eE]([%+%-]%d+)$")
      mant = mant:gsub("%.", ""):gsub("0+$", "")
      if mant == "" then
        mant = "0"
      end
      digits = mant
      e10 = tonumber(exp)
      break
    end
  end
  -- toPrecision(15): for non-integer values with more than 15 significant digits
  -- in their shortest representation, round to 15 sig digits half-away-from-zero
  -- (JS semantics). Values with <= 15 digits already satisfy toPrecision(15)
  -- exactly (same float), so no rounding is needed and we keep the shorter form.
  if a ~= math.floor(a) and #digits > 15 then
    digits, e10 = round15_digits(digits, e10)
  end
  return format_digits(digits, e10, neg)
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

function H.serialize(x, indent, depth)
  depth = depth or 0
  local V = require("jsonata.value")
  if type(x) == "table" and (x._jsonata_function or x._jsonata_lambda) then
    return '""'
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
    if indent then
      if #x == 0 then
        return "[]"
      end
      local pad = string.rep(" ", indent * (depth + 1))
      local closepad = string.rep(" ", indent * depth)
      local parts = {}
      for i = 1, #x do
        parts[i] = H.serialize(x[i], indent, depth + 1)
      end
      return "[\n" .. pad .. table.concat(parts, ",\n" .. pad) .. "\n" .. closepad .. "]"
    else
      local parts = {}
      for i = 1, #x do
        parts[i] = H.serialize(x[i])
      end
      return "[" .. table.concat(parts, ",") .. "]"
    end
  elseif t == "object" then
    if indent then
      local keys = V.obj_keys(x)
      local kvs = {}
      for _, k in ipairs(keys) do
        local val = V.obj_get(x, k)
        if not V.is_nothing(val) then
          kvs[#kvs + 1] = '"' .. json_escape(k) .. '": ' .. H.serialize(val, indent, depth + 1)
        end
      end
      if #kvs == 0 then
        return "{}"
      end
      local pad = string.rep(" ", indent * (depth + 1))
      local closepad = string.rep(" ", indent * depth)
      return "{\n" .. pad .. table.concat(kvs, ",\n" .. pad) .. "\n" .. closepad .. "}"
    else
      local parts = {}
      for _, k in ipairs(V.obj_keys(x)) do
        local val = V.obj_get(x, k)
        if not V.is_nothing(val) then
          parts[#parts + 1] = '"' .. json_escape(k) .. '":' .. H.serialize(val)
        end
      end
      return "{" .. table.concat(parts, ",") .. "}"
    end
  end
  return ""
end

return H
