# lua-jsonata M9a Path Value-Shape Normalization Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Normalize JSONata path value shapes so navigation arrays flatten, constructed arrays preserve row boundaries, and chained predicates can index into selected arrays.

**Architecture:** Keep the parser stable and make the evaluator's path accumulation rules explicit. Add focused path-shape tests first, then route `eval_path` through helper-level chokepoints that distinguish navigation values from array-constructor values. Preserve tuple/joins behavior by regression-running tuple-heavy groups after predicate helper changes.

**Tech Stack:** LuaJIT, busted specs, vendored JSONata official suite via `scripts/run-suite.sh`.

---

## Setup Notes

Execute this plan from a clean implementation branch. If the working tree contains earlier evaluator or baseline experiments, either commit them on their own branch or stash them before starting this plan. This plan is based on the M9a design spec:

- `docs/superpowers/specs/2026-06-26-lua-jsonata-m9a-path-shapes-design.md`

Do not push until the branch is complete and reviewed. If a push is requested later, create or remain on a non-`main` branch before pushing.

## File Structure

- **Create** `spec/path_shapes_spec.lua` - focused unit coverage for M9a path-shape rules.
- **Modify** `src/jsonata/evaluator.lua` - path accumulation helpers, self-contained path seeding, array-constructor append behavior, chained-predicate selected-array behavior.
- **Modify** `spec/jsonata-suite/baseline.lua` - official-suite baseline update after full guard passes.

No parser changes are planned. If implementation proves the evaluator cannot distinguish a required shape from the current AST, stop and update the plan before editing `parser.lua`.

---

### Task 1: Add Focused M9a Path-Shape Tests

**Files:**
- Create: `spec/path_shapes_spec.lua`

- [ ] **Step 1: Write the failing tests**

Create `spec/path_shapes_spec.lua`:

```lua
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
    assert.are.equal(3, run("$[1][0]", {
      { 1, 2 },
      { 3, 4 },
    }))
  end)

  it("fractional predicate numbers floor before indexing", function()
    assert.are.equal(3, run("$[1.1][0.9]", {
      { 1, 2 },
      { 3, 4 },
    }))
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
```

- [ ] **Step 2: Run the focused tests to verify they fail**

Run:

```bash
eval "$(luarocks path --local)"
~/.luarocks/bin/busted spec/path_shapes_spec.lua
```

Expected: FAIL. At least the nested constructor, row-preservation, chained predicate, and navigation flattening cases should expose current shape mismatches.

- [ ] **Step 3: Commit the failing tests**

```bash
git add spec/path_shapes_spec.lua
git commit -m "test(M9a): capture path value-shape cases"
```

---

### Task 2: Introduce Explicit Path Append Helpers

**Files:**
- Modify: `src/jsonata/evaluator.lua`
- Test: `spec/path_shapes_spec.lua`

- [ ] **Step 1: Replace `append_flat` with option-aware helpers**

In `src/jsonata/evaluator.lua`, replace the existing `append_flat` helper with these helpers:

```lua
-- Build a fresh sequence, appending elements with path-shape rules.
local function append_path_value(seq, value, opts)
  opts = opts or {}
  if V.is_nothing(value) then
    return
  end
  if opts.keep_array then
    seq[#seq + 1] = value
    return
  end
  if V.is_array(value) and not V.get_flag(value, "cons") then
    for i = 1, #value do
      seq[#seq + 1] = value[i]
    end
  else
    seq[#seq + 1] = value
  end
end

local function append_flat(seq, value)
  append_path_value(seq, value)
end

local function append_constructor_value(seq, value, has_following_step)
  if V.is_nothing(value) then
    return
  end
  if has_following_step and V.is_array(value) then
    for i = 1, #value do
      seq[#seq + 1] = value[i]
    end
    return
  else
    seq[#seq + 1] = value
  end
end
```

Keep the `append_flat` wrapper so existing tuple/group helper code continues to call the same name.

- [ ] **Step 2: Run a narrow regression check**

Run:

