# fedscreen

**Federated colorectal cancer screening indicators.**

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

Work in progress. The pipeline runs end to end: simulated data, local
indicators at each site, and the central step that checks and combines what
the sites export. The dashboard is still to come.

## Getting started

You need R (built with 4.5.2). Open R in the project root and restore the
package versions:

```r
renv::restore()
```

Then run the whole pipeline:

```sh
Rscript -e 'targets::tar_make()'
```

That takes about a second and does four things in order:

1. **Simulate** one duckdb database per site into `data/sites/`. These files
   are not kept in the repository, because they stand in for data that is not
   allowed to leave a site. They are rebuilt from a fixed seed, so everyone
   gets identical data.
2. **Run the local pipeline** at each site, which is the step that in a real
   federated study would run on the site's own machine. Each site writes one
   aggregate CSV to `data/aggregates/`.
3. **Check** every export against `schema/aggregate_schema.yml`. If a site
   sends something that does not match the agreed shape, the pipeline stops
   and says exactly what is wrong.
4. **Combine** the checked exports into `data/combined/indicators.csv`, which
   is the only file the dashboard reads.

`targets` keeps track of what depends on what, so a second run with nothing
changed does nothing, and changing the schema re-runs the checking without
re-simulating the data.

To run the tests (138 of them):

```sh
Rscript -e 'testthat::test_dir("tests/testthat")'
```

## How the federated part works

```
Site A database  ->  local pipeline  ->  site_a.csv  \
Site B database  ->  local pipeline  ->  site_b.csv   >  check  ->  combine  ->  dashboard
Site C database  ->  local pipeline  ->  site_c.csv  /
```

Everything to the left of the CSVs stays at the site. The central step reads
only the aggregate files, so no individual record ever reaches it. The
aggregate files are small, readable and kept in the repository, so you can see
for yourself exactly what a site shares.

Each file is checked against a schema that both sides agree on in advance:
the columns, the types, the allowed values, and rules such as "no count
between 1 and 4 may ever appear" and "a suppressed row carries no estimate".
A file that breaks any of them is refused, with a message naming the column,
the value and the row.

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
