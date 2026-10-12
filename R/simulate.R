# Simulated screening cohorts for three fictional sites.
#
# Every number in this file is invented. The point is to produce data with a
# realistic shape (participation below 100%, positivity of a few percent,
# findings rarer still) so the indicator code and the dashboard have something
# to work with. The parameters are not real Finnish figures and must not be
# read as real statistics. docs/assumptions.md lists all of them.
#
# Each row is one invited person in one screening year. A person invited in
# two years appears as two rows with different ids. That is a simplification:
# real registry data follows the same person across rounds.

library(DBI)
library(duckdb)

# ---- Parameters -----------------------------------------------------------

screening_years <- 2021:2023

age_groups <- c("55-59", "60-64", "65-69", "70-74", "75-79")

# Share of each site-year's invited people falling in each age group. The two
# edge groups are deliberately tiny. That is what makes some result cells land
# in the 1 to 4 range, so the small-number suppression rule has something to
# hide and we can show it working.
age_share <- c(
  "55-59" = 0.02,
  "60-64" = 0.33,
  "65-69" = 0.32,
  "70-74" = 0.30,
  "75-79" = 0.03
)

# The three sites differ on purpose, so the dashboard has a real comparison to
# make. Site B is the weak programme (low participation, high positivity, poor
# colonoscopy follow-up), site C is the strong one, site A sits in between.
# Each site carries its own seed so that regenerating one site does not shift
# the random draws of the others.
site_params <- list(
  "Site A" = list(
    code = "A", seed = 101, invited_per_year = 12000,
    participation = 0.66, positivity = 0.055, colonoscopy_completion = 0.93,
    p_cancer = 0.045, p_advanced_adenoma = 0.22, p_adenoma = 0.25,
    p_interval_cancer = 0.0006
  ),
  "Site B" = list(
    code = "B", seed = 102, invited_per_year = 9000,
    participation = 0.52, positivity = 0.072, colonoscopy_completion = 0.80,
    p_cancer = 0.038, p_advanced_adenoma = 0.19, p_adenoma = 0.24,
    p_interval_cancer = 0.0009
  ),
  "Site C" = list(
    code = "C", seed = 103, invited_per_year = 10500,
    participation = 0.74, positivity = 0.045, colonoscopy_completion = 0.96,
    p_cancer = 0.050, p_advanced_adenoma = 0.24, p_adenoma = 0.26,
    p_interval_cancer = 0.0005
  )
)

# Multipliers applied to a site's base probability. A value of 1 means no
# change. They encode the usual direction of the gradients: women take part a
# little more often, men test positive and have findings more often, and both
# positivity and findings rise with age. Participation falls off at the two
# edge age groups, which are outside the main invited range.
participation_by_sex <- c(female = 1.06, male = 0.94)
participation_by_age <- c("55-59" = 0.92, "60-64" = 0.98, "65-69" = 1.03,
                          "70-74" = 1.02, "75-79" = 0.90)
participation_by_year <- c("2021" = 0.97, "2022" = 1.00, "2023" = 1.03)

positivity_by_sex <- c(female = 0.85, male = 1.20)
positivity_by_age <- c("55-59" = 0.80, "60-64" = 0.90, "65-69" = 1.00,
                       "70-74" = 1.15, "75-79" = 1.30)

# Used for cancer, advanced adenoma and interval cancer.
finding_by_sex <- c(female = 0.85, male = 1.20)
finding_by_age <- c("55-59" = 0.70, "60-64" = 0.85, "65-69" = 1.00,
                    "70-74" = 1.20, "75-79" = 1.40)

# ---- Simulation -----------------------------------------------------------

