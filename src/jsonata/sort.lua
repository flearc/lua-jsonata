local M = {}

-- Stable merge sort. comp_after(a, b) returns truthy when `a` should sort AFTER
-- `b`. Ties (comp_after false) keep the left element first -> stable.
function M.stable_sort(list, comp_after)
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
  left = M.stable_sort(left, comp_after)
  right = M.stable_sort(right, comp_after)
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

return M
