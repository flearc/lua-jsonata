local V = require("jsonata.value")
local H = require("jsonata.functions.helpers")

local R = {}

-- Lazily reach the evaluator's apply. Avoids a load-time require cycle:
-- evaluator -> functions -> higher_order -> evaluator. By the time any HOF
-- runs, evaluator.apply is defined; require is memoized so this is cheap.
local eval
local function apply(proc, args)
  eval = eval or require("jsonata.evaluator")
  return eval.apply(proc, args)
end

-- Arity a callback declares: lambda -> #params; builtin -> stored arity (= min).
local function arity_of(proc)
  if type(proc) ~= "table" then
    return 0
  end
  if proc._jsonata_lambda then
    return #proc.params
  end
  if proc._jsonata_function then
    return proc.arity or 0
  end
  return 0
end

-- Build the callback arg list, supplying index/array only if the callback wants
-- them (jsonata hofFuncArgs). index is 0-based to match jsonata.
local function hof_args(proc, value, index, array)
  local a = arity_of(proc)
  local args = { value }
  if a >= 2 then
    args[2] = index
  end
  if a >= 3 then
    args[3] = array
  end
  return args
end

-- Coerce a non-array value to a single-element array (jsonata 'a' signature coercion).
local function to_array(x)
  if V.is_array(x) then
    return x
  end
  return V.array({ x })
end

-- $map(array, function): apply fn to each element; collect non-nothing results
-- (null is kept). Returns a sequence so eval_function singleton-unwraps it,
-- matching jsonata-js v2.2.1 behaviour (createSequence).
R.map = H.def(function(arr, fn)
  if V.is_nothing(arr) then
    return V.NOTHING
  end
  arr = to_array(arr)
  local seq = V.sequence()
  for i = 1, #arr do
    local res = apply(fn, hof_args(fn, arr[i], i - 1, arr))
    if not V.is_nothing(res) then
      seq[#seq + 1] = res
    end
  end
  return seq
end, 2, 2)

-- $filter(array, function): keep the ORIGINAL element when fn's result is truthy.
R.filter = H.def(function(arr, fn)
  if V.is_nothing(arr) then
    return V.NOTHING
  end
  arr = to_array(arr)
  local seq = V.sequence()
  for i = 1, #arr do
    if H.truthy(apply(fn, hof_args(fn, arr[i], i - 1, arr))) then
      seq[#seq + 1] = arr[i]
    end
  end
  return seq
end, 2, 2)

return R
