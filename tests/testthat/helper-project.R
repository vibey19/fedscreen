# Loading the project code for the tests.
#
# testthat runs each test file with this folder (tests/testthat) as the working
# directory, while the project's own scripts use paths from the project root,
# like "R/indicators.R" and "data/aggregates". Two things follow.
#
# First, the project files source each other with root-relative paths, so we
# switch to the root while they load, then switch back and leave the working
# directory as testthat set it.
#
# Second, any test that reads a real project file has to build the path
# itself, which is what project_file() is for.

library(testthat)

project_root <- normalizePath(
  if (file.exists("../../R/indicators.R")) "../.." else "."
)

#' Build a path from the project root, whatever the working directory is
project_file <- function(...) file.path(project_root, ...)

# source() evaluates in the global environment by default, so the functions
# land where the tests can see them even though this runs inside local().
local({
  previous <- setwd(project_root)
  on.exit(setwd(previous), add = TRUE)

  source("R/indicators.R")
  source("R/suppress.R")
  source("R/local_pipeline.R")
  source("R/central.R")
})
