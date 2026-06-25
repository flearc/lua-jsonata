-- Lazy PCRE2 adapter. require("rex_pcre2") happens on first compile, so
-- non-regex programs never load it.
local M = {}

local rex -- cached module

local function engine()
  if rex == nil then
    rex = require("rex_pcre2")
  end
  return rex
end

-- Compile /source/flags (jsonata flags: i, m only) into a PCRE2 matcher.
function M.compile(source, flags)
  local e = engine()
  local F = e.flags()
  local cf = 0
  if flags:find("i", 1, true) then
    cf = cf + F.CASELESS
  end
  if flags:find("m", 1, true) then
    cf = cf + F.MULTILINE
  end
  local ok, matcher = pcall(e.new, source, cf)
  if not ok then
    error({ code = "S0303", position = 0, value = source }, 0)
  end
  return matcher
end

-- First match at or after 0-based char index `from`. Returns a plain table
-- { match=<str>, start=<0-based>, ["end"]=<0-based exclusive>, groups={...} } or nil.
-- (PCRE2 byte offsets == char offsets for ASCII; multibyte is a documented edge.)
function M.first(matcher, str, from)
  local init = (from or 0) + 1 -- 1-based byte
  local st, en, caps = matcher:tfind(str, init)
  if not st then
    return nil
  end
  local matched = (en < st) and "" or str:sub(st, en)
  return {
    match = matched,
    start = st - 1,
    ["end"] = st - 1 + #matched,
    groups = caps or {},
  }
end

return M
