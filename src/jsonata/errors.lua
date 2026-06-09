local M = {}

local ERROR_MT = { __name = "jsonata.error" }

-- Message templates for the M1 starter subset. Extended in later milestones.
local MESSAGES = {
  -- Syntax errors
  S0201 = "Syntax error",
  S0203 = "Expected token before end of expression",
  S0211 = "The symbol cannot be used as a unary operator",
  -- Type errors
  T0410 = "Argument of function does not match function signature",
  T0412 = "Argument of function must be an array of strings",
  T1003 = "Key in object structure must evaluate to a string; got: {{value}}",
  T1006 = "Attempted to invoke a non-function",
  T2001 = "The left side of an operator must evaluate to a number",
  T2002 = "The right side of an operator must evaluate to a number",
  T2007 = "Type mismatch when comparing values {{value}} and {{value2}} in order-by clause",
  T2008 = "The expressions within an order-by clause must evaluate to numeric or string values",
  T2010 = "Operands of comparison must both be numbers or both be strings",
  -- Dynamic / runtime errors
  D1001 = "Number out of range to be formatted",
  D1009 = "Multiple key definitions evaluate to same key: {{value}}",
  D3001 = "Unsupported in M1",
  D3020 = "Third argument of function must be a positive integer",
  D3030 = "Unable to cast value to a number",
  D3047 = "Argument of aggregate function must be an array of numbers",
  D3050 = "The second argument of reduce function must be a function with at least two arguments",
  D3060 = "$sqrt of a number that is less than zero",
  D3070 = "The single argument of the $sort function must be an array of strings or numbers. Use a comparator function to sort other types.",
  D3100 = "The radix of $formatBase must be between 2 and 36",
  D3137 = "$error() function evaluated",
  D3138 = "The single() function expected exactly 1 matching result.  Instead it matched more.",
  D3139 = "The single() function expected exactly 1 matching result.  Instead it matched 0.",
  D3141 = "$assert() statement failed",
}

function M.is_error(x)
  return type(x) == "table" and getmetatable(x) == ERROR_MT
end

-- code: string error code; info: optional table with position/token/value/message
function M.raise(code, info)
  info = info or {}
  local err = setmetatable({
    code = code,
    position = info.position,
    token = info.token,
    value = info.value,
    value2 = info.value2,
    message = info.message or MESSAGES[code] or code,
  }, ERROR_MT)
  error(err, 0)
end

return M
