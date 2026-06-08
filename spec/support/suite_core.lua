-- Orchestrate the official suite: run each case, categorize, diff baseline.
local jsonata = require("jsonata")
local loader = require("support.suite_loader")
local compare = require("support.suite_compare")
local json = require("support.suite_json")

local M = {}

local function is_structured_error(err)
  return type(err) == "table" and err.code ~= nil
end

-- Returns "pass" | "fail" | "error"
local function run_case(desc, equal)
  local ok, res = pcall(function()
    return jsonata.compile(desc.expr):evaluate(desc.input, desc.bindings)
  end)

  if desc.expect.kind == "error" then
    if ok then
      return "fail" -- expected an error, got a result
    end
    return is_structured_error(res) and "pass" or "error"
  end

  if not ok then
    -- a value/undefined was expected but the library raised
    return is_structured_error(res) and "fail" or "error"
  end

  if desc.expect.kind == "undefined" then
    return res == nil and "pass" or "fail"
  end

  -- result expectation
  return equal(res, desc.expect.value, desc.unordered) and "pass" or "fail"
end

function M.load_baseline(path)
  local f = io.open(path, "r")
  if not f then
    return {}
  end
  f:close()
  local ok, t = pcall(dofile, path)
  if ok and type(t) == "table" then
    return t
  end
  return {}
end

function M.write_baseline(path, pass_set)
  local ids = {}
  for id in pairs(pass_set) do
    ids[#ids + 1] = id
  end
  table.sort(ids)
  local f = assert(io.open(path, "w"))
  f:write("-- Auto-generated. Currently-passing official test-suite cases.\n")
  f:write("-- Regenerate with: scripts/run-suite.sh --update-baseline\n")
  f:write("return {\n")
  for _, id in ipairs(ids) do
    f:write(string.format("  [%q] = true,\n", id))
  end
  f:write("}\n")
  f:close()
end

function M.run(opts)
  opts = opts or {}
  local dir = opts.suite_dir or "spec/jsonata-suite"
  local baseline_path = opts.baseline_path or (dir .. "/baseline.lua")
  local equal = compare.new(json.NULL)

  local r = {
    total = 0,
    passed = 0,
    failed = 0,
    errored = 0,
    skipped = 0,
    by_group = {},
    pass_set = {},
  }

  for _, desc in ipairs(loader.load_all(dir)) do
    r.total = r.total + 1
    local group = desc.id:match("^([^/]+)/")
    local g = r.by_group[group]
    if not g then
      g = { pass = 0, total = 0 }
      r.by_group[group] = g
    end
    g.total = g.total + 1

    if desc.skip then
      r.skipped = r.skipped + 1
    elseif desc.load_error then
      r.errored = r.errored + 1
    else
      local ok, outcome = pcall(run_case, desc, equal)
      if not ok then
        outcome = "error"
      end
      if outcome == "pass" then
        r.passed = r.passed + 1
        g.pass = g.pass + 1
        r.pass_set[desc.id] = true
      elseif outcome == "error" then
        r.errored = r.errored + 1
      else
        r.failed = r.failed + 1
      end
    end
  end

  local baseline = M.load_baseline(baseline_path)
  r.regressions = {}
  r.surprises = {}
  for id in pairs(baseline) do
    if not r.pass_set[id] then
      r.regressions[#r.regressions + 1] = id
    end
  end
  for id in pairs(r.pass_set) do
    if not baseline[id] then
      r.surprises[#r.surprises + 1] = id
    end
  end
  table.sort(r.regressions)
  table.sort(r.surprises)

  if opts.update then
    M.write_baseline(baseline_path, r.pass_set)
  end

  return r
end

return M
