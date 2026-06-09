local Evaluator = require("jsonata.evaluator")
local Environment = require("jsonata.environment")
local parser = require("jsonata.parser")

describe("explain: evaluator seam", function()
  it("fires the explain hook pre/post for every evaluated node", function()
    local pre, post = {}, {}
    local env = Environment.new():create_frame()
    env:bind("__explain_hook", {
      pre = function(node)
        pre[#pre + 1] = node.type
      end,
      post = function(node)
        post[#post + 1] = node.type
      end,
    })
    local ast = parser.parse("1 + 2")
    assert.are.equal(3, Evaluator.evaluate(ast, nil, env))
    -- binary plus its two number operands = 3 nodes; pre/post balanced
    assert.are.equal(3, #pre)
    assert.are.equal(3, #post)
    assert.are.equal("binary", pre[1])
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
