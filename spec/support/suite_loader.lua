-- Discover and parse official test-suite case files.
local json = require("support.suite_json")

local M = {}

local function read_file(path)
  local f = io.open(path, "r")
  if not f then
    return nil
  end
  local content = f:read("*a") -- "*a" works on 5.1/LuaJIT and 5.2+
  f:close()
  return content
end

-- List case *.json files under <dir>/groups, sorted.
local function list_case_files(dir)
  local cmd = string.format("find %q/groups -name '*.json' -type f", dir)
  local p = io.popen(cmd)
  local files = {}
  if p then
    for line in p:lines() do
      files[#files + 1] = line
    end
    p:close()
  end
  table.sort(files)
  return files
end

local function case_id(dir, path)
  local prefix = dir .. "/groups/"
  local rel = path:sub(#prefix + 1)
  return (rel:gsub("%.json$", ""))
end

-- Build a single descriptor from a case object.
-- dir       = suite root (for dataset lookups)
-- case_dir  = directory containing the case file (for expr-file lookups)
-- id        = the string id for this descriptor
-- case      = the decoded case table
local function build_descriptor(dir, case_dir, id, case)
  local expr = case.expr
  if expr == nil and case["expr-file"] then
    expr = read_file(case_dir .. "/" .. case["expr-file"])
  end

  -- C1: dataset name takes precedence; fall back to inline data field
  local input = nil
  if type(case.dataset) == "string" then
    input = json.decode(read_file(dir .. "/datasets/" .. case.dataset .. ".json"))
  elseif case.data ~= nil then
    input = case.data
  end

  local bindings = nil
  if type(case.bindings) == "table" then
    bindings = case.bindings
  end

  -- C3: top-level code, then error.code, then undefinedResult, then result
  local expect
  if case.code ~= nil then
    expect = { kind = "error", code = case.code }
  elseif type(case.error) == "table" and case.error.code ~= nil then
    expect = { kind = "error", code = case.error.code }
  elseif case.undefinedResult == true then
    expect = { kind = "undefined" }
  else
    expect = { kind = "result", value = case.result }
  end

  return {
    id = id,
    expr = expr,
    input = input,
    bindings = bindings,
    expect = expect,
    unordered = case.unordered == true,
    skip = (case.timelimit ~= nil) or (case.depth ~= nil),
  }
end

-- Kept for backward compatibility; thin wrapper used internally.
function M.load_case(dir, path)
  local raw = json.decode(read_file(path))
  local case_dir = path:match("^(.*)/[^/]+$")
  local base_id = case_id(dir, path)

  -- C2: if the file is an array of cases, return the first element only
  -- (load_all handles full expansion; load_case returns a single descriptor
  -- for the first element to preserve any callers that expect one value)
  local case = raw
  if type(raw) == "table" and type(raw[1]) == "table" then
    case = raw[1]
  end

  return build_descriptor(dir, case_dir, base_id, case)
end

function M.load_all(dir)
  local cases = {}
  for _, path in ipairs(list_case_files(dir)) do
    local base_id = case_id(dir, path)
    local case_dir = path:match("^(.*)/[^/]+$")

    local ok, raw = pcall(function()
      return json.decode(read_file(path))
    end)

    if not ok then
      -- Emit a stub so the case is counted as an error rather than crashing the run.
      cases[#cases + 1] = {
        id = base_id,
        expr = nil,
        input = nil,
        bindings = nil,
        expect = { kind = "result", value = nil },
        unordered = false,
        skip = false,
        load_error = true,
      }
    -- C2: array-of-cases file — expand into N descriptors
    elseif type(raw) == "table" and type(raw[1]) == "table" then
      for i, sub_case in ipairs(raw) do
        local sub_id = base_id .. "/" .. (i - 1)
        local ok2, desc = pcall(build_descriptor, dir, case_dir, sub_id, sub_case)
        if ok2 then
          cases[#cases + 1] = desc
        else
          cases[#cases + 1] = {
            id = sub_id,
            expr = nil,
            input = nil,
            bindings = nil,
            expect = { kind = "result", value = nil },
            unordered = false,
            skip = false,
            load_error = true,
          }
        end
      end
    else
      local ok2, desc = pcall(build_descriptor, dir, case_dir, base_id, raw)
      if ok2 then
        cases[#cases + 1] = desc
      else
        cases[#cases + 1] = {
          id = base_id,
          expr = nil,
          input = nil,
          bindings = nil,
          expect = { kind = "result", value = nil },
          unordered = false,
          skip = false,
          load_error = true,
        }
      end
    end
  end
  return cases
end

return M
