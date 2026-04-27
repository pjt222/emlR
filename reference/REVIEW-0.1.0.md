# emlR 0.1.0 — pre-CRAN review

**Status**: NO-GO for CRAN submission until 4 blockers resolved.

| Field | Value |
|---|---|
| Review commit | `4e37c46883a373d248b4e037c7a861b027000278` |
| Review date | 2026-04-27 |
| Target version | 0.1.0 (currently `0.1.0.9000`) |
| Toolchain | R 4.6.0, Ubuntu 24.04, base R + Deriv |
| Test count at baseline | 191 passing |

## Phase 0 — Mechanical baseline

`R CMD check --as-cran` on commit `4e37c46`:

| Check | Result |
|---|---|
| `R CMD build` | OK (renv lib path required) |
| `--as-cran` overall | 1 ERROR, 1 WARNING, 3 NOTES |
| URLs (12) | ✓ all resolve |
| `roxygen2::roxygenize()` | clean diff (NAMESPACE + man/ in sync) |
| `spelling` package | not installed locally; not in `Suggests` |

**Environment-only failures** (will pass on CRAN servers, not flagged):
- ERROR + WARNING: `pdflatex is not available`
- NOTE: HTML `tidy` not found
- NOTE: `emlR-manual.tex` detritus (caused by failed pdflatex)

**Real findings from `--as-cran` log** (all forwarded as findings below):
1. Title case violation (S-DESC-Title)
2. Version `.9000` suffix (S-DESC-Version)
3. arXiv reference format (S-DESC-Arxiv)

## Reviewer roster

| Phase | Reviewer | Mode |
|---|---|---|
| 1 | r-developer | individual agent (wave 1) |
| 1 | senior-software-developer | individual agent (wave 1) |
| 1 | security-analyst | individual agent (wave 1) |
| 1 | senior-researcher | individual agent (wave 1) |
| 1 | advocatus-diaboli | individual agent (wave 1) |
| 1 | theoretical-researcher | individual agent (wave 1) |
| 2 | r-dev-lead (r-developer) | TeamCreate `emlR-package-review` lead |
| 2 | code-reviewer | team member |
| 2 | sr-sw-dev (senior-software-developer) | team member |
| 2 | security-validator (security-analyst) | team member |
| 3 | — | SKIPPED (rationale below) |

## Executive summary

| Severity | Count | What it means |
|---|---|---|
| Blocker | 4 | Must fix before CRAN submission |
| High | 11 | Should fix before CRAN; reviewer NOTEs likely |
| Medium | 7 | Post-0.1.0 acceptable, but trivial enough to fold in |
| Low | 2 | Nice-to-have |
| Won't-fix | 4 | Documented out-of-scope |

**Note (post-Phase-2 addendum)**: B-EXEC scope expanded — the same eval-sandbox fix must cover `eml_eval` (`R/05_eval.R:38`) in addition to `.fold_constants`. Live re-verification confirmed `eml_eval(quote(system("…")), list())` also executes the shell command. The blocker count remains 4; the fix surface is wider.

**Go/no-go**: NO-GO until the 4 blockers are resolved. Estimated effort: ~1 day of focused work, mostly mechanical edits and one rule guard.

---

## Blockers (must fix before CRAN)

### B-EXEC — Arbitrary code execution across all eval paths

**Files**:
- `R/07_simplify.R:248-254, 277-293` (`.complex_fold_env`, `.fold_constants`)
- `R/05_eval.R:38` (`eml_eval`)

**Source**: security-analyst (wave 1) confirmed live for `simplify_native`; r-dev-lead (Phase 2 addendum) extended scope; live re-verified for `eml_eval`.
**Severity**: blocker

Both eval paths use `parent = baseenv()`, so any name not in the explicit override list (`eml`, `log`, `exp`, `sqrt`) resolves through base R — including `system()`, `file()`, `unlink()`. Empirical reproduction (both paths):

```r
simplify_native(quote(eml(system("echo X 1>&2", intern=FALSE), 1)))
# stderr: X
# returned AST: 1   (call removed)

eml_eval(quote(system("echo X 1>&2", intern=FALSE)), list())
# stderr: X
# returns: 0+0i
```

Additionally, `eml_eval` lacks the `is_eml_expr()` guard that `compile_eml` has at `R/06_compile.R:40-43`, so it silently accepts non-EML calls (e.g. `eml_eval(quote(x+y), list(x=1,y=2))` returns `3+0i` rather than rejecting the input). This is the input-contract asymmetry the code-reviewer flagged.

