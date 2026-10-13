# Screening quality indicators, and the confidence intervals that go with
# them.
#
# This file is the single place where each indicator is defined. Nothing else
# in the project decides what a numerator or a denominator is. docs/indicators.md
# describes each one in words.
#
# The two confidence interval functions are written out by hand rather than
# taken from a package, so the maths is visible and can be checked against a
# textbook or by hand on a small example.

# ---- Confidence intervals -------------------------------------------------

#' Wilson score confidence interval for a proportion
#'
#' For x successes out of n trials. Used for every proportion in this project.
#'
#' The usual textbook interval (p plus or minus z times the standard error)
#' behaves badly when p is near 0 or 1 or when n is small: it can run below 0
#' or above 1, and its real coverage is poor. That matters here, because
#' screening indicators like cancer detection are exactly the small-numerator
#' case. The Wilson interval solves the score equation instead, so it stays
#' inside 0 and 1 and keeps its coverage at small n.
#'
#' With z the normal quantile for the confidence level:
#'
#'   centre = (p + z^2 / 2n) / (1 + z^2 / n)
#'   half   = z / (1 + z^2 / n) * sqrt( p(1 - p) / n  +  z^2 / 4n^2 )
#'
#' and the interval is centre minus half to centre plus half.
#'
#' Returns a data frame with columns lower and upper, one row per input value.
#' A missing or zero denominator gives NA rather than an error, because the
#' pipeline has cells with no one in them.
wilson_ci <- function(x, n, conf_level = 0.95) {
  z <- qnorm(1 - (1 - conf_level) / 2)

  lower <- rep(NA_real_, length(x))
  upper <- rep(NA_real_, length(x))

  ok <- !is.na(x) & !is.na(n) & n > 0
  if (any(ok)) {
    p <- x[ok] / n[ok]
    n_ok <- n[ok]

    centre <- (p + z^2 / (2 * n_ok)) / (1 + z^2 / n_ok)
    half_width <- (z / (1 + z^2 / n_ok)) *
      sqrt(p * (1 - p) / n_ok + z^2 / (4 * n_ok^2))

    # A proportion cannot leave 0 to 1. The formula can step just outside it
    # when x is 0 or equal to n, so clamp.
    lower[ok] <- pmax(0, centre - half_width)
    upper[ok] <- pmin(1, centre + half_width)
  }

  data.frame(lower = lower, upper = upper)
}

#' Exact (Clopper-Pearson style) Poisson confidence interval for a rate
#'
#' For x events observed among n people, reported per `per` people.
#'
#' Counts of rare events are treated as Poisson. The exact interval inverts
#' the Poisson test, and the standard shortcut is that its limits are
#' chi-squared quantiles:
#'
#'   lower count = qchisq(alpha / 2,       2x)     / 2
#'   upper count = qchisq(1 - alpha / 2, 2(x + 1)) / 2
#'
#' With x = 0 the lower limit is 0 (there is no evidence of any events), and
#' the upper limit is still useful, which is the main reason to prefer the
#' exact interval here: a normal approximation gives a zero-width interval of
#' 0 to 0 for a zero count, which would be a false claim of certainty.
#'
#' Returns a data frame with columns lower and upper, on the per-`per` scale.
poisson_rate_ci <- function(x, n, per = 1000, conf_level = 0.95) {
  alpha <- 1 - conf_level

  lower <- rep(NA_real_, length(x))
  upper <- rep(NA_real_, length(x))

  ok <- !is.na(x) & !is.na(n) & n > 0
  if (any(ok)) {
    x_ok <- x[ok]
    n_ok <- n[ok]

    lower_count <- ifelse(x_ok == 0, 0, qchisq(alpha / 2, 2 * x_ok) / 2)
    upper_count <- qchisq(1 - alpha / 2, 2 * (x_ok + 1)) / 2

    lower[ok] <- per * lower_count / n_ok
    upper[ok] <- per * upper_count / n_ok
  }

  data.frame(lower = lower, upper = upper)
}

# ---- Indicator definitions ------------------------------------------------

