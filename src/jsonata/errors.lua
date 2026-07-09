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
  D3001 = "Attempting to invoke string function on Infinity or NaN",
  D3020 = "Third argument of function must be a positive integer",
  D3030 = "Unable to cast value to a number",
  D3047 = "Argument of aggregate function must be an array of numbers",
  D3050 = "The second argument of reduce function must be a function with at least two arguments",
  D3060 = "$sqrt of a number that is less than zero",
  D3070 = "The single argument of the $sort function must be an array of strings or numbers. Use a comparator function to sort other types.",
  D3100 = "The radix of $formatBase must be between 2 and 36",
  D3080 = "The picture string must only contain a maximum of two sub-pictures",
  D3081 = "The sub-picture must not contain more than one instance of the 'decimal-separator' character",
  D3082 = "The sub-picture must not contain more than one instance of the 'percent' character",
  D3083 = "The sub-picture must not contain more than one instance of the 'per-mille' character",
  D3084 = "The sub-picture must not contain both a 'percent' and a 'per-mille' character",
  D3085 = "The mantissa part of a sub-picture must contain at least one character that is either an 'optional digit character' or a member of the 'decimal digit family'",
  D3086 = "The sub-picture must not contain a passive character that is preceded by an active character and that is followed by another active character",
  D3087 = "The sub-picture must not contain a 'grouping-separator' character that appears adjacent to a 'decimal-separator' character",
  D3088 = "The sub-picture must not contain a 'grouping-separator' at the end of the integer part",
  D3089 = "The sub-picture must not contain two adjacent instances of the 'grouping-separator' character",
  D3090 = "The integer part of the sub-picture must not contain a member of the 'decimal digit family' that is followed by an instance of the 'optional digit character'",
  D3091 = "The fractional part of the sub-picture must not contain an instance of the 'optional digit character' that is followed by a member of the 'decimal digit family'",
  D3092 = "A sub-picture that contains a 'percent' or 'per-mille' character must not contain a character treated as an 'exponent-separator'",
  D3093 = "The exponent part of the sub-picture must comprise only of one or more characters that are members of the 'decimal digit family'",
  D3130 = "Formatting or parsing an integer as a sequence starting with {{value}} is not supported by this implementation",
  D3131 = "In a decimal digit pattern, all digits must be from the same decimal group",
  D3132 = "Unknown component specifier {{value}} in date/time picture string",
  D3133 = "The 'name' modifier can only be applied to months and days in the date/time picture string, not {{value}}",
  D3134 = "The timezone integer format specifier cannot have more than four digits",
  D3110 = "The argument of the toMillis function must be an ISO 8601 formatted timestamp. Given {{value}}",
  D3136 = "The date/time picture string is missing specifiers required to parse the timestamp",
  D3135 = "No matching closing bracket ']' in date/time picture string",
  D3137 = "$error() function evaluated",
  D3138 = "The single() function expected exactly 1 matching result.  Instead it matched more.",
  D3139 = "The single() function expected exactly 1 matching result.  Instead it matched 0.",
  D3140 = "Malformed URL passed to ${{{functionName}}}(): {{value}}",
  D3141 = "$assert() statement failed",
  D3120 = "Syntax error in expression passed to function eval: {{value}}",
  D3121 = "Dynamic error evaluating the expression passed to function eval: {{value}}",
  D3010 = "Second argument of replace function cannot be an empty string",
  D3011 = "Fourth argument of replace function must evaluate to a positive number",
  D3012 = "Attempted to replace a matched string with a non-string value",
  D3040 = "Third argument of match function must evaluate to a positive number",
  T1010 = "The matcher function argument passed to function {{token}} does not return the correct object structure",
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