**Fix** (cover all three locations):
1. `simplify_eml` and `simplify_native`: add `if (!is_eml_expr(expr)) stop("…: not an EML expression")` at function top.
2. `eml_eval`: same guard.
3. `.fold_constants` defence in depth: restrict the eval env to a whitelist (`eml`, `exp`, `log`, `sqrt`, arithmetic), or use `parent = emptyenv()` and inject the operators explicitly.

The first two are one-liners; the third is the deeper mitigation. Bundle into one commit.

### B-LICENSE — `License: CC BY 4.0` not acceptable for software

**File**: `DESCRIPTION:15`
**Source**: advocatus-diaboli (wave 1); r-dev-lead (Phase 2 lead).
**Severity**: blocker

Creative Commons explicitly recommends against CC licenses for software. CRAN incoming will reject. Adopt MIT (`License: MIT + file LICENSE` plus `LICENSE` file with copyright line) or GPL-3.

### B-RNG — `eml_fit` mutates global RNG state

**File**: `R/09_master.R:361`
**Source**: senior-researcher (wave 1); empirically verified live.
**Severity**: blocker

`set.seed(seed + k - 1L)` inside the restart loop permanently mutates `.Random.seed`. Confirmed:

```r
set.seed(42); a <- runif(1); set.seed(42)
fit <- eml_fit(xs, log(xs), depth=3, n_restarts=3, seed=100)
b <- runif(1); identical(a, b)  # FALSE; a=0.9148 b=0.8847
```

CRAN "Writing R Extensions" §1.6: packages must not modify global state. This is a hard reject on CRAN incoming.

**Fix**: save/restore around the loop:

```r
old_seed <- if (exists(".Random.seed", envir = .GlobalEnv))
              get(".Random.seed", envir = .GlobalEnv) else NULL
on.exit({
  if (is.null(old_seed)) {
    if (exists(".Random.seed", envir = .GlobalEnv))
      rm(".Random.seed", envir = .GlobalEnv)
  } else {
    assign(".Random.seed", old_seed, envir = .GlobalEnv)
  }
}, add = TRUE)
```

### B-VIGNETTE — SR vignette runs `eml_fit` chunk that may exceed CRAN time limit

**File**: `vignettes/symbolic-regression.Rmd:101-113`
**Source**: r-developer (wave 1); r-dev-lead (Phase 2).
**Severity**: blocker

The chunk runs `eml_fit(depth=3, n_restarts=10, maxit=1000)` with no `eval=FALSE` or `cache=TRUE`. Depth-3 with 10 restarts at 1000 iterations easily exceeds CRAN's per-vignette soft limit (~5 min) and risks the 10-min hard kill on slower check machines.

**Fix**: reduce to `n_restarts=1, maxit=200` for the live build (still illustrative), or set `eval=FALSE` and embed pre-computed output, or guard with `if (Sys.getenv("NOT_CRAN", "false") == "true")`.

---

## High (should fix before CRAN)

### B-SIMPLIFY-EML — `simplify_eml` corrupts or errors on non-EML calls

**File**: `R/07_simplify.R:118-124`
**Severity**: high

Verified live. `simplify_eml(quote(x+y))` returns `eml(x, y)` (silent corruption). `simplify_eml(quote(exp(x)))` errors with "subscript out of bounds". The function unconditionally rebuilds non-EML calls as 2-arg `eml(...)` constructions.

**Fix**: gate at top of function — `if (!is.call(expr) || !identical(expr[[1L]], as.name("eml"))) return(expr)`.

### B-NEG-POW — `C-exp-mul-log` rewrites `exp(0.5*log(-4))` to `(-4)^0.5` returning `NaN`

**File**: `R/07_simplify.R:220-225`
**Severity**: high

Verified live. The rule is sound under the principal-branch complex `^` operator, but R's `^` on a negative real base with non-integer exponent returns `NaN` (real-domain semantics). The simplified expression evaluates to `NaN`; the unsimplified expression (via `.complex_fold_env`'s complex-coerced `log`) evaluates to `2i`. This violates invariant **I3** (principal-branch complex semantics).

**Fix**: gate the rule on `_x > 0` for atomic numeric `_x`, OR replace RHS with `as.complex(_x) ^ _y`, OR rely on the simplifier never being on the eval path (re-document `simplify_native` as inspection-only; users go through `eml_eval`/`run_bytecode`).

