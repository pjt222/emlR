# =============================================================================
#  Pattern matcher and simplifier (EML mode + native mode).
#
#  The simplifier is a tree rewriter. Two entry points:
#    simplify_eml()    — stays in the EML grammar (constant folding only).
#                        Preserves the master formula's completeness.
#    simplify_native() — collapses recognised EML patterns to base R.
#                        The headline correctness check: simplify_native
#                        of tree_log("x") returns quote(log(x)) literally.
#
#  Strategy: top-down rewrite to a fixed point. At each node, try every
#  rule in order; if one matches, substitute its right-hand side and
#  recursively simplify the result. Otherwise descend into children.
#  Top-down avoids the rewrite-blocking that bottom-up suffers when a
#  general rule (N1: eml(_x, 1) -> exp(_x)) fires on a subtree before a
#  more-specific rule (N3: eml(1, eml(eml(1, _x), 1)) -> log(_x)) gets
#  the chance to recognise the larger context.
# =============================================================================

# ---- Pattern matcher -------------------------------------------------------

# A meta-variable is a name whose printed form starts with an underscore.
.is_metavar <- function(x) {
  is.name(x) && startsWith(as.character(x), "_")
}

#' Pattern-match an EML expression against a meta-variable pattern
#'
#' Walks `expr` and `pattern` in parallel. A name in `pattern` whose
#' printed form starts with `_` is a meta-variable that binds to
#' whatever subexpression sits in the corresponding position of `expr`;
#' subsequent occurrences of the same meta-variable must bind to the
#' identical subexpression. Atoms and non-metavar names must match
#' exactly.
#'
#' @param expr the expression to match.
#' @param pattern the pattern.
#' @param bindings named list of meta-variable bindings to extend
#'   (used by the recursive walk; callers usually leave this at the
#'   default empty list).
#' @param tol numeric tolerance for atomic numeric/complex equality.
#'   Default `0` (exact match). Rule-controlled: only the Euler
#'   patterns set this above zero so they can absorb the round-off
#'   in `tree_i() = exp(log(-1)/2)` (`6.12e-17 + 1i`); other rules
#'   use exact equality so user-supplied small constants are not
#'   silently matched against rule literals.
#' @return Named list of bindings (possibly empty if the pattern has no
#'   meta-variables but matches), or `NULL` on no match.
#' @examples
#' match_eml(quote(eml(1, x)),       quote(eml(1, `_x`)))   # _x = x
#' match_eml(quote(eml(x, x)),       quote(eml(`_x`, `_x`))) # _x = x
#' match_eml(quote(eml(x, y)),       quote(eml(`_x`, `_x`))) # NULL
#' match_eml(quote(eml(log(a), 1)),  quote(eml(log(`_x`), 1))) # _x = a
#' @export
match_eml <- function(expr, pattern, bindings = list(), tol = 0) {
  if (.is_metavar(pattern)) {
    nm <- as.character(pattern)
    if (nm %in% names(bindings)) {
      if (identical(bindings[[nm]], expr)) return(bindings)
      return(NULL)
    }
    bindings[[nm]] <- expr
    return(bindings)
  }
  if (is.name(pattern)) {
    if (identical(pattern, expr)) return(bindings)
    return(NULL)
  }
  if (is.atomic(pattern) && length(pattern) == 1L) {
    if (is.atomic(expr) && length(expr) == 1L) {
      # Allow numeric==complex equivalence so literal `0` matches `0+0i`
      # produced by the constant-folder, and `1L` matches `1`. With
      # `tol > 0`, additionally absorb round-off (rule-controlled — the
      # default of 0 means exact equality, which prevents the tolerance
      # from silently eating user constants like `1e-13`; the Euler
      # rules opt in to `tol = 1e-12` because tree_i() = exp(log(-1)/2)
      # produces 6.12e-17 + 1i instead of an exact 0+1i).
      if ((is.numeric(pattern) || is.complex(pattern)) &&
          (is.numeric(expr)    || is.complex(expr))) {
        if (tol > 0) {
          if (isTRUE(abs(as.complex(expr) - as.complex(pattern)) < tol)) {
            return(bindings)
          }
          return(NULL)
        }
        if (isTRUE(as.complex(expr) == as.complex(pattern))) {
          return(bindings)
        }
        return(NULL)
      }
      if (identical(expr, pattern)) return(bindings)
    }
    return(NULL)
  }
  if (is.call(pattern)) {
    if (!is.call(expr)) return(NULL)
    if (length(pattern) != length(expr)) return(NULL)
    if (!identical(pattern[[1L]], expr[[1L]])) return(NULL)
    for (i in seq_len(length(pattern) - 1L) + 1L) {
      bindings <- match_eml(expr[[i]], pattern[[i]], bindings, tol = tol)
      if (is.null(bindings)) return(NULL)
    }
    return(bindings)
  }
  NULL
}

