local V = require("jsonata.value")
local H = require("jsonata.functions.helpers")

-- ===========================================================================
-- Faithful port of jsonata-js v2.2.1 fn:format-integer machinery
-- (jsonata.js: analyseIntegerPicture 327-477, _formatInteger 247-317,
--  generateRegex integer branch 1045-1108). Internals exported under
-- `R._internal` for M8c ($formatDateTime/$parseDateTime) reuse.
-- ===========================================================================

-- the 37 Unicode decimal-zero codepoints (jsonata.js:320)
local DECIMAL_GROUPS = {
  0x30,
  0x0660,
  0x06F0,
  0x07C0,
  0x0966,
  0x09E6,
  0x0A66,
  0x0AE6,
  0x0B66,
  0x0BE6,
  0x0C66,
  0x0CE6,
  0x0D66,
  0x0DE6,
  0x0E50,
  0x0ED0,
  0x0F20,
  0x1040,
  0x1090,
  0x17E0,
  0x1810,
  0x1946,
  0x19D0,
  0x1A80,
  0x1A90,
  0x1B50,
  0x1BB0,
  0x1C40,
  0x1C50,
  0xA620,
  0xA8D0,
  0xA900,
  0xA9D0,
  0xA9F0,
  0xAA50,
  0xABF0,
  0xFF10,
}

