local M = {}
local Environment = {}
Environment.__index = Environment

function M.new(enclosing)
  return setmetatable({ bindings = {}, enclosing = enclosing }, Environment)
end

function Environment:create_frame()
  return M.new(self)
end

function Environment:bind(name, value)
  self.bindings[name] = value
end

function Environment:lookup(name)
  local v = self.bindings[name]
  if v ~= nil then
    return v
  end
  if self.enclosing then
    return self.enclosing:lookup(name)
  end
  return nil
end

return M
