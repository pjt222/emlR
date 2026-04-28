# =============================================================================
#  Master formula and symbolic-regression fitter (SPEC §6).
#
#  At every input slot of an EML tree, the master formula contributes
#      alpha_i * 1 + beta_i * x + gamma_i * f
#  where `f` is the value of the deeper EML node feeding this input
#  (absent at leaf slots). Snapping (alpha_i, beta_i, gamma_i) to a
#  one-hot vertex selects one of {1, x, f}, recovering the discrete
#  EML grammar `S -> 1 | x | eml(S, S)`.
#
#  Slot count and parameter count match the paper (SI III):
#    slots(d)    = 2^(d+1) - 2
#    params(d)   = 5 * 2^d - 6
# =============================================================================

# ---- Master expression construction ----------------------------------------

#' Number of free parameters in a depth-n master formula
#'
#' Equals `5 * 2^depth - 6` (paper, SI III).
#'
#' @param depth integer >= 1.
#' @return Integer.
#' @examples
#' master_n_params(1)   # 4
#' master_n_params(2)   # 14
#' master_n_params(3)   # 34
#' @family eml_master
#' @export
master_n_params <- function(depth) {
  if (depth < 1L) stop("master_n_params: depth must be >= 1.")
  as.integer(5L * 2L^as.integer(depth) - 6L)
}

#' Build a depth-n master-formula expression
#'
#' Returns a parameterised `call` whose free names are
#' `alpha_<i>`, `beta_<i>` (and `gamma_<i>` at inner slots) plus the
#' input variable. The slot index follows a depth-first traversal:
#' each call to the inner `build_input` recursion increments a global
#' counter, so slots are numbered in the order they are emitted (root's
#' left-subtree first, then root's right-subtree).
#'
#' @param depth integer >= 1.
#' @param var_name character — the input variable name.
#' @return A `call`.
#' @examples
#' build_master(1)
#' all.vars(build_master(2))
#' @family eml_master
#' @export
# put id:"mas_build", label:"build_master (depth-n formula)", \
#   node_type:"process", output:"master_formula.internal"
build_master <- function(depth, var_name = "x") {
  if (depth < 1L) stop("build_master: depth must be >= 1.")
  slot_idx <- 0L
  x_sym <- as.name(var_name)

  build_input <- function(remaining_depth) {
    slot_idx <<- slot_idx + 1L
    a <- as.name(paste0("alpha_", slot_idx))
    b <- as.name(paste0("beta_",  slot_idx))
    if (remaining_depth == 0L) {
      bquote(.(a) * 1 + .(b) * .(x_sym))
    } else {
      g <- as.name(paste0("gamma_", slot_idx))
      f_left  <- build_input(remaining_depth - 1L)
      f_right <- build_input(remaining_depth - 1L)
      f <- bquote(eml(.(f_left), .(f_right)))
      bquote(.(a) * 1 + .(b) * .(x_sym) + .(g) * .(f))
    }
  }

  left  <- build_input(depth - 1L)
  right <- build_input(depth - 1L)
  bquote(eml(.(left), .(right)))
}

#' Pack a flat parameter vector into a named list keyed by the symbol names
#'
#' The order matches [build_master()]: depth-first, root's left subtree
#' first. Inner slots receive 3 values (`alpha`, `beta`, `gamma`); leaf
#' slots receive 2 (`alpha`, `beta`).
#'
#' @param par numeric vector of length `master_n_params(depth)`.
#' @param depth integer >= 1.
#' @return A named list ready to feed to [base::eval] alongside the
#'   input variable.
#' @examples
#' v <- runif(master_n_params(2))
#' bindings <- unpack_master_params(v, 2)
#' names(bindings)
#' @family eml_master
#' @export
unpack_master_params <- function(par, depth) {
  if (length(par) != master_n_params(depth)) {
    stop("unpack_master_params: par has length ", length(par),
         ", expected ", master_n_params(depth), ".")
  }
  out <- list()
  slot_idx <- 0L
  idx <- 1L
  build <- function(remaining_depth) {
    slot_idx <<- slot_idx + 1L
    out[[paste0("alpha_", slot_idx)]] <<- par[idx]
    out[[paste0("beta_",  slot_idx)]] <<- par[idx + 1L]
    if (remaining_depth == 0L) {
      idx <<- idx + 2L
    } else {
      out[[paste0("gamma_", slot_idx)]] <<- par[idx + 2L]
      idx <<- idx + 3L
      build(remaining_depth - 1L)
      build(remaining_depth - 1L)
    }
  }
  build(depth - 1L)
  build(depth - 1L)
  out
}

