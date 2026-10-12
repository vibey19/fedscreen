# testthat runs tests with this folder as the working directory, but the
# project's own scripts use paths relative to the project root (for example
# "R/indicators.R" and "data/sites"). Step up to the root first, then load the
# project code once for all the test files.
library(testthat)

if (file.exists("../../R/indicators.R")) {
  setwd("../..")
}

source("R/indicators.R")
source("R/suppress.R")
