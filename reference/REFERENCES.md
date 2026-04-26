# References

## Primary source

**Odrzywołek, A. (2026).** *All elementary functions from a single binary
operator.* arXiv:2603.21852. https://arxiv.org/abs/2603.21852

The paper's HTML version (better for reading): https://arxiv.org/html/2603.21852v2
Zenodo archival snapshot: https://doi.org/10.5281/zenodo.19183008
Author's package (Mathematica/Rust): https://github.com/VA00/SymbolicRegressionPackage

Key sections to consult during implementation:
- **§1**: Operator definition and the three sacred identities
  (exp, log Eq. 5, e from eml(1,1))
- **§3, Table 2**: Reduction sequence; explains why EML works
- **§3, Eq. (4)**: The full operator family — eml, edl, -eml(y,x)
- **§4.1**: EML compiler — RPN form, "single-instruction stack machine"
- **§4.2, Table 4**: K-optimal trees from exhaustive search (NOT what
  this package implements, but useful as a reference for shorter forms)
- **§4.3**: Master formula and symbolic regression — the design
  this package implements, including the (α,β,γ) parameterisation and
  the simplex/softmax mode
- **Supplementary Information, Part II**: Symbolic verification of the
  full identity chain (Mathematica notebook)
- **Supplementary Information, Part III**: Master formula parameter count
  proof (5·2^n − 6)

## Related implementations

