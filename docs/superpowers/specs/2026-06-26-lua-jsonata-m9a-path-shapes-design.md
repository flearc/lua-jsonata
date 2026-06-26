# lua-jsonata M9a - path value-shape normalization

**Status:** approved design (2026-06-26). Local spec written with
`superpowers:brainstorming`.

**Goal:** Design the next path/flattening milestone around one coherent value-shape
model, rather than adding more evaluator-side special cases. M9a targets the
remaining path/array flattening behavior where JSONata distinguishes navigation
sequences from constructed array values.

**Important scope note:** this spec is future-looking. It does not include the
current uncommitted evaluator/baseline experiments as implementation scope. Those
experiments are useful context, but M9a should be planned and implemented as its
own milestone.

---

## In Scope

M9a covers the remaining path/flattening family of official-suite cases:

- Nested array constructors in paths:
  - `nest0.[nest1.[nest2.[nest3]]]`
  - `nest0.nest1.[nest2.[nest3]]`
  - `nest0.[nest1.nest2.[nest3]]`
  - `nest0.nest1.nest2.[nest3]`
- Sequence-of-arrays constructors:
  - `$.[value,epochSeconds]`
  - `$.[value,epochSeconds][]`
- Array field flattening:
  - `[{"a":[1,2]}, {"a":[3]}].a`
- Predicate/index interaction after array flattening:
  - `[{"a":[{"b":[1]}, {"b":[2]}]}, {"a":[{"b":[3]}, {"b":[4]}]}].a[0].b`
  - `a[0].b`
- Object-constructor path edge:
  - `$.{'Hello':'World'}` over array input remains undefined.

The implementation plan should add focused unit tests for these shape categories
and use the official cases as the acceptance source.

## Out Of Scope

M9a does not cover:

- joins flat-stage cross-product deferrals (`library-joins/7,8,10`);
- tail recursion;
- URL/encoding functions;
- mutation or assignment semantics such as `variables/case012`;
- broad parser rewrites unless the plan proves the AST lacks enough information
  to represent a required shape distinction.

---

## Problem Summary

The current evaluator mostly relies on `append_flat` and `finalize_sequence` to
decide result shape. That works for many paths, but the remaining flattening cases
need a more explicit distinction between:

1. values that should join the navigation stream;
2. array constructor results that should remain one value per mapped input;
3. array boundaries that should survive temporarily and only be unwrapped at an
   expression boundary.

Without that distinction, fixes tend to over-flatten row-shaped arrays such as
`$.[value,epochSeconds]` or under-flatten navigated arrays such as `.a` returning
`[1,2]` and `[3]`.

---

## Architecture

M9a should make path value-shape decisions explicit at evaluator chokepoints.

### Shape 1: navigation sequence

The navigation sequence is the normal stream of path items. Field navigation over
array-valued fields opens those arrays into the stream. For example:

```jsonata
[{"a":[1,2]}, {"a":[3]}].a
```

should produce the stream `1, 2, 3`, not two preserved array values
`[1,2]` and `[3]`.

### Shape 2: constructed array value

An array constructor step is a value-producing expression. When it is mapped over
multiple input items, each constructed array is a single value for that input
item. For example:

```jsonata
$.[value,epochSeconds]
```

over two objects should produce:

```json
[[3, 1578381600], [5, 1578381700]]
```

not a flat sequence of four scalar values.

### Shape 3: preserved array boundary

Some arrays intentionally preserve a boundary:

- constructor arrays with the `cons` flag;
- `[]` keepArray paths;
- nested array constructors inside another constructor;
- temporary selected arrays during chained predicates, when the next predicate
  indexes into the selected array.

The design goal is not to preserve every array. It is to preserve the arrays that
are values, and open the arrays that are navigation streams.

---

## Proposed Evaluator Chokepoints

The implementation plan should prefer helper-level changes in `evaluator.lua`
over parser rewrites.

### `append_path_result`

Introduce or formalize a helper for appending a step result to the navigation
context. It should encode when arrays are opened into the stream and when they
are kept as values.

Expected behavior:

