# What the dashboard needs, kept out of the dashboard.
#
# These functions read the combined table and turn numbers into the strings and
# the shapes the charts and tables want. They live here rather than inside
# index.qmd for two reasons. The dashboard stays short enough to read, and the
# one rule that really matters, that a suppressed cell is shown as the word
# "suppressed" and never as a zero or a blank, becomes a function with a test
# on it instead of a formatting decision buried in a chunk.
#
# The only input is data/combined/indicators.csv. The dashboard never opens a
# site database, and nothing here can, which is the whole point of the
# federated setup.

suppressPackageStartupMessages(library(dplyr))

source("R/indicators.R")   # indicator_labels() and RATE_PER
source("R/suppress.R")     # SUPPRESSION_THRESHOLD, for the note under a chart

# The word shown wherever a suppressed cell would otherwise print a number.
SUPPRESSED_LABEL <- "suppressed"

# Age groups in the order a reader expects, youngest first, with the combined
# row last. Sorting these as plain text would also work here, but it would
# break the first time an age group is named something like "80+".
AGE_ORDER <- c("55-59", "60-64", "65-69", "70-74", "75-79", "All")
SEX_ORDER <- c("female", "male", "All")

# ---- Reading --------------------------------------------------------------

#' Read the combined indicator table
#'
#' Adds the human readable indicator label and puts the grouping columns in a
#' sensible order. Everything downstream works on the result of this.
read_indicators <- function(path = "data/combined/indicators.csv") {
  labels <- indicator_labels("label")
  shorts <- indicator_labels("short")

  indicators <- utils::read.csv(path, stringsAsFactors = FALSE)

  # A typo in an indicator name would otherwise show up as a blank label on a
  # chart, which is the kind of thing nobody notices until an interview.
  unknown <- setdiff(indicators$indicator, names(labels))
  if (length(unknown) > 0) {
    stop("unknown indicator(s) in ", path, ": ",
         paste(unknown, collapse = ", "), call. = FALSE)
  }

  indicators %>%
    mutate(
      # A factor, so charts and tables follow the screening pathway (invited,
      # screened, positive, scoped, found) instead of the alphabet. The levels
      # come from indicator_definitions, so the order is defined once.
      indicator_label = factor(labels[.data$indicator], levels = labels),
      indicator_short = factor(shorts[.data$indicator], levels = shorts),
      age_group = factor(.data$age_group, levels = AGE_ORDER),
      sex = factor(.data$sex, levels = SEX_ORDER)
    )
}

# ---- Picking the rows you want --------------------------------------------

# The exports hold six breakdown levels in one long table, told apart by which
# grouping columns say "All". These three helpers name the levels the dashboard
# uses, so the pages read as "the headline level" rather than as a pile of
# filters.

#' One row per site and indicator, all years, sexes and ages together
headline_level <- function(indicators) {
  indicators %>%
    filter(.data$screening_year == "All", .data$sex == "All",
           .data$age_group == "All")
}

#' One row per site, year and indicator
year_level <- function(indicators) {
  indicators %>%
    filter(.data$screening_year != "All", .data$sex == "All",
           .data$age_group == "All")
}

#' One row per site, group and indicator, for sex or for age_group
#'
#' `dimension` is "sex" or "age_group". The other grouping columns are held at
#' "All", so the rows are all years combined, split only the one way.
group_level <- function(indicators, dimension) {
  if (!dimension %in% c("sex", "age_group")) {
    stop("dimension must be sex or age_group, not ", dimension, call. = FALSE)
  }
  other <- setdiff(c("sex", "age_group"), dimension)

  indicators %>%
    filter(.data$screening_year == "All",
           as.character(.data[[dimension]]) != "All",
           as.character(.data[[other]]) == "All") %>%
    mutate(group = factor(as.character(.data[[dimension]]),
                          levels = levels(.data[[dimension]])))
}

# ---- Turning numbers into text --------------------------------------------

#' Format one estimate, as a percentage or as a rate
#'
#' Proportions read better as percentages, and rates are already per 1,000. A
#' suppressed row has no estimate to show, so it gets the word instead. This is
#' the function that keeps the promise made on the About page.
format_estimate <- function(estimate, measure, suppressed, digits = 1) {
  out <- rep(SUPPRESSED_LABEL, length(estimate))

  show <- !suppressed & !is.na(estimate)
  is_proportion <- show & measure == "proportion"
  is_rate <- show & measure != "proportion"

  out[is_proportion] <- paste0(
    formatC(estimate[is_proportion] * 100, format = "f", digits = digits), "%"
  )
  out[is_rate] <- formatC(estimate[is_rate], format = "f", digits = digits)

  # Not suppressed, but still no estimate. This happens when a denominator is
  # zero, so there is genuinely nothing to report. Saying so beats a stray NA.
  out[!suppressed & is.na(estimate)] <- "no data"
  out
}

#' Format a confidence interval the same way
format_interval <- function(ci_lower, ci_upper, measure, suppressed,
                            digits = 1) {
  lower <- format_estimate(ci_lower, measure, suppressed, digits)
  upper <- format_estimate(ci_upper, measure, suppressed, digits)

  ifelse(lower == SUPPRESSED_LABEL | upper == SUPPRESSED_LABEL,
         SUPPRESSED_LABEL,
         paste(lower, "to", upper))
}

