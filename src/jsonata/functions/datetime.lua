local V = require("jsonata.value")
local H = require("jsonata.functions.helpers")
local FI = require("jsonata.functions.formatinteger")._internal

-- ===========================================================================
-- Faithful port of jsonata-js v2.2.1 datetime.js (fn:format-dateTime side).
-- Pure-Lua proleptic-Gregorian calendar (Hinnant civil<->days algorithms)
-- replaces JS Date.UTC / new Date(ms).getUTC*().
-- ===========================================================================

local MILLIS_IN_A_DAY = 86400000

-- integer division truncating toward zero (C-style), as Hinnant's era math requires
local function itrunc(x)
  return x >= 0 and math.floor(x) or math.ceil(x)
end

local function days_from_civil(y, m, d)
  y = (m <= 2) and (y - 1) or y
  local era = itrunc((y >= 0 and y or (y - 399)) / 400)
  local yoe = y - era * 400
  local mp = (m > 2) and (m - 3) or (m + 9)
  local doy = math.floor((153 * mp + 2) / 5) + d - 1
  local doe = yoe * 365 + math.floor(yoe / 4) - math.floor(yoe / 100) + doy
  return era * 146097 + doe - 719468
end

local function civil_from_days(z)
  z = z + 719468
  local era = itrunc((z >= 0 and z or (z - 146096)) / 146097)
  local doe = z - era * 146097
  local yoe = math.floor((doe - math.floor(doe / 1460) + math.floor(doe / 36524) - math.floor(doe / 146096)) / 365)
  local y = yoe + era * 400
  local doy = doe - (365 * yoe + math.floor(yoe / 4) - math.floor(yoe / 100))
  local mp = math.floor((5 * doy + 2) / 153)
  local d = doy - math.floor((153 * mp + 2) / 5) + 1
  local m = (mp < 10) and (mp + 3) or (mp - 9)
  return (m <= 2) and (y + 1) or y, m, d
end

local function millis_to_components(millis)
  local days = math.floor(millis / MILLIS_IN_A_DAY)
  local tod = millis - days * MILLIS_IN_A_DAY
  local year, m, d = civil_from_days(days)
  -- Weekday: epoch (days=0) is Thursday=4.
  -- ((days % 7) + 4) % 7 but Lua's % on negative floats can be negative;
  -- use integer days (already floored) and double-normalize to guarantee 0..6.
  local weekday = (((days % 7) + 4) % 7 + 7) % 7
  return {
    year = year,
    month0 = m - 1,
    day = d,
    hours = math.floor(tod / 3600000),
    minutes = math.floor(tod / 60000) % 60,
    seconds = math.floor(tod / 1000) % 60,
    ms = tod % 1000,
    weekday = weekday,
  }
end

local function components_to_millis(year, month0, day, h, mi, s, ms)
  return days_from_civil(year, month0 + 1, day) * MILLIS_IN_A_DAY + ((h * 60 + mi) * 60 + s) * 1000 + ms
end

local calendar = {
  MILLIS_IN_A_DAY = MILLIS_IN_A_DAY,
  millis_to_components = millis_to_components,
  components_to_millis = components_to_millis,
}

-- ===========================================================================
-- ISO-week helpers (faithful port of jsonata.js:651-824)
-- First week = the week containing the first Thursday; weeks start Monday.
-- ===========================================================================

local function start_of_first_week(year, month0)
  local jan1 = components_to_millis(year, month0, 1, 0, 0, 0, 0)
  local dow = millis_to_components(jan1).weekday
  if dow == 0 then
    dow = 7
  end
  if dow > 4 then
    return jan1 + (8 - dow) * MILLIS_IN_A_DAY
  else
    return jan1 - (dow - 1) * MILLIS_IN_A_DAY
  end
end

local function delta_weeks(start, finish)
  return (finish - start) / (MILLIS_IN_A_DAY * 7) + 1
end

local function next_month(y, m0)
  if m0 == 11 then
    return y + 1, 0
  else
    return y, m0 + 1
  end
end
local function prev_month(y, m0)
  if m0 == 0 then
    return y - 1, 11
  else
    return y, m0 - 1
  end
end