# Substitute meta-variable bindings into the right-hand side of a rule.
# Uses base::substitute via do.call so we can pass `bindings` programmatically.
.subst_bindings <- function(expr, bindings) {
  do.call(substitute, list(expr, bindings))
}

# ---- simplify_eml: stay-inside-EML (constant folding only) -----------------

#' Simplify an EML expression, keeping the EML grammar intact
#'
#' Constant-folds subtrees that contain no free variables; otherwise
#' recurses into the children. Preserves every `eml` call that has at
#' least one free variable in either subtree, so the simplified form is
#' still drawn from the EML grammar (literals, names, and `eml` nodes
#' only). Idempotent on every catalog entry.
#'
#' @param expr an EML expression.
#' @return An EML expression (literal or call).
#' @examples
#' simplify_eml(quote(eml(1, 1)))          # numeric e (folded)
#' simplify_eml(quote(eml(x, 1)))          # unchanged
#' simplify_eml(quote(eml(x, eml(1, 1))))  # eml(x, e)
#' @export
simplify_eml <- function(expr) {
  if (!.tree_uses_only_safe_heads(expr)) {
    stop("simplify_eml: `expr` contains a call to a function that ",
         "is not part of the EML or simplifier vocabulary. Allowed ",
         "heads: ",
         paste(.SAFE_SIMPLIFIER_HEADS, collapse = ", "), ".")
  }
  if (!is.call(expr)) return(expr)
  # Pass non-EML calls through unchanged. (After the safe-heads guard
  # above, these can only be exp/log/sqrt/arithmetic from re-applying
  # the function to simplifier output.)
  if (!identical(expr[[1L]], as.name("eml"))) return(expr)
  if (length(all.vars(expr)) == 0L) {
    return(eval(expr, list2env(list(eml = eml), parent = emptyenv())))
  }
  call("eml", simplify_eml(expr[[2L]]), simplify_eml(expr[[3L]]))
}

# ---- Rule guards used by simplify_native rules -----------------------------

# Fold a closed (no-free-variable) subtree to its numeric/complex
# value via the simplifier's complex-aware env. Returns NULL if the
# tree has free variables, fails to fold, or the value is not a
# finite scalar. R's parser turns the source literal `-4` into
# call("-", 4), so guards that need the actual base value must fold
# rather than just inspect the AST shape.
.fold_to_scalar <- function(x) {
  if (length(all.vars(x)) > 0L) return(NULL)
  v <- tryCatch(eval(x, .complex_fold_env()),
                error = function(e) NULL,
                warning = function(w) NULL)
  if (is.null(v) || length(v) != 1L) return(NULL)
  if (!(is.numeric(v) || is.complex(v))) return(NULL)
  if (!is.finite(v)) return(NULL)
  v
}

# `_x ^ _y` rewrites only when _x cannot drive R's `^` into the real
# branch on a negative base. Symbolic _x (free variables present) is
# allowed; the caller is responsible for domain at eval time. Atomic
# or closed _x must fold to a positive real, or to a complex with
# non-zero imaginary part (R's complex `^` matches the EML chain's
# principal-branch value there).
.pow_base_safe <- function(x) {
  if (length(all.vars(x)) > 0L) return(TRUE)
  v <- .fold_to_scalar(x)
  if (is.null(v)) return(FALSE)
  if (is.complex(v) && Im(v) != 0) return(TRUE)
  Re(v) > 0
}

