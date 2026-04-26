# =============================================================================
#  v1 -> v2 compatibility shim tests. Confirms that the legacy names from
#  the v1 prototype still work (with deprecation warnings) and produce
#  the right values.
# =============================================================================

test_that("as_eml_tree is a deprecated alias for as_eml_expr", {
  expect_warning(out <- as_eml_tree(2), "deprecated")
  expect_identical(out, 2)
})

test_that("eml_eval_real warns and produces the real part", {
  expect_warning(out <- eml_eval_real(quote(eml(x, 1)), list(x = 1)),
                 "deprecated")
  expect_equal(out, exp(1), tolerance = 1e-12)
})

test_that("ONE constant equals literal 1", {
  expect_identical(ONE, 1)
})

test_that("eml_master_n_params is alias for master_n_params", {
  expect_warning(out <- eml_master_n_params(3), "deprecated")
  expect_identical(out, master_n_params(3))
})

test_that("theta_for_ln returns v1 list-of-lists and works with eml_master_eval", {
  suppressWarnings({
    theta_v1 <- theta_for_ln()
  })
  expect_type(theta_v1, "list")
  expect_equal(length(theta_v1), 14)
  expect_named(theta_v1[[1]], c("alpha", "beta", "gamma"))

  xs <- c(0.5, 1, 2, 5)
  suppressWarnings({
    pred <- Re(eml_master_eval(3, xs, theta_v1))
  })
  expect_equal(pred, log(xs), tolerance = 1e-10)
})

test_that("eml_master_eval accepts both v1 list-of-lists and v2 numeric par", {
  xs <- seq(-1, 1, length.out = 5)
  # v2 form
  suppressWarnings({
    pred_v2 <- Re(eml_master_eval(1, xs, theta_for_exp()))
  })
  # v1 form
  v1_theta <- list(list(alpha = 0, beta = 1),
                   list(alpha = 1, beta = 0))
  suppressWarnings({
    pred_v1 <- Re(eml_master_eval(1, xs, v1_theta))
  })
  expect_equal(pred_v1, pred_v2, tolerance = 1e-12)
  expect_equal(pred_v1, exp(xs), tolerance = 1e-12)
})

test_that("unpack_theta returns v1 list-of-lists shape", {
  par <- runif(master_n_params(2))
  suppressWarnings({
    out <- unpack_theta(par, 2)
  })
  expect_type(out, "list")
  expect_equal(length(out), 6)              # slots(2) = 6
  expect_named(out[[1]], c("alpha", "beta", "gamma"))   # inner
  expect_named(out[[2]], c("alpha", "beta"))            # leaf
})

test_that("eml_tree shim warns and accepts left/right children", {
  expect_warning(out <- eml_tree(left = 1, right = "x"), "deprecated")
  expect_identical(out, quote(eml(1, x)))
})
