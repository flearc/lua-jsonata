local V = require("jsonata.value")
local Tokenizer = require("jsonata.tokenizer")
local Parser = require("jsonata.parser")

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

local function render_error(err)
  if type(err) == "table" then
    local s = err.code or "error"
    if err.position then
      s = s .. " at position " .. tostring(err.position)
    end
    if err.token ~= nil then
      s = s .. " (token: " .. tostring(err.token) .. ")"
    end
    return s
  end
  return tostring(err)
end
M._render_error = render_error

local function node_label(node)
  local t = node.type
  if t == "name" then
    return string.format('name "%s"', tostring(node.value))
  elseif t == "variable" then
    local v = node.value
    if v == "" then
      return "$"
    end
    return "$" .. tostring(v)
  elseif t == "binary" or t == "unary" or t == "bind" then
    return string.format('%s "%s"', t, tostring(node.value))
  elseif t == "number" then
    return "number " .. render_value(node.value)
  elseif t == "string" then
    return "string " .. render_value(node.value)
  elseif t == "boolean" then
    return "boolean " .. tostring(node.value)
  end
  return t
end

-- Build the {pre,post} hook that collects a trace tree during evaluation.
-- Scope note: this observes every node evaluated through the evaluator's
-- `evaluate` seam (the path node itself, predicates, operators, function calls,
-- self-contained path steps, HOF/lambda/transform sub-evaluations). It does NOT
-- show `name`/`variable` path steps that `eval_step_on_item` resolves inline
-- (a deliberate evaluator fast path) -- use the `ast`/`ast-norm` stages to see
-- the full step structure. This keeps the evaluation hot path untouched.
local function make_eval_hook()
  local root = { children = {} }
  local stack = { root }
  local hook = {
    pre = function(node, input)
      local e = { label = node_label(node), input = render_value(input), children = {} }
      local top = stack[#stack]
      top.children[#top.children + 1] = e
      stack[#stack + 1] = e
    end,
    post = function(_, _, _, result)
      local e = stack[#stack]
      e.result = render_value(result)
      stack[#stack] = nil
    end,
  }
  return hook, root
end

local function render_trace_tree(entry, indent, lines)
  lines[#lines + 1] = string.format("%s%s  $=%s  => %s", indent, entry.label, entry.input, entry.result or "?")
  for _, child in ipairs(entry.children) do
    render_trace_tree(child, indent .. "  ", lines)
  end
end

local function render_eval(source, input)
  local lines = {}
  local ok, err = pcall(function()
    local jsonata = require("jsonata")
    local expr = jsonata.compile(source)
    local hook, root = make_eval_hook()
    expr._explain_hook = hook
    expr:evaluate(input)
    for _, child in ipairs(root.children) do
      render_trace_tree(child, "  ", lines)
    end
    local top = root.children[#root.children]
    if top then
      lines[#lines + 1] = "=> " .. (top.result or "?")
    end
  end)
  if not ok then
    lines[#lines + 1] = "!! error: " .. render_error(err)
  end
  return table.concat(lines, "\n")
end

M._render_eval = render_eval

local function section(title, body)
  return "== " .. title .. " ==\n" .. body
end

function M.explain(source, input, stage)
  stage = stage or "all"
  local parts = {}
  local function add(title, fn)
    local ok, body = pcall(fn)
    if not ok then
      body = "!! error: " .. render_error(body)
    end
    parts[#parts + 1] = section(title, body)
  end
  if stage == "tokens" or stage == "all" then
    add("TOKENS", function()
      return render_tokens(source)
    end)
  end
  if stage == "ast" or stage == "all" then
    add("AST (raw, pre-process_ast)", function()
      return render_ast(Parser.parse_raw(source))
    end)
  end
  if stage == "ast-norm" or stage == "all" then
    add("AST (normalized, post-process_ast)", function()
      return render_ast(Parser.parse(source))
    end)
  end
  if stage == "eval" or stage == "all" then
    add("EVAL", function()
      return render_eval(source, input)
    end)
  end
  if #parts == 0 then
    error("unknown explain stage: " .. tostring(stage))
  end
  return table.concat(parts, "\n\n")
end

return M