```bash
eval "$(luarocks path --local)"
~/.luarocks/bin/busted spec/joins_spec.lua spec/keeparray_spec.lua
```

Expected: PASS. The helper is behavior-preserving until `eval_path` is routed through the new constructor-specific helper.

- [ ] **Step 3: Commit the helper extraction**

```bash
git add src/jsonata/evaluator.lua
git commit -m "refactor(M9a): add explicit path append helpers"
```

---

### Task 3: Route Normal Path Steps Through Shape-Aware Appends

**Files:**
- Modify: `src/jsonata/evaluator.lua`
- Test: `spec/path_shapes_spec.lua`

- [ ] **Step 1: Update self-contained first-step detection**

In `src/jsonata/evaluator.lua`, update `step_is_self_contained` so object constructors can seed a path, and the context variable `$` after an array constructor remains self-contained:

```lua
local function step_is_self_contained(steps)
  local s1 = steps[1]
  return s1
    and (
      s1.type == "variable"
      or s1.type == "function"
      or s1.type == "block"
      or s1.type == "path"
      or s1.type == "object"
      or s1.type == "wildcard"
      or s1.type == "descendant"
      or s1.type == "parent"
      or (s1.type == "array" and not (steps[2] and steps[2].type == "variable" and steps[2].value ~= ""))
    )
end
```

- [ ] **Step 2: Update the self-contained seeding block**

In `eval_path`, replace the first-step seeding append logic with:

```lua
  if first_is_self_contained then
    local var_val = evaluate(steps[1], input, env)
    local result = V.sequence()
    if steps[1].type == "array" and V.is_array(var_val) then
      for i = 1, #var_val do
        result[#result + 1] = var_val[i]
      end
    else
      append_path_value(result, var_val)
    end
    if steps[1].predicate then
      result = apply_predicates(result, steps[1].predicate, env)
    end
    context = result
    start = 2
  elseif V.is_array(input) then
    context = input
  else
    context = V.sequence(input)
  end
```

- [ ] **Step 3: Update the main `eval_path` step accumulation**

In `eval_path`, replace the generic `append_flat(result, eval_step_on_item(step, item, env))` accumulation with:

```lua
      local result = V.sequence()
      for j = 1, #context do
        local item = context[j]
        if not V.is_nothing(item) then
          local value = eval_step_on_item(step, item, env)
          if step.type == "array" then
            append_constructor_value(result, value, i < #steps)
          else
            append_path_value(result, value)
          end
        end
      end
      context = result
```

Do not change the `sort` or `group` branches in this task.

- [ ] **Step 4: Run focused path-shape tests**

Run:

```bash
eval "$(luarocks path --local)"
~/.luarocks/bin/busted spec/path_shapes_spec.lua
```

Expected: the object-constructor path edge, constructed-row preservation, navigation array flattening, and nested constructor tests PASS. The chained predicate block remains red until Task 4.

- [ ] **Step 5: Run targeted official groups**

Run:

```bash
scripts/run-suite.sh
```

Expected: exit 0. Surprise passes are acceptable; regressions are not. If regressions appear, stop and inspect whether a constructor array was opened as navigation or a navigation array was preserved.

- [ ] **Step 6: Commit**

```bash
git add src/jsonata/evaluator.lua
git commit -m "feat(M9a): route path steps through shape-aware appends"
```

---

### Task 4: Define Chained Predicate Selected-Array Semantics

**Files:**
- Modify: `src/jsonata/evaluator.lua`
- Test: `spec/path_shapes_spec.lua`, `spec/joins_spec.lua`

- [ ] **Step 1: Update `apply_predicates` to descend into a selected array**

In `src/jsonata/evaluator.lua`, change the `apply_predicates` loop header from:

```lua
  for _, pred in ipairs(predicates) do
    local next_seq = V.sequence()
```

to:

```lua
  for pi, pred in ipairs(predicates) do
    if pi > 1 and #current == 1 and V.is_array(current[1]) then
      current = current[1]
    end
    local next_seq = V.sequence()
```

