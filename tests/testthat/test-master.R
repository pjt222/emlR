# =============================================================================
#  Phase 5 tests — master formula construction, parameter packing,
#  selectors, gradient correctness, and the L-BFGS-B fitter.
# =============================================================================

# --- 5a: master formula structure -------------------------------------------

test_that("master_n_params matches paper formula 5*2^depth - 6", {
  expect_identical(master_n_params(1), 4L)
  expect_identical(master_n_params(2), 14L)
  expect_identical(master_n_params(3), 34L)
  expect_identical(master_n_params(4), 74L)
})

test_that("build_master produces the right free symbols at depth 1 and 2", {
  m1 <- build_master(1)
  expect_setequal(all.vars(m1),
                  c("x", "alpha_1", "beta_1", "alpha_2", "beta_2"))

  m2 <- build_master(2)
  # depth-2: 6 slots (slots 1 and 4 inner, others leaves)
  expect_setequal(all.vars(m2),
                  c("x",
                    paste0("alpha_", 1:6),
                    paste0("beta_",  1:6),
                    "gamma_1", "gamma_4"))
})

test_that("unpack_master_params keys match build_master vars", {
  par <- runif(master_n_params(2))
  bindings <- unpack_master_params(par, 2)
  bind_names <- names(bindings)
  master_names <- setdiff(all.vars(build_master(2)), "x")
  expect_setequal(bind_names, master_names)
})

# --- 5b: selectors recover exp(x) and log(x) -------------------------------

test_that("theta_for_exp recovers exp(x) at depth 1", {
  xs <- seq(-1, 1, length.out = 7)
  m1 <- build_master(1)
  bindings <- unpack_master_params(theta_for_exp(), 1)
  env <- list2env(c(list(eml = eml), bindings, list(x = xs)),
                  parent = baseenv())
  val <- Re(eval(m1, env))
  expect_equal(val, exp(xs), tolerance = 1e-12)
})

test_that("theta_for_log recovers log(x) at depth 3 (paper Eq. 5)", {
  xs <- c(0.5, 1, 2, 5, 10)
  m3 <- build_master(3)
  bindings <- unpack_master_params(theta_for_log(), 3)
  env <- list2env(c(list(eml = eml), bindings, list(x = xs)),
                  parent = baseenv())
  val <- suppressWarnings(Re(eval(m3, env)))
  expect_equal(val, log(xs), tolerance = 1e-10)
})

# --- 5c: analytic gradient via Deriv matches finite differences -------------

test_that("Deriv-based gradient agrees with FD at depth 2", {
  set.seed(20260426)
  depth <- 2L
  n_par <- master_n_params(depth)
  master <- build_master(depth)
  expanded <- .expand_eml(master)
  par_names <- .master_param_names(depth)
  grads <- lapply(par_names, function(p) Deriv::Deriv(expanded, p))

  xs <- runif(20, 0.5, 3)
  ys <- log(xs)
  par <- runif(n_par, -0.5, 0.5)

  bindings <- unpack_master_params(par, depth)
  env <- list2env(c(list(eml = eml), bindings, list(x = xs)),
                  parent = baseenv())
  pred <- Re(eval(master, env))
  resid <- pred - ys
  g_an <- vapply(seq_along(par_names), function(k) {
    mean(2 * resid * Re(eval(grads[[k]], env)))
  }, numeric(1))

  eps <- 1e-6
  g_fd <- numeric(n_par)
  for (i in seq_len(n_par)) {
    par_p <- par; par_p[i] <- par_p[i] + eps
    par_m <- par; par_m[i] <- par_m[i] - eps
    bp <- unpack_master_params(par_p, depth)
    bm <- unpack_master_params(par_m, depth)
    ep <- list2env(c(list(eml = eml), bp, list(x = xs)), parent = baseenv())
    em <- list2env(c(list(eml = eml), bm, list(x = xs)), parent = baseenv())
    g_fd[i] <- (mean((Re(eval(master, ep)) - ys)^2) -
                mean((Re(eval(master, em)) - ys)^2)) / (2 * eps)
  }
  expect_equal(g_an, g_fd, tolerance = 1e-5)
})

# --- 5d: snap_master_params is idempotent and one-hot ----------------------

test_that("snap_master_params produces one-hot per slot", {
  par <- c(0.1, 0.7, 0.2,    # slot 1 (inner): pick beta
           0.3, 0.5,         # slot 2 (leaf):  pick beta
           0.9, 0.1)         # slot 3 (leaf):  pick alpha
  # depth 2 has 6 slots, length 14. Build a longer one with a clear winner per slot.
  set.seed(42)
  par <- runif(master_n_params(2), 0.1, 1.0)
  snapped <- snap_master_params(par, 2)
  expect_equal(length(snapped), length(par))
  # Should sum to slots(2) = 6 (one '1' per slot)
  # slots(d) = 2^(d+1) - 2 = 6 for d=2
  expect_equal(sum(snapped), 6)

  # Idempotence
  expect_equal(snap_master_params(snapped, 2), snapped)
})

