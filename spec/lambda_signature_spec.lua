local jsonata = require("jsonata")

local function run(src, input)
  return jsonata.compile(src):evaluate(input)
end

describe("lambda: λ alias", function()
  it("λ is an alias for function", function()
    assert.are.equal(5, run("λ($x){$x}(5)"))
    assert.are.equal(8, run("λ($x, $y){$x + $y}(3, 5)"))
  end)
end)

describe("lambda: typed signatures", function()
  it("validates basic types", function()
    assert.is_false(run("λ($a)<b:b>{$not($a)}(true)"))
    assert.are.equal(8, run("function($x, $y)<nn:n>{$x + $y}(3, 5)"))
  end)

  it("injects context for a '-' marker", function()
    assert.are.equal(8, run("function($x, $y)<n-n:n>{$x + $y}(2, 6)"))
    assert.are.same({ 7, 8, 9, 10, 11 }, run("[1..5].function($x, $y)<n-n:n>{$x + $y}(6)"))
    assert.are.equal(34, run("Age.function($x, $y)<n-n:n>{$x + $y}(6)", { Age = 28 }))
  end)

  it("injects context for a trailing '-' (no explicit arg)", function()
    assert.are.equal("HELLO", run('λ($s)<s->{$uppercase($s)}("hello")'))
  end)

  it("raises T0410 on a type mismatch", function()
    local ok, err = pcall(run, 'λ($a, $b)<nn:a>{[$a, $b]}(1, "2")')
    assert.is_false(ok)
    assert.are.equal("T0410", err.code)
  end)

  it("raises S0401 at compile for a bad signature", function()
    local ok, err = pcall(run, "λ($a)<n<n>>{$a}(5)")
    assert.is_false(ok)
    assert.are.equal("S0401", err.code)
  end)

  it("still runs an unsigned lambda (no regression)", function()
    assert.are.equal(25, run("function($x){$x * $x}(5)"))
  end)
end)
