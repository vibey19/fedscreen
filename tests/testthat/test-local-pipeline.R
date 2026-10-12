# A tiny site, written out person by person so the counts can be checked by
# hand. 20 people invited, all in 2021, all aged 60-64, 10 female and 10 male.
#
#   person 1      female, screened, FIT positive, colonoscopy, cancer found
#   persons 2-6   female, screened, FIT negative (person 2 later gets an
#                 interval cancer)
#   persons 7-10  female, not screened
#   person 11     male, screened, FIT positive, colonoscopy, nothing found
#   person 12     male, screened, FIT positive, no colonoscopy
#   persons 13-16 male, screened, FIT negative
#   persons 17-20 male, not screened
#
# So the whole site adds up to:
#   invited 20, screened 12, FIT positive 3, FIT negative 9,
#   colonoscopies 2, cancers 1, advanced adenomas 0, interval cancers 1
tiny_cohort <- function(site = "Test site") {
  data.frame(
    person_id = sprintf("T%02d", 1:20),
    site = site,
    sex = c(rep("female", 10), rep("male", 10)),
    age_group = "60-64",
    screening_year = 2021L,
    invited = TRUE,
    screened = c(rep(TRUE, 6), rep(FALSE, 4), rep(TRUE, 6), rep(FALSE, 4)),
    fit_result = c("positive", rep("negative", 5), rep(NA, 4),
                   "positive", "positive", rep("negative", 4), rep(NA, 4)),
    colonoscopy_done = c(TRUE, rep(NA, 9), TRUE, FALSE, rep(NA, 8)),
    finding = c("cancer", rep(NA, 9), "none", rep(NA, 9)),
    interval_cancer = c(NA, TRUE, rep(FALSE, 4), rep(NA, 4),
                        NA, NA, rep(FALSE, 4), rep(NA, 4)),
    stringsAsFactors = FALSE
  )
}

# Write that cohort to a throwaway duckdb file and hand the connection to a
# block of test code. withr::defer, which testthat makes available, closes the
# connection and deletes the file when the test finishes, pass or fail.
with_tiny_db <- function(code, cohort = tiny_cohort()) {
  path <- tempfile(fileext = ".duckdb")
  con <- dbConnect(duckdb::duckdb(shared_home = FALSE), dbdir = path)
  withr::defer({
    dbDisconnect(con, shutdown = TRUE)
    unlink(path)
  })
  dbWriteTable(con, "screening", cohort, overwrite = TRUE)
  code(con)
}

test_that("SQL counts match the hand count for the whole site", {
  with_tiny_db(function(con) {
    counts <- count_cells(con)

    expect_equal(nrow(counts), 1)
    expect_equal(counts$n_invited, 20)
    expect_equal(counts$n_screened, 12)
    expect_equal(counts$n_fit_positive, 3)
    expect_equal(counts$n_fit_negative, 9)
    expect_equal(counts$n_colonoscopy, 2)
    expect_equal(counts$n_cancer, 1)
    expect_equal(counts$n_advanced_adenoma, 0)
    expect_equal(counts$n_interval_cancer, 1)
  })
})

test_that("empty values are not counted as negatives", {
  with_tiny_db(function(con) {
    counts <- count_cells(con)

    # 18 of the 20 people have no colonoscopy value at all, because they were
    # never referred. They must not be counted as "colonoscopy not done", and
    # the 1 person who was referred but did not attend must not be counted as
    # done. So the count is 2, and the completion denominator is the 3 positive
    # FITs, not 20.
    expect_equal(counts$n_colonoscopy, 2)
    expect_equal(counts$n_fit_positive, 3)

    # Likewise interval cancer is only defined for the 9 negative FITs.
    expect_equal(counts$n_interval_cancer, 1)
  })
})

test_that("SQL counts match the hand count by sex", {
  with_tiny_db(function(con) {
    counts <- count_cells(con, "sex")
    female <- counts[counts$sex == "female", ]
    male <- counts[counts$sex == "male", ]

    # female: 10 invited, 6 screened, 1 positive, 5 negative, 1 colonoscopy,
    #         1 cancer, 1 interval cancer
    expect_equal(female$n_invited, 10)
    expect_equal(female$n_screened, 6)
    expect_equal(female$n_fit_positive, 1)
    expect_equal(female$n_cancer, 1)
    expect_equal(female$n_interval_cancer, 1)

    # male: 10 invited, 6 screened, 2 positive, 4 negative, 1 colonoscopy,
    #       0 cancers, 0 interval cancers
    expect_equal(male$n_invited, 10)
    expect_equal(male$n_fit_positive, 2)
    expect_equal(male$n_colonoscopy, 1)
    expect_equal(male$n_cancer, 0)
  })
})