| Project | Language | Purpose | Lessons for emlR2 |
|---------|----------|---------|-------------------|
| [VA00/SymbolicRegressionPackage](https://github.com/VA00/SymbolicRegressionPackage) | Mathematica | Author's reference; includes EML toolkit and Log_fit.nb | Authoritative identity chain; Log_fit.nb is the SR demo to reproduce |
| [cool-japan/oxieml](https://github.com/cool-japan/oxieml) | Rust | Pure-Rust crate implementing the operator and bytecode | Discovery vs. execution split; parser roundtrip property |
| [tomdif/eml-lean](https://github.com/tomdif/eml-lean) | Lean 4 | Formal verification of paper identities | Independent confirmation that the identity chain is correct |

The Lean 4 project is particularly valuable as a sanity check: every
identity it verifies, our `simplify_native` should produce the
corresponding base-R primitive.

## Why complex arithmetic is mandatory

The paper notes (§1, after Eq. 3): "Computations must be done in the
complex domain, e.g.: generating constants like i and π requires
evaluating ln(−1), so eml(x,y) internally operates over ℂ using the
principal branch."

R's principal branch convention matches Mathematica's:
- `log(as.complex(-1))` returns `0+πi`
- `exp(0+πi)` returns `-1+0i` (modulo float epsilon on the imag part)

This is correct for our purposes. Code that uses `log(-1)` (real) would
get `NaN`, which is wrong. Always coerce to complex first.

## Why extended-real semantics matter

Paper §4.1: "EML expressions in general do not work 'out of the box' in,
e.g., pure Python/Julia or numerical Mathematica. In the first case, this
is because special floats are trapped and raise errors. However, EML
works in NumPy, PyTorch."

R behaves like NumPy here. `log(0+0i)` returns `-Inf+0i`, and
`exp(-Inf+0i)` returns `0+0i`. The construction `−1 = exp(log(0)) − log(exp(1))
= 0 − 1` works correctly.

If you find yourself wanting to "fix" an `Inf` or `NaN` intermediate,
stop — it's almost certainly carrying real semantic information that the
paper relies on. Trace through the construction with paper §4.1 in hand
before touching it.

## v1 prototype

The v1 prototype is in `reference/emlR-v1/`. Treat it as:
- An authoritative source for which identities need to exist
- A correctness reference for numeric outputs
- A *negative* example of how to structure the AST

Do not copy v1's `eml_tree` S3 class or its `switch(type, ...)` dispatch
into v2. The whole point of v2 is to use R's native AST instead. The
construction logic in `tree_*` identity functions is correct and should
be ported, but the type system around them should be replaced.

## Derivation notes for tricky identities

These are derivations I worked through during v1 design. Recording them
here so the v2 implementer doesn't have to re-derive.

### log(x), K=7 (paper Eq. 5)

`eml(1, eml(eml(1, x), 1))`

Trace:
- innermost: `eml(1, x) = exp(1) - log(x) = e - log(x)`
- middle: `eml(e - log(x), 1) = exp(e - log(x)) - log(1) = exp(e - log(x))`
- outer: `eml(1, exp(e - log(x))) = exp(1) - log(exp(e - log(x))) = e - (e - log(x)) = log(x)` ✓

### sub(x, y) = x − y, K=3

`eml(log(x), exp(y))` evaluates as:
`exp(log(x)) - log(exp(y)) = x - y` (for x > 0; principal-branch elsewhere) ✓

### −1 via extended reals

`−1 = sub(0, 1) = eml(log(0), exp(1))`

Trace:
- `log(0) = -Inf` (extended real, or `-Inf+0i` in complex)
- `exp(1) = e`
- `eml(-Inf, e) = exp(-Inf) - log(e) = 0 - 1 = -1` ✓

### 0 via log(1)

`zero = log(1) = eml(1, eml(eml(1, 1), 1))`

Trace:
- `eml(1, 1) = e`
- `eml(e, 1) = exp(e) - 0 = exp(e)`
- `eml(1, exp(e)) = e - e = 0` ✓

### Why neg_one's construction is large

Because we need `log(0)` as an intermediate, and `log` itself is K=7.
So `neg_one = eml(log(zero), exp(1)) = eml(log_tree(zero_tree), exp_tree(1))`,
which expands to a tree of K = 7 + 7 + 3 + 1 ≈ 18, give or take the
sharing of subtrees. Compare to paper Table 4 column "Direct search":
−1 has K=15 in the optimal exhaustive-search form. We're at 17-18. Not
optimal but correct.

If you want to match the paper's K=15 form, you need the actual K-optimal
tree from the paper's supplementary material — which is not printed in
the article. Either run the author's `rust_verify` tool to find it, or
accept the larger K and move on.

### i and π are circular

`i = exp(log(-1) / 2)` and `π = log(-1) / i`. These reference each
other through `log(-1)`. The construction uses `i` to compute `π` and
vice-versa — but since `tree_i` and `tree_pi` both expand to fixed
expressions in `eml` and constants, the recursion bottoms out at the
EML level. Trace evaluation will show this.

### sin and cos via Euler

`sin(x) = (exp(i*x) - exp(-i*x)) / (2*i)` — standard identity, expands
to a moderately deep EML tree. The `simplify_native` rule E1 (SPEC §5.3)
recognises the post-simplified form and collapses it back to `sin(x)`.
Without E1, the simplifier produces a correct-but-ugly expression in
`exp` and `i`; with E1, it produces `sin(x)` literally.

## What I did NOT verify

- Paper Table 4 K-optimal forms beyond the three sacred identities. The
  catalog uses straightforward constructions, not optimal ones. If a user
  wants K-optimal trees, point them at the paper's supplementary material.
- The EDL and -EML(y,x) variants from Eq. (4b/4c). They should work
  similarly to EML but the catalog is built around EML only. v3 work.
- The ternary operator T(x,y,z) hinted at in §5. The paper mentions it
  as in-preparation work; not part of arXiv:2603.21852 proper.

## Citation for emlR2 itself

If you publish results using this package:

```bibtex
@software{emlR2,
  author = {Thielen, Philipp},
  title = {emlR2: All elementary functions from a single binary
           operator, in R},
  year = {2026},
  url = {https://github.com/...},
  note = {Implementation of arXiv:2603.21852 (Odrzywołek 2026)}
}
```

And cite the original paper:

```bibtex
@article{odrzywolek2026eml,
  title  = {All elementary functions from a single binary operator},
  author = {Odrzywołek, Andrzej},
  year   = {2026},
  eprint = {2603.21852},
  archivePrefix = {arXiv},
  primaryClass  = {cs.SC}
}
```