This rule means `$[1][0]` first selects the array at index 1, then the next
predicate indexes into that selected array's members.

- [ ] **Step 2: Run chained-predicate focused tests**

Run:

```bash
eval "$(luarocks path --local)"
~/.luarocks/bin/busted spec/path_shapes_spec.lua
```

Expected: the `M9a path shapes: chained predicates index selected arrays` block passes.

- [ ] **Step 3: Run tuple/joins regression tests**

Run:

```bash
eval "$(luarocks path --local)"
~/.luarocks/bin/busted spec/joins_spec.lua spec/parent_spec.lua
```

Expected: PASS. `apply_predicates` is shared with tuple mode, so these tests must stay green.

- [ ] **Step 4: Run official guard**

Run:

```bash
scripts/run-suite.sh
```

Expected: exit 0. The official cases `array-constructor/case010`,
`simple-array-selectors/case021`, and `simple-array-selectors/case022` should be surprise passes if not already in the baseline.

- [ ] **Step 5: Commit**

```bash
git add src/jsonata/evaluator.lua
git commit -m "feat(M9a): let chained predicates index selected arrays"
```

---

### Task 5: Verify The M9a Official Case Matrix

**Files:**
- Test: `spec/path_shapes_spec.lua`

- [ ] **Step 1: Run focused tests**

Run:

```bash
eval "$(luarocks path --local)"
~/.luarocks/bin/busted spec/path_shapes_spec.lua
```

Expected: all `spec/path_shapes_spec.lua` tests PASS.

- [ ] **Step 2: Run the official suite guard**

Run:

```bash
scripts/run-suite.sh
```

Expected: exit 0. Expected surprise passes include the M9a in-scope official cases. No regressions.

- [ ] **Step 3: Record the expected M9a surprise pass ids**

From the `SURPRISE PASSES` section, record the M9a-related ids in your implementation notes. The expected ids are drawn from these groups:

- `flattening`
- `array-constructor`
- `simple-array-selectors`

Do not update `spec/jsonata-suite/baseline.lua` in this task.

---

### Task 6: Regenerate Official-Suite Baseline

**Files:**
- Modify: `spec/jsonata-suite/baseline.lua`

- [ ] **Step 1: Run the full official suite before updating baseline**

Run:

```bash
scripts/run-suite.sh
```

Expected: exit 0 with surprise passes and no regressions.

- [ ] **Step 2: Update the baseline**

Run:

```bash
scripts/run-suite.sh --update-baseline
```

Expected: command exits 0 and prints `Baseline updated.`

- [ ] **Step 3: Re-run the full official suite after baseline update**

Run:

```bash
scripts/run-suite.sh
```

Expected: exit 0 with no `SURPRISE PASSES` section and no `REGRESSIONS` section.

- [ ] **Step 4: Inspect the baseline diff**

Run:

```bash
git diff -- spec/jsonata-suite/baseline.lua
```

Expected: only newly passing M9a official case ids are added. No removals.

- [ ] **Step 5: Commit**

```bash
git add spec/jsonata-suite/baseline.lua
git commit -m "test(M9a): record path-shape official suite passes"
```

---

### Task 7: Final Verification And Handoff

**Files:**
- No file changes expected.

- [ ] **Step 1: Run focused specs**

Run:

```bash
eval "$(luarocks path --local)"
~/.luarocks/bin/busted spec/path_shapes_spec.lua spec/joins_spec.lua spec/keeparray_spec.lua spec/parent_spec.lua
```

Expected: PASS.

- [ ] **Step 2: Run full official guard**

Run:

```bash
scripts/run-suite.sh
```

Expected: exit 0 with no regressions and no surprise passes.

- [ ] **Step 3: Check working tree**

Run:

```bash
git status --short
```

Expected: no uncommitted files.

- [ ] **Step 4: Summarize remaining out-of-scope failures**

Run:

```bash
scripts/run-suite.sh
```

Expected: use the printed group summary to note remaining red areas such as joins flat-stage deferrals, tail recursion, URL/encoding, or unrelated function gaps.