# log(exp(_x)) -> _x is sound only when |Im(_x)| <= pi. Symbolic _x
# is allowed (catalog flows do not produce out-of-strip values);
# atomic / closed _x must fold to a value in the principal strip.
.log_exp_unwrap_safe <- function(x) {
  if (length(all.vars(x)) > 0L) return(TRUE)
  v <- .fold_to_scalar(x)
  if (is.null(v)) return(FALSE)
  abs(Im(as.complex(v))) <= base::pi
}

# ---- simplify_native: collapse to base-R primitives ------------------------

# The rule list. Order matters: at every node we try rules top-to-bottom and
# fire the first match. More specific rules come first.
.native_rules <- function() {
  list(
    # N3: log via paper Eq. 5. Most specific structure — must come before N1.
    list(name = "N3",
         lhs  = quote(eml(1, eml(eml(1, `_x`), 1))),
         rhs  = quote(log(`_x`))),

    # N4: subtraction directly from defn.
    list(name = "N4",
         lhs  = quote(eml(log(`_x`), exp(`_y`))),
         rhs  = quote(`_x` - `_y`)),

    # N5: eml(log(x), 1) = exp(log(x)) - log(1) = x.
    list(name = "N5",
         lhs  = quote(eml(log(`_x`), 1)),
         rhs  = quote(`_x`)),

    # N7: eml(_x, exp(_y)) = exp(_x) - _y.
    list(name = "N7",
         lhs  = quote(eml(`_x`, exp(`_y`))),
         rhs  = quote(exp(`_x`) - `_y`)),

    # N6: eml(0, _y) = 1 - log(_y).
    list(name = "N6",
         lhs  = quote(eml(0, `_y`)),
         rhs  = quote(1 - log(`_y`))),

    # N2: e literal (folded).
    list(name = "N2",
         lhs  = quote(eml(1, 1)),
         rhs  = quote(exp(1))),

    # N5b: general log-on-left.  exp(log(_x)) - log(_y) = _x - log(_y).
    # Subsumes N5 (taking _y = 1, log(1) = 0) but kept after N5 so the
    # cleaner form fires first when applicable.
    list(name = "N5b",
         lhs  = quote(eml(log(`_x`), `_y`)),
         rhs  = quote(`_x` - log(`_y`))),

    # N1: exp directly from paper. Most general — last among eml rules.
    list(name = "N1",
         lhs  = quote(eml(`_x`, 1)),
         rhs  = quote(exp(`_x`)))
  )
}

