# The central step.
#
# It reads the aggregate CSV each site exported, checks every one against the
# shared schema, refuses the whole run if any of them is wrong, and combines
# the good ones into a single table for the dashboard.
#
# It never opens a site database. The only input is the aggregate files, which
# is the point of the whole exercise: by the time data reaches this script,
# every individual record has already been left behind at the site.
#
# The checking is deliberately strict and deliberately noisy. In a federated
# study the central analyst cannot look at the source data to work out why a
# number looks odd, so a file that does not match the agreed contract has to
# stop the pipeline with a message that says exactly what is wrong, rather
# than being quietly tidied up into a plausible looking comparison.

# Quietly, so the pipeline output in CI stays readable.
suppressPackageStartupMessages(library(dplyr))

source("R/suppress.R")   # SUPPRESSION_THRESHOLD and is_small_count()

# Values this far apart count as equal. The exported numbers are rounded to 6
# decimal places, so comparisons have to allow for that.
TOLERANCE <- 1e-6

# ---- The schema -----------------------------------------------------------

#' Read the shared schema
read_aggregate_schema <- function(path = "schema/aggregate_schema.yml") {
  schema <- yaml::read_yaml(path)
  schema$path <- path
  schema
}

schema_column_names <- function(schema) {
  vapply(schema$columns, function(column) column$name, character(1))
}

#' Stop with every problem listed at once
#'
#' Reporting all the problems together matters. Stopping at the first one means
#' a site fixes it, re-runs, and hits the next one, which is a slow way to work
#' when the two sides of the conversation are different organisations.
stop_validation <- function(source, schema_path, problems) {
  stop(
    sprintf("%s does not match %s:\n%s",
            source, schema_path,
            paste0("  - ", problems, collapse = "\n")),
    call. = FALSE
  )
}

# ---- Small helpers --------------------------------------------------------

# An empty field and the literal NA both mean "no value".
is_blank <- function(x) is.na(x) | trimws(x) == ""

#' Point at the offending rows in a message
#'
#' An error that says "column numerator is wrong" sends someone hunting. One
#' that says "'two' (row 37)" does not.
describe_rows <- function(values, bad, max_show = 3) {
  rows <- which(bad)
  shown <- utils::head(rows, max_show)
  labels <- ifelse(is.na(values[shown]), "empty", sprintf("'%s'", values[shown]))
  message_text <- paste(sprintf("%s (row %d)", labels, shown), collapse = ", ")
  hidden <- length(rows) - length(shown)
  if (hidden > 0) {
    message_text <- sprintf("%s, and %d more", message_text, hidden)
  }
  message_text
}

#' Turn text from the CSV into the type the schema asks for
#'
#' Everything is read as text first and converted here, rather than letting
#' read.csv() guess. Guessing is what hides problems: a numerator column
#' holding "two" would come back as text, and a later comparison against a
#' number would fail somewhere far from the cause. Converting here means the
#' complaint names the column, the value and the row.
#'
#' Returns a list with the converted values and a problem message, or NULL if
#' the column was fine.
coerce_column <- function(raw, spec) {
  blank <- is_blank(raw)
  problem <- NULL

  if (spec$type == "character") {
    value <- raw
  } else if (spec$type == "integer") {
    bad <- !blank & !grepl("^-?[0-9]+$", raw)
    if (any(bad)) {
      problem <- sprintf("expected whole numbers, found %s",
                         describe_rows(raw, bad))
    }
    value <- rep(NA_integer_, length(raw))
    usable <- !blank & !bad
    value[usable] <- as.integer(raw[usable])
  } else if (spec$type == "double") {
    value <- suppressWarnings(as.numeric(raw))
    bad <- !blank & is.na(value)
    if (any(bad)) {
      problem <- sprintf("expected numbers, found %s", describe_rows(raw, bad))
    }
  } else if (spec$type == "logical") {
    bad <- !blank & !toupper(raw) %in% c("TRUE", "FALSE")
    if (any(bad)) {
      problem <- sprintf("expected TRUE or FALSE, found %s",
                         describe_rows(raw, bad))
    }
    value <- rep(NA, length(raw))
    usable <- !blank & !bad
    value[usable] <- toupper(raw[usable]) == "TRUE"
  } else {
    stop("the schema asks for an unknown type: ", spec$type, call. = FALSE)
  }

  value[blank] <- NA
  list(value = value, problem = problem)
}

# ---- Column by column checks ----------------------------------------------