### B-LOG-EXP-WRAP — `C-log-exp` misses principal-branch wrap

**File**: `R/07_simplify.R:183-185`
**Severity**: high

Verified live. `simplify_native(quote(log(exp(0+4i))))` returns `0+4i` instead of `0-2.283i`. Identity `log(exp(z)) = z` only holds for `|Im(z)| ≤ π`.

**Fix**: gate the rule on numeric `_x` with `|Im(_x)| ≤ π`. Symbolic `_x` cannot be checked at compile time; either drop the rule (it fires on already-collapsed shapes that are uncommon in catalog flows) or add a runtime branch-check guard.

### B-TOL-USER — Tolerance matcher eats user constants near `0`

**File**: `R/07_simplify.R:67-78`
**Severity**: high

Verified live. `simplify_native(quote(eml(1e-13, x)))` rewrites to `1 - log(x)`, dropping the user's `1e-13` because it matches literal `0` within the `1e-12` matcher tolerance. Same effect for `1 + 5e-13` → `1`.

**Fix**: apply tolerance matching only when the *pattern-side* constant matches a folded-residue family (e.g. only for `0+1i`, `0+2i` patterns where round-off is expected). For simple integer patterns like `0`, `1`, `2`, require exact equality. Implementation: pass a `tol = 0` flag on most rules and `tol = 1e-12` only on Euler patterns E1/E2 and adjacent.

### B-CONSTPLUS-OF — `C-exp-const-plus-log` overflow at extreme `x`

**File**: `R/07_simplify.R:233-240`
**Severity**: high

Verified live. `exp(710 + log(1e-310))` raw evaluates to `0.0223`; simplified to `exp(710) * x` which gives `Inf` (since `exp(710) > .Machine$double.xmax`). The new rule destroys numerical conditioning when the raw form has cancelling additions.

