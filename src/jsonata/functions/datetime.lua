local V = require("jsonata.value")
local H = require("jsonata.functions.helpers")
local FI = require("jsonata.functions.formatinteger")._internal

-- ===========================================================================
-- Faithful port of jsonata-js v2.2.1 datetime.js (fn:format-dateTime side).
-- Pure-Lua proleptic-Gregorian calendar (Hinnant civil<->days algorithms)
-- replaces JS Date.UTC / new Date(ms).getUTC*().
-- ===========================================================================

local MILLIS_IN_A_DAY = 86400000

local function days_from_civil(y, m, d)
  y = (m <= 2) and (y - 1) or y
  local era = math.floor((y >= 0 and y or (y - 399)) / 400)
  local yoe = y - era * 400
  local mp = (m > 2) and (m - 3) or (m + 9)
  local doy = math.floor((153 * mp + 2) / 5) + d - 1
  local doe = yoe * 365 + math.floor(yoe / 4) - math.floor(yoe / 100) + doy
  return era * 146097 + doe - 719468
end

local function civil_from_days(z)
  z = z + 719468
  local era = math.floor((z >= 0 and z or (z - 146096)) / 146097)
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

local R = {}
R._internal = { calendar = calendar }
return R
