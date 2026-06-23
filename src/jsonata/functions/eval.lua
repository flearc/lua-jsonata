local V = require("jsonata.value")
local errors = require("jsonata.errors")

local R = {}

-- Lazy requires (break the evaluator -> functions -> evaluator load cycle; memoized).
local parser, evaluator
local function get_parser()
  parser = parser or require("jsonata.parser")
  return parser
end
local function get_evaluator()
  evaluator = evaluator or require("jsonata.evaluator")
  return evaluator
end

-- $eval(expr [, focus]) — parse `expr` as JSONata and evaluate it against the
-- current environment + the call-site input (or `focus` if supplied).
-- wants_env: M.apply prepends (env, input) ahead of the validated args.
local function eval_impl(env, input, expr, focus)
  if V.is_nothing(expr) then
    return V.NOTHING
  end

  -- Parse — non-recovering; any syntax error becomes D3120.
  local ok, ast = pcall(get_parser().parse, expr)
  if not ok then
    errors.raise("D3120", { value = (type(ast) == "table" and ast.message) or tostring(ast) })
  end

  -- Pick the input: explicit focus overrides; else the threaded call-site input.
  -- A non-sequence array focus carries the internal `cons` flag (from array
  -- construction), which corrupts path steps; rebuild it clean (jsonata wraps a
  -- non-sequence array focus so it's treated as a normal value).
  local target = focus
  if V.is_nothing(focus) then
    target = input
  elseif V.is_array(focus) and not V.is_sequence(focus) then
    local clean = {}
    for i = 1, #focus do
      clean[i] = focus[i]
    end
    target = V.array(clean)
  end

  -- Evaluate against the CURRENT env — any runtime error becomes D3121.
  local ok2, result = pcall(get_evaluator().evaluate, ast, target, env)
  if not ok2 then
    errors.raise("D3121", { value = (type(result) == "table" and result.message) or tostring(result) })
  end
  return result
end

-- Build the def manually: with wants_env, M.apply calls proc.impl(env, input, ...validated_args).
-- The H.def arity-checking wrapper would count env+input as extra args and fail.
-- The signature already validates the user-supplied args; we just need arity=1 for HOF hints.
R.eval = {
  _jsonata_function = true,
  impl = eval_impl,
  arity = 1,
  signature = require("jsonata.signature").parse("<sx?:x>"),
  wants_env = true,
}

return R
