# =============================================================================
#  Master formula and symbolic regression
#
#  Following Section 4.3 of Odrzywolek (2026):
#
#  At every "input slot" of an EML tree, we form a linear combination of
#  three sources:
#
#         alpha_i * 1  +  beta_i * x  +  gamma_i * f
#
#  where f is the value of the previous (deeper) eml node.  At leaves, only
#  alpha and beta are present (no f).
#
#  By snapping (alpha_i, beta_i, gamma_i) to one-hot vertices, we recover
#  the discrete grammar S -> 1 | x | eml(S, S).  When trained as a continuous
#  function (e.g. logits through softmax), gradient-based optimization can
#  recover exact closed-form formulas at shallow depths.
#
#  The level-n master formula has 5 * 2^n - 6 free parameters (paper, SI III).
# =============================================================================

#' Build a depth-n master formula and evaluate it.
#'
#' @param depth tree depth >= 1
#' @param x scalar or vector of input values (real or complex)
#' @param params named list with:
#'   - alpha: numeric vector of length n_inner + n_leaf
#'   - beta:  same length
#'   - gamma: numeric vector of length n_inner (no gamma at leaves)
#'   The orderings are: deeper nodes first (post-order), with the final
#'   element being the root's left input, then the root's right input
#'   for alpha/beta; gamma indexes only inner-node inputs.
#'
#' For simplicity, this implementation enumerates the inputs in a recursive
#' top-down order and lets you supply parameters as a single flat list of
#' triples.
#'
#' @return complex vector of f(x) values
#' @export
eml_master_eval <- function(depth, x, theta) {
  # theta is a list of (alpha, beta, gamma) triples for each input slot.
  # The recursion places left input before right input, depth-first.
  if (depth < 1) stop("depth must be >= 1")
  x <- as.complex(x)

  # We use a stateful counter to walk through theta.
  slot_idx <- 0L

  build_input <- function(remaining_depth, prev_f) {
    slot_idx <<- slot_idx + 1L
    p <- theta[[slot_idx]]
    a <- p$alpha; b <- p$beta; g <- if (is.null(p$gamma)) 0 else p$gamma

    if (remaining_depth == 0L) {
      # Leaf input: only 1 and x available
      a * 1 + b * x
    } else {
      # Inner input: also has access to a deeper eml output `f`
      f_left  <- build_input(remaining_depth - 1L, NULL)
      f_right <- build_input(remaining_depth - 1L, NULL)
      f       <- eml(f_left, f_right)
      a * 1 + b * x + g * f
    }
  }

  # Root has two inputs, each at "depth - 1" remaining
  left  <- build_input(depth - 1L, NULL)
  right <- build_input(depth - 1L, NULL)
  eml(left, right)
}

#' Number of parameter slots in the depth-n master formula.
#' Each slot holds (alpha, beta) at depth-0 inputs, and (alpha, beta, gamma)
#' at deeper inputs.  Total slots = 2 * (2^depth - 1) ... wait, recount:
#' depth-1 tree has 2 leaf inputs => 2 slots.
#' depth-2 tree has 2 inner inputs (each containing 2 leaf inputs) => 6 slots.
#' Generally: 2^(d+1) - 2 slots.
#' Free parameter count: 2 * #leaf-slots + 3 * #inner-slots.
#'   #leaf-slots  = 2^depth
#'   #inner-slots = 2^(depth+1) - 2 - 2^depth = 2^depth - 2
#' => total = 2 * 2^depth + 3 * (2^depth - 2) = 5 * 2^depth - 6.   (Matches paper.)
#' @export
eml_master_n_params <- function(depth) {
  5L * 2L^depth - 6L
}

#' Convenience constructor: produce a "selector" theta list that extracts
#' a known function. Useful for sanity-checking and as initialization.
#' For example, exp(x) at depth 1: left = x (alpha=0, beta=1), right = 1
#' (alpha=1, beta=0).
#' @export
theta_for_exp <- function() {
  list(
    list(alpha = 0, beta = 1),  # left input of root: x
    list(alpha = 1, beta = 0)   # right input of root: 1
  )
}

#' Selector for ln(x) at depth 3 (matches paper Eq. 5).
#' ln(x) = eml(1, eml(eml(1, x), 1))
#'
#' Slot ordering follows build_input(): root.left subtree fully traversed
#' (slots 1-7), then root.right subtree (slots 8-14).
#' @export
theta_for_ln <- function() {
  filler_inner <- list(alpha = 1, beta = 0, gamma = 0)
  filler_leaf  <- list(alpha = 1, beta = 0)
  one_inner    <- list(alpha = 1, beta = 0, gamma = 0)
  one_leaf     <- list(alpha = 1, beta = 0)
  x_leaf       <- list(alpha = 0, beta = 1)
  use_f_inner  <- list(alpha = 0, beta = 0, gamma = 1)

  list(
    one_inner,    # 1: root.left = 1
    filler_inner, # 2: unused subtree...
    filler_leaf,  # 3
    filler_leaf,  # 4
    filler_inner, # 5
    filler_leaf,  # 6
    filler_leaf,  # 7
    use_f_inner,  # 8: root.right = inner eml
    use_f_inner,  # 9: root.right.left = inner eml(1, x)
    one_leaf,     # 10: ...left.left = 1
    x_leaf,       # 11: ...left.right = x
    one_inner,    # 12: root.right.right = 1
    filler_leaf,  # 13
    filler_leaf   # 14
  )
}

