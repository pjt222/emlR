# emlR

<!-- badges: start -->
[![R-CMD-check](https://github.com/pjt222/emlR/actions/workflows/R-CMD-check.yaml/badge.svg)](https://github.com/pjt222/emlR/actions/workflows/R-CMD-check.yaml)
[![pkgdown](https://github.com/pjt222/emlR/actions/workflows/pkgdown.yaml/badge.svg)](https://pjt222.github.io/emlR/)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![arXiv](https://img.shields.io/badge/arXiv-2603.21852-b31b1b.svg)](https://arxiv.org/abs/2603.21852)
<!-- badges: end -->

> R implementation of the EML (Exp-Minus-Log) Sheffer operator from
> **Odrzywołek, A. (2026). All elementary functions from a single binary
> operator.** [**arXiv:2603.21852**](https://arxiv.org/abs/2603.21852).

The paper proves a remarkable result: the single binary operator

$$\mathrm{eml}(x, y) \;=\; \exp(x) - \ln(y)$$

together with the constant `1`, generates **every elementary function** —
sums, products, powers, logarithms, trigonometric functions, π, *i*, the
lot — over the complex numbers (principal branch). emlR operationalises
that result in idiomatic R for symbolic manipulation, symbolic regression,
and pedagogical exploration.

> **Note.** All mathematical results in this package are due to
> Odrzywołek (2026). emlR is an independent R implementation; please
> cite the paper if you use it in published work — see
> [Citation](#citation) below.

## Installation

```r
# install.packages("Deriv")
# install.packages("remotes"); remotes::install_github("pjt222/emlR")
```

The package depends only on base R and [`Deriv`](https://CRAN.R-project.org/package=Deriv).

## Quick start

```r
library(emlR)

# The three sacred identities (paper, §1 + Eq. 5)
simplify_native(quote(eml(x, 1)))                          #> exp(x)
simplify_native(quote(eml(1, 1)))                          #> exp(1) ≈ 2.718
simplify_native(quote(eml(1, eml(eml(1, x), 1))))           #> log(x)

# Vectorised evaluation through the bytecode fast path
xs <- seq(0.5, 5, length.out = 30)
bc <- compile_eml(quote(eml(1, eml(eml(1, x), 1))))
Re(run_bytecode(bc, list(x = xs)))                          # log(xs)

# Symbolic regression: recover ln(x) from data with the master formula
fit <- eml_fit(xs, log(xs), depth = 3, n_restarts = 10)
fit$snap_mse                                                # ~0 ⇒ exact recovery
```

## What's in the box

| | |
|---|---|
| **Operator** | `eml()`, `eml_real()` — complex-domain, principal branch |
| **AST** | Native R `call` objects; free interop with `deparse`, `bquote`, `Deriv::Deriv`, `eval` |
| **Inspect** | `eml_K()`, `eml_depth()`, `eml_rpn()` |
| **Evaluate** | `eml_eval()`, plus a stack-machine `compile_eml()` / `run_bytecode()` for vectorised input |
| **Simplify** | `simplify_eml()` (stays in EML), `simplify_native()` (collapses to base-R primitives) |
| **Catalog** | `tree_*` constructors and `eml_catalog()` for every standard primitive; `verify_catalog()` to confirm |
| **SR** | `build_master()` + `eml_fit()` with L-BFGS-B and analytic gradients via `Deriv` |

See the package website at <https://pjt222.github.io/emlR/> for full
documentation and articles.

## Related implementations

If you use this package, you may also be interested in the following
implementations of the same operator and identities:

| Project | Language | Author | Purpose |
|---|---|---|---|
| [VA00/SymbolicRegressionPackage](https://github.com/VA00/SymbolicRegressionPackage) | Mathematica + Rust | Andrzej Odrzywołek | Author's reference; includes the EML toolkit and the `Log_fit.nb` symbolic-regression notebook reproduced as a vignette here |
| [cool-japan/oxieml](https://github.com/cool-japan/oxieml) | Rust | KitaSan AI | Pure-Rust crate implementing the operator and bytecode evaluator |
| [tomdif/eml-lean](https://github.com/tomdif/eml-lean) | Lean 4 | tomdif | Formal verification of the paper's identity chain |
| **emlR** | R | Philipp Thoss | This package — peephole simplifier, vectorised bytecode, and SR fitter |

The Lean 4 project is particularly valuable as a sanity check: every
identity it verifies, emlR's `simplify_native()` should produce the
corresponding base-R primitive.

## Status

Pre-release (0.1.0 in development). Targeting 0.1.0 as the first CRAN
submission.

## Scope and limitations

What this release covers and what it does not:

* **Variables.** Univariate and bivariate expressions are tested
  exhaustively (every catalog entry, the SR fitter, the bytecode
  evaluator). The infrastructure does not preclude `x, y, z, ...`
  but cases beyond two variables are not part of the test surface.
* **Operator family.** Only the EML operator `eml(x, y) = exp(x) − log(y)`
  is implemented. The EDL variant `exp(x) / log(y)` and the swapped
  form `−eml(y, x)` from the paper Eq. (4b/4c) are out of scope for
  this release.
* **Symbolic regression.** `eml_fit()` uses the paper's master-formula
  approach with L-BFGS-B + analytic gradients. Tree-topology search
  (genetic-programming style) is not provided; the master formula at
  fixed depth is sufficient for reproducing the paper's results.
* **Acceleration.** Pure base R + `Deriv`. No Rcpp, no `torch`, no
  parallelisation. The bytecode evaluator vectorises over input
  bindings within a single R loop, which is fast enough for the
  paper's reproducibility scale; it is not a benchmark machine.
* **Branch semantics.** Everything is on the principal complex
  branch (`log(-1) = iπ`). Multi-valued or alternative-branch
  evaluation is not supported.
* **Numerical tolerance.** The simplifier's atomic-equality check
  uses a `1e-12` tolerance to absorb round-off from complex
  `exp`/`log` chains in catalog constructions like
  `tree_i() = exp(log(-1)/2)`. User constants below that magnitude
  are preserved unless paired with a dominantly large component;
  see `?simplify_native` for the full rule.

## Citation

If you use emlR in published work, please cite both the paper and the
package:

```bibtex
@article{odrzywolek2026eml,
  title         = {All elementary functions from a single binary operator},
  author        = {Odrzywołek, Andrzej},
  year          = {2026},
  eprint        = {2603.21852},
  archivePrefix = {arXiv},
  primaryClass  = {cs.SC},
  url           = {https://arxiv.org/abs/2603.21852}
}

@software{emlR,
  author = {Thoss, Philipp},
  title  = {{emlR}: All elementary functions from a single binary
            operator, in {R}},
  year   = {2026},
  url    = {https://github.com/pjt222/emlR},
  note   = {Independent R implementation of arXiv:2603.21852}
}
```

## License

MIT (see [`LICENSE`](LICENSE)). The paper itself is CC BY 4.0; all
mathematical results are due to Odrzywołek (2026), and emlR is an
independent R implementation. Cite the paper for any reuse of the
results.
