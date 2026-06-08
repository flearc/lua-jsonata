local M = {}

local ERROR_MT = { __name = "jsonata.error" }

-- Message templates for the M1 starter subset. Extended in later milestones.
local MESSAGES = {
  S0201 = "Syntax error",
  S0203 = "Expected token before end of expression",
  S0211 = "The symbol cannot be used as a unary operator",
  T0410 = "Argument of function does not match function signature",
  T0412 = "Argument of function must be an array of strings",
  D3020 = "Third argument of function must be a positive integer",
  T1006 = "Attempted to invoke a non-function",
  T2001 = "The left side of an operator must evaluate to a number",
  T2002 = "The right side of an operator must evaluate to a number",
  T2010 = "Operands of comparison must both be numbers or both be strings",
  D3001 = "Unsupported in M1",
  D1001 = "Number out of range to be formatted",
  D3030 = "Unable to cast value to a number",
  D3047 = "Argument of aggregate function must be an array of numbers",
  D3060 = "$sqrt of a number that is less than zero",
  D3100 = "The radix of $formatBase must be between 2 and 36",
  D3137 = "$error() function evaluated",
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
    message = info.message or MESSAGES[code] or code,
  }, ERROR_MT)
  error(err, 0)
end

return M