test_that("only known dimensions can be grouped by", {
  with_tiny_db(function(con) {
    # The grouping names are pasted into the SQL text, so anything not on the
    # allowed list has to be refused rather than sent to the database.
    expect_error(count_cells(con, "postcode"), "not a grouping dimension")
    expect_error(count_cells(con, "1; DROP TABLE screening"),
                 "not a grouping dimension")
  })
})

test_that("the aggregate covers every breakdown level once", {
  with_tiny_db(function(con) {
    aggregate <- site_aggregate(con)

    # With 1 year, 2 sexes and 1 age group the six breakdown levels give
    # 1 + 1 + 2 + 1 + 2 + 1 = 8 group cells, and each cell has 8 indicators.
    expect_equal(nrow(aggregate), 64)

    expect_named(aggregate, c(
      "site", "screening_year", "sex", "age_group", "indicator", "measure",
      "numerator", "denominator", "estimate", "ci_lower", "ci_upper",
      "suppressed"
    ))

    # The headline row for the site has "All" in all three dimensions.
    headline <- aggregate[aggregate$screening_year == "All" &
                            aggregate$sex == "All" &
                            aggregate$age_group == "All", ]
    expect_equal(nrow(headline), 8)

    # Participation for the whole site is 12 out of 20.
    participation <- headline[headline$indicator == "participation", ]
    expect_equal(participation$numerator, 12L)
    expect_equal(participation$denominator, 20L)
    expect_equal(participation$estimate, 0.6)
  })
})

test_that("the aggregate leaves no small count behind", {
  with_tiny_db(function(con) {
    aggregate <- site_aggregate(con)

    # This site is deliberately tiny, so most of it has to be suppressed.
    expect_true(any(aggregate$suppressed))
    expect_false(any(is_small_count(aggregate$numerator)))
    expect_false(any(is_small_count(aggregate$denominator)))

    # Every suppressed row has nothing left to work back from.
    hidden <- aggregate[aggregate$suppressed, ]
    expect_true(all(is.na(hidden$estimate)))
    expect_true(all(is.na(hidden$ci_lower)))
    expect_true(all(is.na(hidden$ci_upper)))
  })
})

test_that("the site label comes from the data, and one file means one site", {
  with_tiny_db(function(con) {
    expect_equal(site_name(con), "Test site")
  })

  # Two sites in one database would mean the federated split had been broken.
  two_sites <- rbind(tiny_cohort("Site X"), tiny_cohort("Site Y"))
  with_tiny_db(cohort = two_sites, code = function(con) {
    expect_error(site_name(con), "exactly one site")
  })
})

test_that("the exported CSV reads back as the same table", {
  with_tiny_db(function(con) {
    out_dir <- withr::local_tempdir()

    # run_local_pipeline() needs a path rather than a connection, so write the
    # cohort to its own file first.
    db_path <- file.path(out_dir, "test_site.duckdb")
    write_con <- dbConnect(duckdb::duckdb(shared_home = FALSE), dbdir = db_path)
    dbWriteTable(write_con, "screening", tiny_cohort(), overwrite = TRUE)
    dbDisconnect(write_con, shutdown = TRUE)

    path <- run_local_pipeline(db_path, out_dir = out_dir)
    expect_true(file.exists(path))
    expect_match(basename(path), "^test_site\\.csv$")

    written <- read.csv(path, stringsAsFactors = FALSE)
    expect_equal(nrow(written), 64)
    expect_type(written$suppressed, "logical")

    # A suppressed count must still be missing after the round trip, not 0 and
    # not the string "NA".
    expect_true(any(is.na(written$numerator)))

    participation <- written[written$indicator == "participation" &
                               written$screening_year == "All" &
                               written$sex == "All" &
                               written$age_group == "All", ]
    expect_equal(participation$estimate, 0.6)
  })
})
