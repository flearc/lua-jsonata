local tokenizer = require("jsonata.tokenizer")

local function tokens(src)
  local tk = tokenizer.new(src)
  local out = {}
  while true do
    local t = tk:next()
    if t == nil then
      break
    end
    out[#out + 1] = t
  end
  return out
end

describe("tokenizer", function()
  it("tokenizes numbers", function()
    local t = tokens("42")
    assert.are.equal("number", t[1].type)
    assert.are.equal(42, t[1].value)
  end)

  it("tokenizes double and single quoted strings with escapes", function()
    local t = tokens([["a\nb" 'c']])
    assert.are.equal("string", t[1].type)
    assert.are.equal("a\nb", t[1].value)
    assert.are.equal("c", t[2].value)
  end)

  it("tokenizes names, backtick names and variables", function()
    local t = tokens("foo `b c` $x $")
    assert.are.equal("name", t[1].type)
    assert.are.equal("foo", t[1].value)
    assert.are.equal("name", t[2].type)
    assert.are.equal("b c", t[2].value)
    assert.are.equal("variable", t[3].type)
    assert.are.equal("x", t[3].value)
    assert.are.equal("variable", t[4].type)
    assert.are.equal("", t[4].value)
  end)

  it("tokenizes multi-char and single-char operators", function()
    local t = tokens(":= != <= >= . [ ] + &")
    local kinds = {}
    for _, tok in ipairs(t) do
      kinds[#kinds + 1] = tok.value
    end
    assert.are.same({ ":=", "!=", "<=", ">=", ".", "[", "]", "+", "&" }, kinds)
    assert.are.equal("operator", t[1].type)
  end)

  it("tokenizes keywords true/false/null/and/or", function()
    local t = tokens("true and false or null")
    assert.are.equal("keyword", t[1].type)
    assert.are.equal("true", t[1].value)
    assert.are.equal("and", t[2].value)
  end)

  it("records positions", function()
    local t = tokens("  42")
    assert.are.equal(3, t[1].position)
  end)
end)

describe("tokenizer: function keyword", function()
  it("tokenizes function as a keyword", function()
    local tk = tokenizer.new("function")
    local t = tk:next()
    assert.are.equal("keyword", t.type)
    assert.are.equal("function", t.value)
  end)
end)