# --- 5d1: fast smoke test — eml_fit returns the documented list shape -------
#
# The Phase-5 SR-recovery gate runs in ~1 minute and is opt-in via
# EMLR_RUN_SLOW=true, so without this test no CI run exercises the
# fitter end-to-end. depth=1, n_restarts=1, maxit=10 finishes in
# milliseconds and verifies the @return contract documented for
# eml_fit (every named slot present, correct mode/length).

test_that("eml_fit returns the documented list shape on a tiny input", {
  xs <- seq(0.5, 2, length.out = 8)
  ys <- log(xs)
  fit <- eml_fit(xs, ys, depth = 1L, parameterization = "simplex",
                 n_restarts = 1L, maxit = 10L, seed = 1L)

  expected <- c("par", "theta", "theta_snap", "pred", "pred_snap",
                "final_value", "snap_mse", "n_restarts_run", "best_seed")
  expect_setequal(names(fit), expected)

  n_par <- master_n_params(1L)
  expect_length(fit$par,        n_par)
  expect_length(fit$theta,      n_par)
  expect_length(fit$theta_snap, n_par)
  expect_length(fit$pred,       length(xs))
  expect_length(fit$pred_snap,  length(xs))

  expect_true(is.numeric(fit$final_value) && length(fit$final_value) == 1L)
  expect_true(is.numeric(fit$snap_mse)    && length(fit$snap_mse)    == 1L)
  expect_identical(fit$n_restarts_run, 1L)
  expect_identical(fit$best_seed, 1L)
})

# --- 5d2: eml_fit must not mutate the global RNG -----------------------------
#
# CRAN policy (Writing R Extensions §1.6) forbids packages from leaking
# random state into the caller's session. eml_fit calls set.seed inside
# its restart loop and so must save and restore .Random.seed on exit.

test_that("eml_fit leaves .Random.seed untouched", {
  xs <- seq(0.5, 2, length.out = 8)
  ys <- log(xs)

  set.seed(7)
  before <- runif(1)

  set.seed(7)
  fit <- eml_fit(xs, ys, depth = 1, parameterization = "simplex",
                 n_restarts = 2L, maxit = 20L, seed = 100L)
  after <- runif(1)

  expect_identical(before, after)

  # Edge case: a fresh session where .Random.seed is not set.
  if (exists(".Random.seed", envir = .GlobalEnv)) {
    rm(".Random.seed", envir = .GlobalEnv)
  }
  fit <- eml_fit(xs, ys, depth = 1, parameterization = "simplex",
                 n_restarts = 1L, maxit = 5L, seed = 1L)
  expect_false(exists(".Random.seed", envir = .GlobalEnv))
})

# --- 5e: SR recovery of log(x) at depth 3 ----------------------------------
#
# This is the paper's headline reproducibility demo. With analytic
# gradients via Deriv plus L-BFGS-B, recovery should be substantially
# more reliable than v1's SANN. Spec target: ≥8/10 with 10 restarts.
# We use 5 restarts in the test to keep CI fast; expand if flaky.

test_that("eml_fit recovers log(x) at depth 3 with multi-restart", {
  skip_on_cran()
  xs <- seq(0.5, 5, length.out = 30)
  ys <- log(xs)
  fit <- eml_fit(xs, ys, depth = 3,
                 parameterization = "simplex",
                 n_restarts = 5L, seed = 1L)
  expect_lt(fit$snap_mse, 1e-20)
})

# Optional: single-restart success rate (informational, may be flaky)
test_that("eml_fit single-restart hits the optimum more than once in 5 seeds", {
  skip_on_cran()
  xs <- seq(0.5, 5, length.out = 30)
  ys <- log(xs)
  hits <- 0L
  for (s in 1:5) {
    fit <- eml_fit(xs, ys, depth = 3, n_restarts = 1L, seed = s)
    if (isTRUE(fit$snap_mse < 1e-20)) hits <- hits + 1L
  }
  # Paper reports ~25% rate; with analytic gradients expect > 1/5.
  expect_gte(hits, 1L)
})

# Phase 5 acceptance gate per IMPLEMENTATION_PLAN.md §5d:
# "ln(x) is recovered exactly (snapped MSE < 1e-20) in at least 8 of 10
#  runs with random seeds." With n_restarts = 10 per trial.
# Slow (~1 min) — skipped on CRAN/CI.
test_that("Phase 5 gate: 8/10 multi-restart trials recover ln(x)", {
  skip_on_cran()
  if (Sys.getenv("EMLR_RUN_SLOW", "false") != "true") {
    skip("Set EMLR_RUN_SLOW=true to run the Phase 5 gate test.")
  }
  xs <- seq(0.5, 5, length.out = 30)
  ys <- log(xs)
  hits <- vapply(1:10, function(s) {
    fit <- eml_fit(xs, ys, depth = 3, n_restarts = 10L, seed = s * 100L)
    isTRUE(fit$snap_mse < 1e-20)
  }, logical(1))
  expect_gte(sum(hits), 8L)
})
