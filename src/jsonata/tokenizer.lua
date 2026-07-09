local errors = require("jsonata.errors")

local M = {}
local Tokenizer = {}
Tokenizer.__index = Tokenizer
local operand_expected

local KEYWORDS = {
  ["true"] = true,
  ["false"] = true,
  ["null"] = true,
  ["and"] = true,
  ["or"] = true,
  ["in"] = true,
  ["function"] = true,
}

-- Multi-character operators, longest first.
local MULTI_OPS = { ":=", "!=", "<=", ">=", "~>", ">>", "**", "..", "??", "?:" }
local SINGLE_OPS = "%.%[%]{}%(%)%+%-%*/%%=<>&|%^?:;,@#~"

local ESCAPES = {
  ["n"] = "\n",
  ["t"] = "\t",
  ["r"] = "\r",
  ["f"] = "\f",
  ["b"] = "\b",
  ['"'] = '"',
  ["'"] = "'",
  ["\\"] = "\\",
  ["/"] = "/",
}

local function utf8_from_codepoint(code)
  if code < 0x80 then
    return string.char(code)
  elseif code < 0x800 then
    return string.char(0xC0 + math.floor(code / 0x40), 0x80 + (code % 0x40))
  elseif code < 0x10000 then
    return string.char(0xE0 + math.floor(code / 0x1000), 0x80 + (math.floor(code / 0x40) % 0x40), 0x80 + (code % 0x40))
  end
  return string.char(
    0xF0 + math.floor(code / 0x40000),
    0x80 + (math.floor(code / 0x1000) % 0x40),
    0x80 + (math.floor(code / 0x40) % 0x40),
    0x80 + (code % 0x40)
  )
end

