local M = {}

-- Sentinels: unique singletons, never confused with Lua nil.
M.NULL = setmetatable({}, {
  __name = "jsonata.null",
  __tostring = function()
    return "null"
  end,
})
M.NOTHING = setmetatable({}, {
  __name = "jsonata.nothing",
  __tostring = function()
    return "nothing"
  end,
})

-- Tags (metatables) distinguishing container kinds.
local ArrayMT = { __name = "jsonata.array" }
local SequenceMT = { __name = "jsonata.sequence" }
local ObjectMT = { __name = "jsonata.object" }

M.ArrayMT = ArrayMT
M.SequenceMT = SequenceMT
M.ObjectMT = ObjectMT

-- Flags are stored in a dedicated subtable to avoid colliding with array indices.
local function flags(x)
  local f = rawget(x, "__flags")
  if f == nil then
    f = {}
    rawset(x, "__flags", f)
  end
  return f
end

function M.is_null(x)
  return x == M.NULL
end

function M.is_nothing(x)
  return x == M.NOTHING
end

function M.array(t)
  return setmetatable(t or {}, ArrayMT)
end

function M.is_array(x)
  if type(x) ~= "table" then
    return false
  end
  local mt = getmetatable(x)
  return mt == ArrayMT or mt == SequenceMT
end

function M.sequence(...)
  local s = setmetatable({}, SequenceMT)
  local n = select("#", ...)
  for i = 1, n do
    s[i] = (select(i, ...))
  end
  return s
end

function M.is_sequence(x)
  return type(x) == "table" and getmetatable(x) == SequenceMT
end

function M.set_flag(seq, name, val)
  flags(seq)[name] = val
end

function M.get_flag(seq, name)
  local f = rawget(seq, "__flags")
  return f ~= nil and f[name] or false
end

function M.object()
  return setmetatable({ keys = {}, map = {} }, ObjectMT)
end

function M.is_object(x)
  return type(x) == "table" and getmetatable(x) == ObjectMT
end

function M.obj_set(o, k, v)
  if o.map[k] == nil then
    o.keys[#o.keys + 1] = k
  end
  o.map[k] = v
end

function M.obj_get(o, k)
  local v = o.map[k]
  if v == nil then
    return M.NOTHING
  end
  return v
end

function M.obj_keys(o)
  return o.keys
end

function M.obj_delete(o, k)
  if o.map[k] == nil then
    return
  end
  o.map[k] = nil
  for i = 1, #o.keys do
    if o.keys[i] == k then
      table.remove(o.keys, i)
      break
    end
  end
end

function M.typeof(x)
  if x == M.NULL then
    return "null"
  end
  if x == M.NOTHING then
    return "nothing"
  end
  local t = type(x)
  if t == "table" then
    local mt = getmetatable(x)
    if mt == ArrayMT or mt == SequenceMT then
      return "array"
    end
    if mt == ObjectMT then
      return "object"
    end
    return "object"
  end
  return t
end

return M