# Parameter symbol names in the same DFS order, used to enumerate
# Deriv calls and to assemble parameter vectors.
.master_param_names <- function(depth) {
  names(unpack_master_params(rep(0, master_n_params(depth)), depth))
}

# ---- Selectors: parameter vectors that recover known functions ------------

# Helper: build a named param list from per-slot specs (specs[[i]] is
# a length-2 or length-3 numeric vector). Then flatten in DFS order.
.slots_to_par <- function(slots, depth) {
  par <- numeric(0)
  slot_idx <- 0L
  build <- function(remaining_depth) {
    slot_idx <<- slot_idx + 1L
    s <- slots[[slot_idx]]
    if (remaining_depth == 0L) {
      par <<- c(par, s[1L], s[2L])
    } else {
      par <<- c(par, s[1L], s[2L], s[3L])
      build(remaining_depth - 1L)
      build(remaining_depth - 1L)
    }
  }
  build(depth - 1L)
  build(depth - 1L)
  par
}

#' Selector parameter vector for the `exp(x)` master at depth 1
#'
#' Recovers `exp(x) = eml(x, 1)` in the depth-1 master:
#' left input `x` (slot 1: alpha=0, beta=1), right input `1`
#' (slot 2: alpha=1, beta=0).
#' @return Numeric vector of length 4.
#' @examples
#' theta_for_exp()
#' @family eml_master
#' @export
theta_for_exp <- function() {
  .slots_to_par(list(c(0, 1), c(1, 0)), depth = 1L)
}

#' Selector parameter vector for the `log(x)` master at depth 3
#'
#' Recovers `log(x) = eml(1, eml(eml(1, x), 1))` (paper Eq. 5).
#' All inner slots use `gamma = 1` (route through `f`); leaf slots
#' choose the literal `1` or the input `x` per the structure.
#'
#' @return Numeric vector of length 34.
#' @examples
#' length(theta_for_log())          # 34 — matches master_n_params(3)
#' @family eml_master
#' @export
theta_for_log <- function() {
  use_one_inner    <- c(1, 0, 0)
  use_x_inner      <- c(0, 1, 0)
  route_f_inner    <- c(0, 0, 1)
  use_one_leaf     <- c(1, 0)
  use_x_leaf       <- c(0, 1)

  # DFS order: root.left subtree (slots 1-7), then root.right (slots 8-14).
  # Root.left subtree must select the literal `1` — i.e., resolve to 1.
  # Easiest: every slot in root.left selects alpha (=> contributes 1).
  # Root.right subtree must produce eml(eml(1, x), 1).
  slots <- list(
    use_one_inner,    # 1: root.left  inner — pick 1 (alpha)
    use_one_inner,    # 2: root.left.left  inner
    use_one_leaf,     # 3: leaf -> 1
    use_one_leaf,     # 4: leaf -> 1
    use_one_inner,    # 5: root.left.right inner
    use_one_leaf,     # 6: leaf -> 1
    use_one_leaf,     # 7: leaf -> 1
    route_f_inner,    # 8: root.right inner — route through f
    route_f_inner,    # 9: root.right.left inner — route through f
    use_one_leaf,     # 10: leaf -> 1
    use_x_leaf,       # 11: leaf -> x
    use_one_inner,    # 12: root.right.right inner — pick 1
    use_one_leaf,     # 13: leaf -> 1
    use_one_leaf      # 14: leaf -> 1
  )
  .slots_to_par(slots, depth = 3L)
}