function M.new(source)
  return setmetatable({ src = source, pos = 1, len = #source, _prev = nil }, Tokenizer)
end

function Tokenizer:_peek()
  return self.src:sub(self.pos, self.pos)
end

function Tokenizer:_skip_ws()
  while self.pos <= self.len do
    local c = self:_peek()
    if c == " " or c == "\t" or c == "\n" or c == "\r" then
      self.pos = self.pos + 1
    elseif c == "/" and self.src:sub(self.pos + 1, self.pos + 1) == "*" then
      local finish = self.src:find("*/", self.pos + 2, true)
      if not finish then
        errors.raise("S0201", { position = self.pos, token = "/*" })
      end
      self.pos = finish + 2
    else
      break
    end
  end
end

function Tokenizer:_read_string(quote)
  local start = self.pos
  self.pos = self.pos + 1 -- skip opening quote
  local buf = {}
  while self.pos <= self.len do
    local c = self:_peek()
    if c == "\\" then
      local nxt = self.src:sub(self.pos + 1, self.pos + 1)
      if nxt == "u" then
        local hex = self.src:sub(self.pos + 2, self.pos + 5)
        local code = tonumber(hex, 16)
        if not code then
          errors.raise("S0201", { position = self.pos, token = "\\u" })
        end
        local width = 6
        if code >= 0xD800 and code <= 0xDBFF and self.src:sub(self.pos + 6, self.pos + 7) == "\\u" then
          local low = tonumber(self.src:sub(self.pos + 8, self.pos + 11), 16)
          if low and low >= 0xDC00 and low <= 0xDFFF then
            code = 0x10000 + (code - 0xD800) * 0x400 + (low - 0xDC00)
            width = 12
          end
        end
        buf[#buf + 1] = utf8_from_codepoint(code)
        self.pos = self.pos + width
      elseif ESCAPES[nxt] then
        buf[#buf + 1] = ESCAPES[nxt]
        self.pos = self.pos + 2
      else
        errors.raise("S0201", { position = self.pos, token = "\\" .. nxt })
      end
    elseif c == quote then
      self.pos = self.pos + 1
      return { type = "string", value = table.concat(buf), position = start }
    else
      buf[#buf + 1] = c
      self.pos = self.pos + 1
    end
  end
  errors.raise("S0201", { position = start, token = quote })
end

function Tokenizer:_read_backtick()
  local start = self.pos
  self.pos = self.pos + 1
  local s = self.pos
  while self.pos <= self.len and self:_peek() ~= "`" do
    self.pos = self.pos + 1
  end
  if self.pos > self.len then
    errors.raise("S0201", { position = start, token = "`" })
  end
  local value = self.src:sub(s, self.pos - 1)
  self.pos = self.pos + 1
  return { type = "name", value = value, position = start }
end

function Tokenizer:_next_raw()
  self:_skip_ws()
  if self.pos > self.len then
    return nil
  end
  local start = self.pos
  local c = self:_peek()

  -- strings
  if c == '"' or c == "'" then
    return self:_read_string(c)
  end
  if c == "`" then
    return self:_read_backtick()
  end

  -- numbers (a decimal point must be followed by digits, so 1..5 is not "1.")
  if c:match("%d") then
    local s = self.pos
    local len = #self.src:match("^%d+", s)
    local frac = self.src:match("^%.%d+", s + len)
    if frac then
      len = len + #frac
    end
    local exp = self.src:match("^[eE][%+%-]?%d+", s + len)
    if exp then
      len = len + #exp
    end
    local num = self.src:sub(s, s + len - 1)
    self.pos = s + len
    return { type = "number", value = tonumber(num), position = start }
  end

  -- variables
  if c == "$" then
    self.pos = self.pos + 1
    local name = self.src:match("^[%a_][%w_]*", self.pos) or ""
    self.pos = self.pos + #name
    -- handle $$ (root) : name will be "" and next char is $
    if name == "" and self:_peek() == "$" then
      self.pos = self.pos + 1
      return { type = "variable", value = "$", position = start }
    end
    return { type = "variable", value = name, position = start }
  end

  -- λ (U+03BB, UTF-8 0xCE 0xBB) is an alias for the `function` keyword.
  if self.src:sub(self.pos, self.pos + 1) == "\206\187" then
    self.pos = self.pos + 2
    return { type = "keyword", value = "function", position = start }
  end

  -- names / keywords
  if c:match("[%a_]") then
    local name = self.src:match("^[%a_][%w_]*", self.pos)
    self.pos = self.pos + #name
    if KEYWORDS[name] then
      if (name == "and" or name == "or" or name == "in") and operand_expected(self._prev) then
        return { type = "name", value = name, position = start }
      end
      return { type = "keyword", value = name, position = start }
    end
    return { type = "name", value = name, position = start }
  end

  -- multi-char operators
  for _, op in ipairs(MULTI_OPS) do
    if self.src:sub(self.pos, self.pos + #op - 1) == op then
      self.pos = self.pos + #op
      return { type = "operator", value = op, position = start }
    end
  end

  -- single-char operators
  if c:match("[" .. SINGLE_OPS .. "]") then
    self.pos = self.pos + 1
    return { type = "operator", value = c, position = start }
  end

  errors.raise("S0201", { position = start, token = c })
end

-- A `/` is a regex when an operand is expected, division when a value precedes.
local VALUE_END_KEYWORDS = { ["true"] = true, ["false"] = true, ["null"] = true }
function operand_expected(prev)
  if prev == nil then
    return true
  end
  local t, v = prev.type, prev.value
  if t == "number" or t == "string" or t == "variable" or t == "name" then
    return false
  end
  if t == "operator" and (v == ")" or v == "]" or v == "}") then
    return false
  end
  if t == "keyword" and VALUE_END_KEYWORDS[v] then
    return false
  end
  return true
end

function Tokenizer:next()
  self:_skip_ws()
  if self.pos <= self.len and self:_peek() == "/" and operand_expected(self._prev) then
    local tok = self:_read_regex()
    self._prev = tok
    return tok
  end
  local tok = self:_next_raw()
  self._prev = tok
  return tok
end

function Tokenizer:_read_regex()
  local start = self.pos
  self.pos = self.pos + 1 -- consume opening '/'
  local pat_start = self.pos
  local depth = 0
  while self.pos <= self.len do
    local ch = self:_peek()
    if ch == "\\" then
      self.pos = self.pos + 2 -- skip escaped char
    elseif ch == "/" and depth == 0 then
      local pattern = self.src:sub(pat_start, self.pos - 1)
      if pattern == "" then
        errors.raise("S0301", { position = self.pos })
      end
      self.pos = self.pos + 1 -- consume closing '/'
      local fstart = self.pos
      while self.pos <= self.len do
        local f = self:_peek()
        if f == "i" or f == "m" then
          self.pos = self.pos + 1
        else
          break
        end
      end
      local flags = self.src:sub(fstart, self.pos - 1)
      return { type = "regex", source = pattern, flags = flags, position = start }
    else
      if ch == "(" or ch == "[" or ch == "{" then
        depth = depth + 1
      elseif ch == ")" or ch == "]" or ch == "}" then
        depth = depth - 1
      end
      self.pos = self.pos + 1
    end
  end
  errors.raise("S0302", { position = self.pos })
end

return M
