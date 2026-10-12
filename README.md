# Federated colorectal cancer screening indicators

This project is a small, working example of federated analysis for cancer
screening statistics. Three fictional screening sites each hold their own
individual-level data in their own local database. Each site runs the same R
pipeline on its own data, computes standard colorectal screening quality
indicators (participation, FIT positivity, colonoscopy completion, detection
rates, positive predictive value and interval cancer rate), suppresses small
counts, and exports only aggregate tables. A central script then collects those
aggregate tables, checks them against a shared schema, and combines them into
one set of comparison outputs and a dashboard. The central side never sees a
single individual record.

**All individual-level data here is simulated.** No real screening data is used,
and the simulation parameters are illustrative only. They are not real Finnish
figures and must not be read as real statistics. See `docs/assumptions.md` for
every parameter used.

## Status

Work in progress. The simulated data, the indicators and the local pipeline
are in place (phases 1 and 2). The central combination step and the dashboard
are still to come.

## Getting started

You need R (built with 4.5.2). Open R in the project root and restore the
package versions:

```r
renv::restore()
```

Then generate the three site databases:

```r
source("R/simulate.R")
build_all_sites()
```

That writes one duckdb file per site into `data/sites/`. Those files are not
kept in the repository, because they stand in for data that is not allowed to
leave a site. They are rebuilt from a fixed seed, so everyone gets identical
data.

Then run the local pipeline at each site. This is the step that in a real
federated study would run on the site's own machine:

```r
source("R/local_pipeline.R")
run_all_local_pipelines()
```

Each site writes one aggregate CSV to `data/aggregates/`. Those files are
small and are kept in the repository, because they are what a site is allowed
to share.

To run the tests:

```sh
Rscript -e 'testthat::test_dir("tests/testthat")'
```

## Indicators

Eight indicators, each with a 95% confidence interval, each defined in
`R/indicators.R` and described with its numerator and denominator in
[docs/indicators.md](docs/indicators.md):

- Participation rate
- FIT positivity rate
- Colonoscopy completion
- Cancer detection rate per 1,000 screened
- Advanced adenoma detection rate per 1,000 screened
- PPV of FIT for cancer, and for advanced neoplasia
- Interval cancer rate per 1,000 negative FITs

Proportions get a Wilson score interval and rates get an exact Poisson
interval. Both are written out by hand in `R/indicators.R`.

Any count between 1 and 4 is suppressed before a site exports anything, which
is how registries protect small groups from being identified. The rule is
described in [docs/assumptions.md](docs/assumptions.md).

More detail on the dashboard will be added as the project is built up.
