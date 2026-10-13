# These tests work on the real aggregate files in data/aggregates/, which are
# committed, and on deliberately damaged copies of them. The damaged copies
# are the point: the central step has to refuse them, because in a federated
# study nobody at the centre can look at the source data to work out what went
# wrong.

schema_path <- project_file("schema/aggregate_schema.yml")
schema <- read_aggregate_schema(schema_path)

# Write a copy of a real site export with one thing changed, and return its
# path. The copy goes in a temporary folder that testthat deletes afterwards.
broken_copy <- function(change, from = project_file("data/aggregates/site_a.csv")) {
  raw <- read.csv(from, colClasses = "character")
  raw <- change(raw)
  path <- file.path(withr::local_tempdir(.local_envir = parent.frame()),
                    "site_a.csv")
  write.csv(raw, path, row.names = FALSE)
  path
}

test_that("the real site exports pass the schema", {
  for (path in site_aggregate_paths(project_file("data/aggregates"))) {
    expect_no_error(read_site_aggregate(path, schema))
  }
})

test_that("combining the three sites gives one table with every site in it", {
  combined <- combine_site_aggregates(site_aggregate_paths(project_file("data/aggregates")), schema)

  # 3 sites, 32 group cells each, 8 indicators: 3 * 32 * 8 = 768 rows.
  expect_equal(nrow(combined), 768)
  expect_setequal(combined$site, c("Site A", "Site B", "Site C"))
  expect_equal(length(unique(combined$indicator)), 8)

  # The types survived the trip through the CSV.
  expect_type(combined$numerator, "integer")
  expect_type(combined$estimate, "double")
  expect_type(combined$suppressed, "logical")
})

test_that("a count between 1 and 4 is refused", {
  # The most important test in the file. A site that forgot to suppress, or
  # suppressed the wrong column, must not get its numbers published.
  path <- broken_copy(function(d) {
    d$numerator[5] <- "2"
    d$suppressed[5] <- "FALSE"
    d
  })

  expect_error(read_site_aggregate(path, schema), "between 1 and 4")
  expect_error(read_site_aggregate(path, schema), "row 5")
})

test_that("a column of the wrong type is refused, naming the value and the row", {
  path <- broken_copy(function(d) {
    d$numerator[37] <- "two"
    d
  })

  expect_error(read_site_aggregate(path, schema),
               "column 'numerator': expected whole numbers, found 'two' \\(row 37\\)")
})

test_that("an indicator nobody agreed to is refused", {
  path <- broken_copy(function(d) {
    d$indicator[9] <- "ppv_total"
    d
  })

  expect_error(read_site_aggregate(path, schema), "ppv_total")
})

test_that("a missing column is refused", {
  path <- broken_copy(function(d) {
    d$ci_upper <- NULL
    d
  })

  expect_error(read_site_aggregate(path, schema), "missing column\\(s\\): ci_upper")
})

test_that("an extra column is refused", {
  # Not a harmless extra. A column nobody agreed to is how data leaves a site
  # by accident, so the file is refused rather than trimmed.
  path <- broken_copy(function(d) {
    d$person_count <- "1"
    d
  })

  expect_error(read_site_aggregate(path, schema),
               "unexpected column\\(s\\): person_count")
})

test_that("a suppressed row that still carries its estimate is refused", {
  path <- broken_copy(function(d) {
    row <- which(d$suppressed == "TRUE")[1]
    d$estimate[row] <- "0.5"
    d
  })

  expect_error(read_site_aggregate(path, schema), "flagged as suppressed")
})

test_that("a proportion greater than 1 is refused", {
  path <- broken_copy(function(d) {
    row <- which(d$measure == "proportion" & d$suppressed == "FALSE")[1]
    d$estimate[row] <- "1.4"
    d
  })

  expect_error(read_site_aggregate(path, schema), "greater than 1")
})

test_that("a repeated row is refused", {
  path <- broken_copy(function(d) rbind(d, d[1, ]))

  expect_error(read_site_aggregate(path, schema), "repeat a row")
})

test_that("every problem is reported at once, not just the first", {
  path <- broken_copy(function(d) {
    d$sex[2] <- "unknown"
    d$age_group[3] <- "60to64"
    d
  })

  problem <- tryCatch(read_site_aggregate(path, schema),
                      error = conditionMessage)

  # One error message, both problems named, so a site can fix them in one go
  # rather than discovering them one re-run at a time.
  expect_match(problem, "'unknown'")
  expect_match(problem, "'60to64'")
})

test_that("two files reporting the same site are refused", {
  dir <- withr::local_tempdir()
  one <- file.path(dir, "site_a.csv")
  two <- file.path(dir, "site_a_again.csv")
  file.copy(project_file("data/aggregates/site_a.csv"), one)
  file.copy(project_file("data/aggregates/site_a.csv"), two)

  expect_error(combine_site_aggregates(c(one, two), schema),
               "two files report the same site")
})

test_that("a site that reports a different set of indicators is refused", {
  dir <- withr::local_tempdir()
  full <- file.path(dir, "site_a.csv")
  short <- file.path(dir, "site_b.csv")
  file.copy(project_file("data/aggregates/site_a.csv"), full)

  partial <- read.csv(project_file("data/aggregates/site_b.csv"), colClasses = "character")
  partial <- partial[partial$indicator != "interval_cancer_rate", ]
  write.csv(partial, short, row.names = FALSE)

  expect_error(combine_site_aggregates(c(full, short), schema),
               "different set of indicators")
})

test_that("a rule in the schema with no code behind it is reported", {
  # This keeps the schema honest. If someone adds a rule to the YAML and
  # forgets to write the check, the pipeline says so instead of silently not
  # checking it.
  invented <- schema
  invented$rules <- c(invented$rules,
                      list(list(name = "counts_are_even",
                                description = "made up for this test")))

  good <- read.csv(project_file("data/aggregates/site_a.csv"))
  problems <- rule_problems(good, invented)

  expect_match(paste(problems, collapse = " "), "counts_are_even")
  expect_match(paste(problems, collapse = " "), "no check")
})

test_that("an empty folder of aggregates is refused, not quietly ignored", {
  expect_error(combine_site_aggregates(character(0), schema),
               "no aggregate files")
})

test_that("the combined table is written and reads back the same", {
  dir <- withr::local_tempdir()
  out <- file.path(dir, "indicators.csv")

  path <- build_combined_aggregate(
    site_aggregate_paths(project_file("data/aggregates")),
    schema_path = schema_path,
    out_path = out
  )
  expect_equal(path, out)

  written <- read.csv(out, stringsAsFactors = FALSE)
  expect_equal(nrow(written), 768)

  # The combined file must itself satisfy the schema, apart from holding more
  # than one site.
  expect_equal(sort(unique(written$site)), c("Site A", "Site B", "Site C"))
  expect_false(any(is_small_count(written$numerator)))
})
