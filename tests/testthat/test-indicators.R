# One tiny set of counts, used by every test in this file. The numbers are
# small enough to do in your head:
#
#   100 people invited
#    60 took part                     participation           60/100 = 0.6
#     6 had a positive FIT            FIT positivity           6/60  = 0.1
#    54 had a negative FIT
#     5 of the 6 had a colonoscopy    colonoscopy completion   5/6   = 0.8333
#     1 cancer found                  cancer detection         1/60  = 16.67 per 1,000
#     2 advanced adenomas found       adv adenoma detection    2/60  = 33.33 per 1,000
#                                     PPV cancer               1/5   = 0.2
#                                     PPV advanced neoplasia  (1+2)/5 = 0.6
#     0 interval cancers              interval cancer rate     0/54  = 0 per 1,000
tiny_counts <- function() {
  data.frame(
    site = "Test site",
    screening_year = "2021",
    sex = "All",
    age_group = "All",
    n_invited = 100L,
    n_screened = 60L,
    n_fit_positive = 6L,
    n_fit_negative = 54L,
    n_colonoscopy = 5L,
    n_cancer = 1L,
    n_advanced_adenoma = 2L,
    n_interval_cancer = 0L,
    stringsAsFactors = FALSE
  )
}

estimate_for <- function(indicators, name) {
  indicators$estimate[indicators$indicator == name]
}

test_that("every indicator gets one row, with its grouping columns kept", {
  out <- compute_indicators(tiny_counts())

  expect_equal(nrow(out), 8)
  expect_setequal(out$indicator, c(
    "participation", "fit_positivity", "colonoscopy_completion",
    "cancer_detection_rate", "advanced_adenoma_detection_rate",
    "ppv_cancer", "ppv_advanced_neoplasia", "interval_cancer_rate"
  ))
  expect_true(all(out$site == "Test site"))
  expect_true(all(out$screening_year == "2021"))
})

test_that("the three proportions come out as expected", {
  out <- compute_indicators(tiny_counts())

  expect_equal(estimate_for(out, "participation"), 0.6)            # 60/100
  expect_equal(estimate_for(out, "fit_positivity"), 0.1)           #  6/60
  expect_equal(estimate_for(out, "colonoscopy_completion"),
               5 / 6, tolerance = 1e-9)                            #  5/6
})

test_that("the two detection rates are per 1,000 screened", {
  out <- compute_indicators(tiny_counts())

  # 1 cancer among 60 screened is 16.666... per 1,000, not 0.0167.
  expect_equal(estimate_for(out, "cancer_detection_rate"),
               16.666667, tolerance = 1e-5)
  expect_equal(estimate_for(out, "advanced_adenoma_detection_rate"),
               33.333333, tolerance = 1e-5)
})

test_that("PPV uses colonoscopies as its denominator, not positive FITs", {
  out <- compute_indicators(tiny_counts())

  # 5 colonoscopies were done, not 6. Using the 6 positive FITs instead would
  # give 1/6 = 0.167 and would understate the PPV.
  expect_equal(estimate_for(out, "ppv_cancer"), 0.2)               # 1/5
  expect_equal(out$denominator[out$indicator == "ppv_cancer"], 5L)
})

test_that("PPV for advanced neoplasia adds cancers and advanced adenomas", {
  out <- compute_indicators(tiny_counts())

  # (1 cancer + 2 advanced adenomas) / 5 colonoscopies = 0.6
  expect_equal(estimate_for(out, "ppv_advanced_neoplasia"), 0.6)
  expect_equal(out$numerator[out$indicator == "ppv_advanced_neoplasia"], 3L)
})

test_that("interval cancer rate uses negative FITs as its denominator", {
  out <- compute_indicators(tiny_counts())

  # 0 interval cancers among the 54 people with a negative FIT. The estimate is
  # a real 0, and only the upper confidence limit carries any information:
  # qchisq(0.975, 2)/2 = 3.688879, so 3.688879/54*1000 = 68.31 per 1,000.
  expect_equal(estimate_for(out, "interval_cancer_rate"), 0)
  expect_equal(out$denominator[out$indicator == "interval_cancer_rate"], 54L)

  ci_upper <- out$ci_upper[out$indicator == "interval_cancer_rate"]
  expect_equal(ci_upper, 3.688879 / 54 * 1000, tolerance = 1e-4)
})

test_that("proportions get Wilson intervals and rates get Poisson ones", {
  out <- compute_indicators(tiny_counts())

  # Participation, 60 out of 100. Checked against wilson_ci() directly.
  participation <- out[out$indicator == "participation", ]
  expect_equal(participation$measure, "proportion")
  expect_equal(participation$ci_lower, wilson_ci(60, 100)$lower)
  expect_equal(participation$ci_upper, wilson_ci(60, 100)$upper)

  cancer <- out[out$indicator == "cancer_detection_rate", ]
  expect_equal(cancer$measure, "rate_per_1000")
  expect_equal(cancer$ci_lower, poisson_rate_ci(1, 60, per = 1000)$lower)

  # Every estimate must sit inside its own interval.
  inside <- out$estimate >= out$ci_lower & out$estimate <= out$ci_upper
  expect_true(all(inside))
})

test_that("an empty cell gives NA rather than a number", {
  empty <- tiny_counts()
  empty[, grep("^n_", names(empty))] <- 0L

  out <- compute_indicators(empty)

  # 0 out of 0 is not 0 and it is not an error. It is unknown.
  expect_true(all(is.na(out$estimate)))
  expect_true(all(is.na(out$ci_lower)))
})

test_that("missing count columns stop the pipeline with a clear message", {
  broken <- tiny_counts()
  broken$n_colonoscopy <- NULL

  expect_error(compute_indicators(broken), "n_colonoscopy")
})