local function get_datetime_fragment(comp, component)
  if component == "Y" then
    return comp.year
  elseif component == "M" then
    return comp.month0 + 1
  elseif component == "D" then
    return comp.day
  elseif component == "d" then
    local today = components_to_millis(comp.year, comp.month0, comp.day, 0, 0, 0, 0)
    local firstJan = components_to_millis(comp.year, 0, 1, 0, 0, 0, 0)
    return (today - firstJan) / MILLIS_IN_A_DAY + 1
  elseif component == "F" then
    local v = comp.weekday
    if v == 0 then
      v = 7
    end
    return v
  elseif component == "W" then
    local start1 = start_of_first_week(comp.year, 0)
    local today = components_to_millis(comp.year, comp.month0, comp.day, 0, 0, 0, 0)
    local week = delta_weeks(start1, today)
    if week > 52 then
      if today >= start_of_first_week(comp.year + 1, 0) then
        week = 1
      end
    elseif week < 1 then
      week = delta_weeks(start_of_first_week(comp.year - 1, 0), today)
    end
    return math.floor(week)
  elseif component == "w" then
    local start1 = start_of_first_week(comp.year, comp.month0)
    local today = components_to_millis(comp.year, comp.month0, comp.day, 0, 0, 0, 0)
    local week = delta_weeks(start1, today)
    if week > 4 then
      local ny, nm = next_month(comp.year, comp.month0)
      if today >= start_of_first_week(ny, nm) then
        week = 1
      end
    elseif week < 1 then
      local py, pm = prev_month(comp.year, comp.month0)
      week = delta_weeks(start_of_first_week(py, pm), today)
    end
    return math.floor(week)
  elseif component == "X" then
    local start = start_of_first_week(comp.year, 0)
    local finish = start_of_first_week(comp.year + 1, 0)
    local now = components_to_millis(comp.year, comp.month0, comp.day, comp.hours, comp.minutes, comp.seconds, comp.ms)
    if now < start then
      return comp.year - 1
    elseif now >= finish then
      return comp.year + 1
    else
      return comp.year
    end
  elseif component == "x" then
    local start = start_of_first_week(comp.year, comp.month0)
    local ny, nm = next_month(comp.year, comp.month0)
    local finish = start_of_first_week(ny, nm)
    local now = components_to_millis(comp.year, comp.month0, comp.day, comp.hours, comp.minutes, comp.seconds, comp.ms)
    if now < start then
      local _, pm = prev_month(comp.year, comp.month0)
      return pm + 1
    elseif now >= finish then
      return nm + 1
    else
      return comp.month0 + 1
    end
  elseif component == "H" then
    return comp.hours
  elseif component == "h" then
    local v = comp.hours % 12
    if v == 0 then
      v = 12
    end
    return v
  elseif component == "P" then
    return comp.hours >= 12 and "pm" or "am"
  elseif component == "m" then
    return comp.minutes
  elseif component == "s" then
    return comp.seconds
  elseif component == "f" then
    return comp.ms
  elseif component == "C" or component == "E" then
    return "ISO"
  end
end

-- ===========================================================================
-- analyse_datetime_picture (faithful port of jsonata.js:490-645)
-- ===========================================================================

local DEFAULT_PRESENTATION = {
  Y = "1",
  M = "1",
  D = "1",
  d = "1",
  F = "n",
  W = "1",
  w = "1",
  X = "1",
  x = "1",
  H = "1",
  h = "1",
  P = "n",
  m = "01",
  s = "01",
  f = "1",
  Z = "01:01",
  z = "01:01",
  C = "n",
  E = "n",
}