#' Check each column against its own entry in the schema
column_problems <- function(df, schema) {
  problems <- character(0)

  for (spec in schema$columns) {
    values <- df[[spec$name]]
    label <- sprintf("column '%s'", spec$name)

    if (isFALSE(spec$missing_ok) && any(is.na(values))) {
      problems <- c(problems, sprintf(
        "%s must always have a value, but %d row(s) are empty (first at row %d)",
        label, sum(is.na(values)), which(is.na(values))[1]
      ))
    }

    if (!is.null(spec$allowed)) {
      bad <- !is.na(values) & !values %in% spec$allowed
      if (any(bad)) {
        problems <- c(problems, sprintf(
          "%s only allows %s, but found %s",
          label, paste(spec$allowed, collapse = ", "),
          describe_rows(values, bad)
        ))
      }
    }

    if (!is.null(spec$pattern)) {
      bad <- !is.na(values) & !grepl(spec$pattern, values)
      if (any(bad)) {
        problems <- c(problems, sprintf(
          "%s must look like %s, but found %s",
          label, spec$pattern, describe_rows(values, bad)
        ))
      }
    }

    if (!is.null(spec$min)) {
      bad <- !is.na(values) & values < spec$min
      if (any(bad)) {
        problems <- c(problems, sprintf(
          "%s must be at least %s, but found %s",
          label, spec$min, describe_rows(values, bad)
        ))
      }
    }
  }

  problems
}

# ---- Checks that span several columns -------------------------------------

# One function per rule listed in the schema, named to match. Keeping the names
# the same means the schema cannot describe a check that does not exist: an
# entry with no function here is itself reported as a problem.
RULE_CHECKS <- list(

  no_small_counts = function(df) {
    bad <- is_small_count(df$numerator) | is_small_count(df$denominator)
    if (!any(bad)) return(character(0))
    sprintf(paste("%d row(s) hold a count between 1 and %d, which must never",
                  "be published (first at row %d)"),
            sum(bad), SUPPRESSION_THRESHOLD - 1, which(bad)[1])
  },

  suppressed_rows_are_empty = function(df) {
    bad <- df$suppressed &
      (!is.na(df$estimate) | !is.na(df$ci_lower) | !is.na(df$ci_upper))
    if (!any(bad)) return(character(0))
    sprintf(paste("%d row(s) are flagged as suppressed but still carry an",
                  "estimate or a confidence interval (first at row %d)"),
            sum(bad), which(bad)[1])
  },

  published_rows_have_an_estimate = function(df) {
    bad <- !df$suppressed & is.na(df$estimate) &
      !is.na(df$denominator) & df$denominator > 0
    if (!any(bad)) return(character(0))
    sprintf(paste("%d row(s) are not suppressed and have people in the",
                  "denominator, but have no estimate (first at row %d)"),
            sum(bad), which(bad)[1])
  },

  estimate_inside_interval = function(df) {
    comparable <- !is.na(df$estimate) & !is.na(df$ci_lower) & !is.na(df$ci_upper)
    bad <- comparable &
      (df$estimate < df$ci_lower - TOLERANCE |
         df$estimate > df$ci_upper + TOLERANCE)
    if (!any(bad)) return(character(0))
    sprintf("%d row(s) have an estimate outside their own confidence interval (first at row %d)",
            sum(bad), which(bad)[1])
  },

  proportions_are_proportions = function(df) {
    is_proportion <- df$measure == "proportion"
    above_one <- is_proportion &
      ((!is.na(df$estimate) & df$estimate > 1 + TOLERANCE) |
         (!is.na(df$ci_upper) & df$ci_upper > 1 + TOLERANCE))
    over_counted <- is_proportion &
      !is.na(df$numerator) & !is.na(df$denominator) &
      df$numerator > df$denominator

    problems <- character(0)
    if (any(above_one)) {
      problems <- c(problems, sprintf(
        "%d proportion row(s) are greater than 1 (first at row %d)",
        sum(above_one), which(above_one)[1]
      ))
    }
    if (any(over_counted)) {
      problems <- c(problems, sprintf(
        "%d proportion row(s) have a numerator larger than their denominator (first at row %d)",
        sum(over_counted), which(over_counted)[1]
      ))
    }
    problems
  },

  key_is_unique = function(df, key = c("site", "screening_year", "sex",
                                       "age_group", "indicator")) {
    identifiers <- do.call(paste, c(df[key], sep = " | "))
    repeated <- duplicated(identifiers)
    if (!any(repeated)) return(character(0))
    sprintf("%d row(s) repeat a row that is already in the table: %s",
            sum(repeated), identifiers[which(repeated)[1]])
  }
)

#' Run every rule the schema lists
rule_problems <- function(df, schema) {
  unlist(lapply(schema$rules, function(rule) {
    check <- RULE_CHECKS[[rule$name]]
    if (is.null(check)) {
      return(sprintf(
        "the schema lists a rule called '%s', but R/central.R has no check for it",
        rule$name
      ))
    }
    if (identical(rule$name, "key_is_unique")) {
      return(check(df, key = unlist(schema$key)))
    }
    check(df)
  }))
}

# ---- Reading one site's file ----------------------------------------------

