local V = require("jsonata.value")
local H = require("jsonata.functions.helpers")

local R = {}

R.keys = H.def(function(x)
  if V.is_nothing(x) then
    return V.NOTHING
  end
  local out = V.array({})
  if V.is_object(x) then
    for _, k in ipairs(V.obj_keys(x)) do
      out[#out + 1] = k
    end
  elseif V.is_array(x) then
    local seen = {}
    for i = 1, #x do
      if V.is_object(x[i]) then
        for _, k in ipairs(V.obj_keys(x[i])) do
          if not seen[k] then
            seen[k] = true
            out[#out + 1] = k
          end
        end
      end
    end
  end
  if #out == 0 then
    return V.NOTHING
  end
  return out
end, 1, 1, "<x-:a<s>>")

R.lookup = H.def(function(x, key)
  if V.is_nothing(x) then
    return V.NOTHING
  end
  if V.is_array(x) then
    local out = V.array({})
    for i = 1, #x do
      if V.is_object(x[i]) then
        local v = V.obj_get(x[i], key)
        if not V.is_nothing(v) then
          out[#out + 1] = v
        end
      end
    end
    if #out == 0 then
      return V.NOTHING
    elseif #out == 1 then
      return out[1]
    end
    return out
  end
  if V.is_object(x) then
    return V.obj_get(x, key)
  end
  return V.NOTHING
end, 2, 2, "<x-s:x>")

R.spread = H.def(function(x)
  if V.is_nothing(x) then
    return V.NOTHING
  end
  local out = V.array({})
  local function spread_obj(o)
    for _, k in ipairs(V.obj_keys(o)) do
      local single = V.object()
      V.obj_set(single, k, V.obj_get(o, k))
      out[#out + 1] = single
    end
  end
  if V.is_object(x) then
    spread_obj(x)
  elseif V.is_array(x) then
    for i = 1, #x do
      if V.is_object(x[i]) then
        spread_obj(x[i])
      end
    end
  else
    return x -- scalar: jsonata functionSpread echoes the argument unchanged
  end
  return out
end, 1, 1, "<x-:a<o>>")

R.merge = H.def(function(x)
  if V.is_nothing(x) then
    return V.NOTHING
  end
  local merged = V.object()
  local function absorb(o)
    for _, k in ipairs(V.obj_keys(o)) do
      V.obj_set(merged, k, V.obj_get(o, k))
    end
  end
  if V.is_object(x) then
    absorb(x)
  elseif V.is_array(x) then
    for i = 1, #x do
      if V.is_object(x[i]) then
        absorb(x[i])
      end
    end
  end
  return merged
end, 1, 1, "<a<o>:o>")

R.type = H.def(function(x)
  if V.is_nothing(x) then
    return V.NOTHING
  end
  if type(x) == "table" and (x._jsonata_function or x._jsonata_lambda) then
    return "function"
  end
  return V.typeof(x)
end, 1)

R.error = H.def(function(msg)
  H.err("D3137", { message = V.is_nothing(msg) and "$error() function evaluated" or msg })
end, 0, 1)

R.assert = H.def(function(cond, msg)
  if V.is_nothing(cond) or not cond then
    H.err("D3141", { message = V.is_nothing(msg) and "$assert() statement failed" or msg })
  end
  return V.NOTHING
end, 1, 2, "<bs?:x>")

return R
