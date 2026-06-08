-- CLI for the official suite. Run via scripts/run-suite.sh.
-- Flags: --update-baseline   (rewrite baseline from current passes)
local core = require("support.suite_core")

local update = false
for _, a in ipairs(arg or {}) do
  if a == "--update-baseline" then
    update = true
  end
end

local r = core.run({ update = update })

local groups = {}
for g in pairs(r.by_group) do
  groups[#groups + 1] = g
end
table.sort(groups)
for _, g in ipairs(groups) do
  local s = r.by_group[g]
  print(string.format("  %-34s %d/%d", g, s.pass, s.total))
end

print(string.rep("-", 52))
print(string.format("TOTAL %d | pass %d | fail %d | error %d | skip %d", r.total, r.passed, r.failed, r.errored, r.skipped))
local denom = r.total - r.skipped
local pct = denom > 0 and (100 * r.passed / denom) or 0
print(string.format("Pass rate (excl. skipped): %.1f%%", pct))

if #r.surprises > 0 then
  print(string.format("\nSURPRISE PASSES (%d) — record with --update-baseline:", #r.surprises))
  for _, id in ipairs(r.surprises) do
    print("  + " .. id)
  end
end

if #r.regressions > 0 then
  print(string.format("\nREGRESSIONS (%d):", #r.regressions))
  for _, id in ipairs(r.regressions) do
    print("  - " .. id)
  end
  os.exit(1)
end

if update then
  print("\nBaseline updated.")
end
