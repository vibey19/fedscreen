# The pipeline that runs inside a site.
#
# It opens one site's own database, counts people in SQL, turns those counts
# into indicators with confidence intervals, suppresses small cells and writes
# a single aggregate CSV. That CSV is the only thing allowed to leave the site.
# Nothing here ever reads another site's database.

library(DBI)
library(duckdb)

source("R/indicators.R")
source("R/suppress.R")

# The dimensions a site may break its figures down by.
GROUP_DIMENSIONS <- c("screening_year", "sex", "age_group")

# Which breakdowns to export. Each entry is a set of dimensions, and the
# dimensions not listed are collapsed (shown as "All").
#
# Not every combination is here. The full cross of year by sex by age group
# would give cells of a few dozen people, where nearly every count is small
# enough to be suppressed, so the extra rows would be mostly empty. These six
# levels are the ones the dashboard actually uses: a headline figure per site,
# a trend over years, and one-way breakdowns by sex and by age.
BREAKDOWN_LEVELS <- list(
  character(0),
  "screening_year",
  c("screening_year", "sex"),
  c("screening_year", "age_group"),
  "sex",
  "age_group"
)

#' Count people in one site's database
#'
#' The counting is done in SQL because that is what a database is for: it reads
#' the rows once and returns a handful of numbers, instead of pulling 36,000
#' individual records into R first. Everything after this point in the project
#' works on counts only.
#'
#' `by` is any subset of GROUP_DIMENSIONS. An empty `by` counts the whole site.
#'
#' The FILTER clauses carry the NA rules from the data through into the counts.
#' colonoscopy_done is NULL for anyone never referred, and a NULL never passes
#' a WHERE test, so those people are simply not counted. The denominators stay
#' honest without any extra work.
count_cells <- function(con, by = character(0)) {
  unknown <- setdiff(by, GROUP_DIMENSIONS)
  if (length(unknown) > 0) {
    # These names are pasted into SQL, so only known column names are allowed.
    stop("not a grouping dimension: ", paste(unknown, collapse = ", "))
  }

  select_group <- if (length(by) > 0) paste0(paste(by, collapse = ", "), ",") else ""
  group_clause <- if (length(by) > 0) paste("GROUP BY", paste(by, collapse = ", ")) else ""

  sql <- sprintf("
    SELECT
      %s
      COUNT(*) FILTER (WHERE invited)                          AS n_invited,
      COUNT(*) FILTER (WHERE screened)                         AS n_screened,
      COUNT(*) FILTER (WHERE fit_result = 'positive')          AS n_fit_positive,
      COUNT(*) FILTER (WHERE fit_result = 'negative')          AS n_fit_negative,
      COUNT(*) FILTER (WHERE colonoscopy_done)                 AS n_colonoscopy,
      COUNT(*) FILTER (WHERE finding = 'cancer')               AS n_cancer,
      COUNT(*) FILTER (WHERE finding = 'advanced adenoma')     AS n_advanced_adenoma,
      COUNT(*) FILTER (WHERE interval_cancer)                  AS n_interval_cancer
    FROM screening
    %s", select_group, group_clause)

  dbGetQuery(con, sql)
}

#' The site name held in a database
#'
#' Read from the data rather than passed in, so a file cannot be labelled as a
#' site it does not contain. More than one site in one file would mean the
#' federated setup has been broken, so stop.
site_name <- function(con) {
  sites <- dbGetQuery(con, "SELECT DISTINCT site FROM screening ORDER BY site")$site
  if (length(sites) != 1) {
    stop("expected exactly one site in this database, found ", length(sites),
         call. = FALSE)
  }
  sites
}

#' Build the full aggregate table for one open database connection
#'
#' Returns the long, suppressed indicator table for every breakdown level.
site_aggregate <- function(con) {
  site <- site_name(con)

  levels <- lapply(BREAKDOWN_LEVELS, function(by) {
    counts <- count_cells(con, by)

    # Dimensions this level does not break down by are shown as "All", so
    # every row has a value in every column and the dashboard can filter on
    # them without worrying about missing values.
    for (dim in setdiff(GROUP_DIMENSIONS, by)) {
      counts[[dim]] <- "All"
    }
    counts$screening_year <- as.character(counts$screening_year)
    counts$site <- site

    compute_indicators(counts)
  })

  aggregate <- dplyr::bind_rows(levels)
  aggregate <- suppress_small_counts(aggregate)

  aggregate <- dplyr::arrange(
    aggregate,
    .data$indicator, .data$screening_year, .data$sex, .data$age_group
  )

  dplyr::select(
    aggregate,
    "site", "screening_year", "sex", "age_group", "indicator", "measure",
    "numerator", "denominator", "estimate", "ci_lower", "ci_upper",
    "suppressed"
  )
}

#' Where a site's aggregate CSV is written
aggregate_path <- function(site, dir = "data/aggregates") {
  file.path(dir, paste0(gsub(" ", "_", tolower(site)), ".csv"))
}

#' Run the local pipeline for one site
#'
#' Opens the database read only, because a pipeline that only reports should
#' not be able to change the source data.
run_local_pipeline <- function(db_path, out_dir = "data/aggregates") {
  con <- dbConnect(duckdb::duckdb(shared_home = FALSE),
                   dbdir = db_path, read_only = TRUE)
  on.exit(dbDisconnect(con, shutdown = TRUE), add = TRUE)

  aggregate <- site_aggregate(con)

  # The last gate before anything leaves the site.
  assert_no_small_counts(aggregate)

  # Rounded on the way out. Nobody needs 17 significant figures, and a tidy
  # file is easier to read and to diff.
  for (col in c("estimate", "ci_lower", "ci_upper")) {
    aggregate[[col]] <- round(aggregate[[col]], 6)
  }

  dir.create(out_dir, showWarnings = FALSE, recursive = TRUE)
  path <- aggregate_path(aggregate$site[1], out_dir)
  write.csv(aggregate, path, row.names = FALSE)

  message(sprintf("%s: %d aggregate rows (%d suppressed) written to %s",
                  aggregate$site[1], nrow(aggregate),
                  sum(aggregate$suppressed), path))
  path
}

#' Run the local pipeline at every site
#'
#' In a real federated study this loop does not exist: each site runs its own
#' copy of run_local_pipeline() on its own machine and sends the CSV. The loop
#' is only here because all three fictional sites live on one laptop.
run_all_local_pipelines <- function(db_dir = "data/sites",
                                    out_dir = "data/aggregates") {
  db_paths <- sort(list.files(db_dir, pattern = "\\.duckdb$", full.names = TRUE))
  if (length(db_paths) == 0) {
    stop("no site databases in ", db_dir,
         ". Run build_all_sites() from R/simulate.R first.", call. = FALSE)
  }
  vapply(db_paths, run_local_pipeline, character(1), out_dir = out_dir,
         USE.NAMES = FALSE)
}
