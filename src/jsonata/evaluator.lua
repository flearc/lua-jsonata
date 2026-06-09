local V = require("jsonata.value")
local errors = require("jsonata.errors")
local functions = require("jsonata.functions")
local sort = require("jsonata.sort")

local M = {}

local evaluate -- forward declaration

local function as_number(x, code)
  if V.typeof(x) ~= "number" then
    errors.raise(code, { value = x })
  end
  return x
end

local function is_integer(x)
  return V.typeof(x) == "number" and x == math.floor(x)
end

local function eval_binary(node, input, env)
  local op = node.value
  if op == "and" then
    return functions.truthy(evaluate(node.lhs, input, env)) and functions.truthy(evaluate(node.rhs, input, env))
  elseif op == "or" then
    return functions.truthy(evaluate(node.lhs, input, env)) or functions.truthy(evaluate(node.rhs, input, env))
  end

  local lhs = evaluate(node.lhs, input, env)
  local rhs = evaluate(node.rhs, input, env)

  if op == "&" then
    return functions.string.impl(lhs) .. functions.string.impl(rhs)
  end

  if op == "+" or op == "-" or op == "*" or op == "/" or op == "%" then
    local a = as_number(lhs, "T2001")
    local b = as_number(rhs, "T2002")
    if op == "+" then
      return a + b
    elseif op == "-" then
      return a - b
    elseif op == "*" then
      return a * b
    elseif op == "/" then
      return a / b
    else
      return a % b
    end
  end

  if op == "=" then
    return M.deep_equal(lhs, rhs)
  elseif op == "!=" then
    return not M.deep_equal(lhs, rhs)
  elseif op == "<" or op == "<=" or op == ">" or op == ">=" then
    local lt, rt = V.typeof(lhs), V.typeof(rhs)
    if (lt ~= "number" and lt ~= "string") or lt ~= rt then
      errors.raise("T2010", { value = lhs })
    end
    if op == "<" then
      return lhs < rhs
    elseif op == "<=" then
      return lhs <= rhs
    elseif op == ">" then
      return lhs > rhs
    else
      return lhs >= rhs
    end
  end

  errors.raise("S0201", { token = op })
end

function M.deep_equal(a, b)
  if a == b then
    return true
  end
  local ta, tb = V.typeof(a), V.typeof(b)
  if ta ~= tb then
    return false
  end
  if ta == "array" then
    if #a ~= #b then
      return false
    end
    for i = 1, #a do
      if not M.deep_equal(a[i], b[i]) then
        return false
      end
    end
    return true
  elseif ta == "object" then
    local ka = V.obj_keys(a)
    if #ka ~= #V.obj_keys(b) then
      return false
    end
    for _, k in ipairs(ka) do
      if not M.deep_equal(V.obj_get(a, k), V.obj_get(b, k)) then
        return false
      end
    end
    return true
  end
  return false
end

-- Variable lookup: $ is the current input/context; named vars resolve via the frame chain.
function M.eval_variable(node, input, env)
  if node.value == "" then
    return input
  end
  local v = env:lookup(node.value)
  if v == nil then
    return V.NOTHING
  end
  return v
end