#' Read and check one site's aggregate export
#'
#' Fails rather than returning anything questionable.
read_site_aggregate <- function(path, schema = read_aggregate_schema()) {
  if (!file.exists(path)) {
    stop("no aggregate file at ", path, call. = FALSE)
  }
  source_label <- basename(path)

  raw <- utils::read.csv(path, colClasses = "character", check.names = FALSE)

  expected <- schema_column_names(schema)
  missing <- setdiff(expected, names(raw))
  # An unexpected column is not a harmless extra. A site that adds a column is
  # sending something nobody agreed to, which in a federated setting is how
  # data gets disclosed by accident, so the file is refused.
  unexpected <- setdiff(names(raw), expected)

  structure_problems <- character(0)
  if (length(missing) > 0) {
    structure_problems <- c(structure_problems,
                            paste("missing column(s):", paste(missing, collapse = ", ")))
  }
  if (length(unexpected) > 0) {
    structure_problems <- c(structure_problems,
                            paste("unexpected column(s):", paste(unexpected, collapse = ", ")))
  }
  if (length(structure_problems) > 0) {
    stop_validation(source_label, schema$path, structure_problems)
  }

  # Convert first. If the types are wrong there is no point checking the
  # values, because every later comparison would be against a guess.
  converted <- list()
  type_problems <- character(0)
  for (spec in schema$columns) {
    result <- coerce_column(raw[[spec$name]], spec)
    converted[[spec$name]] <- result$value
    if (!is.null(result$problem)) {
      type_problems <- c(type_problems,
                         sprintf("column '%s': %s", spec$name, result$problem))
    }
  }
  if (length(type_problems) > 0) {
    stop_validation(source_label, schema$path, type_problems)
  }

  df <- as.data.frame(converted, stringsAsFactors = FALSE)

  problems <- c(column_problems(df, schema), rule_problems(df, schema))
  if (length(problems) > 0) {
    stop_validation(source_label, schema$path, problems)
  }

  df
}

# ---- Combining every site -------------------------------------------------

#' Checks that only make sense once all the sites are together
cross_site_problems <- function(tables, paths) {
  problems <- character(0)

  sites_per_file <- vapply(tables, function(df) length(unique(df$site)), integer(1))
  if (any(sites_per_file != 1)) {
    offenders <- basename(paths[sites_per_file != 1])
    problems <- c(problems, sprintf(
      "each file must hold exactly one site, but %s does not",
      paste(offenders, collapse = ", ")
    ))
  }

  site_names <- unlist(lapply(tables, function(df) unique(df$site)))
  if (anyDuplicated(site_names)) {
    problems <- c(problems, sprintf(
      "two files report the same site: %s",
      paste(unique(site_names[duplicated(site_names)]), collapse = ", ")
    ))
  }

  # Every site runs the same pipeline, so every site should report the same
  # set of indicators. A missing one would leave a silent gap in a comparison,
  # which is worse than a loud failure.
  indicator_sets <- lapply(tables, function(df) sort(unique(df$indicator)))
  reference <- indicator_sets[[1]]
  for (i in seq_along(indicator_sets)) {
    if (!identical(indicator_sets[[i]], reference)) {
      problems <- c(problems, sprintf(
        "%s reports a different set of indicators from %s",
        basename(paths[i]), basename(paths[1])
      ))
    }
  }

  problems
}

#' Read every site's export and combine them into one table
combine_site_aggregates <- function(paths, schema = read_aggregate_schema()) {
  if (length(paths) == 0) {
    stop("there are no aggregate files to combine", call. = FALSE)
  }

  # Each file is checked on its own first, so an error names the site that
  # caused it.
  tables <- lapply(paths, read_site_aggregate, schema = schema)

  problems <- cross_site_problems(tables, paths)
  if (length(problems) > 0) {
    stop_validation(sprintf("the %d site files together", length(paths)),
                    schema$path, problems)
  }

  combined <- dplyr::bind_rows(tables)

  # The key has to be unique across the whole set, not just inside each file.
  combined_problems <- rule_problems(combined, schema)
  if (length(combined_problems) > 0) {
    stop_validation("the combined table", schema$path, combined_problems)
  }

  dplyr::arrange(combined, .data$indicator, .data$site,
                 .data$screening_year, .data$sex, .data$age_group)
}

#' Find the aggregate files a site has exported
site_aggregate_paths <- function(dir = "data/aggregates") {
  sort(list.files(dir, pattern = "\\.csv$", full.names = TRUE))
}

#' Combine the site exports and write the table the dashboard reads
#'
#' Returns the path written, so the targets pipeline can depend on it.
build_combined_aggregate <- function(
    paths = site_aggregate_paths(),
    schema_path = "schema/aggregate_schema.yml",
    out_path = "data/combined/indicators.csv") {

  schema <- read_aggregate_schema(schema_path)
  combined <- combine_site_aggregates(paths, schema)

  dir.create(dirname(out_path), showWarnings = FALSE, recursive = TRUE)
  utils::write.csv(combined, out_path, row.names = FALSE)

  message(sprintf("combined %d site file(s) into %d rows at %s",
                  length(paths), nrow(combined), out_path))
  out_path
}
