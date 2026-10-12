# The rule: a count of 1, 2, 3 or 4 is suppressed. 0 is published, 5 and above
# are published.

test_that("only counts from 1 to 4 count as small", {
  expect_equal(
    is_small_count(c(0, 1, 2, 3, 4, 5, 6, NA)),
    c(FALSE, TRUE, TRUE, TRUE, TRUE, FALSE, FALSE, FALSE)
  )
})

# The same tiny site as in test-indicators.R: 100 invited, 60 screened,
# 6 positive FITs, 54 negative, 5 colonoscopies, 1 cancer, 2 advanced
# adenomas, 0 interval cancers.
#
# So four of the eight indicators must be suppressed:
#   cancer_detection_rate            numerator 1
#   ppv_cancer                       numerator 1
#   advanced_adenoma_detection_rate  numerator 2
#   ppv_advanced_neoplasia           numerator 1 + 2 = 3
#
# and four must survive:
#   participation                    60 / 100
#   fit_positivity                    6 / 60
#   colonoscopy_completion            5 / 6     (5 is on the publishable side)
#   interval_cancer_rate              0 / 54    (0 is not suppressed)
suppressed_tiny <- function() {
  counts <- data.frame(
    site = "Test site", screening_year = "2021", sex = "All", age_group = "All",
    n_invited = 100L, n_screened = 60L, n_fit_positive = 6L,
    n_fit_negative = 54L, n_colonoscopy = 5L, n_cancer = 1L,
    n_advanced_adenoma = 2L, n_interval_cancer = 0L,
    stringsAsFactors = FALSE
  )
  suppress_small_counts(compute_indicators(counts))
}

test_that("exactly the four small-numerator indicators are suppressed", {
  out <- suppressed_tiny()

  expect_setequal(
    out$indicator[out$suppressed],
    c("cancer_detection_rate", "ppv_cancer",
      "advanced_adenoma_detection_rate", "ppv_advanced_neoplasia")
  )
  expect_setequal(
    out$indicator[!out$suppressed],
    c("participation", "fit_positivity", "colonoscopy_completion",
      "interval_cancer_rate")
  )
})

test_that("a suppressed row loses its count, its estimate and its interval", {
  out <- suppressed_tiny()
  cancer <- out[out$indicator == "cancer_detection_rate", ]

  # The numerator was 1, so it goes. Publishing the rate or the interval would
  # give it straight back.
  expect_true(is.na(cancer$numerator))
  expect_true(is.na(cancer$estimate))
  expect_true(is.na(cancer$ci_lower))
  expect_true(is.na(cancer$ci_upper))

  # The denominator was 60, which is publishable, so it stays.
  expect_equal(cancer$denominator, 60L)
})

test_that("a count of 5 is published and a count of 0 is published", {
  out <- suppressed_tiny()

  colonoscopy <- out[out$indicator == "colonoscopy_completion", ]
  expect_false(colonoscopy$suppressed)
  expect_equal(colonoscopy$numerator, 5L)

  interval <- out[out$indicator == "interval_cancer_rate", ]
  expect_false(interval$suppressed)
  expect_equal(interval$numerator, 0L)
  expect_equal(interval$estimate, 0)
})

test_that("a small denominator suppresses the row as well", {
  # Only 3 colonoscopies done, so both PPV indicators have a denominator of 3
  # and cannot be published whatever their numerators are.
  counts <- data.frame(
    site = "Test site", screening_year = "2021", sex = "All", age_group = "All",
    n_invited = 100L, n_screened = 60L, n_fit_positive = 6L,
    n_fit_negative = 54L, n_colonoscopy = 3L, n_cancer = 0L,
    n_advanced_adenoma = 0L, n_interval_cancer = 0L,
    stringsAsFactors = FALSE
  )
  out <- suppress_small_counts(compute_indicators(counts))
  ppv <- out[out$indicator == "ppv_cancer", ]

  expect_true(ppv$suppressed)
  expect_true(is.na(ppv$denominator))
  expect_true(is.na(ppv$estimate))

  # The numerator here was 0, which the rule publishes on its own, but the row
  # is suppressed because of the denominator.
  expect_equal(ppv$numerator, 0L)
})

test_that("the export gate refuses a table that still holds a small count", {
  out <- suppressed_tiny()
  expect_equal(assert_no_small_counts(out), out)   # passes, returns unchanged

  # Put a 2 back in, as if suppression had been skipped.
  leaky <- out
  leaky$numerator[1] <- 2L
  expect_error(assert_no_small_counts(leaky), "refusing to export")
})
