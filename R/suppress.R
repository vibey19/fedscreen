# Small-number suppression.
#
# The rule: any count from 1 to 4 is too small to publish, so it is replaced
# by NA and flagged. Anything calculated from a suppressed count goes too,
# because publishing the proportion and the denominator would give the
# suppressed numerator straight back (0.25 of 8 is 2).
#
# A count of 0 is left alone. Zero says nobody is in the cell, so there is
# nobody to identify.
#
# This mirrors what cancer registries do before releasing a table. The exact
# threshold differs between registries. 5 is a common choice and it is the one
# the brief asks for. docs/assumptions.md records the rule and its limits.

# Counts of 1, 2, 3 and 4 are suppressed. 5 and above are published.
SUPPRESSION_THRESHOLD <- 5

#' Is this count too small to publish?
#'
#' Vectorised, and NA-safe: an already missing count counts as not publishable.
is_small_count <- function(x) {
  !is.na(x) & x > 0 & x < SUPPRESSION_THRESHOLD
}

#' Apply suppression to a long indicator table
#'
#' Takes the output of compute_indicators() and returns it with
#'
#'   - numerator and denominator set to NA where they are 1 to 4,
#'   - estimate, ci_lower and ci_upper set to NA if either count was
#'     suppressed, or was already missing,
#'   - a logical `suppressed` column saying what happened to the row.
#'
#' The flag is the point of the exercise. Without it the dashboard cannot tell
#' "too small to show" apart from "no data", and those mean different things.
suppress_small_counts <- function(indicators) {
  required <- c("numerator", "denominator", "estimate", "ci_lower", "ci_upper")
  missing <- setdiff(required, names(indicators))
  if (length(missing) > 0) {
    stop("suppress_small_counts() is missing columns: ",
         paste(missing, collapse = ", "))
  }

  hide_numerator <- is_small_count(indicators$numerator)
  hide_denominator <- is_small_count(indicators$denominator)
  hide_value <- hide_numerator | hide_denominator

  indicators$suppressed <- hide_value

  indicators$numerator[hide_numerator] <- NA_integer_
  indicators$denominator[hide_denominator] <- NA_integer_

  indicators$estimate[hide_value] <- NA_real_
  indicators$ci_lower[hide_value] <- NA_real_
  indicators$ci_upper[hide_value] <- NA_real_

  indicators
}

#' Check that a table is safe to leave the site
#'
#' A last look before an aggregate file is written. If any publishable count
#' is still in the 1 to 4 range then suppression did not run, or ran on the
#' wrong columns, and the export must stop rather than leak. Returns the table
#' unchanged when it passes, so it can sit in the middle of a pipeline.
assert_no_small_counts <- function(indicators) {
  offenders <- is_small_count(indicators$numerator) |
    is_small_count(indicators$denominator)

  if (any(offenders)) {
    stop("refusing to export: ", sum(offenders),
         " cell(s) still hold a count between 1 and ",
         SUPPRESSION_THRESHOLD - 1, call. = FALSE)
  }

  indicators
}
