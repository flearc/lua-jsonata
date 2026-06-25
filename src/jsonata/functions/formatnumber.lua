local V = require("jsonata.value")
local H = require("jsonata.functions.helpers")

local R = {}

-- ===========================================================================
-- Faithful port of jsonata-js v2.2.1 formatNumber (jsonata.js:2138-2528),
-- the XPath F&O 4.7 decimal-format picture formatter.
--
-- jsonata operates on JS strings as sequences of UTF-16 code units; the
-- picture string and decimal-format symbols may be multi-byte UTF-8 here
-- (e.g. per-mille U+2030, the U+2460 digit family). To keep the transcription
-- mechanical AND correct, we work over arrays of single-codepoint character
-- strings (via H.utf8_chars) and provide JS-mirroring 0-based string helpers
-- that operate on those character arrays. Every JS string op maps to one Lua
-- call with IDENTICAL indices.
-- ===========================================================================

-- A "cstr" is { chars = {<single-char strings>}, len = n }. We pass these
-- around in place of JS strings so charAt/substring/indexOf are character-
-- (not byte-) accurate.
local function cstr(s)
  if type(s) == "table" then
    return s
  end
  local chars = H.utf8_chars(s)
  return { chars = chars, len = #chars }
end

local function cstr_tostring(cs)
  return table.concat(cs.chars)
end

-- 0-based; "" if out of range. Returns a single-char string.
local function charAt(cs, i)
  local c = cs.chars[i + 1]
  return c or ""
end

-- 0-based [a, b); b defaults to end. Returns a cstr.
local function substring(cs, a, b)
  if b == nil then
    b = cs.len
  end
  if a < 0 then
    a = 0
  end
  if b > cs.len then
    b = cs.len
  end
  if b < a then
    b = a
  end
  local out = {}
  for i = a + 1, b do
    out[#out + 1] = cs.chars[i]
  end
  return { chars = out, len = #out }
end

-- 0-based; -1 if absent. `sub` is a single-char string (all jsonata uses here
-- search for single characters or the 2-char grouping++grouping case).
local function indexOf(cs, sub, from)
  from = from or 0
  if from < 0 then
    from = 0
  end
  local subc = cstr(sub)
  if subc.len == 0 then
    return from <= cs.len and from or cs.len
  end
  for i = from, cs.len - subc.len do
    local match = true
    for j = 1, subc.len do
      if cs.chars[i + j] ~= subc.chars[j] then
        match = false
        break
      end
    end
    if match then
      return i
    end
  end
  return -1
end

local function lastIndexOf(cs, sub)
  local subc = cstr(sub)
  local last = -1
  if subc.len == 0 then
    return cs.len
  end
  for i = 0, cs.len - subc.len do
    local match = true
    for j = 1, subc.len do
      if cs.chars[i + j] ~= subc.chars[j] then
        match = false
        break
      end
    end
    if match then
      last = i
    end
  end
  return last
end

-- JS arr.indexOf(x) !== -1 over a Lua list of strings.
local function contains(arr, x)
  for i = 1, #arr do
    if arr[i] == x then
      return true
    end
  end
  return false
end

-- Split a cstr on a single-char literal separator -> list of cstr (JS .split).
local function split_on(cs, sep)
  local out = {}
  local start = 0
  local pos = indexOf(cs, sep, 0)
  while pos ~= -1 do
    out[#out + 1] = substring(cs, start, pos)
    start = pos + 1
    pos = indexOf(cs, sep, start)
  end
  out[#out + 1] = substring(cs, start, cs.len)
  return out
end

-- slice(a, b) like JS string.slice over a cstr -> cstr (only non-negative
-- indices are used by jsonata here).
local function slice(cs, a, b)
  return substring(cs, a, b)
end

-- Codepoint of the first character of a single-char string (UTF-8 decode).
local function codepoint(ch)
  local b1 = ch:byte(1)
  if not b1 then
    return 0
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

-- UTF-8 encode a codepoint -> string.
local function from_codepoint(cp)
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

R.formatNumber = H.def(function(value, picture, options)
  -- undefined inputs always return undefined
  if V.is_nothing(value) then
    return V.NOTHING
  end

  local properties = {
    ["decimal-separator"] = ".",
    ["grouping-separator"] = ",",
    ["exponent-separator"] = "e",
    ["infinity"] = "Infinity",
    ["minus-sign"] = "-",
    ["NaN"] = "NaN",
    ["percent"] = "%",
    ["per-mille"] = from_codepoint(0x2030),
    ["zero-digit"] = "0",
    ["digit"] = "#",
    ["pattern-separator"] = ";",
  }

  -- if `options` is specified, then its entries override defaults
  if not V.is_nothing(options) then
    for _, key in ipairs(V.obj_keys(options)) do
      properties[key] = V.obj_get(options, key)
    end
  end

  local decimalDigitFamily = {}
  local zeroCharCode = codepoint(properties["zero-digit"])
  for ii = zeroCharCode, zeroCharCode + 9 do
    decimalDigitFamily[#decimalDigitFamily + 1] = from_codepoint(ii)
  end

  local activeChars = {}
  for i = 1, #decimalDigitFamily do
    activeChars[#activeChars + 1] = decimalDigitFamily[i]
  end
  activeChars[#activeChars + 1] = properties["decimal-separator"]
  activeChars[#activeChars + 1] = properties["exponent-separator"]
  activeChars[#activeChars + 1] = properties["grouping-separator"]
  activeChars[#activeChars + 1] = properties["digit"]
  activeChars[#activeChars + 1] = properties["pattern-separator"]

  local subPictures = split_on(cstr(picture), properties["pattern-separator"])

  if #subPictures > 2 then
    H.err("D3080")
  end

  local splitParts = function(subpicture)
    local prefix = (function()
      for ii = 0, subpicture.len - 1 do
        local ch = charAt(subpicture, ii)
        if contains(activeChars, ch) and ch ~= properties["exponent-separator"] then
          return substring(subpicture, 0, ii)
        end
      end
      return cstr("")
    end)()
    local suffix = (function()
      for ii = subpicture.len - 1, 0, -1 do
        local ch = charAt(subpicture, ii)
        if contains(activeChars, ch) and ch ~= properties["exponent-separator"] then
          return substring(subpicture, ii + 1)
        end
      end
      return cstr("")
    end)()
    local activePart = substring(subpicture, prefix.len, subpicture.len - suffix.len)
    local mantissaPart, exponentPart, integerPart, fractionalPart
    local exponentPosition = indexOf(subpicture, properties["exponent-separator"], prefix.len)
    if exponentPosition == -1 or exponentPosition > subpicture.len - suffix.len then
      mantissaPart = activePart
      exponentPart = nil
    else
      mantissaPart = substring(activePart, 0, exponentPosition)
      exponentPart = substring(activePart, exponentPosition + 1)
    end
    local decimalPosition = indexOf(mantissaPart, properties["decimal-separator"])
    if decimalPosition == -1 then
      integerPart = mantissaPart
      fractionalPart = suffix
    else
      integerPart = substring(mantissaPart, 0, decimalPosition)
      fractionalPart = substring(mantissaPart, decimalPosition + 1)
    end
    return {
      prefix = prefix,
      suffix = suffix,
      activePart = activePart,
      mantissaPart = mantissaPart,
      exponentPart = exponentPart,
      integerPart = integerPart,
      fractionalPart = fractionalPart,
      subpicture = subpicture,
    }
  end

  -- validate the picture string, F&O 4.7.3
  local validate = function(parts)
    local error_code
    local subpicture = parts.subpicture
    local decimalPos = indexOf(subpicture, properties["decimal-separator"])
    if decimalPos ~= lastIndexOf(subpicture, properties["decimal-separator"]) then
      error_code = "D3081"
    end
    if indexOf(subpicture, properties.percent) ~= lastIndexOf(subpicture, properties.percent) then
      error_code = "D3082"
    end
    if indexOf(subpicture, properties["per-mille"]) ~= lastIndexOf(subpicture, properties["per-mille"]) then
      error_code = "D3083"
    end
    if indexOf(subpicture, properties.percent) ~= -1 and indexOf(subpicture, properties["per-mille"]) ~= -1 then
      error_code = "D3084"
    end
    local valid = false
    for ii = 0, parts.mantissaPart.len - 1 do
      local ch = charAt(parts.mantissaPart, ii)
      if contains(decimalDigitFamily, ch) or ch == properties.digit then
        valid = true
        break
      end
    end
    if not valid then
      error_code = "D3085"
    end
    -- charTypes: 'p' (passive) for chars not in activeChars, 'a' otherwise.
    local hasPassive = false
    for i = 1, parts.activePart.len do
      if not contains(activeChars, parts.activePart.chars[i]) then
        hasPassive = true
        break
      end
    end
    if hasPassive then
      error_code = "D3086"
    end
    if decimalPos ~= -1 then
      if charAt(subpicture, decimalPos - 1) == properties["grouping-separator"] or charAt(subpicture, decimalPos + 1) == properties["grouping-separator"] then
        error_code = "D3087"
      end
    elseif charAt(parts.integerPart, parts.integerPart.len - 1) == properties["grouping-separator"] then
      error_code = "D3088"
    end
    if indexOf(subpicture, properties["grouping-separator"] .. properties["grouping-separator"]) ~= -1 then
      error_code = "D3089"
    end
    local optionalDigitPos = indexOf(parts.integerPart, properties.digit)
    if optionalDigitPos ~= -1 then
      local before = substring(parts.integerPart, 0, optionalDigitPos)
      local found = false
      for i = 1, before.len do
        if contains(decimalDigitFamily, before.chars[i]) then
          found = true
          break
        end
      end
      if found then
        error_code = "D3090"
      end
    end
    optionalDigitPos = lastIndexOf(parts.fractionalPart, properties.digit)
    if optionalDigitPos ~= -1 then
      local after = substring(parts.fractionalPart, optionalDigitPos)
      local found = false
      for i = 1, after.len do
        if contains(decimalDigitFamily, after.chars[i]) then
          found = true
          break
        end
      end
      if found then
        error_code = "D3091"
      end
    end
    local exponentExists = (parts.exponentPart ~= nil)
    if
      exponentExists
      and parts.exponentPart.len > 0
      and (indexOf(subpicture, properties.percent) ~= -1 or indexOf(subpicture, properties["per-mille"]) ~= -1)
    then
      error_code = "D3092"
    end
    if exponentExists then
      local allDigits = true
      if parts.exponentPart.len == 0 then
        allDigits = false
      else
        for i = 1, parts.exponentPart.len do
          if not contains(decimalDigitFamily, parts.exponentPart.chars[i]) then
            allDigits = false
            break
          end
        end
      end
      if not allDigits then
        error_code = "D3093"
      end
    end
    if error_code then
      H.err(error_code)
    end
  end

  -- analyse the picture string, F&O 4.7.4
  local analyse = function(parts)
    local getGroupingPositions = function(part, toLeft)
      local positions = {}
      local groupingPosition = indexOf(part, properties["grouping-separator"])
      while groupingPosition ~= -1 do
        local seg = toLeft and substring(part, 0, groupingPosition) or substring(part, groupingPosition)
        local charsToTheRight = 0
        for i = 1, seg.len do
          local ch = seg.chars[i]
          if contains(decimalDigitFamily, ch) or ch == properties.digit then
            charsToTheRight = charsToTheRight + 1
          end
        end
        positions[#positions + 1] = charsToTheRight
        -- VERBATIM jsonata quirk: references parts.integerPart even for the
        -- fractional call. Do not "fix".
        groupingPosition = indexOf(parts.integerPart, properties["grouping-separator"], groupingPosition + 1)
      end
      return positions
    end
    local integerPartGroupingPositions = getGroupingPositions(parts.integerPart)
    local regular = function(indexes)
      if #indexes == 0 then
        return 0
      end
      local function gcd(a, b)
        return b == 0 and a or gcd(b, a % b)
      end
      local factor = indexes[1]
      for i = 2, #indexes do
        factor = gcd(factor, indexes[i])
      end
      for index = 1, #indexes do
        if not contains(indexes, index * factor) then
          return 0
        end
      end
      return factor
    end

    local regularGrouping = regular(integerPartGroupingPositions)
    local fractionalPartGroupingPositions = getGroupingPositions(parts.fractionalPart, true)

    local minimumIntegerPartSize = 0
    for i = 1, parts.integerPart.len do
      if contains(decimalDigitFamily, parts.integerPart.chars[i]) then
        minimumIntegerPartSize = minimumIntegerPartSize + 1
      end
    end
    local scalingFactor = minimumIntegerPartSize

    local minimumFactionalPartSize = 0
    local maximumFactionalPartSize = 0
    for i = 1, parts.fractionalPart.len do
      local ch = parts.fractionalPart.chars[i]
      if contains(decimalDigitFamily, ch) then
        minimumFactionalPartSize = minimumFactionalPartSize + 1
        maximumFactionalPartSize = maximumFactionalPartSize + 1
      elseif ch == properties.digit then
        maximumFactionalPartSize = maximumFactionalPartSize + 1
      end
    end
    local exponentPresent = (parts.exponentPart ~= nil)
    if minimumIntegerPartSize == 0 and maximumFactionalPartSize == 0 then
      if exponentPresent then
        minimumFactionalPartSize = 1
        maximumFactionalPartSize = 1
      else
        minimumIntegerPartSize = 1
      end
    end
    if exponentPresent and minimumIntegerPartSize == 0 and indexOf(parts.integerPart, properties.digit) ~= -1 then
      minimumIntegerPartSize = 1
    end
    if minimumIntegerPartSize == 0 and minimumFactionalPartSize == 0 then
      minimumFactionalPartSize = 1
    end
    local minimumExponentSize = 0
    if exponentPresent then
      for i = 1, parts.exponentPart.len do
        if contains(decimalDigitFamily, parts.exponentPart.chars[i]) then
          minimumExponentSize = minimumExponentSize + 1
        end
      end
    end

    return {
      integerPartGroupingPositions = integerPartGroupingPositions,
      regularGrouping = regularGrouping,
      minimumIntegerPartSize = minimumIntegerPartSize,
      scalingFactor = scalingFactor,
      prefix = cstr_tostring(parts.prefix),
      fractionalPartGroupingPositions = fractionalPartGroupingPositions,
      minimumFactionalPartSize = minimumFactionalPartSize,
      maximumFactionalPartSize = maximumFactionalPartSize,
      minimumExponentSize = minimumExponentSize,
      suffix = cstr_tostring(parts.suffix),
      picture = cstr_tostring(parts.subpicture),
    }
  end

  local parts = {}
  for i = 1, #subPictures do
    parts[i] = splitParts(subPictures[i])
  end
  for i = 1, #parts do
    validate(parts[i])
  end

  local variables = {}
  for i = 1, #parts do
    variables[i] = analyse(parts[i])
  end

  local minus_sign = properties["minus-sign"]
  local zero_digit = properties["zero-digit"]
  local decimal_separator = properties["decimal-separator"]
  local grouping_separator = properties["grouping-separator"]

  if #variables == 1 then
    -- deep copy variables[1] (plain fields only)
    local src = variables[1]
    local copy = {
      integerPartGroupingPositions = {},
      regularGrouping = src.regularGrouping,
      minimumIntegerPartSize = src.minimumIntegerPartSize,
      scalingFactor = src.scalingFactor,
      prefix = src.prefix,
      fractionalPartGroupingPositions = {},
      minimumFactionalPartSize = src.minimumFactionalPartSize,
      maximumFactionalPartSize = src.maximumFactionalPartSize,
      minimumExponentSize = src.minimumExponentSize,
      suffix = src.suffix,
      picture = src.picture,
    }
    for i = 1, #src.integerPartGroupingPositions do
      copy.integerPartGroupingPositions[i] = src.integerPartGroupingPositions[i]
    end
    for i = 1, #src.fractionalPartGroupingPositions do
      copy.fractionalPartGroupingPositions[i] = src.fractionalPartGroupingPositions[i]
    end
    variables[2] = copy
    variables[2].prefix = minus_sign .. variables[2].prefix
  end

  -- format the number
  local pic
  -- bullet 2:
  if value >= 0 then
    pic = variables[1]
  else
    pic = variables[2]
  end
  local adjustedNumber
  -- bullet 3:
  if indexOf(cstr(pic.picture), properties.percent) ~= -1 then
    adjustedNumber = value * 100
  elseif indexOf(cstr(pic.picture), properties["per-mille"]) ~= -1 then
    adjustedNumber = value * 1000
  else
    adjustedNumber = value
  end
  -- bullet 5:
  local mantissa, exponent
  if pic.minimumExponentSize == 0 then
    mantissa = adjustedNumber
  else
    local maxMantissa = 10 ^ pic.scalingFactor
    local minMantissa = 10 ^ (pic.scalingFactor - 1)
    mantissa = adjustedNumber
    exponent = 0
    -- zero guard (#785): no normalisation for zero input
    if mantissa ~= 0 then
      while math.abs(mantissa) < minMantissa do
        mantissa = mantissa * 10
        exponent = exponent - 1
      end
      while math.abs(mantissa) > maxMantissa do
        mantissa = mantissa / 10
        exponent = exponent + 1
      end
    end
  end
  -- bullet 6:
  local roundedNumber = H.round_half_even(mantissa, pic.maximumFactionalPartSize)
  -- bullet 7:
  local makeString = function(val, dp)
    local str = string.format("%." .. dp .. "f", math.abs(val))
    if zero_digit ~= "0" then
      local out = {}
      for i = 1, #str do
        local c = str:sub(i, i)
        if c >= "0" and c <= "9" then
          out[#out + 1] = decimalDigitFamily[c:byte(1) - 48 + 1]
        else
          out[#out + 1] = c
        end
      end
      str = table.concat(out)
    end
    return str
  end
  local stringValue = cstr(makeString(roundedNumber, pic.maximumFactionalPartSize))
  local decimalPos = indexOf(stringValue, ".")
  if decimalPos == -1 then
    stringValue = cstr(cstr_tostring(stringValue) .. decimal_separator)
  else
    -- replace first "." with decimal_separator
    local p = decimalPos
    stringValue = cstr(cstr_tostring(substring(stringValue, 0, p)) .. decimal_separator .. cstr_tostring(substring(stringValue, p + 1)))
  end
  while charAt(stringValue, 0) == zero_digit do
    stringValue = substring(stringValue, 1)
  end
  while charAt(stringValue, stringValue.len - 1) == zero_digit do
    stringValue = substring(stringValue, 0, stringValue.len - 1)
  end
  -- bullets 8 & 9:
  decimalPos = indexOf(stringValue, decimal_separator)
  local padLeft = pic.minimumIntegerPartSize - decimalPos
  local padRight = pic.minimumFactionalPartSize - (stringValue.len - decimalPos - 1)
  stringValue = cstr((padLeft > 0 and string.rep(zero_digit, padLeft) or "") .. cstr_tostring(stringValue))
  stringValue = cstr(cstr_tostring(stringValue) .. (padRight > 0 and string.rep(zero_digit, padRight) or ""))
  decimalPos = indexOf(stringValue, decimal_separator)
  -- bullet 10:
  if pic.regularGrouping > 0 then
    local groupCount = math.floor((decimalPos - 1) / pic.regularGrouping)
    for group = 1, groupCount do
      stringValue = cstr(
        cstr_tostring(slice(stringValue, 0, decimalPos - group * pic.regularGrouping))
          .. grouping_separator
          .. cstr_tostring(slice(stringValue, decimalPos - group * pic.regularGrouping))
      )
    end
  else
    for _, pos in ipairs(pic.integerPartGroupingPositions) do
      stringValue = cstr(cstr_tostring(slice(stringValue, 0, decimalPos - pos)) .. grouping_separator .. cstr_tostring(slice(stringValue, decimalPos - pos)))
      decimalPos = decimalPos + 1
    end
  end
  -- bullet 11:
  decimalPos = indexOf(stringValue, decimal_separator)
  for _, pos in ipairs(pic.fractionalPartGroupingPositions) do
    stringValue =
      cstr(cstr_tostring(slice(stringValue, 0, pos + decimalPos + 1)) .. grouping_separator .. cstr_tostring(slice(stringValue, pos + decimalPos + 1)))
  end
  -- bullet 12:
  decimalPos = indexOf(stringValue, decimal_separator)
  if indexOf(cstr(pic.picture), decimal_separator) == -1 or decimalPos == stringValue.len - 1 then
    stringValue = substring(stringValue, 0, stringValue.len - 1)
  end
  -- bullet 13:
  if exponent ~= nil then
    local stringExponent = cstr(makeString(exponent, 0))
    padLeft = pic.minimumExponentSize - stringExponent.len
    if padLeft > 0 then
      stringExponent = cstr(string.rep(zero_digit, padLeft) .. cstr_tostring(stringExponent))
    end
    stringValue = cstr(cstr_tostring(stringValue) .. properties["exponent-separator"] .. (exponent < 0 and minus_sign or "") .. cstr_tostring(stringExponent))
  end
  -- bullet 14:
  return pic.prefix .. cstr_tostring(stringValue) .. pic.suffix
end, 2, 3, "<n-so?:s>")

return R