-- ---- analyse_integer_picture (jsonata analyseIntegerPicture) --------------
local function analyse_integer_picture(picture)
  local format = { type = "integer", primary = "decimal", case = "lower", ordinal = false }

  local chars = H.utf8_chars(picture)
  -- lastIndexOf(';')
  local semicolon = -1
  for i = #chars, 1, -1 do
    if chars[i] == ";" then
      semicolon = i
      break
    end
  end
  local primaryFormat
  if semicolon == -1 then
    primaryFormat = picture
  else
    primaryFormat = table.concat(chars, "", 1, semicolon - 1)
    local modifier = table.concat(chars, "", semicolon + 1)
    if modifier:sub(1, 1) == "o" then
      format.ordinal = true
    end
  end

  if primaryFormat == "A" then
    format.case = "upper"
    format.primary = "letters"
  elseif primaryFormat == "a" then
    format.primary = "letters"
  elseif primaryFormat == "I" then
    format.case = "upper"
    format.primary = "roman"
  elseif primaryFormat == "i" then
    format.primary = "roman"
  elseif primaryFormat == "W" then
    format.case = "upper"
    format.primary = "words"
  elseif primaryFormat == "Ww" then
    format.case = "title"
    format.primary = "words"
  elseif primaryFormat == "w" then
    format.primary = "words"
  else
    -- decimal-digit-pattern: reverse the codepoints so separator positions count from the right
    local pchars = H.utf8_chars(primaryFormat)
    local codepoints = {}
    for i = #pchars, 1, -1 do
      codepoints[#codepoints + 1] = H.codepoint(pchars[i])
    end
    local zeroCode, mandatoryDigits, optionalDigits, separatorPosition = nil, 0, 0, 0
    local groupingSeparators = {}
    for _, cp in ipairs(codepoints) do
      local digit = false
      for _, group in ipairs(DECIMAL_GROUPS) do
        if cp >= group and cp <= group + 9 then
          digit = true
          mandatoryDigits = mandatoryDigits + 1
          separatorPosition = separatorPosition + 1
          if zeroCode == nil then
            zeroCode = group
          elseif group ~= zeroCode then
            H.err("D3131", {})
          end
          break
        end
      end
      if not digit then
        if cp == 0x23 then -- '#'
          separatorPosition = separatorPosition + 1
          optionalDigits = optionalDigits + 1
        else
          groupingSeparators[#groupingSeparators + 1] = { position = separatorPosition, character = H.from_codepoint(cp) }
        end
      end
    end
    if mandatoryDigits > 0 then
      format.primary = "decimal"
      format.zeroCode = zeroCode
      format.mandatoryDigits = mandatoryDigits
      format.optionalDigits = optionalDigits
      -- regular grouping? all same char + GCD-of-positions divides every position
      local regular = 0
      if #groupingSeparators > 0 then
        local sepChar = groupingSeparators[1].character
        local same = true
        for i = 2, #groupingSeparators do
          if groupingSeparators[i].character ~= sepChar then
            same = false
            break
          end
        end
        if same then
          local function gcd(a, b)
            if b == 0 then
              return a
            end
            return gcd(b, a % b)
          end
          local factor = groupingSeparators[1].position
          for i = 2, #groupingSeparators do
            factor = gcd(factor, groupingSeparators[i].position)
          end
          local ok = true
          for index = 1, #groupingSeparators do
            local target = index * factor
            local found = false
            for _, s in ipairs(groupingSeparators) do
              if s.position == target then
                found = true
                break
              end
            end
            if not found then
              ok = false
              break
            end
          end
          if ok then
            regular = factor
          end
        end
      end
      if regular > 0 then
        format.regular = true
        format.groupingSeparators = { position = regular, character = groupingSeparators[1].character }
      else
        format.regular = false
        format.groupingSeparators = groupingSeparators
      end
    else
      format.primary = "sequence"
      format.token = primaryFormat
    end
  end
  return format
end

-- ---- decimal format (jsonata _formatInteger DECIMAL branch) ---------------
local function format_decimal(value, format)
  -- value is a non-negative integer here (sign handled by caller)
  local digits = H.utf8_chars(H.num_to_str(value)) -- ASCII digits
  -- left-pad with '0' to mandatoryDigits
  local padLength = format.mandatoryDigits - #digits
  if padLength > 0 then
    local pad = {}
    for _ = 1, padLength do
      pad[#pad + 1] = "0"
    end
    for _, d in ipairs(digits) do
      pad[#pad + 1] = d
    end
    digits = pad
  end
  -- map ASCII digits into the configured family
  if format.zeroCode ~= 0x30 then
    for i, ch in ipairs(digits) do
      digits[i] = H.from_codepoint(ch:byte(1) + format.zeroCode - 0x30)
    end
  end
  -- insert grouping separators (operating on the codepoint array; positions = char count)
  if format.regular then
    local pos = format.groupingSeparators.position
    local n = math.floor((#digits - 1) / pos)
    for ii = n, 1, -1 do
      local at = #digits - ii * pos -- 0-based index to insert before
      table.insert(digits, at + 1, format.groupingSeparators.character)
    end
  else
    -- explicit separators, applied right-to-left (reverse order)
    for i = #format.groupingSeparators, 1, -1 do
      local sep = format.groupingSeparators[i]
      local at = #digits - sep.position -- 0-based
      table.insert(digits, at + 1, sep.character)
    end
  end
  local s = table.concat(digits)
  -- ordinal suffix
  if format.ordinal then
    local suffix123 = { ["1"] = "st", ["2"] = "nd", ["3"] = "rd" }
    local last = s:sub(-1)
    local suffix = suffix123[last]
    if (not suffix) or (#s > 1 and s:sub(-2, -2) == "1") then
      suffix = "th"
    end
    s = s .. suffix
  end
  return s
end

-- ---- decimal parse (jsonata generateRegex DECIMAL .parse) ------------------
local function parse_decimal(value, format)
  local digits = value
  if format.ordinal then
    digits = digits:sub(1, #digits - 2)
  end
  if format.regular then
    digits = digits:gsub(",", "") -- jsonata strips literal ',' for regular grouping
  else
    for _, sep in ipairs(format.groupingSeparators) do
      digits = digits:gsub("%" .. sep.character, "") -- escape; sep chars are single
    end
  end
  if format.zeroCode ~= 0x30 then
    local chars = H.utf8_chars(digits)
    local out = {}
    for _, ch in ipairs(chars) do
      out[#out + 1] = string.char(H.codepoint(ch) - format.zeroCode + 0x30)
    end
    digits = table.concat(out)
  end
  return tonumber(digits)
end

-- ---- roman (jsonata decimalToRoman / romanToDecimal) ----------------------
local ROMAN_NUMERALS = {
  { 1000, "m" },
  { 900, "cm" },
  { 500, "d" },
  { 400, "cd" },
  { 100, "c" },
  { 90, "xc" },
  { 50, "l" },
  { 40, "xl" },
  { 10, "x" },
  { 9, "ix" },
  { 5, "v" },
  { 4, "iv" },
  { 1, "i" },
}
local ROMAN_VALUES = { M = 1000, D = 500, C = 100, L = 50, X = 10, V = 5, I = 1 }

local function decimal_to_roman(value)
  for _, numeral in ipairs(ROMAN_NUMERALS) do
    if value >= numeral[1] then
      return numeral[2] .. decimal_to_roman(value - numeral[1])
    end
  end
  return ""
end

local function roman_to_decimal(roman)
  local decimal, max = 0, 1
  for i = #roman, 1, -1 do
    local value = ROMAN_VALUES[roman:sub(i, i)]
    if value < max then
      decimal = decimal - value
    else
      max = value
      decimal = decimal + value
    end
  end
  return decimal
end

-- ---- letters (jsonata decimalToLetters / lettersToDecimal) ----------------
local function decimal_to_letters(value, aChar)
  local aCode = aChar:byte(1)
  local letters = {}
  while value > 0 do
    table.insert(letters, 1, string.char((value - 1) % 26 + aCode))
    value = math.floor((value - 1) / 26)
  end
  return table.concat(letters)
end

local function letters_to_decimal(letters, aChar)
  local aCode = aChar:byte(1)
  local decimal = 0
  for i = 0, #letters - 1 do
    decimal = decimal + (letters:byte(#letters - i) - aCode + 1) * 26 ^ i
  end
  return decimal
end

-- ---- format dispatch (jsonata _formatInteger) -----------------------------
local function format_integer_spec(value, format)
  local negative = value < 0
  value = math.abs(value)
  local out
  if format.primary == "decimal" then
    out = format_decimal(value, format)
  elseif format.primary == "letters" then
    out = decimal_to_letters(value, format.case == "upper" and "A" or "a")
  elseif format.primary == "roman" then
    out = decimal_to_roman(value)
    if format.case == "upper" then
      out = out:upper()
    end
  elseif format.primary == "words" then
    H.err("D3130", { value = format.primary }) -- filled in Task 3
  elseif format.primary == "sequence" then
    H.err("D3130", { value = format.token })
  end
  if negative then
    out = "-" .. out
  end
  return out
end

-- ---- parse dispatch (jsonata generateRegex integer branch + parseInteger) --
local function integer_parser(format)
  if format.primary == "decimal" then
    return function(value)
      return parse_decimal(value, format)
    end
  elseif format.primary == "letters" then
    return function(value)
      return letters_to_decimal(value, format.case == "upper" and "A" or "a")
    end
  elseif format.primary == "roman" then
    return function(value)
      return roman_to_decimal(format.case == "upper" and value or value:upper())
    end
  elseif format.primary == "words" then
    return function()
      H.err("D3130", { value = format.primary }) -- filled in Task 3
    end
  elseif format.primary == "sequence" then
    return function()
      H.err("D3130", { value = format.token })
    end
  end
end

-- ---- builtins -------------------------------------------------------------
local R = {}

R.formatInteger = H.def(function(value, picture)
  if V.is_nothing(value) then
    return V.NOTHING
  end
  value = math.floor(value)
  return format_integer_spec(value, analyse_integer_picture(picture))
end, 2, 2, "<n-s:s>")

R.parseInteger = H.def(function(value, picture)
  if V.is_nothing(value) then
    return V.NOTHING
  end
  return integer_parser(analyse_integer_picture(picture))(value)
end, 2, 2, "<s-s:n>")

-- exported for M8c reuse
R._internal = {
  analyse = analyse_integer_picture,
  format = format_integer_spec,
  parser = integer_parser,
}

return R
