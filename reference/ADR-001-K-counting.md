# ADR-001: K counts total nodes, not just leaves

**Status:** Accepted
**Date:** 2026-04-26
**Context:** v1 → v2 transition

## Decision

In v2, `eml_K(expr)` returns the total node count (leaves + interior
EML nodes) of the EML expression. This matches the paper's definition
of K as RPN code length.

## Background

The paper (Table 4, Eq. 5) reports `K = 7` for `log(x) = eml(1, eml(eml(1, x), 1))`.
This corresponds to the RPN serialisation `1, 1, x, eml, 1, eml, eml`,
which has 7 tokens: 4 literals + 3 EML operations.

The v1 prototype defined `eml_K` as a leaf count:

```r
eml_K <- function(tree) {
  if (tree$type %in% c("const", "var")) 1L
  else eml_K(tree$left) + eml_K(tree$right)
}
```

This returns 4 for the same expression — counting only the leaves, not
the EML nodes. The v1 README claimed "K = 7 (paper: 7)" was the result.
That claim was a documentation error: v1 returned 4, the paper says 7.

The user did not catch this in v1 because the v1 tests did not assert
specific K values — they only printed K alongside other diagnostics.

## Options considered

**A. Keep v1's leaf-count semantics, rename and document.**
   - Pro: backwards compatible
   - Con: doesn't match the paper, requires re-explaining every time
     someone compares to Table 4

**B. Change `eml_K` to total node count, document in NEWS.md.**
   - Pro: matches the paper, eliminates documentation error
   - Con: silent semantic change; v1 users who relied on K = 4 will
     see K = 7 instead

**C. Keep both: rename v1's behaviour to `eml_leafcount`, make `eml_K`
   the paper-correct total node count.**
   - Pro: matches paper *and* preserves access to v1 behaviour
   - Con: more API surface

## Decision rationale

Option C. The package's value depends on being able to compare directly
to the paper's tables. Anyone reading both the paper and the package
docs will be confused if `eml_K` doesn't match Table 4. Backwards
compatibility for the small number of v1 users is preserved by
`eml_leafcount(expr)`.

## Consequences

- `eml_K(quote(eml(1, eml(eml(1, x), 1))))` returns 7 in v2 (was 4 in v1).
- The v1 test script `reference/emlR-v1/tests/test_eml.R` will print
  different K values after porting; the user should update their notes
  but no test assertions break (v1 didn't assert specific K values).
- Documentation in v2 README and SPEC consistently uses paper's K.
- A `eml_leafcount(expr)` is provided for the (rare) case where leaf
  count is the actual desired metric.

## References

- Paper §3, last paragraph before Table 4: definition of K as
  Kolmogorov-style complexity / RPN program length.
- Paper Table 4: K values for all elementary functions.
- v1 prototype: `reference/emlR-v1/R/02_tree_ops.R::eml_K`