-- Build a fresh sequence, appending elements with flattening rules.
local function append_flat(seq, value)
  if V.is_nothing(value) then
    return
  end
  if V.is_array(value) and not V.get_flag(value, "cons") then
    for i = 1, #value do
      seq[#seq + 1] = value[i]
    end
  else
    seq[#seq + 1] = value
  end
end

-- Evaluate one path step against a single context item.
local function eval_step_on_item(step, item, env)
  if step.type == "name" then
    if not V.is_object(item) then
      return V.NOTHING
    end
    return V.obj_get(item, step.value)
  elseif step.type == "variable" then
    return M.eval_variable(step, item, env)
  else
    return evaluate(step, item, env)
  end
end

-- Apply predicates attached to a step to a sequence.
local function apply_predicates(seq, predicates, env)
  local current = seq
  for _, pred in ipairs(predicates) do
    local next_seq = V.sequence()
    for i = 1, #current do
      local item = current[i]
      local pv = evaluate(pred, item, env)
      local pt = V.typeof(pv)
      if pt == "number" then
        local idx = math.floor(pv)
        if idx < 0 then
          idx = #current + idx
        end
        if i - 1 == idx then
          next_seq[#next_seq + 1] = item
        end
      elseif pt == "array" then
        for j = 1, #pv do
          if V.typeof(pv[j]) == "number" then
            local idx = math.floor(pv[j])
            if idx < 0 then
              idx = #current + idx
            end
            if i - 1 == idx then
              next_seq[#next_seq + 1] = item
              break
            end
          end
        end
      elseif functions.truthy(pv) then
        next_seq[#next_seq + 1] = item
      end
    end
    current = next_seq
  end
  return current
end

-- Reorder a whole context sequence by one or more sort terms (the ^ operator).
-- comp_after(a, b) is true when a should sort AFTER b, matching jsonata's
-- evaluateSortExpression: per term, evaluate the key in each element's context;
-- undefined sorts last; non-number/string -> T2008; mismatched types -> T2007;
-- descending negates; first non-equal term decides.
local function eval_sort_step(context, terms, env)
  local list = {}
  for j = 1, #context do
    list[j] = context[j]
  end
  local comp_after = function(a, b)
    local comp = 0
    for _, term in ipairs(terms) do
      local aa = evaluate(term.expression, a, env)
      local bb = evaluate(term.expression, b, env)
      if V.is_nothing(aa) then
        comp = V.is_nothing(bb) and 0 or 1
      elseif V.is_nothing(bb) then
        comp = -1
      else
        local ta, tb = V.typeof(aa), V.typeof(bb)
        if (ta ~= "number" and ta ~= "string") or (tb ~= "number" and tb ~= "string") then
          errors.raise("T2008", { value = (ta ~= "number" and ta ~= "string") and aa or bb })
        end
        if ta ~= tb then
          errors.raise("T2007", { value = aa, value2 = bb })
        end
        if aa == bb then
          comp = 0
        elseif aa < bb then
          comp = -1
        else
          comp = 1
        end
        if term.descending then
          comp = -comp
        end
      end
      if comp ~= 0 then
        break
      end
    end
    return comp == 1
  end
  local sorted = sort.stable_sort(list, comp_after)
  local seq = V.sequence()
  for j = 1, #sorted do
    seq[j] = sorted[j]
  end
  return seq
end

-- Deep copy a value (objects/arrays recursively; scalars/NULL/NOTHING shared).
-- Used by the transform operator so it can mutate a copy without touching input.
local function deep_clone(v)
  if V.is_array(v) then
    local out = V.array({})
    for i = 1, #v do
      out[i] = deep_clone(v[i])
    end
    return out
  elseif V.is_object(v) then
    local out = V.object()
    for _, k in ipairs(V.obj_keys(v)) do
      V.obj_set(out, k, deep_clone(V.obj_get(v, k)))
    end
    return out
  end
  return v
end

-- Group a context sequence by each pair's key expression, then evaluate each
-- pair's value over its grouped data (the {} group-by operator). Returns a
-- one-element sequence holding the result object. Matches jsonata's
-- evaluateGroupExpression: string keys only (T1003); two different pairs
-- producing the same key -> D1009; 1-item group -> single context, multi -> array.
local function eval_group_step(context, pairs, env)
  local items = {}
  for j = 1, #context do
    items[j] = context[j]
  end
  if #items == 0 then
    items[1] = V.NOTHING
  end

  local order, groups = {}, {}
  for _, item in ipairs(items) do
    for pi, pair in ipairs(pairs) do
      local key = evaluate(pair[1], item, env)
      if not V.is_nothing(key) then
        if V.typeof(key) ~= "string" then
          errors.raise("T1003", { value = key })
        end
        local g = groups[key]
        if g then
          if g.exprIndex ~= pi then
            errors.raise("D1009", { value = key })
          end
          g.data[#g.data + 1] = item
        else
          groups[key] = { data = { item }, exprIndex = pi }
          order[#order + 1] = key
        end
      end
    end
  end

  local result = V.object()
  for _, key in ipairs(order) do
    local g = groups[key]
    local ctx
    if #g.data == 1 then
      ctx = g.data[1]
    else
      local copy = {}
      for i = 1, #g.data do
        copy[i] = g.data[i]
      end
      ctx = V.array(copy)
    end
    local value = evaluate(pairs[g.exprIndex][2], ctx, env)
    if not V.is_nothing(value) then
      V.obj_set(result, key, value)
    end
  end

  local seq = V.sequence()
  seq[1] = result
  return seq
end

local function eval_path(node, input, env)
  -- Special case: when the first step produces a value from the WHOLE input
  -- rather than navigating into it per-element, evaluate it once and seed the
  -- context from that value (flattened into a fresh sequence). This covers:
  --   * a variable ($x) or the context $ — env-bound, independent of input;
  --   * a function call ($f(...)) — a self-contained call;
  --   * a nested path — produced when a predicate/sort wraps a sub-expression
  --     (e.g. a[0].b or $^(key).field); it must run once over the whole input
  --     to build the full context before later steps navigate.
  -- Evaluating once (not per-item) also stops a NOTHING input from being
  -- skipped by the per-step nothing-guard.
  local context
  local steps = node.steps
  local start = 1
  -- An array constructor is self-contained (evaluated once, not per-element)
  -- when it is the sole step or the next step is not a variable lookup.
  -- This covers [range][pred] and [range].(expr).
  -- [arr].$var is kept per-element because Lua's from_lua({}) converts any empty
  -- table to V.object (empty arrays and objects are indistinguishable), so the
  -- correct "undefined" result for variables/case009 ([1,2,3].$v, v=[]) only
  -- falls out from the nothing-guard skipping the array step.
  local first_is_self_contained = steps[1]
    and (
      steps[1].type == "variable"
      or steps[1].type == "function"
      or steps[1].type == "path"
      or (steps[1].type == "array" and not (steps[2] and steps[2].type == "variable"))
    )
  if first_is_self_contained then
    local var_val = evaluate(steps[1], input, env)
    local result = V.sequence()
    if steps[1].type == "array" and V.is_array(var_val) then
      -- Spread array elements into the context sequence so subsequent steps
      -- (predicates, maps) operate on individual elements.
      for i = 1, #var_val do
        result[#result + 1] = var_val[i]
      end
    else
      append_flat(result, var_val)
    end
    if steps[1].predicate then
      result = apply_predicates(result, steps[1].predicate, env)
    end
    context = result
    start = 2
  elseif V.is_array(input) then
    context = input
  else
    context = V.sequence(input)
  end

  for i = start, #steps do
    local step = steps[i]
    if step.type == "sort" then
      context = eval_sort_step(context, step.terms, env)
    elseif step.type == "group" then
      context = eval_group_step(context, step.pairs, env)
    else
      local result = V.sequence()
      for j = 1, #context do
        local item = context[j]
        if not V.is_nothing(item) then
          append_flat(result, eval_step_on_item(step, item, env))
        end
      end
      context = result
    end
    if step.predicate then
      context = apply_predicates(context, step.predicate, env)
    end
  end
  return context
end

-- Singleton unwrapping applied at the boundary of path/array results.
local function finalize_sequence(seq, keep_singleton)
  if #seq == 0 then
    return V.NOTHING
  elseif #seq == 1 and not keep_singleton then
    return seq[1]
  end
  return seq
end
M.finalize_sequence = finalize_sequence

local function _evaluate(node, input, env)
  local t = node.type
  if t == "number" or t == "string" or t == "boolean" then
    return node.value
  elseif t == "null" then
    return V.NULL
  elseif t == "unary" then
    if node.value == "-" then
      return -as_number(evaluate(node.expression, input, env), "T2001")
    end
    errors.raise("S0211", { token = node.value })
  elseif t == "binary" then
    return eval_binary(node, input, env)
  elseif t == "bind" then
    local val = evaluate(node.rhs, input, env)
    env:bind(node.lhs.value, val)
    return val
  elseif t == "block" then
    local result = V.NOTHING
    local frame = env:create_frame()
    for _, e in ipairs(node.expressions) do
      result = evaluate(e, input, frame)
    end
    return result
  elseif t == "condition" then
    if functions.truthy(evaluate(node.condition, input, env)) then
      return evaluate(node.then_expr, input, env)
    else
      return evaluate(node.else_expr, input, env)
    end
  elseif t == "variable" then
    return M.eval_variable(node, input, env)
  elseif t == "name" then
    if V.is_array(input) then
      local seq = V.sequence()
      for k = 1, #input do
        append_flat(seq, eval_step_on_item(node, input[k], env))
      end
      return finalize_sequence(seq, false)
    end
    if not V.is_object(input) then
      return V.NOTHING
    end
    return V.obj_get(input, node.value)
  elseif t == "path" then
    local seq = eval_path(node, input, env)
    return finalize_sequence(seq, false)
  elseif t == "array" then
    local arr = V.array({})
    for _, e in ipairs(node.expressions) do
      local val = evaluate(e, input, env)
      if V.is_sequence(val) then
        for i = 1, #val do
          arr[#arr + 1] = val[i]
        end
      elseif not V.is_nothing(val) then
        arr[#arr + 1] = val
      end
    end
    V.set_flag(arr, "cons", true)
    return arr
  elseif t == "object" then
    local obj = V.object()
    for _, pair in ipairs(node.pairs) do
      local k = evaluate(pair[1], input, env)
      local val = evaluate(pair[2], input, env)
      V.obj_set(obj, functions.string.impl(k), val)
    end
    return obj
  elseif t == "function" then
    return M.eval_function(node, input, env)
  elseif t == "lambda" then
    return { _jsonata_lambda = true, params = node.params, body = node.body, env = env, input = input }
  elseif t == "apply" then
    local lhs = evaluate(node.lhs, input, env)
    local rhs = node.rhs
    if rhs.type == "function" then
      local proc = evaluate(rhs.procedure, input, env)
      local args = { lhs }
      for _, a in ipairs(rhs.arguments) do
        args[#args + 1] = evaluate(a, input, env)
      end
      return M.apply(proc, args)
    end
    return M.apply(evaluate(rhs, input, env), { lhs })
  elseif t == "transform" then
    return {
      _jsonata_function = true,
      impl = function(obj)
        if obj == nil or V.is_nothing(obj) then
          return V.NOTHING
        end
        local result = deep_clone(obj)
        local matches = evaluate(node.pattern, result, env)
        if V.is_nothing(matches) then
          return result
        end
        if not V.is_array(matches) then
          matches = V.array({ matches })
        end
        for i = 1, #matches do
          local match = matches[i]
          local update = evaluate(node.update, match, env)
          if not V.is_nothing(update) then
            if V.typeof(update) ~= "object" then
              errors.raise("T2011", { value = update })
            end
            if V.is_object(match) then
              for _, k in ipairs(V.obj_keys(update)) do
                V.obj_set(match, k, V.obj_get(update, k))
              end
            end
          end
          if node.delete then
            local del = evaluate(node.delete, match, env)
            if not V.is_nothing(del) then
              local original = del
              local list = V.is_array(del) and del or V.array({ del })
              for j = 1, #list do
                if V.typeof(list[j]) ~= "string" then
                  errors.raise("T2012", { value = original })
                end
              end
              if V.is_object(match) then
                for j = 1, #list do
                  V.obj_delete(match, list[j])
                end
              end
            end
          end
        end
        return result
      end,
    }
  elseif t == "range" then
    local lhs = evaluate(node.lhs, input, env)
    local rhs = evaluate(node.rhs, input, env)
    if not V.is_nothing(lhs) and not is_integer(lhs) then
      errors.raise("T2003", { value = lhs })
    end
    if not V.is_nothing(rhs) and not is_integer(rhs) then
      errors.raise("T2004", { value = rhs })
    end
    if V.is_nothing(lhs) or V.is_nothing(rhs) then
      return V.NOTHING
    end
    if lhs > rhs then
      return V.NOTHING
    end
    local size = rhs - lhs + 1
    if size > 1e7 then
      errors.raise("D2014", { value = size })
    end
    local seq = V.sequence()
    local idx = 0
    for n = lhs, rhs do
      idx = idx + 1
      seq[idx] = n
    end
    return seq
  end
  errors.raise("D3001", { token = t })
end

-- Thin explain seam. Assigns the forward-declared `evaluate` upvalue (line 8)
-- that every recursive call site binds to, so an installed hook observes every
-- node evaluated through `evaluate` (incl. HOF/lambda/transform sub-evaluations
-- and the first path step). Note: `eval_step_on_item` resolves `name`/`variable`
-- path steps inline (a deliberate fast path), so those non-first path steps are
-- not individually observed -- intentional, to leave the evaluation hot path
-- untouched. A hook is a table with BOTH `pre` and `post`; anything else (nil,
-- a stray user variable named __explain_hook, a partial table) falls through to
-- the unchanged direct call.
evaluate = function(node, input, env)
  local hook = env:lookup("__explain_hook")
  if not (hook and hook.pre and hook.post) then
    return _evaluate(node, input, env)
  end
  hook.pre(node, input, env)
  local result = _evaluate(node, input, env)
  hook.post(node, input, env, result)
  return result
end

-- Apply a procedure (lambda closure or builtin) to a list of evaluated args.
function M.apply(proc, args)
  if type(proc) == "table" and proc._jsonata_lambda then
    return M.apply_lambda(proc, args)
  end
  if type(proc) == "table" and proc._jsonata_function then
    return proc.impl((table.unpack or unpack)(args, 1, #args))
  end
  errors.raise("T1006", { value = proc })
end

function M.apply_lambda(proc, args)
  local frame = proc.env:create_frame()
  for i, name in ipairs(proc.params) do
    local v = args[i]
    if v == nil then
      v = V.NOTHING
    end
    frame:bind(name, v)
  end
  return evaluate(proc.body, proc.input, frame)
end

function M.eval_function(node, input, env)
  local proc = evaluate(node.procedure, input, env)
  for _, a in ipairs(node.arguments) do
    if a.type == "placeholder" then
      return M.partial(proc, node.arguments, input, env)
    end
  end
  local args = {}
  for i, a in ipairs(node.arguments) do
    args[i] = evaluate(a, input, env)
  end
  -- Context injection: $sift/$each carry inject_context; a bare call (only the
  -- function arg) uses the current input as the object argument. This is our
  -- minimal stand-in for jsonata's '-' context signature marker.
  if type(proc) == "table" and proc.inject_context and #args == 1 then
    table.insert(args, 1, input)
  end
  local result = M.apply(proc, args)
  if V.is_sequence(result) then
    return finalize_sequence(result, false)
  end
  return result
end

-- Partial application: $f(?, x) -> a new function that fills the holes when applied.
function M.partial(proc, argnodes, input, env)
  if not (type(proc) == "table" and (proc._jsonata_lambda or proc._jsonata_function)) then
    errors.raise("T1006", { value = proc })
  end
  local bound = {}
  local holes = {}
  for i, a in ipairs(argnodes) do
    if a.type == "placeholder" then
      holes[#holes + 1] = i
    else
      bound[i] = evaluate(a, input, env)
    end
  end
  return {
    _jsonata_function = true,
    impl = function(...)
      local fill = { ... }
      local args = {}
      for i = 1, #argnodes do
        args[i] = bound[i]
      end
      for k, pos in ipairs(holes) do
        args[pos] = fill[k]
      end
      return M.apply(proc, args)
    end,
  }
end

M.evaluate = evaluate
return M
