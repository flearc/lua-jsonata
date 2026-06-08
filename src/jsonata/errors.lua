local M = {}

local ERROR_MT = { __name = "jsonata.error" }

-- Message templates for the M1 starter subset. Extended in later milestones.
local MESSAGES = {
  S0201 = "Syntax error",
  S0203 = "Expected token before end of expression",
  S0211 = "The symbol cannot be used as a unary operator",
  T0410 = "Argument of function does not match function signature",
  T1006 = "Attempted to invoke a non-function",
  T2001 = "The left side of an operator must evaluate to a number",
  T2002 = "The right side of an operator must evaluate to a number",
  T2010 = "Operands of comparison must both be numbers or both be strings",
  D3001 = "Unsupported in M1",
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
