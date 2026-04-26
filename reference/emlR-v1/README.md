# emlR — All elementary functions from a single binary operator

R implementation of **arXiv:2603.21852** (Andrzej Odrzywołek, *All elementary
functions from a single binary operator*, Jagiellonian University, March 2026).

## What this is

The paper shows that a single binary operator,

    eml(x, y) = exp(x) − ln(y)

together with the constant `1`, generates the entire repertoire of a
scientific calculator — all four arithmetic operations, exponentiation,
trig and hyperbolic functions, the constants e, π, i, and so on. It's the
continuous analogue of the NAND gate's role in Boolean logic.

Every elementary function expression becomes a binary tree under the grammar

    S → 1 | x | eml(S, S)

This package gives you:

1. The operator `eml(x, y)`, evaluated over ℂ on the principal branch
   (required because trig and π need `ln(−1) = iπ`).
2. An expression-tree representation with constructors, evaluation,
   pretty-printing, RPN serialization, and a `K` (leaf-count) function
   matching Mathematica's `LeafCount`.
3. A library of canonical identities in `eml_catalog()`: exp, ln, sin, cos,
   sqrt, +, −, ×, /, ^, plus the constants 0, 1, 2, e, π, i, −1.
4. The "master formula" architecture from Section 4.3 — a parameterized
   depth-n EML tree where each input slot is `α·1 + β·x + γ·f` with weights
   that snap to one-hot to recover discrete grammar productions.
5. A symbolic-regression demo that fits `ln(x)` from data and snaps to the
   exact closed form, mirroring the paper's `Log_fit.nb` notebook.

## Files

```
emlR/
├── R/
│   ├── 01_core.R           eml() operator, tree constructors
│   ├── 02_tree_ops.R       eval, RPN, K, depth, pretty-print
│   ├── 03_identities.R     canonical trees for elementary fns/constants
│   └── 04_master.R         master formula + SR fitting
├── tests/
│   └── test_eml.R          identity verification + SR demo
├── emlR.R                  single-file loader
└── README.md
```

## Usage

```r
# Load
for (f in list.files("R", full.names = TRUE)) source(f)

# The operator (returns complex)
eml(1, 1)          # = e
eml(0, 1)          # = 1 - 0 = 1
eml_real(1, 1)     # real part with imag-residue check

# Build trees
ln_tree <- tree_ln("x")
ln_tree
#> eml(1, eml(eml(1, x), 1))

eml_K(ln_tree)              # 7  (matches paper Table 4)
eml_rpn(ln_tree)            # "1 1 x E 1 E E"
eml_eval(ln_tree, list(x = 5))   # log(5)

# Catalog of identities
cat <- eml_catalog()
eml_eval(cat$pi, list())    # ≈ pi
eml_eval(cat$sin, list(x = pi/4))   # ≈ sqrt(2)/2

# Master formula at depth 1 -- selects exp(x)
eml_master_eval(1, c(0, 1, 2), theta_for_exp())

# Symbolic regression: fit ln(x) at depth 3
xs <- seq(0.5, 5, length.out = 30)
ys <- log(xs)
fit <- eml_fit(xs, ys, depth = 3, maxit = 8000)
fit$snap_mse   # should be near 0 if it found the symbolic answer
```

## Notes on the implementation

**Complex arithmetic is mandatory.** The paper notes that EML internally
operates over ℂ on the principal branch — even purely real elementary
functions need this because `i = exp(ln(-1)/2)` and `π = ln(-1) / i`. R's
built-in complex support handles this once you coerce inputs with
`as.complex()`, which `eml()` does automatically.

**Extended reals are required.** Several constructions go through `ln(0) = -∞`
and `exp(-∞) = 0`, e.g. `−1 = exp(ln(0)) − ln(exp(1)) = 0 − 1`. R handles
this correctly: `log(as.complex(0))` returns `-Inf+0i`, and `exp(-Inf+0i)`
returns `0+0i`. The paper notes (Sect. 4.1) that "out of the box" Python and
Julia trap these as errors; R agrees with the NumPy/PyTorch behavior.

**Tree forms are not K-optimal.** The identities in `R/03_identities.R` are
correct constructively but are NOT the leaf-count-minimal trees from the
paper's Table 4 (which came from exhaustive search up to K=9 and aren't all
explicitly printed in the article). The three identities given verbatim by
Odrzywołek — `exp(x) = eml(x,1)`, `e = eml(1,1)`, and the K=7 logarithm in
Eq. (5) — are reproduced exactly. Everything else is built by bootstrapping
from those three plus the standard exp/log identities for arithmetic.

**SR demo uses simulated annealing**, not Adam. The paper uses PyTorch with
clamping, hardening, and a logits-via-softmax simplex parametrization. R has
the same softmax trick in `eml_fit()`, but without autograd we use base R
`optim(method = "SANN")`. This is enough for depth-3 ln(x) recovery in most
seeds; for deeper trees you'd want to port the PyTorch training loop or use
`torch` for R.

## Citation

Odrzywołek, A. (2026). *All elementary functions from a single binary
operator*. arXiv:2603.21852. https://arxiv.org/abs/2603.21852

## License

This implementation is offered for educational and research use, mirroring
the paper's CC BY 4.0 license. All mathematical results are due to Odrzywołek.
