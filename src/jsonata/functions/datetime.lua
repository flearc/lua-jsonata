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

local R = {}
R._internal = { calendar = calendar, get_datetime_fragment = get_datetime_fragment }
return R
