local Evaluator = require("jsonata.evaluator")
local Environment = require("jsonata.environment")
local parser = require("jsonata.parser")

describe("explain: evaluator seam", function()
  it("fires the explain hook pre/post for every evaluated node", function()
    local pre, post = {}, {}
    local post_results = {}
    local env = Environment.new():create_frame()
    env:bind("__explain_hook", {
      pre = function(node)
        pre[#pre + 1] = node.type
      end,
      post = function(node, input, env, result)
        post[#post + 1] = node.type
        post_results[#post_results + 1] = result
      end,
    })
    local ast = parser.parse("1 + 2")
    assert.are.equal(3, Evaluator.evaluate(ast, nil, env))
    -- binary plus its two number operands = 3 nodes; pre/post balanced
    assert.are.equal(3, #pre)
    assert.are.equal(3, #post)
    assert.are.equal("binary", pre[1])
    -- post fires in completion order; the last one is the top-level binary's result
    assert.are.equal(3, post_results[#post_results])
  end)

  it("does not treat a stray user var named __explain_hook as a hook", function()
    local env = Environment.new():create_frame()
    env:bind("__explain_hook", "just a string")
    local ast = parser.parse("1 + 2")
    assert.are.equal(3, Evaluator.evaluate(ast, nil, env))
  end)

  it("leaves normal evaluation unchanged when no hook is bound", function()
    local env = Environment.new():create_frame()
    local ast = parser.parse("1 + 2")
    assert.are.equal(3, Evaluator.evaluate(ast, nil, env))
  end)
end)

describe("explain: hook injection via public API", function()
  it("Expression:evaluate honors self._explain_hook", function()
    local jsonata = require("jsonata")
    local seen = {}
    local expr = jsonata.compile("1 + 2")
    expr._explain_hook = {
      pre = function(node)
        seen[#seen + 1] = node.type
      end,
      post = function() end,
    }
    assert.are.equal(3, expr:evaluate(nil))
    assert.are.equal(3, #seen)
  end)
end)

describe("explain: render_value", function()
  local explain = require("jsonata.explain")
  local V = require("jsonata.value")
  local rv = explain._render_value

  it("distinguishes the five empty/absent glyphs", function()
    assert.are.equal("*nothing*", rv(V.NOTHING))
    assert.are.equal("null", rv(V.NULL))
    assert.are.equal("<seq:[]>", rv(V.sequence()))
    assert.are.equal("[]", rv(V.array({})))
    assert.are.equal("{}", rv(V.object()))
  end)

  it("renders primitives", function()
    assert.are.equal('"hi"', rv("hi"))
    assert.are.equal('""', rv(""))
    assert.are.equal("2", rv(2))
    assert.are.equal("2.5", rv(2.5))
    assert.are.equal("true", rv(true))
    assert.are.equal("false", rv(false))
  end)

  it("renders arrays and sequences distinctly", function()
    assert.are.equal("[1, 2]", rv(V.array({ 1, 2 })))
    assert.are.equal("<seq:[1, 2]>", rv(V.sequence(1, 2)))
  end)

  it("renders objects preserving key insertion order", function()
    local o = V.object()
    V.obj_set(o, "c", 1)
    V.obj_set(o, "a", 2)
    V.obj_set(o, "b", 3)
    assert.are.equal("{c: 1, a: 2, b: 3}", rv(o))
  end)
end)

describe("explain: render_ast", function()
  local explain = require("jsonata.explain")
  local parser = require("jsonata.parser")

  it("renders the raw '.' binary tree", function()
    local out = explain._render_ast(parser.parse_raw("a.b"))
    assert.is_truthy(out:find("binary %(value=%.%)"))
    assert.is_truthy(out:find("name %(value=a%)"))
    assert.is_truthy(out:find("name %(value=b%)"))
  end)

  it("renders the normalized path with steps", function()
    local out = explain._render_ast(parser.parse("a.b"))
    assert.is_truthy(out:find("path"))
    assert.is_truthy(out:find("steps:"))
  end)

  it("renders a folded predicate under a path step", function()
    local out = explain._render_ast(parser.parse("nums[$>2]"))
    assert.is_truthy(out:find("path"))
    assert.is_truthy(out:find("predicate:"))
    assert.is_truthy(out:find("binary %(value=>%)"))
  end)
end)

describe("explain: render_tokens", function()
  local explain = require("jsonata.explain")

  it("lists the token stream", function()
    local out = explain._render_tokens("nums[$>2]")
    assert.is_truthy(out:find("name"))
    assert.is_truthy(out:find('"nums"'))
    assert.is_truthy(out:find("operator"))
    assert.is_truthy(out:find("number"))
  end)
end)

describe("explain: eval trace", function()
  local explain = require("jsonata.explain")

  it("traces each node with input and result", function()
    local out = explain._render_eval("nums[$>2]", { nums = { 1, 2, 3, 4 } })
    assert.is_truthy(out:find("path"))
    assert.is_truthy(out:find('binary ">"'))
    assert.is_truthy(out:find("%$=1"))
    assert.is_truthy(out:find("number 2"))
    assert.is_truthy(out:find("=> false"))
    assert.is_truthy(out:find("=> true"))
    assert.is_truthy(out:find("3, 4")) -- final result contains 3 and 4 (array or <seq:...>)
  end)

  it("renders an error instead of throwing", function()
    local out = explain._render_eval("1 +", nil)
    assert.is_truthy(out:find("error"))
  end)
end)