# -----------------------------------------------------------------------------
#  Symbolic regression demo using black-box optimization
#
#  Mirrors the paper's "Log_fit.nb" notebook: fit ln(x) data with a
#  depth-3 master formula and snap the result to vertices.
#  We use base-R optim() with simulated annealing (SANN) since we lack
#  autograd and paper notes this works.
# -----------------------------------------------------------------------------

#' Pack a parameter vector into a theta list of the given shape.
#' @export
unpack_theta <- function(par, depth) {
  # Slots in DFS order. Each leaf slot has 2 params (alpha, beta);
  # each inner slot has 3 params (alpha, beta, gamma).
  theta <- list()
  idx <- 1L
  build <- function(remaining_depth) {
    if (remaining_depth == 0L) {
      theta[[length(theta) + 1L]] <<- list(alpha = par[idx], beta = par[idx + 1L])
      idx <<- idx + 2L
    } else {
      theta[[length(theta) + 1L]] <<- list(alpha = par[idx], beta = par[idx + 1L],
                                            gamma = par[idx + 2L])
      idx <<- idx + 3L
      build(remaining_depth - 1L)
      build(remaining_depth - 1L)
    }
  }
  build(depth - 1L)
  build(depth - 1L)
  theta
}

#' Fit a depth-n master formula to (x, y) data using simplex parametrization
#' (alpha, beta, gamma >= 0, sum to 1 per slot via softmax of logits).
#'
#' @param x numeric input vector
#' @param y target output
#' @param depth tree depth
#' @param maxit optim iterations
#' @return list with par, theta, predicted y, snapped (one-hot) theta
#' @export
eml_fit <- function(x, y, depth = 3, maxit = 5000, seed = 42) {
  set.seed(seed)
  n_par <- eml_master_n_params(depth)

  # Use logits with softmax so that (alpha, beta, gamma) sum to 1 per slot.
  # For inner slots: 3 logits per slot; for leaves: 2 logits per slot.
  # Total logits = same count as eml_master_n_params (2*2^d + 3*(2^d - 2)).

  softmax <- function(z) { e <- exp(z - max(z)); e / sum(e) }

  unpack_logits <- function(par) {
    theta <- list()
    idx <- 1L
    build <- function(remaining_depth) {
      if (remaining_depth == 0L) {
        s <- softmax(par[idx:(idx + 1L)])
        theta[[length(theta) + 1L]] <<- list(alpha = s[1], beta = s[2])
        idx <<- idx + 2L
      } else {
        s <- softmax(par[idx:(idx + 2L)])
        theta[[length(theta) + 1L]] <<- list(alpha = s[1], beta = s[2], gamma = s[3])
        idx <<- idx + 3L
        build(remaining_depth - 1L)
        build(remaining_depth - 1L)
      }
    }
    build(depth - 1L)
    build(depth - 1L)
    theta
  }

  loss <- function(par) {
    theta <- unpack_logits(par)
    pred <- tryCatch(
      Re(eml_master_eval(depth, x, theta)),
      error = function(e) rep(NA_real_, length(x)),
      warning = function(w) rep(NA_real_, length(x))
    )
    if (any(!is.finite(pred))) return(1e10)
    mean((pred - y)^2)
  }

  par0 <- rnorm(n_par, sd = 0.3)
  fit <- optim(par0, loss, method = "SANN",
               control = list(maxit = maxit, temp = 5, tmax = 10))

  theta <- unpack_logits(fit$par)
  pred  <- Re(eml_master_eval(depth, x, theta))

  # Snap each slot to its argmax vertex (one-hot).
  snap_slot <- function(s) {
    if (is.null(s$gamma)) {
      probs <- c(s$alpha, s$beta)
      one_hot <- as.integer(probs == max(probs))
      list(alpha = one_hot[1], beta = one_hot[2])
    } else {
      probs <- c(s$alpha, s$beta, s$gamma)
      one_hot <- as.integer(probs == max(probs))
      list(alpha = one_hot[1], beta = one_hot[2], gamma = one_hot[3])
    }
  }
  theta_snap <- lapply(theta, snap_slot)
  pred_snap  <- tryCatch(Re(eml_master_eval(depth, x, theta_snap)),
                         error = function(e) rep(NA_real_, length(x)))

  list(
    par         = fit$par,
    theta       = theta,
    theta_snap  = theta_snap,
    pred        = pred,
    pred_snap   = pred_snap,
    final_value = fit$value,
    snap_mse    = if (all(is.finite(pred_snap))) mean((pred_snap - y)^2) else NA
  )
}