- ordinary navigation results open non-constructor arrays into the stream;
- `NOTHING` is skipped;
- constructor arrays can be kept when the current step is an array constructor
  mapped over an input item;
- existing tuple-mode behavior must not change unless explicitly tested.

### `append_constructor_result`

Array constructor steps need a clear mapping rule: append one constructed array
per input item unless a later path step must navigate inside that constructed
value. This is the rule that protects `$.[value,epochSeconds]` from being
over-flattened while still letting `[1,2,[3,4]][-1][-1]` index into the selected
inner array.

### Predicate chaining rule

Chained predicates need an explicit rule:

- a numeric predicate selects from the current stream;
- if a prior predicate leaves a single array value, the next predicate indexes
  into that selected array's members;
- this rule should be tested outside tuple mode and regression-tested inside
  tuple/joins because `apply_predicates` is shared.

---

## Data Flow

Path evaluation should be specified as these stages:

1. **Seed context.** A self-contained first step (`$`, function, block,
   array/object constructor, nested path, wildcard, descendant, parent) runs once
   against the whole input. Other paths seed from the input sequence.
2. **Evaluate each step per context item.** Ordinary field/name steps navigate
   into the item. Array-valued navigation results join the navigation sequence.
3. **Treat array constructor steps as mapped values.** A constructor step creates
   one array value per context item unless a following path operation explicitly
   navigates into that array value.
4. **Apply predicates after the step result.** Predicates operate on the current
   sequence. Chained predicates can descend into a selected array value when the
   previous predicate leaves exactly one array.
5. **Finalize at expression boundaries.** `finalize_sequence` remains the final
   boundary: empty -> undefined, singleton -> scalar unless keepArray is present,
   multi -> array/sequence. M9a should avoid adding early finalization inside
   ordinary path-step evaluation.

---

## Error Handling

M9a should not introduce public error codes. These are value-shape semantics, so
incorrect behavior should surface as result mismatches in tests, not new
structured errors.

If implementation uncovers an unexpected invalid state, prefer an internal test
that prevents the state from arising rather than a new user-facing error.

---

## Testing Strategy

Add or extend a focused spec file, likely `spec/path_shapes_spec.lua`, with tests
grouped by shape:

- navigation array flattening;
- constructed array preservation;
- nested constructor preservation;
- chained predicate indexing;
- object-constructor path edges.

Run targeted official groups during implementation:

- `flattening`;
- `array-constructor`;
- `simple-array-selectors`;
- `predicates`;
- `joins`.

Then run the full official suite with the baseline guard. Update
`spec/jsonata-suite/baseline.lua` only after the full guard passes.

Success criteria:

- all M9a in-scope official cases pass;
- no regressions in the baseline guard;
- no tuple/joins regression;
- no unrelated parser or formatting behavior changes.

---

## Regression Risks

- **Singleton unwrap risk:** `finalize_sequence` is central. M9a should keep
  finalization behavior unchanged except by feeding it the correct stream.
- **Constructor flattening risk:** over-flattening breaks row-shaped arrays;
  under-flattening breaks navigation sequences.
- **Predicate risk:** `apply_predicates` is shared with tuple mode. Any predicate
  change must run `joins` and parent/tuple-related tests.
- **Object constructor risk:** `{...}` as a standalone expression and `{...}` as
  a mapped path step must remain distinct. `$.{'Hello':'World'}` over empty array
  input should remain undefined.

---

## Recommended Implementation Shape

The follow-up implementation plan should proceed in small guarded steps:

1. Add focused unit tests for in-scope shape categories.
2. Capture the current official failure matrix for the M9a cases.
3. Introduce one path-result append helper and route normal `eval_path` step
   accumulation through it.
4. Add the constructor-step preservation rule.
5. Add or refine the chained-predicate selected-array rule.
6. Run targeted groups after each semantic change.
7. Run the full suite and regenerate the baseline only after the guard is clean.

The first implementation attempt should remain evaluator-side. Parser changes
are allowed only if the implementation plan shows the current AST cannot
distinguish array constructor steps from ordinary path steps at the necessary
chokepoint.
