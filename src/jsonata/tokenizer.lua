local errors = require("jsonata.errors")

local M = {}
local Tokenizer = {}
Tokenizer.__index = Tokenizer

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
local MULTI_OPS = { ":=", "!=", "<=", ">=", "~>", ">>", "**" }
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

function M.new(source)
  return setmetatable({ src = source, pos = 1, len = #source }, Tokenizer)
end

function Tokenizer:_peek()
  return self.src:sub(self.pos, self.pos)
end

function Tokenizer:_skip_ws()
  while self.pos <= self.len do
    local c = self:_peek()
    if c == " " or c == "\t" or c == "\n" or c == "\r" then
      self.pos = self.pos + 1
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
        -- Encode the code point as UTF-8 (BMP-only handling is sufficient for M1).
        if code < 0x80 then
          buf[#buf + 1] = string.char(code)
        elseif code < 0x800 then
          buf[#buf + 1] = string.char(0xC0 + math.floor(code / 0x40), 0x80 + (code % 0x40))
        else
          buf[#buf + 1] = string.char(0xE0 + math.floor(code / 0x1000), 0x80 + (math.floor(code / 0x40) % 0x40), 0x80 + (code % 0x40))
        end
        self.pos = self.pos + 6
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

function Tokenizer:next()
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

  -- numbers
  if c:match("%d") then
    local num = self.src:match("^%d+%.?%d*[eE]?[%+%-]?%d*", self.pos)
    self.pos = self.pos + #num
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

  -- names / keywords
  if c:match("[%a_]") then
    local name = self.src:match("^[%a_][%w_]*", self.pos)
    self.pos = self.pos + #name
    if KEYWORDS[name] then
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

return M
