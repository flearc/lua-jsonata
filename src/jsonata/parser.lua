local tokenizer = require("jsonata.tokenizer")
local errors = require("jsonata.errors")

local M = {}

-- Symbol table: maps an id to { lbp, nud, led }.
local symbols = {}

local function symbol(id, lbp)
  local s = symbols[id]
  if s == nil then
    s = { id = id, lbp = lbp or 0 }
    symbols[id] = s
  elseif lbp and lbp > s.lbp then
    s.lbp = lbp
  end
  return s
end

-- Parser state is held in a closure created per parse() call.
local function make_parser(source)
  local tk = tokenizer.new(source)
  local self = { node = nil }

  local END = { id = "(end)", lbp = 0, type = "(end)" }

  -- Resolve a raw token into a "node" carrying its symbol behavior.
  local function tok_to_node(t)
    if t == nil then
      return setmetatable({}, { __index = END })
    end
    local node = {
      type = t.type,
      value = t.value,
      position = t.position,
    }
    if t.type == "operator" or t.type == "keyword" then
      local sym = symbols[t.value]
      if sym == nil then
        errors.raise("S0201", { position = t.position, token = t.value })
      end
      node.lbp = sym.lbp
      node.nud = sym.nud
      node.led = sym.led
      node.id = t.value
    else
      -- literals / names / variables are terminals
      node.lbp = 0
    end
    return node
  end

  function self.advance()
    self.node = tok_to_node(tk:next())
    return self.node
  end

  function self.expression(rbp)
    local t = self.node
    self.advance()
    if t.nud == nil then
      if t.type == "number" or t.type == "string" or t.type == "name" or t.type == "variable" then
        -- terminals build themselves below
      elseif t.type == "(end)" then
        errors.raise("S0203", { position = #source })
      else
        errors.raise("S0211", { position = t.position, token = t.value })
      end
    end
    local left
    if t.nud then
      left = t.nud(self, t)
    else
      left = self.terminal(t)
    end
    while rbp < self.node.lbp do
      t = self.node
      self.advance()
      left = t.led(self, t, left)
    end
    return left
  end

  -- Build a clean AST node for a terminal token.
  function self.terminal(t)
    if t.type == "number" or t.type == "string" then
      return { type = t.type, value = t.value, position = t.position }
    elseif t.type == "keyword" then
      if t.value == "true" then
        return { type = "boolean", value = true, position = t.position }
      elseif t.value == "false" then
        return { type = "boolean", value = false, position = t.position }
      elseif t.value == "null" then
        return { type = "null", value = nil, position = t.position }
      end
    elseif t.type == "name" then
      return { type = "name", value = t.value, position = t.position }
    elseif t.type == "variable" then
      return { type = "variable", value = t.value, position = t.position }
    end
    errors.raise("S0201", { position = t.position, token = tostring(t.value) })
  end

  return self
end

-- nud for keyword terminals (true/false/null) so expression() can dispatch them.
local function register_keyword_terminals()
  for _, kw in ipairs({ "true", "false", "null" }) do
    local s = symbol(kw, 0)
    s.nud = function(p, t)
      return p.terminal(t)
    end
  end
end
register_keyword_terminals()

-- Binding powers (mirrors jsonata-js precedence).
local function infix(id, bp)
  local s = symbol(id, bp)
  s.led = function(p, t, left)
    return { type = "binary", value = id, lhs = left, rhs = p.expression(bp), position = t.position }
  end
  return s
end

local function infixr(id, bp, node_type)
  local s = symbol(id, bp)
  s.led = function(p, t, left)
    return {
      type = node_type or "binary",
      value = id,
      lhs = left,
      rhs = p.expression(bp - 1),
      position = t.position,
    }
  end
  return s
end

local function prefix(id, bp)
  local s = symbol(id, 0)
  s.nud = function(p, t)
    return { type = "unary", value = id, expression = p.expression(bp), position = t.position }
  end
  return s
end

-- Arithmetic
infix("+", 50)
infix("-", 50)
infix("*", 60)
infix("/", 60)
infix("%", 60)
-- Comparison
infix("=", 40)
infix("!=", 40)
infix("<", 40)
infix("<=", 40)
infix(">", 40)
infix(">=", 40)
-- Boolean
infix("and", 30)
infix("or", 25)
-- String concat
infix("&", 50)
-- Unary minus (high binding power)
prefix("-", 70)
-- Assignment (right-associative) -> "bind" node
infixr(":=", 10, "bind")

-- Path operator: build a temporary binary "." node; processAST flattens it.
infix(".", 75)

-- Parentheses: grouping / block
do
  local s = symbol("(", 80)
  s.nud = function(p, t)
    local expressions = {}
    if p.node.id ~= ")" then
      expressions[#expressions + 1] = p.expression(0)
      while p.node.id == ";" do
        p.advance()
        expressions[#expressions + 1] = p.expression(0)
      end
    end
    if p.node.id ~= ")" then
      errors.raise("S0203", { position = p.node.position, token = ")" })
    end
    p.advance() -- consume ')'
    if #expressions == 1 then
      return expressions[1]
    end
    return { type = "block", expressions = expressions, position = t.position }
  end
end
-- Function call: name/variable immediately followed by '(' .
do
  local s = symbols["("]
  s.led = function(p, t, left)
    local args = {}
    if p.node.id ~= ")" then
      args[#args + 1] = p.expression(0)
      while p.node.id == "," do
        p.advance()
        args[#args + 1] = p.expression(0)
      end
    end
    if p.node.id ~= ")" then
      errors.raise("S0203", { position = p.node.position, token = ")" })
    end
    p.advance()
    return { type = "function", procedure = left, arguments = args, position = t.position }
  end
end
symbol(")", 0)
symbol(";", 0)

-- Array constructor (nud) and predicate/index (led) share '['.
do
  local s = symbol("[", 80)
  s.nud = function(p, t)
    local expressions = {}
    if p.node.id ~= "]" then
      expressions[#expressions + 1] = p.expression(0)
      while p.node.id == "," do
        p.advance()
        expressions[#expressions + 1] = p.expression(0)
      end
    end
    if p.node.id ~= "]" then
      errors.raise("S0203", { position = p.node.position, token = "]" })
    end
    p.advance()
    return { type = "array", expressions = expressions, position = t.position }
  end
  s.led = function(p, t, left)
    local filter = p.expression(0)
    if p.node.id ~= "]" then
      errors.raise("S0203", { position = p.node.position, token = "]" })
    end
    p.advance()
    -- Mark as predicate applied to `left`; processAST relocates it onto a step.
    return { type = "predicate", expr = left, filter = filter, position = t.position }
  end
end
symbol("]", 0)
symbol(",", 0)

-- Object constructor.
do
  local s = symbol("{", 70)
  s.nud = function(p, t)
    local pairs_list = {}
    if p.node.id ~= "}" then
      repeat
        local key = p.expression(0)
        if p.node.id ~= ":" then
          errors.raise("S0203", { position = p.node.position, token = ":" })
        end
        p.advance()
        local val = p.expression(0)
        pairs_list[#pairs_list + 1] = { key, val }
        if p.node.id == "," then
          p.advance()
        else
          break
        end
      until false
    end
    if p.node.id ~= "}" then
      errors.raise("S0203", { position = p.node.position, token = "}" })
    end
    p.advance()
    return { type = "object", pairs = pairs_list, position = t.position }
  end
end
symbol("}", 0)
symbol(":", 0)

-- Group-by operator: lhs { key : value (, key : value)* }. Binding power 70 so
-- the left path forms first (e.g. Account.Order.Product{ProductID: Price}).
do
  local s = symbol("{", 70)
  s.led = function(p, t, left)
    local pairs_list = {}
    if p.node.id ~= "}" then
      repeat
        local key = p.expression(0)
        if p.node.id ~= ":" then
          errors.raise("S0203", { position = p.node.position, token = ":" })
        end
        p.advance() -- ':'
        local val = p.expression(0)
        pairs_list[#pairs_list + 1] = { key, val }
        if p.node.id == "," then
          p.advance()
        else
          break
        end
      until false
    end
    if p.node.id ~= "}" then
      errors.raise("S0203", { position = p.node.position, token = "}" })
    end
    p.advance() -- '}'
    return { type = "group", lhs = left, pairs = pairs_list, position = t.position }
  end
end

-- Ternary conditional.
do
  local s = symbol("?", 20)
  s.led = function(p, t, left)
    local then_expr = p.expression(0)
    if p.node.id ~= ":" then
      errors.raise("S0203", { position = p.node.position, token = ":" })
    end
    p.advance()
    local else_expr = p.expression(0)
    return {
      type = "condition",
      condition = left,
      then_expr = then_expr,
      else_expr = else_expr,
      position = t.position,
    }
  end
end

-- Placeholder for partial application (? in prefix/argument position).
symbols["?"].nud = function(p, t)
  return { type = "placeholder", position = t.position }
end

-- Lambda: function ( $a, $b ) { body }
do
  local s = symbol("function", 0)
  s.nud = function(p, t)
    if p.node.id ~= "(" then
      errors.raise("S0203", { position = p.node.position, token = "(" })
    end
    p.advance() -- consume '('
    local params = {}
    if p.node.id ~= ")" then
      while true do
        if p.node.type ~= "variable" then
          errors.raise("S0203", { position = p.node.position, token = tostring(p.node.value) })
        end
        params[#params + 1] = p.node.value
        p.advance()
        if p.node.id == "," then
          p.advance()
        else
          break
        end
      end
    end
    if p.node.id ~= ")" then
      errors.raise("S0203", { position = p.node.position, token = ")" })
    end
    p.advance() -- consume ')'
    if p.node.id ~= "{" then
      errors.raise("S0203", { position = p.node.position, token = "{" })
    end
    p.advance() -- consume '{'
    local body = p.expression(0)
    if p.node.id ~= "}" then
      errors.raise("S0203", { position = p.node.position, token = "}" })
    end
    p.advance() -- consume '}'
    return { type = "lambda", params = params, body = body, position = t.position }
  end
end

-- Range operator: lhs .. rhs -> an integer sequence. Binding power 20.
do
  local s = symbol("..", 20)
  s.led = function(p, t, left)
    return { type = "range", lhs = left, rhs = p.expression(20), position = t.position }
  end
end

-- Apply / chain operator. RHS is kept as AST: its call-shape decides whether
-- the LHS is prepended as the first argument (evaluated in the evaluator).
do
  local s = symbol("~>", 40)
  s.led = function(p, t, left)
    return { type = "apply", lhs = left, rhs = p.expression(40), position = t.position }
  end
end

-- Transform operator: | pattern | update [, delete] |. Prefix (the rhs of ~>).
-- lbp stays 0 so the inner expressions stop at the next '|' / ','.
do
  local s = symbol("|", 0)
  s.nud = function(p, t)
    local pattern = p.expression(0)
    if p.node.id ~= "|" then
      errors.raise("S0203", { position = p.node.position, token = "|" })
    end
    p.advance() -- middle '|'
    local update = p.expression(0)
    local del = nil
    if p.node.id == "," then
      p.advance()
      del = p.expression(0)
    end
    if p.node.id ~= "|" then
      errors.raise("S0203", { position = p.node.position, token = "|" })
    end
    p.advance() -- closing '|'
    return { type = "transform", pattern = pattern, update = update, delete = del, position = t.position }
  end
end

-- Order-by operator: lhs ^ ( [<|>] term (, [<|>] term)* ). Binding power 40 so
-- the left path/index forms first (e.g. Account.Order.Product^(Price).SKU).
do
  local s = symbol("^", 40)
  s.led = function(p, t, left)
    if p.node.id ~= "(" then
      errors.raise("S0203", { position = p.node.position, token = "(" })
    end
    p.advance() -- consume '('
    local terms = {}
    while true do
      local descending = false
      if p.node.id == "<" then
        p.advance()
      elseif p.node.id == ">" then
        descending = true
        p.advance()
      end
      terms[#terms + 1] = { expression = p.expression(0), descending = descending }
      if p.node.id ~= "," then
        break
      end
      p.advance() -- consume ','
    end
    if p.node.id ~= ")" then
      errors.raise("S0203", { position = p.node.position, token = ")" })
    end
    p.advance() -- consume ')'
    return { type = "sort", lhs = left, terms = terms, position = t.position }
  end
end

do
  local s = symbol("*", 60)
  s.nud = function(p, t)
    return { type = "wildcard", position = t.position }
  end
end

-- Descendant `**`: a prefix-only terminal (no led). `**` already tokenizes via
-- MULTI_OPS; this registers its symbol so it parses to a descendant node.
do
  local s = symbol("**")
  s.nud = function(p, t)
    return { type = "descendant", position = t.position }
  end
end

-- Parent `%`: a prefix-only terminal in step position; `%` keeps its infix
-- modulo led (same nud/led coexistence as `*` wildcard vs multiply).
do
  local s = symbol("%", 60)
  s.nud = function(p, t)
    return { type = "parent", position = t.position }
  end
end

function M.parse_raw(source)
  local p = make_parser(source)
  p.advance()
  local ast = p.expression(0)
  if p.node.type ~= "(end)" then
    errors.raise("S0201", { position = p.node.position, token = p.node.value })
  end
  return ast
end

function M.parse(source)
  return M.process_ast(M.parse_raw(source))
end

local function flatten_path(node, steps)
  if node.type == "binary" and node.value == "." then
    flatten_path(node.lhs, steps)
    flatten_path(node.rhs, steps)
  else
    steps[#steps + 1] = M.process_ast(node)
  end
end

function M.process_ast(ast)
  if ast == nil then
    return ast
  end
  if ast.type == "predicate" then
    local target = M.process_ast(ast.expr)
    if target.type == "path" then
      local last = target.steps[#target.steps]
      last.predicate = last.predicate or {}
      last.predicate[#last.predicate + 1] = M.process_ast(ast.filter)
      return target
    end
    -- Wrap a non-path target as a single-step path carrying the predicate.
    target.predicate = target.predicate or {}
    target.predicate[#target.predicate + 1] = M.process_ast(ast.filter)
    return { type = "path", steps = { target }, position = ast.position }
  end
  if ast.type == "sort" then
    local target = M.process_ast(ast.lhs)
    local sort_step = { type = "sort", terms = {}, position = ast.position }
    for i, term in ipairs(ast.terms) do
      sort_step.terms[i] = {
        expression = M.process_ast(term.expression),
        descending = term.descending,
      }
    end
    if target.type == "path" then
      target.steps[#target.steps + 1] = sort_step
      return target
    end
    return { type = "path", steps = { target, sort_step }, position = ast.position }
  end
  if ast.type == "group" then
    local target = M.process_ast(ast.lhs)
    local group_step = { type = "group", pairs = {}, position = ast.position }
    for i, pair in ipairs(ast.pairs) do
      group_step.pairs[i] = { M.process_ast(pair[1]), M.process_ast(pair[2]) }
    end
    if target.type == "path" then
      target.steps[#target.steps + 1] = group_step
      return target
    end
    return { type = "path", steps = { target, group_step }, position = ast.position }
  end
  if ast.type == "binary" and ast.value == "." then
    local steps = {}
    flatten_path(ast, steps)
    return { type = "path", steps = steps, position = ast.position }
  end
  if ast.type == "binary" or ast.type == "bind" then
    ast.lhs = M.process_ast(ast.lhs)
    ast.rhs = M.process_ast(ast.rhs)
    return ast
  end
  if ast.type == "unary" then
    ast.expression = M.process_ast(ast.expression)
    return ast
  end
  if ast.type == "block" then
    for i, e in ipairs(ast.expressions) do
      ast.expressions[i] = M.process_ast(e)
    end
    return ast
  end
  if ast.type == "array" then
    for i, e in ipairs(ast.expressions) do
      ast.expressions[i] = M.process_ast(e)
    end
    return ast
  end
  if ast.type == "object" then
    for _, pair in ipairs(ast.pairs) do
      pair[1] = M.process_ast(pair[1])
      pair[2] = M.process_ast(pair[2])
    end
    return ast
  end
  if ast.type == "condition" then
    ast.condition = M.process_ast(ast.condition)
    ast.then_expr = M.process_ast(ast.then_expr)
    ast.else_expr = M.process_ast(ast.else_expr)
    return ast
  end
  if ast.type == "function" then
    ast.procedure = M.process_ast(ast.procedure)
    for i, a in ipairs(ast.arguments) do
      ast.arguments[i] = M.process_ast(a)
    end
    return ast
  end
  if ast.type == "lambda" then
    ast.body = M.process_ast(ast.body)
    return ast
  end
  if ast.type == "apply" then
    ast.lhs = M.process_ast(ast.lhs)
    ast.rhs = M.process_ast(ast.rhs)
    return ast
  end
  if ast.type == "range" then
    ast.lhs = M.process_ast(ast.lhs)
    ast.rhs = M.process_ast(ast.rhs)
    return ast
  end
  if ast.type == "transform" then
    ast.pattern = M.process_ast(ast.pattern)
    ast.update = M.process_ast(ast.update)
    if ast.delete then
      ast.delete = M.process_ast(ast.delete)
    end
    return ast
  end
  return ast
end

-- Exposed for later tasks to register operators.
M._symbol = symbol
M._symbols = symbols

return M
