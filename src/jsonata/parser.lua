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
infix("in", 40)
-- ?? and ?: use expression(0) for their RHS, exactly as jsonata-js does.
-- This makes them right-greedy over all same-and-lower precedence operators
-- (=, !=, <, <=, >, >=, in, and, or, ?, ~>).  Without this, `"a"??b=c` would
-- parse as `("a"??b)=c` (left-assoc), but jsonata parses it as `"a"??(b=c)`.
do
  local function make_greedy_binary(id)
    local s = symbol(id, 40)
    s.led = function(p, t, left)
      return { type = "binary", value = id, lhs = left, rhs = p.expression(0), position = t.position }
    end
    return s
  end
  make_greedy_binary("??")
  make_greedy_binary("?:")
end
-- Boolean
infix("and", 30)
infix("or", 25)
-- String concat
infix("&", 50)
-- Unary minus (high binding power)
prefix("-", 70)
-- Assignment (right-associative) -> "bind" node
infixr(":=", 10, "bind")

-- ">>" appears in MULTI_OPS (tokenizer) and is also produced when parsing
-- lambda signatures like <a<n>>, where two consecutive '>' chars are lexed as
-- one ">>" token.  Register it as a zero-binding-power terminal so tok_to_node
-- does not raise S0201 when the signature-scanning loop calls p.advance().
symbol(">>")

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
        if p.node.id == ")" then
          break
        end
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
    if p.node.id == "]" then
      p.advance()
      return { type = "predicate", expr = left, keepArray = true, position = t.position }
    end
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
    local else_expr = nil
    if p.node.id == ":" then
      p.advance()
      else_expr = p.expression(0)
    end
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
    local signature = nil
    if p.node.id == "<" then
      local depth, parts = 0, {}
      while true do
        local val = tostring(p.node.value)
        parts[#parts + 1] = val
        for ch in val:gmatch(".") do
          if ch == "<" then
            depth = depth + 1
          elseif ch == ">" then
            depth = depth - 1
          end
        end
        p.advance()
        if depth <= 0 or p.node.id == "{" or p.node.id == "(end)" then
          break
        end
      end
      signature = require("jsonata.signature").parse(table.concat(parts))
    end
    if p.node.id ~= "{" then
      errors.raise("S0203", { position = p.node.position, token = "{" })
    end
    p.advance() -- consume '{'
    local body = p.expression(0)
    if p.node.id ~= "}" then
      errors.raise("S0203", { position = p.node.position, token = "}" })
    end
    p.advance() -- consume '}'
    return { type = "lambda", params = params, body = body, signature = signature, position = t.position }
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

local process_ast -- forward declaration (ctx-threaded internal)

-- ===== `%` ancestry machinery (M3b), ported from jsonata-js v2.2.1 =====
-- Slots are SHARED, MUTATED references — never copy a slot table.

local seek_parent

-- Walk one slot through one node, anchoring when level reaches 0.
seek_parent = function(node, slot, ctx)
  local t = node.type
  if t == "name" or t == "wildcard" then
    slot.level = slot.level - 1
    if slot.level == 0 then
      if node.ancestor == nil then
        node.ancestor = slot
      else
        -- two % anchored on the same step share one label, so the evaluator
        -- writes ONE tuple binding that both % references resolve through
        ctx.ancestry[slot.index].slot.label = node.ancestor.label
        node.ancestor = slot
      end
      node.tuple = true
    end
  elseif t == "parent" then
    slot.level = slot.level + 1
  elseif t == "block" then
    -- resolve through the block's LAST expression only
    if #node.expressions > 0 then
      node.tuple = true
      slot = seek_parent(node.expressions[#node.expressions], slot, ctx)
    end
  elseif t == "path" then
    node.tuple = true
    local index = #node.steps
    slot = seek_parent(node.steps[index], slot, ctx)
    index = index - 1
    while slot.level > 0 and index >= 1 do
      slot = seek_parent(node.steps[index], slot, ctx)
      index = index - 1
    end
  else
    errors.raise("S0217", { token = t, position = node.position })
  end
  return slot
end

-- Propagate unresolved slots from a child node up to its container.
-- Invariant: a parent node's own seekingParent is nil when this is called
-- (parent nodes are terminals); the in-place append to an adopted array is
-- therefore safe and mirrors jsonata's aliasing.
-- Field name kept camelCase (`seekingParent`) deliberately: it aliases the
-- jsonata-js field 1:1 for port traceability; it is parser-internal transit
-- state, never read by the evaluator.
local function push_ancestry(result, value)
  if value == nil then
    return
  end
  if value.seekingParent ~= nil or value.type == "parent" then
    local slots = value.seekingParent or {}
    if value.type == "parent" then
      slots[#slots + 1] = value.slot
    end
    if result.seekingParent == nil then
      result.seekingParent = slots
    elseif result.seekingParent ~= slots then
      -- identity guard: when the arrays are already aliased (a re-push of the
      -- same pair, e.g. chained predicates on one step), the slots are already
      -- present; appending would grow the table while iterating it.
      for _, s in ipairs(slots) do
        result.seekingParent[#result.seekingParent + 1] = s
      end
    end
  end
end

-- Resolve every step's pending slots against the steps before it. jsonata
-- resolves incrementally at each `.` level (each step is briefly the last
-- step of a sub-path); our flatten-then-wrap assembly emulates that with one
-- positional pass. Step 1 is never a laststep in jsonata's left-assoc
-- assembly, so its seekingParent is (faithfully) NOT read; a parent node AT
-- step 1 is jsonata's lhs-seeding case (walks to index 0 -> path.seekingParent).
-- KNOWN DIVERGENCE: our parser unwraps single-expression parens (M1 design),
-- so shapes like `a.b.((1; %).c)` flatten into one path and the block step's
-- strand resolves here; jsonata-js keeps the block boundary and orphans it
-- (undefined). Exotic; we resolve MORE than jsonata, never less.
local function resolve_ancestry(path, ctx)
  local steps = path.steps
  for i = 1, #steps do
    local st = steps[i]
    local slots = {}
    if i >= 2 and st.seekingParent then
      for _, s in ipairs(st.seekingParent) do
        slots[#slots + 1] = s
      end
    end
    if st.type == "parent" then
      slots[#slots + 1] = st.slot
    end
    for _, slot in ipairs(slots) do
      local idx = i - 1
      while slot.level > 0 do
        if idx < 1 then
          if path.seekingParent == nil then
            path.seekingParent = { slot }
          else
            path.seekingParent[#path.seekingParent + 1] = slot
          end
          break
        end
        local step = steps[idx]
        idx = idx - 1
        -- contiguous focus-bound steps count as one level (future @ support)
        while idx >= 1 and step.focus and steps[idx].focus do
          step = steps[idx]
          idx = idx - 1
        end
        slot = seek_parent(step, slot, ctx)
      end
    end
  end
end

local function flatten_path(node, steps, ctx)
  if node.type == "binary" and node.value == "." then
    flatten_path(node.lhs, steps, ctx)
    flatten_path(node.rhs, steps, ctx)
  else
    steps[#steps + 1] = process_ast(node, ctx)
  end
end

process_ast = function(ast, ctx)
  if ast == nil then
    return ast
  end
  if ast.type == "parent" then
    ast.slot = {
      label = "!" .. ctx.ancestor_label,
      level = 1,
      index = #ctx.ancestry + 1,
    }
    ctx.ancestor_label = ctx.ancestor_label + 1
    ctx.ancestry[#ctx.ancestry + 1] = ast
    return ast
  end
  if ast.type == "predicate" then
    local target = process_ast(ast.expr, ctx)
    local step, path
    if target.type == "path" then
      path = target
      step = target.steps[#target.steps]
    else
      step = target
      path = { type = "path", steps = { target }, position = ast.position }
    end
    if ast.keepArray then
      step.keepArray = true
      push_ancestry(path, step)
      return path
    end
    local filter = process_ast(ast.filter, ctx)
    if filter.seekingParent ~= nil then
      for _, slot in ipairs(filter.seekingParent) do
        if slot.level == 1 then
          seek_parent(step, slot, ctx)
        else
          slot.level = slot.level - 1
        end
      end
      push_ancestry(step, filter)
    end
    step.predicate = step.predicate or {}
    step.predicate[#step.predicate + 1] = filter
    -- Propagate pending ancestry (incl. a bare-parent step's own slot) onto
    -- the path node: the enclosing path's resolve_ancestry pass reads
    -- steps[i].seekingParent on this node, emulating jsonata's read of the
    -- predicated step while it is briefly the laststep of a `.` level.
    push_ancestry(path, step)
    return path
  end
  if ast.type == "sort" then
    local target = process_ast(ast.lhs, ctx)
    local sort_step = { type = "sort", terms = {}, position = ast.position }
    for i, term in ipairs(ast.terms) do
      local expression = process_ast(term.expression, ctx)
      push_ancestry(sort_step, expression)
      sort_step.terms[i] = { expression = expression, descending = term.descending }
    end
    if target.type == "path" then
      target.steps[#target.steps + 1] = sort_step
      resolve_ancestry(target, ctx)
      return target
    end
    local path = { type = "path", steps = { target, sort_step }, position = ast.position }
    resolve_ancestry(path, ctx)
    return path
  end
  if ast.type == "group" then
    -- NB: jsonata-js deliberately does NOT propagate % ancestry through {}
    -- group-by pairs (its '{' case never calls pushAncestry); % slots inside
    -- group pairs are faithfully orphaned -> runtime lookup miss -> undefined.
    local target = process_ast(ast.lhs, ctx)
    local group_step = { type = "group", pairs = {}, position = ast.position }
    for i, pair in ipairs(ast.pairs) do
      group_step.pairs[i] = { process_ast(pair[1], ctx), process_ast(pair[2], ctx) }
    end
    if target.type == "path" then
      target.steps[#target.steps + 1] = group_step
      return target
    end
    return { type = "path", steps = { target, group_step }, position = ast.position }
  end
  if ast.type == "binary" and ast.value == "." then
    local steps = {}
    flatten_path(ast, steps, ctx)
    for i = 2, #steps do
      if steps[i].type == "string" then
        steps[i] = { type = "name", value = steps[i].value, position = steps[i].position }
      end
    end
    local path = { type = "path", steps = steps, position = ast.position }
    resolve_ancestry(path, ctx)
    return path
  end
  if ast.type == "bind" then
    ast.lhs = process_ast(ast.lhs, ctx)
    ast.rhs = process_ast(ast.rhs, ctx)
    push_ancestry(ast, ast.rhs)
    return ast
  end
  if ast.type == "binary" then
    ast.lhs = process_ast(ast.lhs, ctx)
    ast.rhs = process_ast(ast.rhs, ctx)
    push_ancestry(ast, ast.lhs)
    push_ancestry(ast, ast.rhs)
    return ast
  end
  if ast.type == "unary" then
    ast.expression = process_ast(ast.expression, ctx)
    push_ancestry(ast, ast.expression)
    return ast
  end
  if ast.type == "block" then
    for i, e in ipairs(ast.expressions) do
      ast.expressions[i] = process_ast(e, ctx)
      push_ancestry(ast, ast.expressions[i])
    end
    return ast
  end
  if ast.type == "array" then
    for i, e in ipairs(ast.expressions) do
      ast.expressions[i] = process_ast(e, ctx)
      push_ancestry(ast, ast.expressions[i])
    end
    return ast
  end
  if ast.type == "object" then
    for _, pair in ipairs(ast.pairs) do
      pair[1] = process_ast(pair[1], ctx)
      pair[2] = process_ast(pair[2], ctx)
      push_ancestry(ast, pair[1])
      push_ancestry(ast, pair[2])
    end
    return ast
  end
  if ast.type == "condition" then
    ast.condition = process_ast(ast.condition, ctx)
    ast.then_expr = process_ast(ast.then_expr, ctx)
    ast.else_expr = process_ast(ast.else_expr, ctx)
    push_ancestry(ast, ast.condition)
    push_ancestry(ast, ast.then_expr)
    push_ancestry(ast, ast.else_expr)
    return ast
  end
  if ast.type == "function" then
    ast.procedure = process_ast(ast.procedure, ctx)
    for i, a in ipairs(ast.arguments) do
      ast.arguments[i] = process_ast(a, ctx)
      push_ancestry(ast, ast.arguments[i])
    end
    return ast
  end
  if ast.type == "lambda" then
    ast.body = process_ast(ast.body, ctx)
    return ast
  end
  if ast.type == "apply" then
    ast.lhs = process_ast(ast.lhs, ctx)
    ast.rhs = process_ast(ast.rhs, ctx)
    -- NB: no push_ancestry here. jsonata-js does push through '~>' but no
    -- observable divergence exists (verified against a jsonata-js oracle);
    -- % inside an apply rhs is lambda-scope and orphans identically.
    return ast
  end
  if ast.type == "range" then
    ast.lhs = process_ast(ast.lhs, ctx)
    ast.rhs = process_ast(ast.rhs, ctx)
    push_ancestry(ast, ast.lhs)
    push_ancestry(ast, ast.rhs)
    return ast
  end
  if ast.type == "transform" then
    -- NB: no push_ancestry (matches jsonata-js: transform never propagates
    -- ancestry).
    ast.pattern = process_ast(ast.pattern, ctx)
    ast.update = process_ast(ast.update, ctx)
    if ast.delete then
      ast.delete = process_ast(ast.delete, ctx)
    end
    return ast
  end
  return ast
end

-- Public entry: mints fresh per-parse ancestry state (mirrors jsonata-js,
-- where ancestry/ancestorLabel live in the per-call parser closure).
function M.process_ast(ast)
  local ctx = { ancestry = {}, ancestor_label = 0 }
  local result = process_ast(ast, ctx)
  if result ~= nil and (result.type == "parent" or result.seekingParent ~= nil) then
    errors.raise("S0217", { token = result.type, position = result.position })
  end
  return result
end

-- Exposed for later tasks to register operators.
M._symbol = symbol
M._symbols = symbols

return M
