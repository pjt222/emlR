# =============================================================================
#  v1 -> v2 compatibility shim. Lets the unmodified v1 test script run on v2,
#  modulo the K-counting correction documented in NEWS.md.
#
#  Most of v1's API survives unchanged because v2 already provides the same
#  function names (eml, eml_real, eml_const, eml_var, eml_node, E,
#  eml_eval, eml_K, eml_rpn, eml_depth, tree_*, eml_catalog, eml_fit).
#  The shim adds the few v1-only names that have no direct v2 equivalent.
# =============================================================================

#' Deprecated: legacy name for [as_eml_expr()]
#' @param x input.
#' @keywords internal
#' @export
as_eml_tree <- function(x) {
  warning("`as_eml_tree()` is deprecated; use `as_eml_expr()` instead.",
          call. = FALSE)
  as_eml_expr(x)
}

#' Deprecated: legacy form of evaluating with `real = TRUE`
#' @inheritParams eml_eval
#' @export
eml_eval_real <- function(expr, vars = list(), tol = 1e-8) {
  warning("`eml_eval_real()` is deprecated; use `eml_eval(expr, vars, real = TRUE)`.",
          call. = FALSE)
  eml_eval(expr, vars = vars, real = TRUE, tol = tol)
}

#' Deprecated: v1 ONE constant
#'
#' v1 exposed `ONE` as the literal-1 leaf constant. v2 uses the bare
#' literal `1` — there is no special constant required.
#' @export
ONE <- 1

#' Deprecated: legacy alias for [master_n_params()]
#' @inheritParams master_n_params
#' @export
eml_master_n_params <- function(depth) {
  warning("`eml_master_n_params()` is deprecated; use `master_n_params()`.",
          call. = FALSE)
  master_n_params(depth)
}

#' Deprecated: legacy alias for [theta_for_log()]
#'
#' v1 used `theta_for_ln()` returning a list of per-slot lists. v2's
#' [theta_for_log()] returns a flat numeric vector matching the
#' [unpack_master_params()] convention. This shim returns the **v1
#' list-of-lists** form so that legacy code (and the v1 test script)
#' continues to work via [eml_master_eval()].
#' @export
theta_for_ln <- function() {
  warning(paste("`theta_for_ln()` returns the v1 list-of-lists form for",
                "use with the deprecated `eml_master_eval()`. Prefer",
                "v2's `theta_for_log()` (flat numeric vector) with",
                "`build_master()` + `eml_eval()`."),
          call. = FALSE)
  filler_inner <- list(alpha = 1, beta = 0, gamma = 0)
  filler_leaf  <- list(alpha = 1, beta = 0)
  one_inner    <- list(alpha = 1, beta = 0, gamma = 0)
  one_leaf     <- list(alpha = 1, beta = 0)
  x_leaf       <- list(alpha = 0, beta = 1)
  use_f_inner  <- list(alpha = 0, beta = 0, gamma = 1)
  list(
    one_inner, filler_inner, filler_leaf, filler_leaf,
    filler_inner, filler_leaf, filler_leaf,
    use_f_inner, use_f_inner, one_leaf, x_leaf,
    one_inner, filler_leaf, filler_leaf
  )
}

# Convert a v1 list-of-lists theta into a flat numeric vector matching
# the v2 [unpack_master_params()] / [build_master()] DFS slot order.
.theta_v1_to_v2 <- function(theta_v1, depth) {
  par <- numeric(0)
  slot_idx <- 0L
  build <- function(remaining_depth) {
    slot_idx <<- slot_idx + 1L
    p <- theta_v1[[slot_idx]]
    if (remaining_depth == 0L) {
      par <<- c(par, p$alpha, p$beta)
    } else {
      par <<- c(par, p$alpha, p$beta,
                if (is.null(p$gamma)) 0 else p$gamma)
      build(remaining_depth - 1L)
      build(remaining_depth - 1L)
    }
  }
  build(depth - 1L)
  build(depth - 1L)
  par
}

#' Deprecated: legacy depth-n master evaluator
#'
#' v1's `eml_master_eval(depth, x, theta)` accepted a list of per-slot
#' lists with `alpha` / `beta` / `gamma` entries. The shim converts to
#' v2's flat parameter vector and dispatches through [build_master()] +
#' [base::eval]. v2 callers should use that pipeline directly.
#'
#' @param depth integer >= 1.
#' @param x numeric or complex input.
#' @param theta either a v1-style list of per-slot lists, or a v2-style
#'   flat numeric vector of length `master_n_params(depth)`.
#' @return Complex vector.
#' @export
eml_master_eval <- function(depth, x, theta) {
  warning(paste("`eml_master_eval()` is deprecated; use",
                "`eml_eval(build_master(depth),",
                "c(unpack_master_params(par, depth),",
                "list(x = x)))` directly."),
          call. = FALSE)
  if (is.list(theta)) {
    par <- .theta_v1_to_v2(theta, depth)
  } else if (is.numeric(theta)) {
    par <- theta
  } else {
    stop("eml_master_eval: theta must be a v1 list-of-lists or a v2 numeric vector.")
  }
  bindings <- unpack_master_params(par, depth)
  master <- build_master(depth, var_name = "x")
  env <- list2env(c(list(eml = eml), bindings, list(x = x)),
                  parent = baseenv())
  eval(master, env)
}

#' Deprecated: v1 eml_tree constructor
#'
#' v1 had no constructor of this name (it used `eml_const`/`eml_var`/
#' `eml_node`); some external code may refer to it. Always returns a
#' v2 native expression with a deprecation warning.
#'
#' @param ... ignored.
#' @keywords internal
#' @export
eml_tree <- function(...) {
  warning(paste("`eml_tree()` is deprecated; v2 uses native R calls.",
                "Use `eml_node()` or `E()` instead."),
          call. = FALSE)
  args <- list(...)
  if (length(args) >= 2L && all(c("left", "right") %in% names(args))) {
    return(eml_node(args$left, args$right))
  }
  if (length(args) >= 2L) return(eml_node(args[[1L]], args[[2L]]))
  if (length(args) == 1L) return(as_eml_expr(args[[1L]]))
  stop("eml_tree: legacy shim requires a left and right child.")
}

#' Deprecated: v1 unpack_theta returning list-of-lists
#'
#' v1 returned a list of per-slot `(alpha, beta, gamma)` lists. v2's
#' [unpack_master_params()] returns a flat named list keyed by symbol
#' names suitable for `eval()`. This shim provides the v1 shape.
#'
#' @param par numeric vector of length `master_n_params(depth)`.
#' @param depth integer >= 1.
#' @return List of per-slot lists.
#' @export
unpack_theta <- function(par, depth) {
  warning("`unpack_theta()` is deprecated; use `unpack_master_params()`.",
          call. = FALSE)
  out <- list()
  idx <- 1L
  build <- function(remaining_depth) {
    if (remaining_depth == 0L) {
      out[[length(out) + 1L]] <<- list(alpha = par[idx],
                                       beta  = par[idx + 1L])
      idx <<- idx + 2L
    } else {
      out[[length(out) + 1L]] <<- list(alpha = par[idx],
                                       beta  = par[idx + 1L],
                                       gamma = par[idx + 2L])
      idx <<- idx + 3L
      build(remaining_depth - 1L)
      build(remaining_depth - 1L)
    }
  }
  build(depth - 1L)
  build(depth - 1L)
  out
}
