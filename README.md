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

The pipeline runs end to end: simulated data, local indicators at each site,
the central step that checks and combines what the sites export, and a
dashboard built from the combined table. It all runs in Docker from one
command, and every push to this repository runs the tests and the pipeline
and publishes the dashboard. Still to come: a screenshot and a final pass on
the README.

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

Then build the dashboard:

```sh
quarto render
```

That writes `_site/dashboard/index.html`, which you can open in a browser. It
needs Quarto installed (built with 1.10). The dashboard reads
`data/combined/indicators.csv` and nothing else.

To run the tests (181 of them):

```sh
Rscript -e 'testthat::test_dir("tests/testthat")'
```

## Running it in Docker

If you would rather not install R, Quarto and the packages, everything runs
in a container instead:

```sh
docker build -t fedscreen .
docker run --rm -v "$PWD/_site:/project/_site" fedscreen
```

The build installs R 4.5.2, the exact package versions from `renv.lock` and
Quarto 1.10, then the run does the three steps above: tests, pipeline,
dashboard. The `-v` option maps the container's output folder onto your own,
so when it finishes you can open `_site/dashboard/index.html` on your
machine.

The build takes a few minutes, mostly downloading. It works on both Intel and
Apple Silicon machines: the packages are fetched ready-built for whichever
one you are on, so nothing is compiled.

## Automatic checks

`.github/workflows/pipeline.yml` runs on every push. It restores the pinned
package versions, runs the tests, runs the pipeline, and renders the
dashboard, which is to say it does exactly what this README asks a person to
do. If an instruction here stops working, the run goes red.

It then checks one more thing: the aggregate CSVs in this repository were
just rebuilt from a fixed seed, so if the rebuilt files differ from the
committed ones by so much as a digit, the run fails. That is the claim of
reproducibility, tested rather than asserted.

Finally, on `main`, the rendered dashboard is published to GitHub Pages.

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

## The dashboard

Four pages, built with Quarto and plotly from the combined table:

- **Overview**: every indicator for every site, with confidence intervals, as
  a chart and as a table.
- **Trends**: the same indicators across the three screening years.
- **Sex and age**: the breakdown by sex and by age band, and a table showing
  what suppression hides.
- **About the data**: that the data is simulated, how the federated setup
  works, and the suppression rule in full.

A suppressed cell is shown as the word "suppressed", never as a zero. That
distinction matters: zero means a site looked and found nothing, suppressed
means a site found between 1 and 4 and is not allowed to say. The dashboard
has a table showing both in the same column, and there is a test for it.