**Fix**: gate on `|Re(_C)| < 700` (R's overflow margin). Above that, leave the structural form. Alternative: drop the rule and let sqrt/sin/cos remain at their previous structural form (revert to "almost canonical").

### S1 — `R/99_compat_v1.R` ships in a first release

**File**: `R/99_compat_v1.R`, `tests/testthat/test-compat-v1.R`, 8 `man/*.Rd` pages, 8 NAMESPACE exports
**Severity**: high

Backward-compat shim for an unreleased v1 prototype. The project's own `.claude/CLAUDE.md` states: "the prototype is preserved as a design reference and should not be promoted to a public predecessor — it has never been released." Shipping deprecated exports in a first release confuses CRAN reviewers and locks in 8 unnecessary forward-compat promises.

**Fix**: delete the file, the test file, and the 8 corresponding `man/*.Rd` pages (`as_eml_tree.Rd`, `eml_eval_real.Rd`, `ONE.Rd`, `eml_master_n_params.Rd`, `theta_for_ln.Rd`, `eml_master_eval.Rd`, `eml_tree.Rd`, `unpack_theta.Rd`). Re-run `roxygen2::roxygenize()`.

### S2 — 17 exported functions lack `\examples{}`

**Files**: `man/eml_fit.Rd`, `man/eml_master_eval.Rd`, `man/eml_master_n_params.Rd`, `man/eml_eval_real.Rd`, `man/is_eml_const.Rd`, `man/is_eml_var.Rd`, `man/snap_master_params.Rd`, `man/theta_for_exp.Rd`, `man/theta_for_log.Rd`, `man/theta_for_ln.Rd`, `man/tree_identities.Rd`, `man/unpack_theta.Rd`, plus the 8 deprecated entries from S1.
**Severity**: high

Each missing-example page generates an `--as-cran` NOTE. Deleting S1's 8 pages reduces this to ~9. For slow functions like `eml_fit`, use `\donttest{}` (skipped on CRAN, runs for users) — *not* `\dontrun{}` (skipped everywhere).

### S7 — `eml_fit` `@return` documents non-existent field

**File**: `R/09_master.R:301`; `man/eml_fit.Rd:39`
**Severity**: high

`@return` lists `n_restarts_run` but the return list (`R/09_master.R:404-413`) does not include it. Either add `n_restarts_run = k` to the return, or correct the docstring.

### S4 — `inst/CITATION` missing

**Severity**: high

Package implements a specific arXiv paper. CRAN convention: ship `inst/CITATION` so `citation("emlR")` returns a structured reference. Note: existing `reference/REFERENCES.md:163-184` has a draft BibTeX block, but with the wrong author surname ("Thielen" instead of "Thoss"); fix that while creating CITATION.

### S5 — NEWS.md heading marker

**File**: `NEWS.md:1`
**Severity**: high

`# emlR 0.1.0 (in development)` must read `# emlR 0.1.0` for release. CRAN incoming checks this.

### S-CRAN-COMMENTS — `cran-comments.md` missing

**Severity**: high

Not enforced by `--as-cran` but expected by CRAN reviewers. Should document the test environments, known NOTEs (new submission, version 9000 transition, arXiv→DOI), and submission context.

---

## Medium (post-0.1.0 acceptable)

### S-DESC-Title — Title case violation

**File**: `DESCRIPTION:2`
**Severity**: medium

"All Elementary Functions From a Single Binary Operator" → "from" lowercase (preposition rule). Flagged by `--as-cran`.

### S-DESC-Version — Version `.9000` suffix

**File**: `DESCRIPTION:3`
**Severity**: medium

`Version: 0.1.0.9000` → `0.1.0`. Flagged by `--as-cran`.

### S-DESC-Arxiv — arXiv reference format

**File**: `DESCRIPTION:8`
**Severity**: medium

`arXiv:2603.21852` → `<doi:10.48550/arXiv.2603.21852>` (CRAN preferred form for arXiv preprints). Flagged by `--as-cran`.

### S6 — `eml_catalog()` docstring overclaims

**File**: `R/08_identities.R:139`
**Severity**: medium

"all standard elementary functions" — but `tan`, `sinh`, `cosh`, `tanh`, `asin`, `acos`, `atan` are absent. NEWS.md "Scope" section already correctly limits coverage. Fix docstring to match: "EML expressions for the 18 standard elementary functions and constants implemented in this release."

### F4 — Identity tests are structural-only, not semantic

**File**: `tests/testthat/test-identities.R:47-68`
**Source**: code-reviewer (Phase 2 addendum); advocatus-diaboli (wave 1 finding 3, originally deferred but promoted).
**Severity**: medium

The test compares `deparse(simplify_native(catalog[[nm]]))` against an expected string. A wrong constant (e.g. `exp(2)` where `exp(1)` is expected) is only caught if it differs in string form. After the structural check, evaluate both the simplified form and `eml_eval` output at one or more numeric points and compare with tolerance. This catches semantic regressions that pass the deparse test.

### S9 — ORCID URL form

**File**: `DESCRIPTION:6`
**Severity**: medium

`comment = c(ORCID = "0000-0002-4672-2792")` → `comment = c(ORCID = "https://orcid.org/0000-0002-4672-2792")` per current CRAN guidance.

### S10 — `Depends: R (>= 3.6)` not credibly tested

**File**: `DESCRIPTION:20`
**Severity**: medium

Never tested below R 4.x. No native pipe `|>` found in `R/*.R`, so R 4.0 is defensible. Setting R 3.6 risks failure on actual 3.6 if/when CRAN adds it to the matrix. Recommend `R (>= 4.0.0)` or `R (>= 4.1.0)`.

### S-MISSING-SPELLING — `spelling` not in Suggests

**Severity**: medium

`devtools::spell_check()` requires it; ASCII-only NEWS rule is easier with automated spell checking. Add `spelling` to `Suggests`.

---

## Low / nice-to-have

### S11 — API surface trim

After S1's 8 deletions, 50 exports remain. Further candidates: `match_eml` (DSL-internal), `eml_nodecount` (duplicates `eml_K` for a non-paper metric). Not blocking. Per `sr-sw-dev`'s recommendation, defer to 0.1.1.

### F6 — No sub-second `eml_fit` smoke test

**File**: `tests/testthat/test-master.R`
**Source**: code-reviewer (Phase 2 addendum).
**Severity**: low

The Phase-5 convergence gate is gated behind `EMLR_RUN_SLOW=true`. Without it, no test exercises the `eml_fit` machinery end-to-end. A depth-1, n_restarts=1, maxit=10 smoke test runs in milliseconds and proves the fitter is operational — including verifying the S7 fix (presence of `n_restarts_run` in the return list) without needing the slow gate. Add as `test_that("eml_fit returns a structurally complete result on a tiny input", ...)`.

---

## Won't-fix / out-of-scope

| Item | Rationale |
|---|---|
| `tan`, `sinh`, `cosh`, `tanh` in catalog | Explicitly out-of-scope per SPEC §10 and NEWS scope section |
| EDL variant `exp(x)/log(y)` and `−eml(y, x)` | Explicitly deferred per SPEC §10 |
| Rcpp / `torch` acceleration | Explicitly deferred per SPEC §10 |
| Multivariate (>2 var) coverage | Infrastructure non-precluding; tested surface is uni/bivariate |
| `reference/emlR-v1/` prototype | Excluded from build; design reference only |

---

## Phase 1 disposition table

Every wave-1 hypothesis with its resolution. R = refuted, V = verified live, F = forwarded as finding, D = deferred/out-of-scope, A = absorbed into another finding.

| Hypothesis (originating agent) | Status | Resolution |
|---|---|---|
| Title case "From" → "from" (Phase 0) | F | S-DESC-Title medium |
| Version `.9000` → `0.1.0` (Phase 0) | F | S-DESC-Version medium |
| arXiv → DOI form (Phase 0) | F | S-DESC-Arxiv medium |
| `spelling` Suggests missing (Phase 0) | F | S-MISSING-SPELLING medium |
| `eml_fit` @return non-existent field (r-developer) | F | S7 high |
| 12+ `\examples{}` missing (r-developer) | F | S2 high |
| Vignette SR chunk timeout risk (r-developer) | F | B-VIGNETTE blocker |
| Compat shim should not ship (r-developer) | F | S1 high |
| `inst/CITATION` missing (r-developer) | F | S4 high |
| NEWS.md "(in development)" (r-developer) | F | S5 high |
| `99_compat_v1.R` should not ship (sr-sw-dev) | F | S1 high (same as above) |
| `simplify_eml` corrupts non-EML (sr-sw-dev) | V→F | B-SIMPLIFY-EML high; live verified |
| `eml_eval`/`run_bytecode` input parity (sr-sw-dev) | V→F | Partial: bytecode handles complex correctly. Wider input-validation gap remains; rolled into S2/S11 trim |
| API surface 58 exports (sr-sw-dev) | F | S11 low + S1 high |
| `add_const` redundant comparisons (sr-sw-dev) | D | Cosmetic; defer to 0.1.1 |
| Numeric file-prefix convention (sr-sw-dev) | D | Internal convention; not user-facing |
| `.fold_constants` executes `system()` (security-analyst) | V→F | B-EXEC blocker; live verified |
| `eml_eval` evaluates in `baseenv()` (security-analyst) | A | Subsumed by B-EXEC mitigation (input-validation guard) |
| `run_bytecode` no bounds checking (security-analyst) | D | Robustness, not security; defer |
| CI workflows clean (security-analyst) | R | Confirmed clean |
| Phase-5 8/10 gate hidden behind `EMLR_RUN_SLOW` (senior-researcher) | A | Documented limitation; not a CRAN issue |
| `inst/CITATION` missing (senior-researcher) | F | S4 high (same as r-developer) |
| Vignette 90%+ recovery unverified (senior-researcher) | D | Filed as future task: empirical 30-trial validation |
| Catalog incompleteness vs Table 4 (senior-researcher) | F | S6 medium |
| Catalog single-point verification (senior-researcher) | D | Filed as future task: principal-branch sweep |
| `eml_fit` mutates global RNG (senior-researcher) | V→F | B-RNG blocker; live verified |
| `C-exp-const-plus-log` numerical regression (advocatus-diaboli) | V→F | B-CONSTPLUS-OF high; live verified at extreme inputs |
| 1e-12 tolerance corrupts user constants (advocatus-diaboli) | V→F | B-TOL-USER high; live verified |
| Catalog test is structural-only (advocatus-diaboli) | D | Filed as future task: eval-equivalence sweep |
| `99_compat_v1.R` should not ship (advocatus-diaboli) | F | S1 high (3rd convergence) |
| CC BY 4.0 license (advocatus-diaboli) | F | B-LICENSE blocker |
| ORCID URL form (advocatus-diaboli) | F | S9 medium |
| `log(-1)` first-issue prediction (advocatus-diaboli) | D | Documentation hardening; defer to 0.1.0 README polish |
| `Depends: R (>= 3.6)` unrealistic (advocatus-diaboli) | F | S10 medium |
| Snap discontinuity at `1e-12` (advocatus-diaboli) | D | Theoretical; no practical input demonstrates harm |
| SR positioning in DESCRIPTION (advocatus-diaboli) | D | Cosmetic positioning; defer |
| `C-log-exp` unsound for `Im > π` (theoretical-researcher) | V→F | B-LOG-EXP-WRAP high; live verified |
| `simplify_eml` corrupts non-EML (theoretical-researcher) | V→F | B-SIMPLIFY-EML high (2nd convergence) |
| `eml_catalog` overclaims (theoretical-researcher) | F | S6 medium (2nd convergence) |
| `(-4)^0.5` regression (theoretical-researcher) | V→F | B-NEG-POW high; live verified |
| Bytecode missing complex coercion (theoretical-researcher) | R | Live test: `run_bytecode(eml(1, x), x=-1)` returns correct `e − iπ` |
| Tolerance noLD platform sensitivity (theoretical-researcher) | D | Theoretical; no observed failure |
| Phase 2 lead — code-reviewer error message hygiene | A | Rolled into Phase 2 lead synthesis (B-EXEC mitigation depth) |
| Phase 2 lead — `cran-comments.md` missing | F | S-CRAN-COMMENTS high |

**Convergence signals** (≥2 independent agents reaching same finding):
- `99_compat_v1.R` should not ship: r-developer + sr-sw-dev + advocatus-diaboli (3 agents)
- `simplify_eml` non-EML corruption: sr-sw-dev + theoretical-researcher (2 agents) + live verification
- `inst/CITATION` missing: r-developer + senior-researcher (2 agents)
- `eml_catalog()` overclaims: senior-researcher + theoretical-researcher (2 agents)
- 1e-12 tolerance issue: advocatus-diaboli + r-dev-lead (2 agents) + live verification

## Phase 3 — methodology team

**Status**: SKIPPED.

**Rationale**: every methodology hypothesis from wave 1 was either (a) verified empirically by live R execution and forwarded as a blocker/high finding (B-RNG, B-TOL-USER, B-CONSTPLUS-OF), (b) covered as a high-severity finding by Phase 2 (S6 catalog overclaim, S4 missing CITATION), or (c) filed as a future empirical-validation task that does not benefit from another team round (90%+ recovery rate, principal-branch sweep). No remaining methodology question warrants a fresh `ml-data-science-review` team. Documenting here so the audit trail is complete.

**Future tasks deferred** (not pre-CRAN blockers, but worth filing as 0.1.1 issues):
- Empirical estimation of `eml_fit` 90%+ recovery rate over ≥30 outer seeds
- Principal-branch sweep test: each catalog entry evaluated at ≥5 boundary points
- Eval-equivalence sweep: `eml_eval(raw)` vs `eval(simplify_native(raw))` over randomised inputs

---

## Phase 5 — pre-CRAN gate

To be appended after blockers are resolved. Procedure:

1. Re-run `R CMD check --as-cran` on the post-fix commit.
2. Compare against this baseline (commit `4e37c46`): assert no new NOTEs introduced; expect the 4 noted "real" sub-findings (title case, version, arXiv, new submission) to disappear.
3. Generate `cran-comments.md` draft listing test environments and remaining acceptable NOTEs.
4. Confirm `roxygen2::roxygenize()` produces clean diff.
5. Confirm vignettes rebuild cleanly under `R CMD check --as-cran` time budget.

Remote checks (win-builder, R-hub) are deferred to the user's own schedule per their explicit choice during plan approval.

---

## Recommended fix order

To minimise rework cycles:

1. Delete `R/99_compat_v1.R` + test + 8 man pages (closes S1, reduces S2 by 8). One commit, mechanical.
2. Fix B-LICENSE (DESCRIPTION + LICENSE file). One commit, mechanical.
3. Fix B-RNG (save/restore `.Random.seed` in `eml_fit`). One commit + new test.
4. Fix B-VIGNETTE (reduce `n_restarts` or add `eval=FALSE`). One commit.
5. Fix B-EXEC (input-validation guard at top of `simplify_eml`/`simplify_native`). One commit + new test.
6. Address remaining High items: B-SIMPLIFY-EML (subset of B-EXEC fix), B-NEG-POW, B-LOG-EXP-WRAP, B-TOL-USER, B-CONSTPLUS-OF — each is a rule guard or rule revert. Group into one commit per rule.
7. Mechanical edits: title case, version, arXiv→DOI, NEWS heading, ORCID URL form, R version floor, `eml_catalog()` docstring, S7 @return mismatch, `inst/CITATION`, `cran-comments.md`, `spelling` Suggests. One bundling commit.
8. Re-run `R CMD check --as-cran`. Fold any residual notes into `cran-comments.md`.

Estimated total effort: ~1 day focused. Most items are rote.