# Algebraic-cleanup rules. Applied after the EML rules so the expression
# has been mostly collapsed; these tidy up the residue. Required for
# reaching the SPEC §5.2 expected forms on tree_minus, tree_add,
# tree_mul, tree_div, tree_pow.
.native_cleanup_rules <- function() {
  list(
    # log/exp inverses on the principal branch. log(exp(z)) = z holds
    # only when |Im(z)| <= pi; outside the strip, R's principal-branch
    # log wraps and the rewrite would lose information. Refuse to fire
    # on atomic literals whose imaginary part exits the strip.
    # Symbolic _x is allowed (catalog flows that nest log(exp(.)) inside
    # the simplifier do not produce out-of-strip values in practice).
    list(name = "C-log-exp",
         lhs  = quote(log(exp(`_x`))),
         rhs  = quote(`_x`),
         guard = function(b) .log_exp_unwrap_safe(b[["_x"]])),
    list(name = "C-exp-log",
         lhs  = quote(exp(log(`_x`))),
         rhs  = quote(`_x`)),

    # Subtraction identities — let `0 - x` collapse to `-x` so subsequent
    # `_x - (-_y) -> _x + _y` rule can fire.
    list(name = "C-zero-minus",
         lhs  = quote(0 - `_x`),
         rhs  = quote(-`_x`)),
    list(name = "C-minus-zero",
         lhs  = quote(`_x` - 0),
         rhs  = quote(`_x`)),
    list(name = "C-double-neg",
         lhs  = quote(- -`_x`),
         rhs  = quote(`_x`)),
    list(name = "C-sub-neg",
         lhs  = quote(`_x` - -`_y`),
         rhs  = quote(`_x` + `_y`)),

    # eml(log(0), _y) — extended-real residue from tree_minus/add/mul.
    # Proof: exp(log(0)) - log(_y) = 0 - log(_y) = -log(_y).
    list(name = "C-eml-log0",
         lhs  = quote(eml(log(0), `_y`)),
         rhs  = quote(-log(`_y`))),

    # log(_x) + log(_y) = log(_x * _y) and log(_x) - log(_y) = log(_x / _y)
    list(name = "C-log-prod",
         lhs  = quote(log(`_x`) + log(`_y`)),
         rhs  = quote(log(`_x` * `_y`))),
    list(name = "C-log-quot",
         lhs  = quote(log(`_x`) - log(`_y`)),
         rhs  = quote(log(`_x` / `_y`))),

    # exp(_y * log(_x)) = _x ^ _y    — pow shortcut.
    # Sound on the principal branch when _x is symbolic (the user is
    # responsible for the domain at eval time) or atomic positive
    # real. For atomic negative real, R's `^` returns NaN
    # (real-domain semantics), breaking I3 — so refuse to fire.
    list(name = "C-exp-mul-log",
         lhs  = quote(exp(`_y` * log(`_x`))),
         rhs  = quote(`_x` ^ `_y`),
         guard = function(b) .pow_base_safe(b[["_x"]])),
    list(name = "C-exp-log-mul",
         lhs  = quote(exp(log(`_x`) * `_y`)),
         rhs  = quote(`_x` ^ `_y`),
         guard = function(b) .pow_base_safe(b[["_x"]])),

    # exp(_C + log(_x)) = exp(_C) * _x    — re-merge constants that
    # premature folding has lifted out of a log. Sound on the principal
    # branch via exp(a+b) = exp(a)*exp(b) and exp(log(z)) = z; no Im
    # constraint needed because the surrounding exp absorbs any 2πi
    # ambiguity. Two guards:
    # - _C must be a numeric/complex literal (so the rule does not
    #   reorder symbolic expressions).
    # - |Re(_C)| < 700 — beyond that, exp(_C) overflows to Inf or
    #   underflows to 0 even though the unsimplified form
    #   exp(_C + log(_x)) may evaluate finitely via cancellation.
    list(name = "C-exp-const-plus-log",
         lhs  = quote(exp(`_C` + log(`_x`))),
         rhs  = quote(exp(`_C`) * `_x`),
         guard = function(b) {
           v <- b[["_C"]]
           is.atomic(v) && length(v) == 1L &&
             (is.numeric(v) || is.complex(v)) &&
             abs(Re(as.complex(v))) < 700
         })
  )
}

# Constant-aware evaluation environment: log/exp/sqrt complex-coerce
# their arguments, so log(-1) and log(0) and similar resolve via the
# principal branch (matching the EML semantics) rather than producing
# real-domain NaN.
#
# parent = emptyenv() restricts the env to the explicit bindings only.
# This prevents resolution of any base-R function (system, source, ...)
# even if an adversarial call slips past the input-validation guard.
# All operators the simplifier may emit are injected explicitly.
.complex_fold_env <- function() {
  list2env(list(
    eml  = eml,
    log  = function(x) base::log(as.complex(x)),
    exp  = function(x) base::exp(as.complex(x)),
    sqrt = function(x) base::sqrt(as.complex(x)),
    `+`  = `+`,
    `-`  = `-`,
    `*`  = `*`,
    `/`  = `/`,
    `^`  = `^`,
    `(`  = `(`
  ), parent = emptyenv())
}

# Snap residual round-off in a folded complex constant. Only zeros a
# tiny component when the other component is dominantly large, so a
# genuinely small value (e.g. 1e-15+0i from a deliberate user constant)
# is preserved. Collapses purely-real complex back to real for cleaner
# downstream arithmetic.
.snap_zero <- function(z, tol = 1e-12) {
  if (!is.complex(z) || length(z) != 1L || !is.finite(z)) return(z)
  re <- Re(z); im <- Im(z)
  if (abs(im) < tol && abs(re) >= tol) {
    z <- complex(real = re, imaginary = 0)
  } else if (abs(re) < tol && abs(im) >= tol) {
    z <- complex(real = 0, imaginary = im)
  }
  if (Im(z) == 0) Re(z) else z
}

