-- Curated M1 smoke cases. NOTE: this is NOT the full official jsonata-js
-- test-suite (test/test-suite/groups/*); integrating the real JSON-driven
-- suite is deferred to M2. Each case: { expr, data, result } or { expr, code }.
local A = require("jsonata.adapter")
return {
  { group = "literals", expr = "42", data = nil, result = 42 },
  { group = "literals", expr = [["hello"]], data = nil, result = "hello" },
  { group = "literals", expr = "true", data = nil, result = true },
  { group = "numeric", expr = "2 + 3 * 4", data = nil, result = 14 },
  { group = "numeric", expr = "(2 + 3) * 4", data = nil, result = 20 },
  { group = "comparison", expr = "3 > 2", data = nil, result = true },
  { group = "boolean", expr = "true and false", data = nil, result = false },
  { group = "fields", expr = "name", data = { name = "Bob" }, result = "Bob" },
  { group = "path", expr = "a.b.c", data = { a = { b = { c = 7 } } }, result = 7 },
  { group = "path-multi", expr = "o.p", data = { o = { { p = 1 }, { p = 2 } } }, result = { 1, 2 } },
  { group = "predicate", expr = "items[1]", data = { items = { 10, 20, 30 } }, result = 20 },
  { group = "array-constructor", expr = "[1, 2, 3]", data = nil, result = { 1, 2, 3 } },
  { group = "variables", expr = "($x := 5; $x + 1)", data = nil, result = 6 },
  { group = "functions", expr = "$count(items)", data = { items = { 1, 2, 3 } }, result = 3 },
  { group = "path-single", expr = "o.p", data = { o = { { p = 7 } } }, result = 7 },
  { group = "cons", expr = "a.[b, c]", data = { a = { b = 1, c = 2 } }, result = { 1, 2 } },
  { group = "predicate-array", expr = "items[[0, 2]]", data = { items = { 10, 20, 30 } }, result = { 10, 30 } },
  { group = "null", expr = "x", data = { x = A.NULL }, result = A.NULL },
  { group = "error", expr = "1 +", code = "S0203" },
}
