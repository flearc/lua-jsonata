local jsonata = require("jsonata")

local function run(src, input)
  return jsonata.compile(src):evaluate(input)
end

describe("M9a path shapes: constructed arrays in paths", function()
  local rows = {
    { epochSeconds = 1578381600, value = 3 },
    { epochSeconds = 1578381700, value = 5 },
  }

  it("$.[value,epochSeconds] preserves one constructed row per input item", function()
    assert.are.same({
      { 3, 1578381600 },
      { 5, 1578381700 },
    }, run("$.[value,epochSeconds]", rows))
  end)

  it("$.[value,epochSeconds][] keeps the mapped row arrays when keepArray is present", function()
    assert.are.same({
      { 3, 1578381600 },
      { 5, 1578381700 },
    }, run("$.[value,epochSeconds][]", rows))
  end)

  it("single mapped row unwraps without [] and stays wrapped with []", function()
    local one = { { epochSeconds = 1578381600, value = 3 } }
    assert.are.same({ 3, 1578381600 }, run("$.[value,epochSeconds]", one))
    assert.are.same({ { 3, 1578381600 } }, run("$.[value,epochSeconds][]", one))
  end)

  it("constructed rows remain whole when followed by sort", function()
    local unsorted = {
      { epochSeconds = 1578381700, value = 5 },
      { epochSeconds = 1578381600, value = 3 },
    }
    assert.are.same({
      { 3, 1578381600 },
      { 5, 1578381700 },
    }, run("$.[value,epochSeconds]^($[1])", unsorted))
  end)

  it("constructed rows remain whole when followed by group", function()
    assert.are.same({
      ["3"] = { 3, 1578381600 },
      ["5"] = { 5, 1578381700 },
    }, run("$.[value,epochSeconds]{ $string($[0]): $ }", rows))
  end)
end)

describe("M9a path shapes: nested array constructors", function()
  local data = {
    nest0 = {
      {
        nest1 = {
          { nest2 = { { nest3 = 1 }, { nest3 = 2 } } },
          { nest2 = { { nest3 = 3 }, { nest3 = 4 } } },
        },
      },
      {
        nest1 = {
          { nest2 = { { nest3 = 5 }, { nest3 = 6 } } },
          { nest2 = { { nest3 = 7 }, { nest3 = 8 } } },
        },
      },
    },
  }

  it("nest0.[nest1.[nest2.[nest3]]] preserves each constructor boundary", function()
    assert.are.same({
      {
        { { 1 }, { 2 } },
        { { 3 }, { 4 } },
      },
      {
        { { 5 }, { 6 } },
        { { 7 }, { 8 } },
      },
    }, run("nest0.[nest1.[nest2.[nest3]]]", data))
  end)

  it("nest0.nest1.nest2.[nest3] preserves only the terminal constructor", function()
    assert.are.same({
      { 1 },
      { 2 },
      { 3 },
      { 4 },
      { 5 },
      { 6 },
      { 7 },
      { 8 },
    }, run("nest0.nest1.nest2.[nest3]", data))
  end)
end)

describe("M9a path shapes: navigation arrays flatten", function()
  it("array-valued fields join the navigation sequence", function()
    assert.are.same({ 1, 2, 3 }, run('[{"a":[1,2]}, {"a":[3]}].a'))
  end)

  it("predicate after flattened array field selects per JSONata path sequence", function()
    assert.are.same({
      1,
      3,
    }, run('[{"a":[{"b":[1]}, {"b":[2]}]}, {"a":[{"b":[3]}, {"b":[4]}]}].a[0].b'))
  end)

  it("path over array input keeps existing array-input selector behavior", function()
    local data = {
      { a = { { b = { 1 } }, { b = { 2 } } } },
      { a = { { b = { 3 } }, { b = { 4 } } } },
    }
    assert.are.same({ 1 }, run("a[0].b", data))
  end)
end)

describe("M9a path shapes: chained predicates index selected arrays", function()
  it("$[1][0] indexes into the array selected by the first predicate", function()
    assert.are.equal(
      3,
      run("$[1][0]", {
        { 1, 2 },
        { 3, 4 },
      })
    )
  end)

  it("fractional predicate numbers floor before indexing", function()
    assert.are.equal(
      3,
      run("$[1.1][0.9]", {
        { 1, 2 },
        { 3, 4 },
      })
    )
  end)

  it("nested array selected by a negative index can be indexed again", function()
    assert.are.equal(4, run("[1, 2, [3, 4]][-1][-1]"))
  end)
end)

describe("M9a path shapes: object constructor path edge", function()
  it("$.{'Hello':'World'} over empty array input is undefined", function()
    assert.is_nil(run("$.{'Hello':'World'}", {}))
  end)

  it("{'Hello':'World'} standalone remains an object", function()
    assert.are.same({ Hello = "World" }, run("{'Hello':'World'}", {}))
  end)
end)
