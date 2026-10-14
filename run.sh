#!/bin/sh
# The whole project, in the order the README describes it.
#
# This is what `docker run` does by default. It is a shell script rather than
# three R calls because rendering the dashboard is a Quarto job, not an R one.

set -e

Rscript -e 'testthat::test_dir("tests/testthat")'
Rscript -e 'targets::tar_make()'
quarto render
