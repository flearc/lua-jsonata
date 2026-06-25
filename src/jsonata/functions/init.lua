local helpers = require("jsonata.functions.helpers")

local M = {}

-- Merge every category's registry into one name->def table.
local categories = {
  require("jsonata.functions.boolean"),
  require("jsonata.functions.string"),
  require("jsonata.functions.numeric"),
  require("jsonata.functions.formatnumber"),
  require("jsonata.functions.aggregation"),
  require("jsonata.functions.array"),
  require("jsonata.functions.object"),
  require("jsonata.functions.higher_order"),
  require("jsonata.functions.eval"),
}

M.registry = {}
for _, cat in ipairs(categories) do
  for name, def in pairs(cat) do
    if type(name) == "string" and name:sub(1, 1) ~= "_" then
      M.registry[name] = def
    end
  end
end

-- Expose each def as M.<name> so existing unit tests (F.string.impl, F.count.impl, ...) keep working.
for name, def in pairs(M.registry) do
  M[name] = def
end

-- Engine-consumed interface (evaluator.lua uses functions.truthy and functions.string.impl).
M.truthy = helpers.truthy

return M