#' Build the invited cohort for one site
#'
#' Returns one row per invited person per screening year, with the screening
#' pathway filled in: screened or not, FIT result, colonoscopy, finding and
#' interval cancer. Columns that do not apply to a person are NA rather than
#' FALSE or zero, so later counts cannot silently treat "not applicable" as
#' "no". For example colonoscopy_done is NA for anyone who was never FIT
#' positive.
simulate_site <- function(site, params) {
  set.seed(params$seed)

  # One row per stratum first, then repeat each row as many times as there are
  # people in it. rep() on row numbers is the cheap way to go from counts to
  # individual rows.
  strata <- expand.grid(
    screening_year = screening_years,
    age_group = age_groups,
    sex = c("female", "male"),
    stringsAsFactors = FALSE
  )
  strata$n_invited <- round(
    params$invited_per_year * age_share[strata$age_group] * 0.5
  )

  cohort <- strata[rep(seq_len(nrow(strata)), strata$n_invited),
                   c("screening_year", "age_group", "sex")]
  rownames(cohort) <- NULL
  n <- nrow(cohort)

  cohort$site <- site
  cohort$person_id <- sprintf("%s%06d", params$code, seq_len(n))

  # Everyone in this table was invited. The column is kept so the denominator
  # of the participation rate is explicit in the data rather than implied by
  # the number of rows.
  cohort$invited <- TRUE

  # Did the person take part?
  p_screened <- params$participation *
    participation_by_sex[cohort$sex] *
    participation_by_age[cohort$age_group] *
    participation_by_year[as.character(cohort$screening_year)]
  cohort$screened <- rbinom(n, 1, p_screened) == 1

  # FIT result, only for people who took part.
  p_positive <- params$positivity *
    positivity_by_sex[cohort$sex] *
    positivity_by_age[cohort$age_group]
  is_positive <- cohort$screened & rbinom(n, 1, p_positive) == 1
  cohort$fit_result <- NA_character_
  cohort$fit_result[cohort$screened] <- ifelse(is_positive[cohort$screened],
                                               "positive", "negative")

  # Colonoscopy, only offered to people with a positive FIT. Not everyone who
  # is referred actually goes, and that gap is the point of the colonoscopy
  # completion indicator.
  cohort$colonoscopy_done <- NA
  cohort$colonoscopy_done[is_positive] <-
    rbinom(sum(is_positive), 1, params$colonoscopy_completion) == 1
  had_colonoscopy <- !is.na(cohort$colonoscopy_done) & cohort$colonoscopy_done

  # What the colonoscopy found. One uniform draw per person is compared
  # against running totals of the category probabilities, which is the same
  # thing as sampling from the four categories but keeps the per-person
  # multipliers easy to read.
  p_cancer <- params$p_cancer *
    finding_by_sex[cohort$sex] * finding_by_age[cohort$age_group]
  p_advanced <- params$p_advanced_adenoma *
    finding_by_sex[cohort$sex] * finding_by_age[cohort$age_group]
  p_adenoma <- params$p_adenoma

  u <- runif(n)
  finding <- ifelse(
    u < p_cancer, "cancer",
    ifelse(u < p_cancer + p_advanced, "advanced adenoma",
           ifelse(u < p_cancer + p_advanced + p_adenoma, "adenoma", "none"))
  )
  cohort$finding <- NA_character_
  cohort$finding[had_colonoscopy] <- finding[had_colonoscopy]

  # Interval cancer: a cancer found after a negative FIT and before the next
  # scheduled round. Only defined for people with a negative FIT, so everyone
  # else is NA.
  is_negative <- !is.na(cohort$fit_result) & cohort$fit_result == "negative"
  p_interval <- params$p_interval_cancer * finding_by_age[cohort$age_group]
  cohort$interval_cancer <- NA
  cohort$interval_cancer[is_negative] <-
    rbinom(sum(is_negative), 1, p_interval[is_negative]) == 1

  # Fixed column order, so the duckdb table is the same shape every time.
  cohort[, c("person_id", "site", "sex", "age_group", "screening_year",
             "invited", "screened", "fit_result", "colonoscopy_done",
             "finding", "interval_cancer")]
}

#' Write one site's cohort to its own duckdb file
#'
#' Each site gets a separate database file because in a federated setup each
#' site really does have its own database that the others cannot read.
write_site_db <- function(cohort, path) {
  # shared_home = FALSE keeps duckdb from asking about a cache directory for
  # extensions and secrets. We use neither, and it keeps the output quiet.
  con <- dbConnect(duckdb::duckdb(shared_home = FALSE), dbdir = path)
  on.exit(dbDisconnect(con, shutdown = TRUE), add = TRUE)
  dbWriteTable(con, "screening", cohort, overwrite = TRUE)
  path
}

#' Path to a site's database file
site_db_path <- function(site, dir = "data/sites") {
  file.path(dir, paste0(gsub(" ", "_", tolower(site)), ".duckdb"))
}

#' Simulate every site and write the database files
#'
#' Returns the paths written, so the targets pipeline in Phase 3 can depend on
#' them.
build_all_sites <- function(dir = "data/sites") {
  dir.create(dir, showWarnings = FALSE, recursive = TRUE)

  paths <- character(0)
  for (site in names(site_params)) {
    cohort <- simulate_site(site, site_params[[site]])
    path <- site_db_path(site, dir)
    write_site_db(cohort, path)
    message(sprintf("%s: %d rows written to %s", site, nrow(cohort), path))
    paths <- c(paths, path)
  }
  paths
}
