-- Port of jsonata-js v2.2.1 src/signature.js: compile a function-signature
-- string into a validator. jsonata builds a JS RegExp; we build an equivalent
-- Lua pattern (the signature regex uses only [class], ?, +, captures, ^$).
local V = require("jsonata.value")
local errors = require("jsonata.errors")

local M = {}

-- subtype char -> English plural, for the T0412 `type` field.
local ARRAY_SIG_MAPPING = {
  a = "arrays",
  b = "booleans",
  f = "functions",
  n = "numbers",
  o = "objects",
  s = "strings",
}

-- Map a runtime value to a single-char type symbol (jsonata getSymbol).
-- Function FIRST: a function value is an MT-less table -> V.typeof says "object".
local function get_symbol(value)
  if V.is_nothing(value) then
    return "m"
  end
  if type(value) == "table" and (value._jsonata_function or value._jsonata_lambda) then
    return "f"
  end
  local t = V.typeof(value)
  if t == "null" then
    return "l"
  elseif t == "number" then
    return "n"
  elseif t == "string" then
    return "s"
  elseif t == "boolean" then
    return "b"
  elseif t == "array" then
    return "a"
  elseif t == "object" then
    return "o"
  end
  return "m"
end
M.get_symbol = get_symbol

-- Position (1-based) of the close bracket balancing the open at `start`.
local function find_closing(s, start, open, close)
  local depth = 1
  local pos = start
  while pos < #s do
    pos = pos + 1
    local ch = s:sub(pos, pos)
    if ch == close then
      depth = depth - 1
      if depth == 0 then
        break
      end
    elseif ch == open then
      depth = depth + 1
    end
  end
  return pos
end

-- Parse "<...>" into a validator object. Raises S0401/S0402 on bad signatures.
function M.parse(signature)
  local params = {}
  local param = {}
  local prev = param
  local function next_param()
    params[#params + 1] = param
    prev = param
    param = {}
  end

  local position = 2 -- skip the leading '<' (char 1)
  while position <= #signature do
    local symbol = signature:sub(position, position)
    if symbol == ":" then
      break -- return type ignored
    elseif symbol == "s" or symbol == "n" or symbol == "b" or symbol == "l" or symbol == "o" then
      param.regex = "[" .. symbol .. "m]"
      param.type = symbol
      next_param()
    elseif symbol == "a" then
      param.regex = "[asnblfom]"
      param.type = "a"
      param.array = true
      next_param()
    elseif symbol == "f" then
      param.regex = "f"
      param.type = "f"
      next_param()
    elseif symbol == "j" then
      param.regex = "[asnblom]"
      param.type = "j"
      next_param()
    elseif symbol == "x" then
      param.regex = "[asnblfom]"
      param.type = "x"
      next_param()
    elseif symbol == "-" then
      prev.context = true
      prev.context_regex = prev.regex -- snapshot before adding '?'
      prev.regex = prev.regex .. "?"
    elseif symbol == "?" or symbol == "+" then
      prev.regex = prev.regex .. symbol
    elseif symbol == "(" then
      local end_paren = find_closing(signature, position, "(", ")")
      local choice = signature:sub(position + 1, end_paren - 1)
      if choice:find("<", 1, true) then
        errors.raise("S0402", { value = choice, position = position })
      end
      param.regex = "[" .. choice .. "m]"
      param.type = "(" .. choice .. ")"
      position = end_paren
      next_param()
    elseif symbol == "<" then
      if prev.type == "a" or prev.type == "f" then
        local end_pos = find_closing(signature, position, "<", ">")
        prev.subtype = signature:sub(position + 1, end_pos - 1)
        position = end_pos
      else
        errors.raise("S0401", { value = prev.type, position = position })
      end
    end
    position = position + 1
  end

  local pieces = {}
  for i = 1, #params do
    pieces[i] = "(" .. params[i].regex .. ")"
  end
  local pattern = "^" .. table.concat(pieces) .. "$"

  return { params = params, pattern = pattern, _mapping = ARRAY_SIG_MAPPING }
end

return M
