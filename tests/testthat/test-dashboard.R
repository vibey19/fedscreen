# What the dashboard does with the numbers.
#
# These tests are mostly about one promise: a suppressed cell is shown as the
# word "suppressed" and never as a zero or a blank. That promise is made in
# writing on the About page, so it is worth a test rather than a careful eye.

test_that("a proportion is shown as a percentage", {
  expect_equal(format_estimate(0.66, "proportion", FALSE), "66.0%")
  expect_equal(format_estimate(0.0456, "proportion", FALSE), "4.6%")
  expect_equal(format_estimate(1, "proportion", FALSE), "100.0%")
})

test_that("a rate is shown as it is stored, per 1,000", {
  expect_equal(format_estimate(2.13, "rate_per_1000", FALSE), "2.1")
  expect_equal(format_estimate(12.549, "rate_per_1000", FALSE), "12.5")
})

test_that("a suppressed cell is the word, not a number", {
  # The number is NA in a suppressed row anyway, but pass one in to be sure
  # the flag wins. A suppressed cell must never print a value.
  expect_equal(format_estimate(NA_real_, "proportion", TRUE), "suppressed")
  expect_equal(format_estimate(0.66, "proportion", TRUE), "suppressed")
  expect_equal(format_count(NA_integer_, 500L, TRUE), "suppressed")
  expect_equal(format_interval(0.1, 0.2, "proportion", TRUE), "suppressed")
})

test_that("a suppressed cell is never shown as zero", {
  # The whole point: zero is a finding, suppressed is a refusal to say.
  expect_false(grepl("0", format_estimate(NA_real_, "proportion", TRUE)))
  expect_equal(format_estimate(0, "rate_per_1000", FALSE), "0.0")
})

test_that("a real zero is published", {
  expect_equal(format_estimate(0, "proportion", FALSE), "0.0%")
  expect_equal(format_count(0L, 400L, FALSE), "0 / 400")
})

test_that("a missing estimate that is not suppressed says so", {
  # This is a cell with nobody in the denominator, so there is nothing to
  # report. "no data" is honest; a blank would look like a bug.
  expect_equal(format_estimate(NA_real_, "proportion", FALSE), "no data")
})

test_that("format_estimate works on a whole column at once", {
  estimates <- c(0.5, NA, 0.25)
  measures <- c("proportion", "proportion", "proportion")
  suppressed <- c(FALSE, TRUE, FALSE)

  expect_equal(format_estimate(estimates, measures, suppressed),
               c("50.0%", "suppressed", "25.0%"))
})

test_that("an interval reads as lower to upper", {
  expect_equal(format_interval(0.655, 0.665, "proportion", FALSE),
               "65.5% to 66.5%")
  expect_equal(format_interval(1.6, 2.8, "rate_per_1000", FALSE), "1.6 to 2.8")
})

test_that("counts are shown as numerator over denominator", {
  expect_equal(format_count(61168L, 94500L, FALSE), "61,168 / 94,500")
})

# ---- Reading the real combined table --------------------------------------

test_that("the combined table reads with labels attached", {
  indicators <- read_indicators(
    project_file("data", "combined", "indicators.csv")
  )

  expect_equal(nrow(indicators), 768)
  expect_true(all(c("indicator_label", "indicator_short") %in%
                    names(indicators)))
  expect_false(any(is.na(indicators$indicator_label)))
})

test_that("indicators are ordered along the screening pathway", {
  indicators <- read_indicators(
    project_file("data", "combined", "indicators.csv")
  )

  # Alphabetical order would put advanced adenoma first, which tells the story
  # backwards. Participation comes first because that is what happens first.
  expect_equal(as.character(levels(indicators$indicator_label))[1],
               "Participation rate")
  expect_equal(as.character(levels(indicators$indicator_short))[1],
               "Participation")
})

test_that("an unknown indicator name is refused", {
  indicators <- utils::read.csv(
    project_file("data", "combined", "indicators.csv")
  )
  indicators$indicator[1] <- "made_up_indicator"

  path <- withr::local_tempfile(fileext = ".csv")
  utils::write.csv(indicators, path, row.names = FALSE)

  expect_error(read_indicators(path), "made_up_indicator")
})

test_that("the breakdown levels pick out the rows they say they do", {
  indicators <- read_indicators(
    project_file("data", "combined", "indicators.csv")
  )

  # 3 sites x 8 indicators, with nothing split
  expect_equal(nrow(headline_level(indicators)), 24)
  # the same, times 3 screening years
  expect_equal(nrow(year_level(indicators)), 72)
  # times 2 sexes
  expect_equal(nrow(group_level(indicators, "sex")), 48)
  # times 5 age bands
  expect_equal(nrow(group_level(indicators, "age_group")), 120)

  expect_error(group_level(indicators, "screening_year"), "must be sex")
})

test_that("a group level never holds an All row", {
  indicators <- read_indicators(
    project_file("data", "combined", "indicators.csv")
  )

  by_sex <- group_level(indicators, "sex")
  expect_false(any(as.character(by_sex$group) == "All"))
  expect_true(all(as.character(by_sex$age_group) == "All"))
})

test_that("a table shows suppressed cells and real zeros side by side", {
  indicators <- read_indicators(
    project_file("data", "combined", "indicators.csv")
  )
  by_age <- group_level(indicators, "age_group")

  table <- breakdown_table(by_age, "cancer_detection_rate")
  oldest <- table[table$Group == "75-79", ]

  # Site B found no cancers in the oldest band, Site A found between 1 and 4.
  # One of those is published and the other is not, and the table has to tell
  # them apart. This is the example the dashboard points at.
  expect_true(any(grepl("^0.0", unlist(oldest[-1]))))
  expect_true(any(unlist(oldest[-1]) == "suppressed"))
})

test_that("charts are never handed a suppressed row", {
  indicators <- read_indicators(
    project_file("data", "combined", "indicators.csv")
  )
  by_age <- group_level(indicators, "age_group")

  drawable <- plottable(by_age)
  expect_false(any(drawable$suppressed))
  expect_false(any(is.na(drawable$estimate)))
  expect_lt(nrow(drawable), nrow(by_age))   # something really was dropped
})

test_that("a chart that drops rows says how many", {
  indicators <- read_indicators(
    project_file("data", "combined", "indicators.csv")
  )

  note <- suppressed_note(group_level(indicators, "age_group"))
  expect_match(note, "16 of 120")
  expect_match(note, "between 1 and 4")

  # Nothing hidden, nothing to say.
  expect_equal(suppressed_note(headline_level(indicators)), "")
})

test_that("proportions are put on a percent scale and rates are left alone", {
  indicators <- read_indicators(
    project_file("data", "combined", "indicators.csv")
  )
  scaled <- to_display_scale(headline_level(indicators))

  participation <- scaled[scaled$indicator == "participation" &
                            scaled$site == "Site A", ]
  expect_equal(participation$value, participation$estimate * 100)

  cancer <- scaled[scaled$indicator == "cancer_detection_rate" &
                     scaled$site == "Site A", ]
  expect_equal(cancer$value, cancer$estimate)
})

test_that("the headline counts match the simulation", {
  indicators <- read_indicators(
    project_file("data", "combined", "indicators.csv")
  )

  # 12,000 + 9,000 + 10,500 invited a year, over three years.
  expect_equal(total_count(indicators, "participation"), 94500)
  expect_equal(big_number(94500), "94,500")
})