# Recursively fold sub-trees with no free variables to a literal value,
# using the complex-domain env. Only commits the fold if the resulting
# value is finite; otherwise leaves the structural form in place so the
# user (or downstream code) can choose how to handle the divergence.
.fold_constants <- function(expr) {
  if (!is.call(expr)) return(expr)
  if (length(all.vars(expr)) == 0L) {
    val <- tryCatch(
      eval(expr, .complex_fold_env()),
      error = function(e) NULL,
      warning = function(w) NULL
    )
    if (!is.null(val) && length(val) == 1L &&
        (is.numeric(val) || is.complex(val)) &&
        is.finite(Re(val)) && is.finite(Im(val))) {
      return(.snap_zero(val))
    }
  }
  new_args <- lapply(as.list(expr)[-1L], .fold_constants)
  as.call(c(list(expr[[1L]]), new_args))
}

# Try every rule at the root of `expr`; return the rewritten form on the
# first match, or NULL if no rule fires. Rules may carry an optional
# `guard` predicate evaluated against the bindings; the rule is skipped
# unless the guard returns TRUE.
.try_rules <- function(expr, rules) {
  for (rule in rules) {
    rule_tol <- if (is.null(rule$tol)) 0 else rule$tol
    bindings <- match_eml(expr, rule$lhs, tol = rule_tol)
    if (!is.null(bindings)) {
      if (!is.null(rule$guard) && !isTRUE(rule$guard(bindings))) next
      return(list(expr = .subst_bindings(rule$rhs, bindings),
                  rule = rule$name))
    }
  }
  NULL
}

# Top-down single-pass rewrite. Try rules at the root; if one fires,
# recursively simplify the result. Otherwise descend into children and
# retry rules at the root after children have been rewritten (this lets
# rules that need a particular shape match after simplification).
.rewrite_top_down <- function(expr, rules, trace_env = NULL) {
  hit <- .try_rules(expr, rules)
  if (!is.null(hit)) {
    if (!is.null(trace_env)) {
      trace_env$rules <- c(trace_env$rules, hit$rule)
      trace_env$intermediates <-
        c(trace_env$intermediates, list(hit$expr))
    }
    return(.rewrite_top_down(hit$expr, rules, trace_env))
  }
  if (is.call(expr)) {
    new_args <- lapply(as.list(expr)[-1L],
                       function(a) .rewrite_top_down(a, rules, trace_env))
    new_expr <- as.call(c(list(expr[[1L]]), new_args))
    # Fold sub-trees with no free variables before retrying parent rules,
    # so e.g. an emerging `log(1)` collapses to `0` and a parent rule
    # sees `eml(0, _y)` (which N6 catches) rather than
    # `eml(log(1), _y)` (which only the more general N5b catches and may
    # yield a less canonical form).
    new_expr <- .fold_constants(new_expr)
    hit <- .try_rules(new_expr, rules)
    if (!is.null(hit)) {
      if (!is.null(trace_env)) {
        trace_env$rules <- c(trace_env$rules, hit$rule)
        trace_env$intermediates <-
          c(trace_env$intermediates, list(hit$expr))
      }
      return(.rewrite_top_down(hit$expr, rules, trace_env))
    }
    return(new_expr)
  }
  expr
}

