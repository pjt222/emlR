test_that("eml() returns complex with the right values", {
  z <- eml(1, 1)
  expect_true(is.complex(z))
  expect_equal(Re(z), exp(1), tolerance = 1e-12)
  expect_equal(Im(z), 0, tolerance = 1e-12)

  expect_equal(eml(0, 1), 1 + 0i, tolerance = 1e-12)
})

test_that("eml() handles complex / extended-real cases", {
  # eml(0, -1) = 1 - i*pi (principal-branch log of -1 is i*pi)
  z <- eml(0, -1)
  expect_equal(Re(z), 1, tolerance = 1e-12)
  expect_equal(Im(z), -pi, tolerance = 1e-12)

  # Extended reals: -1 = exp(-Inf) - log(e) = 0 - 1
  expect_equal(Re(eml(-Inf, exp(1))), -1, tolerance = 1e-12)
})

test_that("eml_real() returns numeric and warns on imaginary residue", {
  expect_equal(eml_real(1, 1), exp(1), tolerance = 1e-12)
  expect_equal(eml_real(0, 1), 1, tolerance = 1e-12)

  # eml(0, -1) has imag part -pi: well above tol, must warn
  expect_warning(out <- eml_real(0, -1), "exceeds tol")
  expect_equal(out, 1, tolerance = 1e-12)

  # tol = NA disables the check
  expect_silent(eml_real(0, -1, tol = NA))
})

test_that("constructors: eml_const, eml_var, eml_node, E, as_eml_expr", {
  expect_identical(eml_const(2), 2)
  expect_identical(eml_var("x"), as.name("x"))
  expect_identical(eml_var(as.name("z")), as.name("z"))
  expect_error(eml_var(""))
  expect_error(eml_var(c("x", "y")))

  expect_identical(eml_node(1, "x"), quote(eml(1, x)))
  expect_identical(Eml(1, "x"), quote(eml(1, x)))

  # K=7 paper expression via Eml()
  built <- Eml(1, Eml(Eml(1, "x"), 1))
  expected <- quote(eml(1, eml(eml(1, x), 1)))
  expect_identical(built, expected)

  # as_eml_expr passes through
  expect_identical(as_eml_expr(2), 2)
  expect_identical(as_eml_expr("x"), as.name("x"))
  expect_identical(as_eml_expr(quote(eml(1, x))), quote(eml(1, x)))
  expect_identical(as_eml_expr(quote(x)), quote(x))
  expect_error(as_eml_expr(c(1, 2)))
  expect_error(as_eml_expr(NULL))
})

test_that("predicates classify correctly", {
  expect_true(is_eml_const(1))
  expect_true(is_eml_const(1 + 0i))
  expect_false(is_eml_const(c(1, 2)))
  expect_false(is_eml_const(quote(x)))

  expect_true(is_eml_var(quote(x)))
  expect_false(is_eml_var("x"))
  expect_false(is_eml_var(1))

  expect_true(is_eml_call(quote(eml(1, x))))
  expect_false(is_eml_call(quote(x + y)))
  expect_false(is_eml_call(quote(x)))
  expect_false(is_eml_call(1))

  expect_true(is_eml_expr(1))
  expect_true(is_eml_expr(quote(x)))
  expect_true(is_eml_expr(quote(eml(1, eml(eml(1, x), 1)))))
  expect_false(is_eml_expr(quote(x + y)))
  expect_false(is_eml_expr(quote(eml(x + 1, 1)))) # child not EML
})

test_that("eml_K returns total node count (paper definition)", {
  expect_identical(eml_K(1), 1L)
  expect_identical(eml_K(quote(x)), 1L)
  expect_identical(eml_K(quote(eml(1, 1))), 3L) # e, paper
  expect_identical(eml_K(quote(eml(x, 1))), 3L) # exp, paper
  # log(x): paper Eq. 5, K = 7
  expect_identical(eml_K(quote(eml(1, eml(eml(1, x), 1)))), 7L)
})

test_that("eml_leafcount preserves v1 semantics", {
  expect_identical(eml_leafcount(quote(eml(1, eml(eml(1, x), 1)))), 4L)
  expect_identical(eml_leafcount(quote(eml(x, 1))), 2L)
  expect_identical(eml_leafcount(1), 1L)
})

test_that("eml_depth returns root-zero depth", {
  expect_identical(eml_depth(1), 0L)
  expect_identical(eml_depth(quote(x)), 0L)
  expect_identical(eml_depth(quote(eml(x, 1))), 1L)
  expect_identical(eml_depth(quote(eml(1, eml(1, x)))), 2L)
  expect_identical(eml_depth(quote(eml(1, eml(eml(1, x), 1)))), 3L)
})

test_that("eml_rpn matches paper for the K=7 log(x) expression", {
  expect_identical(eml_rpn(quote(eml(x, 1))), "x 1 E")
  expect_identical(eml_rpn(quote(eml(1, 1))), "1 1 E")
  expect_identical(
    eml_rpn(quote(eml(1, eml(eml(1, x), 1)))),
    "1 1 x E 1 E E"
  )
})