local function analyse_datetime_picture(picture)
  local spec = {}
  local format = { type = "datetime", parts = spec }

  -- addLiteral(start, end) with 0-based [start, end) JS semantics.
  -- We mirror JS string indices: picture is treated as a byte string here
  -- (the suite is ASCII; markers/literals could be multibyte but JS itself
  -- operates over UTF-16 code units, and our byte ops match for ASCII).
  local len = #picture
  local function char_at(i) -- 0-based; returns "" past end (JS charAt)
    if i < 0 or i >= len then
      return ""
    end
    return picture:sub(i + 1, i + 1)
  end
  local function substring(a, b) -- 0-based [a, b)
    return picture:sub(a + 1, b)
  end
  local function index_of(needle, from) -- 0-based, -1 if not found
    local p = picture:find(needle, from + 1, true)
    if p == nil then
      return -1
    end
    return p - 1
  end

  local function add_literal(start, finish)
    if finish > start then
      local literal = substring(start, finish)
      literal = literal:gsub("%]%]", "]")
      spec[#spec + 1] = { type = "literal", value = literal }
    end
  end

  local start, pos = 0, 0
  while pos < len do
    if char_at(pos) == "[" then
      if char_at(pos + 1) == "[" then
        -- literal [
        add_literal(start, pos)
        spec[#spec + 1] = { type = "literal", value = "[" }
        pos = pos + 2
        start = pos
      else
        -- start of variable marker
        add_literal(start, pos)
        start = pos
        pos = index_of("]", start)
        if pos == -1 then
          H.err("D3135", {})
        end
        local marker = substring(start + 1, pos)
        -- whitespace within a variable marker is ignored
        marker = marker:gsub("%s+", "")

        local def = { type = "marker", component = marker:sub(1, 1) }
        -- lastIndexOf(',')
        local comma = -1
        for i = #marker, 1, -1 do
          if marker:sub(i, i) == "," then
            comma = i - 1 -- 0-based
            break
          end
        end
        local presMod
        if comma ~= -1 then
          local widthMod = marker:sub(comma + 2) -- marker.substring(comma+1)
          local dashPos = widthMod:find("-", 1, true)
          local minStr, maxStr
          if dashPos == nil then
            minStr = widthMod
          else
            minStr = widthMod:sub(1, dashPos - 1)
            maxStr = widthMod:sub(dashPos + 1)
          end
          local function parse_width(wm)
            if wm == nil or wm == "*" then
              return nil
            else
              return math.floor(tonumber(wm))
            end
          end
          def.width = { min = parse_width(minStr), max = parse_width(maxStr) }
          presMod = marker:sub(2, comma) -- marker.substring(1, comma)
        else
          presMod = marker:sub(2) -- marker.substring(1)
        end

        if #presMod == 1 then
          def.presentation1 = presMod
        elseif #presMod > 1 then
          local lastChar = presMod:sub(#presMod, #presMod)
          if ("atco"):find(lastChar, 1, true) then
            def.presentation2 = lastChar
            if lastChar == "o" then
              def.ordinal = true
            end
            def.presentation1 = presMod:sub(1, #presMod - 1)
          else
            def.presentation1 = presMod
          end
        else
          def.presentation1 = DEFAULT_PRESENTATION[def.component]
        end

        if def.presentation1 == nil then
          H.err("D3132", { value = def.component })
        end

        if def.presentation1:sub(1, 1) == "n" then
          def.names = "lower"
        elseif def.presentation1:sub(1, 1) == "N" then
          if def.presentation1:sub(2, 2) == "n" then
            def.names = "title"
          else
            def.names = "upper"
          end
        elseif ("YMDdFWwXxHhmsf"):find(def.component, 1, true) then
          local integerPattern = def.presentation1
          if def.presentation2 then
            integerPattern = integerPattern .. ";" .. def.presentation2
          end
          def.integerFormat = FI.analyse(integerPattern)
          if def.width and def.width.min ~= nil then
            if def.integerFormat.mandatoryDigits < def.width.min then
              def.integerFormat.mandatoryDigits = def.width.min
            end
          end
          if def.component == "Y" then
            def.n = -1
            if def.width and def.width.max ~= nil then
              def.n = def.width.max
              def.integerFormat.mandatoryDigits = def.n
            else
              local w = def.integerFormat.mandatoryDigits + def.integerFormat.optionalDigits
              if w >= 2 then
                def.n = w
              end
            end
          end
          local previousPart = spec[#spec]
          if previousPart and previousPart.integerFormat then
            previousPart.integerFormat.parseWidth = previousPart.integerFormat.mandatoryDigits
          end
        end

        if def.component == "Z" or def.component == "z" then
          def.integerFormat = FI.analyse(def.presentation1)
        end

        spec[#spec + 1] = def
        start = pos + 1
      end
    else
      pos = pos + 1
    end
  end
  add_literal(start, pos)
  return format
end

-- ===========================================================================
-- format_datetime (faithful port of jsonata.js:835-948)
-- ===========================================================================

local MONTHS = {
  "January",
  "February",
  "March",
  "April",
  "May",
  "June",
  "July",
  "August",
  "September",
  "October",
  "November",
  "December",
} -- 1..12
local DAYS = {
  "Monday",
  "Tuesday",
  "Wednesday",
  "Thursday",
  "Friday",
  "Saturday",
  "Sunday",
} -- 1..7

local function format_component(comp, part, offsetHours, offsetMinutes)
  local value = get_datetime_fragment(comp, part.component)

  if ("YMDdFWwXxHhms"):find(part.component, 1, true) then
    if part.component == "Y" then
      -- JS: componentValue % Math.pow(10, n). When n is undefined (the [YN]
      -- name path, where the integer branch was skipped) JS yields NaN and
      -- falls through to the D3133 throw below; guard against 10^nil in Lua.
      if part.n ~= nil and part.n ~= -1 then
        value = value % (10 ^ part.n)
      end
    end
    if part.names then
      if part.component == "M" or part.component == "x" then
        value = MONTHS[value]
      elseif part.component == "F" then
        value = DAYS[value]
      else
        H.err("D3133", { value = part.component })
      end
      if part.names == "upper" then
        value = value:upper()
      elseif part.names == "lower" then
        value = value:lower()
      end
      if part.width and part.width.max and #value > part.width.max then
        value = value:sub(1, part.width.max)
      end
    else
      value = FI.format(value, part.integerFormat)
    end
  elseif part.component == "f" then
    value = FI.format(value, part.integerFormat)
  elseif part.component == "Z" or part.component == "z" then
    local offset = offsetHours * 100 + offsetMinutes
    if part.integerFormat.regular then
      value = FI.format(offset, part.integerFormat)
    else
      local numDigits = part.integerFormat.mandatoryDigits
      if numDigits == 1 or numDigits == 2 then
        value = FI.format(offsetHours, part.integerFormat)
        if offsetMinutes ~= 0 then
          value = value .. ":" .. FI.format(offsetMinutes, FI.analyse("00"))
        end
      elseif numDigits == 3 or numDigits == 4 then
        value = FI.format(offset, part.integerFormat)
      else
        H.err("D3134", { value = numDigits })
      end
    end
    if offset >= 0 then
      value = "+" .. value
    end
    if part.component == "z" then
      value = "GMT" .. value
    end
    if offset == 0 and part.presentation2 == "t" then
      value = "Z"
    end
  elseif part.component == "P" then
    if part.names == "upper" then
      value = value:upper()
    end
  end
  return value
end

local function format_datetime(millis, picture, timezone)
  local offsetHours, offsetMinutes = 0, 0
  if not (timezone == nil or V.is_nothing(timezone)) then
    local offset = tonumber(timezone) or 0
    local sign = offset < 0 and -1 or 1
    offsetHours = sign * math.floor(math.abs(offset) / 100)
    offsetMinutes = offset - offsetHours * 100
  end

  local formatSpec
  if picture == nil or V.is_nothing(picture) then
    formatSpec = analyse_datetime_picture("[Y0001]-[M01]-[D01]T[H01]:[m01]:[s01].[f001][Z01:01t]")
  else
    formatSpec = analyse_datetime_picture(picture)
  end

  local offsetMillis = (60 * offsetHours + offsetMinutes) * 60000
  local comp = millis_to_components(millis + offsetMillis)

  local result = {}
  for _, part in ipairs(formatSpec.parts) do
    if part.type == "literal" then
      result[#result + 1] = part.value
    else
      result[#result + 1] = tostring(format_component(comp, part, offsetHours, offsetMinutes))
    end
  end
  return table.concat(result)
end

local R = {}

R.fromMillis = H.def(function(millis, picture, timezone)
  if V.is_nothing(millis) then
    return V.NOTHING
  end
  return format_datetime(millis, picture, timezone)
end, 1, 3, "<n-s?s?:s>")

R._internal = {
  calendar = calendar,
  get_datetime_fragment = get_datetime_fragment,
  analyse_datetime_picture = analyse_datetime_picture,
  format_datetime = format_datetime,
  days = DAYS,
  months = MONTHS,
}
return R
