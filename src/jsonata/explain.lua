local V = require("jsonata.value")
local Tokenizer = require("jsonata.tokenizer")

local M = {}

-- Render an INTERNAL tagged value to a compact one-line string.
-- Order matters: sentinels are tables, and empty seq/array/object are all empty
-- tables distinguished only by metatable, so check sentinels first and
-- sequence-before-array. Uses value.lua predicates (NOT adapter.to_lua) to
-- preserve null/nothing/seq-vs-array/object-order distinctions.
local function render_value(x, seen)
  if V.is_nothing(x) then
    return "*nothing*"
  end
  if V.is_null(x) then
    return "null"
  end
  local tx = type(x)
  if tx ~= "table" then
    if tx == "string" then
      return string.format("%q", x)
    end
    if tx == "number" then
      if x == x and x ~= math.huge and x ~= -math.huge and x == math.floor(x) then
        return string.format("%.0f", x)
      end
      return tostring(x)
    end
    return tostring(x) -- boolean / other
  end
  if x._jsonata_lambda then
    return "<lambda>"
  end
  if x._jsonata_function then
    return "<function>"
  end
  seen = seen or {}
  if seen[x] then
    return "<cycle>"
  end
  seen[x] = true
  local out
  if V.is_sequence(x) then
    local parts = {}
    for i = 1, #x do
      parts[i] = render_value(x[i], seen)
    end
    out = "<seq:[" .. table.concat(parts, ", ") .. "]>"
  elseif V.is_array(x) then
    local parts = {}
    for i = 1, #x do
      parts[i] = render_value(x[i], seen)
    end
    out = "[" .. table.concat(parts, ", ") .. "]"
  elseif V.is_object(x) then
    local parts = {}
    local keys = V.obj_keys(x)
    for i = 1, #keys do
      local k = keys[i]
      parts[i] = tostring(k) .. ": " .. render_value(x.map[k], seen)
    end
    out = "{" .. table.concat(parts, ", ") .. "}"
  else
    out = "<" .. tostring(x) .. ">"
  end
  seen[x] = nil
  return out
end

M._render_value = render_value

local CHILD_FIELDS = {
  "lhs",
  "rhs",
  "expr",
  "filter",
  "expression",
  "condition",
  "then_expr",
  "else_expr",
  "procedure",
  "body",
  "pattern",
  "update",
  "delete",
}
local LIST_NODE_FIELDS = { "steps", "expressions", "arguments", "predicate" }

local function node_header(node)
  if node.value ~= nil then
    return node.type .. " (value=" .. tostring(node.value) .. ")"
  end
  return node.type
end

local function render_ast(node, indent, label)
  indent = indent or ""
  label = label or ""
  local lines = { indent .. label .. node_header(node) }
  local function emit(s)
    lines[#lines + 1] = s
  end
  local ci = indent .. "  "
  for _, f in ipairs(CHILD_FIELDS) do
    local c = node[f]
    if type(c) == "table" and c.type then
      emit(render_ast(c, ci, f .. ": "))
    end
  end
  for _, f in ipairs(LIST_NODE_FIELDS) do
    local list = node[f]
    if type(list) == "table" and #list > 0 then
      emit(ci .. f .. ":")
      for i = 1, #list do
        emit(render_ast(list[i], ci .. "  ", "[" .. i .. "] "))
      end
    end
  end
  if type(node.terms) == "table" and #node.terms > 0 then
    emit(ci .. "terms:")
    for i = 1, #node.terms do
      local term = node.terms[i]
      local dir = term.descending and " (descending)" or " (ascending)"
      emit(render_ast(term.expression, ci .. "  ", "[" .. i .. "]" .. dir .. " "))
    end
  end
  if type(node.pairs) == "table" and #node.pairs > 0 then
    emit(ci .. "pairs:")
    for i = 1, #node.pairs do
      local pr = node.pairs[i]
      emit(render_ast(pr[1], ci .. "  ", "[" .. i .. "] key: "))
      emit(render_ast(pr[2], ci .. "  ", "[" .. i .. "] val: "))
    end
  end
  if type(node.params) == "table" and #node.params > 0 then
    emit(ci .. "params: " .. table.concat(node.params, ", "))
  end
  return table.concat(lines, "\n")
end

M._render_ast = render_ast

local function render_tokens(source)
  local tk = Tokenizer.new(source)
  local lines = {}
  local i = 0
  local t = tk:next()
  while t ~= nil do
    i = i + 1
    lines[#lines + 1] = string.format("  [%d] %-9s %s", i, t.type, render_value(t.value))
    t = tk:next()
  end
  return table.concat(lines, "\n")
end

M._render_tokens = render_tokens

return M
