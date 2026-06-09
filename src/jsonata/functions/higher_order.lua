local V = require("jsonata.value")
local H = require("jsonata.functions.helpers")
local errors = require("jsonata.errors")

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

-- $reduce(array, function[, init]): fold left. The undefined-sequence check
-- happens BEFORE the arity check (jsonata foldLeft), so $reduce(nothing, fn)
-- returns nothing even if fn would fail the arity check.
R.reduce = H.def(function(arr, fn, init)
  if V.is_nothing(arr) then
    return V.NOTHING
  end
  arr = to_array(arr)
  local a = arity_of(fn)
  if a < 2 then
    errors.raise("D3050")
  end
  local has_init = not (init == nil or V.is_nothing(init))
  if not has_init and #arr == 0 then
    return V.NOTHING
  end
  local acc, start
  if not has_init then
    acc, start = arr[1], 2
  else
    acc, start = init, 1
  end
  for i = start, #arr do
    local args = { acc, arr[i] }
    if a >= 3 then
      args[3] = i - 1
    end
    if a >= 4 then
      args[4] = arr
    end
    acc = apply(fn, args)
  end
  return acc
end, 2, 3)

-- $single(array[, function]): return the one element matching the predicate
-- (missing predicate = always match). D3138 if >1 match, D3139 if none.
R.single = H.def(function(arr, fn)
  if V.is_nothing(arr) then
    return V.NOTHING
  end
  arr = to_array(arr)
  local found = false
  local result = V.NOTHING
  for i = 1, #arr do
    local positive = true
    if fn ~= nil then
      positive = H.truthy(apply(fn, hof_args(fn, arr[i], i - 1, arr)))
    end
    if positive then
      if not found then
        result = arr[i]
        found = true
      else
        errors.raise("D3138")
      end
    end
  end
  if not found then
    errors.raise("D3139")
  end
  return result
end, 1, 2)

-- $sift(object, function): keep key/value pairs whose callback result is truthy.
-- Empty result -> nothing. inject_context: a bare $sift(fn) uses the current input.
R.sift = H.def(function(obj, fn)
  if not V.is_object(obj) then
    return V.NOTHING
  end
  local result = V.object()
  for _, k in ipairs(V.obj_keys(obj)) do
    local v = V.obj_get(obj, k)
    if H.truthy(apply(fn, hof_args(fn, v, k, obj))) then
      V.obj_set(result, k, v)
    end
  end
  if #V.obj_keys(result) == 0 then
    return V.NOTHING
  end
  return result
end, 2, 2)
R.sift.inject_context = true

-- $each(object, function): collect non-nothing callback results into a sequence.
R.each = H.def(function(obj, fn)
  if not V.is_object(obj) then
    return V.NOTHING
  end
  local seq = V.sequence()
  for _, k in ipairs(V.obj_keys(obj)) do
    local v = V.obj_get(obj, k)
    local res = apply(fn, hof_args(fn, v, k, obj))
    if not V.is_nothing(res) then
      seq[#seq + 1] = res
    end
  end
  return seq
end, 2, 2)
R.each.inject_context = true

-- Stable merge sort. comp_after(a, b) returns truthy when `a` should sort AFTER
-- `b`. Ties (comp_after false) keep the left element first -> stable. Matches
-- jsonata-js sort's merge logic.
local function stable_sort(list, comp_after)
  local n = #list
  if n <= 1 then
    return list
  end
  local mid = math.floor(n / 2)
  local left, right = {}, {}
  for i = 1, mid do
    left[i] = list[i]
  end
  for i = mid + 1, n do
    right[i - mid] = list[i]
  end
  left = stable_sort(left, comp_after)
  right = stable_sort(right, comp_after)
  local result = {}
  local i, j = 1, 1
  while i <= #left and j <= #right do
    if comp_after(left[i], right[j]) then
      result[#result + 1] = right[j]
      j = j + 1
    else
      result[#result + 1] = left[i]
      i = i + 1
    end
  end
  while i <= #left do
    result[#result + 1] = left[i]
    i = i + 1
  end
  while j <= #right do
    result[#result + 1] = right[j]
    j = j + 1
  end
  return result
end

-- True iff every element of `arr` has JSONata type `t`.
local function all_of_type(arr, t)
  for i = 1, #arr do
    if V.typeof(arr[i]) ~= t then
      return false
    end
  end
  return true
end

-- $sort(array[, comparator]): stable sort. With no comparator the array must be
-- all-numbers or all-strings (else D3070) and sorts ascending. A comparator
-- function returns truthy when its first arg should sort AFTER its second.
R.sort = H.def(function(arr, comparator)
  if V.is_nothing(arr) then
    return V.NOTHING
  end
  arr = to_array(arr)
  if #arr <= 1 then
    return V.array(arr)
  end
  local comp_after
  if comparator ~= nil then
    comp_after = function(a, b)
      return H.truthy(apply(comparator, { a, b }))
    end
  else
    if not (all_of_type(arr, "number") or all_of_type(arr, "string")) then
      errors.raise("D3070")
    end
    comp_after = function(a, b)
      return a > b
    end
  end
  return V.array(stable_sort(arr, comp_after))
end, 1, 2)

return R
