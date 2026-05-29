test_that("eml_eval matches eml() on simple expressions", {
  expect_equal(eml_eval(quote(eml(1, 1))), eml(1, 1), tolerance = 1e-12)
  expect_equal(eml_eval(quote(eml(0, 1))), 1 + 0i, tolerance = 1e-12)
  expect_equal(eml_eval(quote(eml(x, 1)), list(x = 0.5)),
    eml(0.5, 1),
    tolerance = 1e-12
  )
})

test_that("eml_eval evaluates the K=7 paper expression to log(x)", {
  log_expr <- quote(eml(1, eml(eml(1, x), 1)))
  expect_equal(Re(eml_eval(log_expr, list(x = 2))), log(2),
    tolerance = 1e-12
  )
  expect_equal(Re(eml_eval(log_expr, list(x = 5))), log(5),
    tolerance = 1e-12
  )
})

test_that("eml_eval is vectorised over input bindings", {
  xs <- c(0.5, 1, 2, 3, 5)
  lx <- eml_eval(quote(eml(1, eml(eml(1, x), 1))),
    list(x = xs),
    real = TRUE
  )
  expect_equal(lx, log(xs), tolerance = 1e-12)
})

test_that("eml_eval handles bivariate operations (sub via paper identity)", {
  # x - y = eml(log(x), exp(y)); but here we need to express it in EML.
  # Use the v1 sub construction: sub(x, y) = eml(ln(x), exp(y)).
  ln_x <- quote(eml(1, eml(eml(1, x), 1)))
  exp_y <- quote(eml(y, 1))
  sub_expr <- bquote(eml(.(ln_x), .(exp_y)))
  expect_equal(Re(eml_eval(sub_expr, list(x = 5, y = 2))),
    5 - 2,
    tolerance = 1e-10
  )
})

test_that("eml_eval(real = TRUE) warns on large imaginary residue", {
  # eml(0, -1) has imag part -pi
  expect_warning(
    out <- eml_eval(quote(eml(0, -1)), real = TRUE),
    "exceeds tol"
  )
  expect_equal(out, 1, tolerance = 1e-12)

  # tol = NA disables the check
  expect_silent(eml_eval(quote(eml(0, -1)), real = TRUE, tol = NA))
})

test_that("eml_eval extended-real semantics: -1 from eml(-Inf, e)", {
  # -1 = exp(-Inf) - log(e) = 0 - 1
  z <- eml_eval(
    quote(eml(neg_inf, ee)),
    list(neg_inf = -Inf, ee = exp(1))
  )
  expect_equal(Re(z), -1, tolerance = 1e-12)
})

test_that("eml_eval extended-real semantics: log(0) = -Inf gives +Inf", {
  # Complement of the exp(-Inf) direction above (I4): the log(0) = -Inf
  # branch. eml(1, 0) = exp(1) - log(0) = e - (-Inf) = +Inf; likewise
  # eml(0, 0). These are TESTS.md T1 cases that were otherwise unasserted.
  expect_equal(Re(eml_eval(quote(eml(1, 0)))), Inf)
  expect_equal(Re(eml_eval(quote(eml(0, 0)))), Inf)
})

test_that("eml_eval rejects non-list vars", {
  expect_error(eml_eval(quote(eml(x, 1)), vars = c(x = 1)), "named list")
})

test_that("eml_eval returns complex when real = FALSE", {
  z <- eml_eval(quote(eml(x, 1)), list(x = 1.5))
  expect_true(is.complex(z))
})

# --- 5d. input validation -- security regression ----------------------------
#
# Pre-fix, `eml_eval(quote(system("..."")), list())` executed the
# shell call. The is_eml_expr guard plus parent=emptyenv() eval env
# close that path.

test_that("eml_eval rejects non-EML expressions", {
  expect_error(eml_eval(quote(x + y), list(x = 1, y = 2)), "EML expression")
  expect_error(eml_eval(quote(system("echo X")), list()), "EML expression")
  # Wrapping the malicious call inside an `eml(...)` does not bypass —
  # the recursive is_eml_expr check rejects the inner non-EML call.
  expect_error(
    eml_eval(quote(eml(system("echo X"), 1)), list()),
    "EML expression"
  )
})

test_that("eml_eval rejects unnamed entries in vars", {
  expect_error(eml_eval(quote(eml(x, 1)), list(1)), "named")
})
