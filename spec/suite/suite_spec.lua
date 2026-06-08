local jsonata = require("jsonata")
local cases = require("spec.suite.cases.m1")

describe("official test-suite (M1 subset)", function()
  for i, case in ipairs(cases) do
    it(string.format("[%s] %s", case.group, case.expr), function()
      if case.code then
        local errs = require("jsonata.errors")
        local ok, err = pcall(function()
          jsonata.compile(case.expr):evaluate(case.data or {})
        end)
        assert.is_false(ok)
        assert.is_true(errs.is_error(err))
        assert.are.equal(case.code, err.code)
      else
        local got = jsonata.compile(case.expr):evaluate(case.data or {})
        assert.are.same(case.result, got)
      end
    end)
  end
end)
