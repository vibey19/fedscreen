# The expected numbers here are written out so they can be checked by hand or
# against a textbook, rather than being whatever the code happens to return.
#
# Throughout, z is the 97.5% normal quantile, 1.959964 (near enough 1.96), so
# z^2 is 3.8416.

test_that("Wilson interval matches the textbook example of 5 out of 20", {
  # p = 5/20 = 0.25, n = 20
  #   centre = (0.25 + 3.8416/40) / (1 + 3.8416/20)
  #          = 0.34604 / 1.19208 = 0.29028
  #   half   = (1.96/1.19208) * sqrt(0.25*0.75/20 + 3.8416/1600)
  #          = 1.64435 * sqrt(0.0117760) = 0.17845
  #   so roughly 0.1118 to 0.4687
  ci <- wilson_ci(5, 20)
  expect_equal(ci$lower, 0.111862, tolerance = 1e-5)
  expect_equal(ci$upper, 0.468701, tolerance = 1e-5)
})

test_that("Wilson interval is symmetric around a half", {
  # p = 10/20 = 0.5, so the interval must be the same distance either side.
  # 0.299298 to 0.700702, and those two add up to exactly 1.
  ci <- wilson_ci(10, 20)
  expect_equal(ci$lower, 0.299298, tolerance = 1e-5)
  expect_equal(ci$upper, 0.700702, tolerance = 1e-5)
  expect_equal(ci$lower + ci$upper, 1, tolerance = 1e-9)
})

test_that("Wilson interval stays inside 0 and 1 at the edges", {
  # 0 out of 10. The formula gives a lower limit a hair below zero
  # (centre 0.138769 minus half-width 0.138787), which is clamped to 0.
  # The upper limit is the useful part: still 0.2775, not 0.
  zero <- wilson_ci(0, 10)
  expect_equal(zero$lower, 0)
  expect_equal(zero$upper, 0.277533, tolerance = 1e-5)

  # 20 out of 20 is the mirror image: upper clamped to 1, lower 0.8389.
  all_of_them <- wilson_ci(20, 20)
  expect_equal(all_of_them$lower, 0.838875, tolerance = 1e-5)
  expect_equal(all_of_them$upper, 1)
})

test_that("Wilson interval returns NA for an empty denominator", {
  # 0 out of 0 is not a proportion, so there is nothing to report.
  ci <- wilson_ci(0, 0)
  expect_true(is.na(ci$lower))
  expect_true(is.na(ci$upper))

  missing <- wilson_ci(NA_integer_, 100)
  expect_true(is.na(missing$lower))
})

test_that("Wilson interval is vectorised", {
  ci <- wilson_ci(c(5, 10), c(20, 20))
  expect_equal(nrow(ci), 2)
  expect_equal(ci$lower, c(0.111862, 0.299298), tolerance = 1e-5)
})

test_that("exact Poisson interval matches its chi-squared quantiles", {
  # 10 events among 5,000 people, reported per 1,000.
  # The point estimate is 10/5000*1000 = 2 per 1,000.
  #   lower count = qchisq(0.025, 20)/2 =  4.795389
  #   upper count = qchisq(0.975, 22)/2 = 18.390356
  # per 1,000: 4.795389/5000*1000 = 0.959078
  #            18.390356/5000*1000 = 3.678071
  ci <- poisson_rate_ci(10, 5000, per = 1000)
  expect_equal(ci$lower, 0.959078, tolerance = 1e-5)
  expect_equal(ci$upper, 3.678071, tolerance = 1e-5)

  # The point estimate must sit inside its own interval.
  expect_lt(ci$lower, 2)
  expect_gt(ci$upper, 2)
})

test_that("exact Poisson interval handles a zero count", {
  # 0 events among 1,000 people. The lower limit is 0, but the upper limit is
  # not: qchisq(0.975, 2)/2 = 3.688879, so 3.688879 per 1,000.
  # This is the reason for using the exact interval. A normal approximation
  # would give 0 to 0 here, which claims a certainty the data does not have.
  ci <- poisson_rate_ci(0, 1000, per = 1000)
  expect_equal(ci$lower, 0)
  expect_equal(ci$upper, 3.688879, tolerance = 1e-5)
})

test_that("exact Poisson interval returns NA for an empty denominator", {
  ci <- poisson_rate_ci(0, 0, per = 1000)
  expect_true(is.na(ci$lower))
  expect_true(is.na(ci$upper))
})