#' How many people a cell was computed from, or the word
format_count <- function(numerator, denominator, suppressed) {
  ifelse(suppressed,
         SUPPRESSED_LABEL,
         paste0(format(numerator, big.mark = ",", trim = TRUE), " / ",
                format(denominator, big.mark = ",", trim = TRUE)))
}

#' Add the two text columns a table can show
#'
#' `display` is the estimate with its interval, `counts` is the numerator over
#' the denominator. Both come out as the word "suppressed" where the cell is
#' suppressed, which is the rule the About page promises and the tests check.
add_display_columns <- function(level) {
  level %>%
    mutate(
      display = paste0(
        format_estimate(.data$estimate, .data$measure, .data$suppressed),
        ifelse(.data$suppressed, "",
               paste0("  (", format_interval(.data$ci_lower, .data$ci_upper,
                                             .data$measure, .data$suppressed),
                      ")"))
      ),
      counts = format_count(.data$numerator, .data$denominator,
                            .data$suppressed)
    )
}

#' Long table in, wide table out: one row per group, one column per site
#'
#' This is the honest version of the whole project, because a wide table of
#' what the sites sent is all the central side ever had.
wide_table <- function(level, row_column, value_column = "display",
                       row_heading = "Indicator") {
  level %>%
    add_display_columns() %>%
    select(all_of(c(row_column, "site", value_column))) %>%
    tidyr::pivot_wider(names_from = "site",
                       values_from = all_of(value_column)) %>%
    rename(!!row_heading := all_of(row_column))
}

#' One row per indicator, one column per site
indicator_table <- function(level, value_column = "display") {
  level %>%
    # pivot_wider keeps the row order it is given, so sort into pathway order
    # first. The factor levels do the sorting.
    arrange(.data$indicator_label) %>%
    wide_table("indicator_label", value_column, row_heading = "Indicator")
}

#' One indicator, one row per group (sex or age band), one column per site
#'
#' Used to show suppression as it really appears: a suppressed cell and a
#' genuine zero sitting next to each other in the same column, told apart.
breakdown_table <- function(level, indicator_name, value_column = "display") {
  rows <- level %>% filter(.data$indicator == indicator_name)

  if (nrow(rows) == 0) {
    stop("no rows for indicator ", indicator_name, call. = FALSE)
  }

  rows %>%
    arrange(.data$group) %>%
    wide_table("group", value_column, row_heading = "Group")
}

# ---- Chart plumbing -------------------------------------------------------

# One colour per site, used on every chart so a site is the same colour
# everywhere. Chosen to stay apart for the most common kinds of colour
# blindness, and to be calm rather than bright.
SITE_COLOURS <- c("Site A" = "#1b6ca8", "Site B" = "#c86a1a",
                  "Site C" = "#4c7a34")

#' Put estimates and intervals on the scale the axis is labelled with
#'
#' Proportions are stored as 0 to 1 and shown as 0 to 100. Rates are already
#' per 1,000. Doing this in one place stops a chart quietly mixing the two.
to_display_scale <- function(level) {
  factor_for <- ifelse(level$measure == "proportion", 100, 1)

  level %>%
    mutate(
      value = .data$estimate * factor_for,
      value_lower = .data$ci_lower * factor_for,
      value_upper = .data$ci_upper * factor_for
    )
}

#' The rows a chart can actually draw, and a note about the rest
#'
#' A suppressed row has no point to plot. Dropping it silently would make a
#' chart that quietly understates how patchy the small groups are, so every
#' chart that drops rows says how many it dropped.
plottable <- function(level) {
  level[!level$suppressed & !is.na(level$estimate), , drop = FALSE]
}

#' A sentence naming what a chart could not show, or nothing
suppressed_note <- function(level) {
  hidden <- sum(level$suppressed)
  if (hidden == 0) return("")
  paste0(hidden, " of ", nrow(level),
         " cells are suppressed and so are not drawn. ",
         "A suppressed cell had a count between 1 and ",
         SUPPRESSION_THRESHOLD - 1, " behind it.")
}

# ---- Headline counts ------------------------------------------------------

#' One count from the headline level, added up over the sites
#'
#' The value boxes at the top of the dashboard need plain totals, for example
#' how many people were invited in all. Every count is already in the table, as
#' the numerator or the denominator of some indicator, so this picks one out
#' rather than recomputing anything.
total_count <- function(indicators, indicator_name, part = "denominator") {
  rows <- headline_level(indicators) %>%
    filter(.data$indicator == indicator_name)

  if (nrow(rows) == 0) {
    stop("no headline row for indicator ", indicator_name, call. = FALSE)
  }
  if (any(rows$suppressed)) {
    return(NA_integer_)   # should never happen at this level, but say so if it does
  }
  sum(rows[[part]])
}

#' A count with thousands separators, for a value box
big_number <- function(x) {
  if (is.na(x)) return(SUPPRESSED_LABEL)
  format(x, big.mark = ",", trim = TRUE)
}