#' Simplify by collapsing recognised EML patterns to base-R primitives
#'
#' Applies a top-down rewrite system to fixed point. The output may
#' contain `exp`, `log`, `+`, `-`, `*`, `/`, `^`, and (with
#' `include_euler = TRUE`) `sin`, `cos` — anything `eval()` can handle.
#'
#' Rule list (SPEC §3.3, with order tuned to ensure N3 fires before N1
#' on the structured `log` pattern):
#' \describe{
#'   \item{N3}{`eml(1, eml(eml(1, _x), 1))` → `log(_x)`}
#'   \item{N4}{`eml(log(_x), exp(_y))` → `_x - _y`}
#'   \item{N5}{`eml(log(_x), 1)` → `_x`}
#'   \item{N7}{`eml(_x, exp(_y))` → `exp(_x) - _y`}
#'   \item{N6}{`eml(0, _y)` → `1 - log(_y)`}
#'   \item{N2}{`eml(1, 1)` → `exp(1)`}
#'   \item{N1}{`eml(_x, 1)` → `exp(_x)`}
#'   \item{C-log-exp}{`log(exp(_x))` → `_x`}
#'   \item{C-exp-log}{`exp(log(_x))` → `_x`}
#' }
#' Constant subtrees are folded as a final step.
#'
#' @param expr an EML expression (or any R `call` for re-application).
#' @param include_euler include the Euler rules E1 (`sin`) and E2
#'   (`cos`). Default `TRUE`.
#' @param trace if `TRUE`, return a list `(result, rules, intermediates)`
#'   capturing every rule firing in order. For debugging only.
#' @return The simplified expression, or — if `trace = TRUE` — a list
#'   containing the simplified expression plus the firing trace.
#' @examples
#' simplify_native(quote(eml(x, 1)))                            # exp(x)
#' simplify_native(quote(eml(1, eml(eml(1, x), 1))))             # log(x)
#' simplify_native(quote(eml(log(a), exp(b))))                   # a - b
#' @export
simplify_native <- function(expr, include_euler = TRUE, trace = FALSE) {
  if (!.tree_uses_only_safe_heads(expr)) {
    stop("simplify_native: `expr` contains a call to a function that ",
         "is not part of the EML or simplifier vocabulary. Allowed ",
         "heads: ",
         paste(.SAFE_SIMPLIFIER_HEADS, collapse = ", "), ".")
  }
  rules <- c(.native_rules(), .native_cleanup_rules())
  if (isTRUE(include_euler)) {
    rules <- c(rules, .euler_rules())
  }
  trace_env <- if (isTRUE(trace)) {
    new.env(parent = emptyenv())
  } else NULL
  if (!is.null(trace_env)) {
    trace_env$rules <- character(0)
    trace_env$intermediates <- list()
  }

  # Iterate to fixed point with rule application AND constant folding
  # interleaved. The fold uses a complex-aware env and only commits the
  # value when it is finite — so `log(0)` (which evaluates to -Inf) is
  # left as a structural call, preserving patterns like
  # `eml(log(0), _y)` for the C-eml-log0 rule. Other constants
  # (`log(1) -> 0`, `exp(1) -> e`) collapse, freeing cleanup rules like
  # `0 - _x -> -_x` to fire on the next pass.
  prev <- NULL
  curr <- expr
  iter <- 0L
  while (!identical(curr, prev) && iter < 200L) {
    prev <- curr
    curr <- .rewrite_top_down(curr, rules, trace_env)
    curr <- .fold_constants(curr)
    iter <- iter + 1L
  }

  if (isTRUE(trace)) {
    return(list(result = curr,
                rules = trace_env$rules,
                intermediates = trace_env$intermediates))
  }
  curr
}

# Euler rules — collapse the standard exponential forms back to sin/cos.
# Patterns are constructed via `call()` because R's parser folds
# `0+1i * _x` to `+(0, *(0+1i, _x))`, not the desired `*(0+1i, _x)`.
# Tolerance-aware atomic equality in match_eml() absorbs the residual
# round-off in tree_i() = exp(log(-1)/2), which yields 6.12e-17 + 1i
# rather than an exact 0+1i.
.euler_rules <- function() {
  ix     <- call("*", 0+1i, as.name("_x"))
  neg_ix <- call("-", ix)
  # Tolerance ONLY on Euler patterns. The Euler RHSs need to match
  # `0+1i` and `0+2i` against the residue of tree_i() = exp(log(-1)/2),
  # which floats noise around 6.12e-17. Other rules use exact equality
  # (the default tol = 0) so user-supplied literals like `1e-13` do
  # not get matched against `0`.
  list(
    list(name = "E1",
         lhs  = call("/",
                     call("-", call("exp", ix), call("exp", neg_ix)),
                     0+2i),
         rhs  = quote(sin(`_x`)),
         tol  = 1e-12),
    list(name = "E2",
         lhs  = call("/",
                     call("+", call("exp", ix), call("exp", neg_ix)),
                     2),
         rhs  = quote(cos(`_x`)),
         tol  = 1e-12)
  )
}