# ---- Differentiation: expand eml -> exp/log, then Deriv --------------------

# Walk the master expression and replace every eml(a, b) with the
# expanded form exp(a) - log(b). Deriv knows exp/log natively.
.expand_eml <- function(expr) {
  if (is_eml_call(expr)) {
    l <- .expand_eml(expr[[2L]])
    r <- .expand_eml(expr[[3L]])
    return(bquote(exp(.(l)) - log(.(r))))
  }
  if (is.call(expr)) {
    new_args <- lapply(as.list(expr)[-1L], .expand_eml)
    return(as.call(c(list(expr[[1L]]), new_args)))
  }
  expr
}

# Compute symbolic gradient expressions (one per parameter) for an
# expanded master expression. Cached per (expanded_expr, par_names).
.master_grad_exprs <- function(expanded_expr, par_names) {
  lapply(par_names, function(p) Deriv::Deriv(expanded_expr, p))
}

# ---- Snapping --------------------------------------------------------------

#' Snap continuous master parameters to one-hot vertices
#'
#' For each slot, picks the largest of `(alpha, beta[, gamma])` and
#' sets it to 1, the others to 0. Recovers the discrete grammar choice
#' at every slot. After snapping, evaluating the master should reproduce
#' the corresponding closed-form symbolic expression.
#'
#' @param par numeric vector of length `master_n_params(depth)`.
#' @param depth integer >= 1.
#' @return Numeric vector of the same length as `par`.
#' @examples
#' theta <- theta_for_exp()
#' snapped <- snap_master_params(theta, depth = 1)
#' identical(snapped, theta)        # already one-hot
#' @family eml_master
#' @export
snap_master_params <- function(par, depth) {
  if (length(par) != master_n_params(depth)) {
    stop("snap_master_params: par has wrong length.")
  }
  out <- par
  idx <- 1L
  build <- function(remaining_depth) {
    if (remaining_depth == 0L) {
      sl <- par[idx:(idx + 1L)]
      win <- which.max(sl)
      out[idx:(idx + 1L)] <<- as.numeric(seq_along(sl) == win)
      idx <<- idx + 2L
    } else {
      sl <- par[idx:(idx + 2L)]
      win <- which.max(sl)
      out[idx:(idx + 2L)] <<- as.numeric(seq_along(sl) == win)
      idx <<- idx + 3L
      build(remaining_depth - 1L)
      build(remaining_depth - 1L)
    }
  }
  build(depth - 1L)
  build(depth - 1L)
  out
}

# Slot-wise softmax: for each slot's logits, returns simplex weights.
.softmax_slots <- function(par, depth) {
  out <- par
  idx <- 1L
  build <- function(remaining_depth) {
    if (remaining_depth == 0L) {
      z <- par[idx:(idx + 1L)]
      e <- exp(z - max(z))
      out[idx:(idx + 1L)] <<- e / sum(e)
      idx <<- idx + 2L
    } else {
      z <- par[idx:(idx + 2L)]
      e <- exp(z - max(z))
      out[idx:(idx + 2L)] <<- e / sum(e)
      idx <<- idx + 3L
      build(remaining_depth - 1L)
      build(remaining_depth - 1L)
    }
  }
  build(depth - 1L)
  build(depth - 1L)
  out
}

# ---- The fitter -----------------------------------------------------------

