local M = {}

local ERROR_MT = { __name = "jsonata.error" }

-- Message templates for the M1 starter subset. Extended in later milestones.
local MESSAGES = {
  -- Syntax errors
  S0201 = "Syntax error",
  S0203 = "Expected token before end of expression",
  S0211 = "The symbol cannot be used as a unary operator",
  S0214 = "The right side of the {{token}} operator must be a variable name",
  S0215 = "A context variable binding must precede any predicates on a step in a path expression",
  S0216 = "A context variable binding must precede the order-by clause on a step in a path expression",
  S0217 = "The object representing the 'parent' cannot be derived from this expression",
  S0301 = "Empty regular expressions are not allowed",
  S0302 = "No terminating / in regular expression",
  S0303 = "Invalid regular expression: {{value}}",
  S0401 = "Type parameters can only be applied to functions and arrays",
  S0402 = "Choice groups containing parameterized types are not supported",
  -- Type errors
  T0410 = "Argument {{index}} of function {{token}} does not match function signature",
  T0411 = "Context value is not a compatible type with argument {{index}} of function {{token}}",
  T0412 = "Argument {{index}} of function {{token}} must be an array of {{type}}",
  T1003 = "Key in object structure must evaluate to a string; got: {{value}}",
  T1006 = "Attempted to invoke a non-function",
  T2001 = "The left side of an operator must evaluate to a number",
  T2006 = "The right side of the function application operator ~> must be a function",
  T2002 = "The right side of an operator must evaluate to a number",
  T2003 = "The left side of the range operator (..) must evaluate to an integer",
  T2004 = "The right side of the range operator (..) must evaluate to an integer",
  T2007 = "Type mismatch when comparing values {{value}} and {{value2}} in order-by clause",
  T2008 = "The expressions within an order-by clause must evaluate to numeric or string values",
  T2009 = "The values {{value}} and {{value2}} either side of operator {{token}} must be of the same data type",
  T2010 = "Operands of comparison must both be numbers or both be strings",
  T2011 = "The insert/update clause of the transform expression must evaluate to an object",
  T2012 = "The delete clause of the transform expression must evaluate to an array of strings",
  -- Dynamic / runtime errors
  D1001 = "Number out of range to be formatted",
  D1004 = "Regular expression matches zero length string at position {{position}}",
  D1002 = "Cannot negate a non-numeric value: {{value}}",
  D1009 = "Multiple key definitions evaluate to same key: {{value}}",
  D2014 = "The size of the sequence allocated by the range operator (..) must not exceed 1e7.  Attempted to allocate {{value}}.",
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
  D3120 = "Syntax error in expression passed to function eval: {{value}}",
  D3121 = "Dynamic error evaluating the expression passed to function eval: {{value}}",
}

function M.is_error(x)
  return type(x) == "table" and getmetatable(x) == ERROR_MT
end

-- Render a value the way jsonata's JSON.stringify would for {{x}} interpolation
-- (the scalar fields error messages reference: index/token/type/value).
local function render(v)
  if v == nil then
    return "undefined"
  elseif type(v) == "string" then
    return '"' .. v:gsub('"', '\\"') .. '"'
  else
    return tostring(v)
  end
end

-- Port of jsonata populateMessage: {{{k}}} -> raw field; {{k}} -> JSON.stringify(field).
local function populate(template, err)
  if type(template) ~= "string" then
    return template
  end
  template = template:gsub("{{{([%w_]+)}}}", function(k)
    local v = err[k]
    return v == nil and "undefined" or tostring(v)
  end)
  template = template:gsub("{{([%w_]+)}}", function(k)
    return render(err[k])
  end)
  return template
end

-- code: string error code; info: optional table with position/token/value/message
function M.raise(code, info)
  info = info or {}
  local err = setmetatable({
    code = code,
    index = info.index,
    type = info.type,
    position = info.position,
    token = info.token,
    value = info.value,
    value2 = info.value2,
    message = info.message or MESSAGES[code] or code,
  }, ERROR_MT)
  err.message = populate(err.message, err)
  error(err, 0)
end

return M