# Each definition names the count columns it needs. `numerator` may name more
# than one column, in which case they are added together (that is how PPV for
# advanced neoplasia combines cancers and advanced adenomas).
#
# `measure` picks the confidence interval: proportions get Wilson, rates per
# 1,000 get the exact Poisson interval.
indicator_definitions <- list(
  list(
    name = "participation",
    label = "Participation rate",
    short = "Participation",
    measure = "proportion",
    numerator = "n_screened",
    denominator = "n_invited"
  ),
  list(
    name = "fit_positivity",
    label = "FIT positivity rate",
    short = "FIT positivity",
    measure = "proportion",
    numerator = "n_fit_positive",
    denominator = "n_screened"
  ),
  list(
    name = "colonoscopy_completion",
    label = "Colonoscopy completion",
    short = "Colonoscopy completion",
    measure = "proportion",
    numerator = "n_colonoscopy",
    denominator = "n_fit_positive"
  ),
  list(
    name = "cancer_detection_rate",
    label = "Cancer detection rate per 1,000 screened",
    short = "Cancer detection",
    measure = "rate_per_1000",
    numerator = "n_cancer",
    denominator = "n_screened"
  ),
  list(
    name = "advanced_adenoma_detection_rate",
    label = "Advanced adenoma detection rate per 1,000 screened",
    short = "Advanced adenoma detection",
    measure = "rate_per_1000",
    numerator = "n_advanced_adenoma",
    denominator = "n_screened"
  ),
  list(
    name = "ppv_cancer",
    label = "PPV of FIT for cancer",
    short = "PPV, cancer",
    measure = "proportion",
    numerator = "n_cancer",
    denominator = "n_colonoscopy"
  ),
  list(
    name = "ppv_advanced_neoplasia",
    label = "PPV of FIT for advanced neoplasia",
    short = "PPV, advanced neoplasia",
    measure = "proportion",
    numerator = c("n_cancer", "n_advanced_adenoma"),
    denominator = "n_colonoscopy"
  ),
  list(
    name = "interval_cancer_rate",
    label = "Interval cancer rate per 1,000 negative FITs",
    short = "Interval cancer",
    measure = "rate_per_1000",
    numerator = "n_interval_cancer",
    denominator = "n_fit_negative"
  )
)

#' Indicator labels, for the dashboard
#'
#' `field` is "label" for the full name used in tables and documentation, or
#' "short" for the compact one used on chart axes, where a long name squeezes
#' the plotting area down to nothing on a narrow screen. Both live in
#' indicator_definitions so there is one place to change a name.
indicator_labels <- function(field = "label") {
  if (!field %in% c("label", "short")) {
    stop("field must be label or short, not ", field, call. = FALSE)
  }
  stats::setNames(
    vapply(indicator_definitions, function(d) d[[field]], character(1)),
    vapply(indicator_definitions, function(d) d$name, character(1))
  )
}

# How many people a rate is reported per.
RATE_PER <- 1000

#' Turn a table of counts into one row per indicator
#'
#' `counts` is one row per group (whatever grouping was used) with the count
#' columns n_invited, n_screened, n_fit_positive, n_fit_negative,
#' n_colonoscopy, n_cancer, n_advanced_adenoma and n_interval_cancer. Any
#' grouping columns present are carried through unchanged.
#'
#' The result is long rather than wide: one row per group per indicator. Long
#' is easier to validate against a schema, easier to suppress (one rule, one
#' column) and easier for the dashboard to filter.
compute_indicators <- function(counts) {
  required <- c("n_invited", "n_screened", "n_fit_positive", "n_fit_negative",
                "n_colonoscopy", "n_cancer", "n_advanced_adenoma",
                "n_interval_cancer")
  missing <- setdiff(required, names(counts))
  if (length(missing) > 0) {
    stop("compute_indicators() is missing count columns: ",
         paste(missing, collapse = ", "))
  }

  group_cols <- intersect(c("site", "screening_year", "sex", "age_group"),
                          names(counts))

  blocks <- lapply(indicator_definitions, function(def) {
    numerator <- rowSums(counts[, def$numerator, drop = FALSE])
    denominator <- counts[[def$denominator]]

    if (def$measure == "proportion") {
      estimate <- numerator / denominator
      ci <- wilson_ci(numerator, denominator)
    } else {
      estimate <- RATE_PER * numerator / denominator
      ci <- poisson_rate_ci(numerator, denominator, per = RATE_PER)
    }

    # An empty cell gives 0 / 0. Report that as missing, not as a number.
    estimate[is.na(denominator) | denominator == 0] <- NA_real_

    out <- counts[, group_cols, drop = FALSE]
    out$indicator <- def$name
    out$measure <- def$measure
    out$numerator <- as.integer(numerator)
    out$denominator <- as.integer(denominator)
    out$estimate <- estimate
    out$ci_lower <- ci$lower
    out$ci_upper <- ci$upper
    out
  })

  dplyr::bind_rows(blocks)
}