#' Fit a depth-n master formula to data (symbolic regression)
#'
#' Replaces v1's SANN with L-BFGS-B plus analytic gradients via
#' [Deriv::Deriv] applied to the eml-expanded master expression. After
#' convergence, snaps each slot to its argmax one-hot vertex and
#' reports the snapped MSE — values at machine epsilon squared
#' indicate exact symbolic recovery.
#'
#' @param x numeric vector of inputs.
#' @param y numeric vector of targets.
#' @param depth integer >= 1.
#' @param parameterization either `"simplex"` (logits → per-slot
#'   softmax; the paper's choice) or `"direct"` (raw scaling).
#' @param method `optim` method; defaults to `"L-BFGS-B"`.
#' @param maxit maximum optimiser iterations.
#' @param n_restarts number of independent random restarts; the best is
#'   returned.
#' @param seed RNG seed for reproducibility (each restart shifts it by 1).
#' @return List with `par`, `theta`, `theta_snap`, `pred`, `pred_snap`,
#'   `final_value`, `snap_mse`, `n_restarts_run`, `best_seed`.
#' @examples
#' \donttest{
#' xs <- seq(0.5, 5, length.out = 30)
#' ys <- log(xs)
#' fit <- eml_fit(xs, ys, depth = 3, n_restarts = 2,
#'                maxit = 200, seed = 1)
#' fit$snap_mse  # ~ 0 indicates exact symbolic recovery of log(x)
#' }
#' @family eml_master
#' @export
# put id:"mas_data", label:"Training data (x, y)", node_type:"input", \
#   output:"data.internal"
# put id:"mas_fit", label:"eml_fit (L-BFGS-B + Deriv gradient)", \
#   node_type:"process", input:"data.internal,master_formula.internal", output:"theta_snap.internal"
# put id:"mas_recover", label:"Recovered AST (snap to one-hot)", \
#   node_type:"output", input:"theta_snap.internal"
eml_fit <- function(x, y, depth = 3L,
                    parameterization = c("simplex", "direct"),
                    method = "L-BFGS-B", maxit = 1000L,
                    n_restarts = 1L, seed = 42L) {
  parameterization <- match.arg(parameterization)
  n_par <- master_n_params(depth)

  master  <- build_master(depth, var_name = "x")
  expanded <- .expand_eml(master)
  par_names <- .master_param_names(depth)
  grad_exprs <- .master_grad_exprs(expanded, par_names)

  # Build the prediction and gradient closures over a working env.
  to_theta <- if (parameterization == "simplex") {
    function(par) .softmax_slots(par, depth)
  } else identity

  PENALTY <- 1e10
  loss_and_grad <- function(par) {
    theta_par <- to_theta(par)
    bindings <- unpack_master_params(theta_par, depth)
    env <- list2env(c(list(eml = eml), bindings, list(x = x)),
                    parent = baseenv())
    pred <- tryCatch(suppressWarnings(Re(eval(master, env))),
                     error = function(e) NULL)
    if (is.null(pred) || any(!is.finite(pred))) {
      return(list(value = PENALTY, grad = rep(0, n_par)))
    }
    resid <- pred - y
    val   <- mean(resid^2)
    if (!is.finite(val)) return(list(value = PENALTY, grad = rep(0, n_par)))

    g_theta <- vapply(seq_along(par_names), function(k) {
      gp <- tryCatch(suppressWarnings(Re(eval(grad_exprs[[k]], env))),
                     error = function(e) NULL)
      if (is.null(gp) || any(!is.finite(gp))) return(NA_real_)
      mean(2 * resid * gp)
    }, numeric(1))

    if (any(!is.finite(g_theta))) {
      return(list(value = PENALTY, grad = rep(0, n_par)))
    }

    g_par <- if (parameterization == "simplex") {
      .softmax_chain(g_theta, par, depth)
    } else g_theta
    if (any(!is.finite(g_par))) {
      return(list(value = PENALTY, grad = rep(0, n_par)))
    }

    list(value = val, grad = g_par)
  }

  fn <- function(par) loss_and_grad(par)$value
  gr <- function(par) loss_and_grad(par)$grad

  # Save/restore the caller's RNG state. set.seed() inside the loop
  # would otherwise leak deterministic state into the user's session
  # (CRAN policy violation: packages must not modify global state).
  old_seed <- if (exists(".Random.seed", envir = .GlobalEnv)) {
    get(".Random.seed", envir = .GlobalEnv)
  } else {
    NULL
  }
  on.exit({
    if (is.null(old_seed)) {
      if (exists(".Random.seed", envir = .GlobalEnv)) {
        rm(".Random.seed", envir = .GlobalEnv)
      }
    } else {
      assign(".Random.seed", old_seed, envir = .GlobalEnv)
    }
  }, add = TRUE)

  best <- NULL
  n_run <- 0L
  for (k in seq_len(n_restarts)) {
    n_run <- n_run + 1L
    set.seed(seed + k - 1L)
    par0 <- rnorm(n_par, sd = 0.5)
    # Guard: if the starting point is non-finite, skip to a small jitter
    # rather than letting L-BFGS-B abort.
    if (!is.finite(fn(par0))) {
      par0 <- rnorm(n_par, sd = 0.1)
    }
    fit <- tryCatch(
      stats::optim(par0, fn, gr, method = method,
                   control = list(maxit = maxit)),
      error = function(e) NULL
    )
    # Fall back to method = "BFGS" (no bounds) if L-BFGS-B aborts.
    if (is.null(fit) && method == "L-BFGS-B") {
      fit <- tryCatch(
        stats::optim(par0, fn, gr, method = "BFGS",
                     control = list(maxit = maxit)),
        error = function(e) NULL
      )
    }
    if (is.null(fit)) next
    if (is.null(best) || fit$value < best$value) {
      best <- fit
      best$seed <- seed + k - 1L
    }
  }
  if (is.null(best)) stop("eml_fit: all restarts failed.")

  theta_par <- to_theta(best$par)
  theta_par_snap <- snap_master_params(theta_par, depth)

  bindings <- unpack_master_params(theta_par, depth)
  bindings_snap <- unpack_master_params(theta_par_snap, depth)
  env_pred <- list2env(c(list(eml = eml), bindings,      list(x = x)),
                       parent = baseenv())
  env_snap <- list2env(c(list(eml = eml), bindings_snap, list(x = x)),
                       parent = baseenv())
  pred      <- tryCatch(Re(eval(master, env_pred)),
                        error = function(e) rep(NA_real_, length(x)))
  pred_snap <- tryCatch(Re(eval(master, env_snap)),
                        error = function(e) rep(NA_real_, length(x)))
  snap_mse <- if (all(is.finite(pred_snap))) mean((pred_snap - y)^2) else NA_real_

  list(
    par             = best$par,
    theta           = theta_par,
    theta_snap      = theta_par_snap,
    pred            = pred,
    pred_snap       = pred_snap,
    final_value     = best$value,
    snap_mse        = snap_mse,
    n_restarts_run  = n_run,
    best_seed       = best$seed
  )
}

# Chain rule: g_par[k] = sum_i g_theta[i] * d(theta_i)/d(par_k).
# For per-slot softmax with logits par_slot: theta_i = exp(par_i)/sum,
# d(theta_i)/d(par_k) = theta_i * (delta_{ik} - theta_k).
# Cross-slot derivatives are zero.
.softmax_chain <- function(g_theta, par, depth) {
  out <- numeric(length(par))
  idx <- 1L
  build <- function(remaining_depth) {
    sz <- if (remaining_depth == 0L) 2L else 3L
    rng <- idx:(idx + sz - 1L)
    z <- par[rng]
    e <- exp(z - max(z))
    th <- e / sum(e)
    g_th <- g_theta[rng]
    # Jacobian-vector product: out[k] = th[k] * (g_th[k] - sum_i th[i] * g_th[i])
    s <- sum(th * g_th)
    out[rng] <<- th * (g_th - s)
    idx <<- idx + sz
    if (remaining_depth > 0L) {
      build(remaining_depth - 1L)
      build(remaining_depth - 1L)
    }
  }
  build(depth - 1L)
  build(depth - 1L)
  out
}
