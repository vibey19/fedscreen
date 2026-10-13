# The whole pipeline, as a dependency graph.
#
# `targets` works out what depends on what, and on a re-run it only redoes the
# steps whose code or inputs have changed. Running it is one command:
#
#   Rscript -e 'targets::tar_make()'
#
# The order below is the federated story in four steps. Each site's data is
# simulated, each site exports aggregates from its own database, and the
# central step reads only those exports.

library(targets)

# Packages the targets need. targets loads them in the process that runs the
# pipeline, so the scripts do not have to.
tar_option_set(packages = c("DBI", "duckdb", "dplyr"))

# Load every function in R/. tar_source() is the targets way of doing this: it
# tracks the files, so editing a function invalidates the targets that use it.
tar_source("R")

list(

  # One duckdb file per site. In a real federated study this step does not
  # exist, because the data is already there.
  tar_target(
    site_databases,
    build_all_sites(),
    format = "file"
  ),

  # What each site runs on its own machine. One aggregate CSV out of each
  # database, and nothing else leaves.
  tar_target(
    site_exports,
    vapply(site_databases, run_local_pipeline, character(1),
           out_dir = "data/aggregates"),
    format = "file"
  ),

  # The shared contract. Tracked as a file, so editing the schema re-runs the
  # validation.
  tar_target(
    aggregate_schema,
    "schema/aggregate_schema.yml",
    format = "file"
  ),

  # The central step: check every export against the schema, refuse the lot if
  # any of them is wrong, and combine the rest into the one table the
  # dashboard reads.
  tar_target(
    combined_indicators,
    build_combined_aggregate(site_exports, schema_path = aggregate_schema),
    format = "file"
  )
)
