# fedscreen

**Federated colorectal cancer screening indicators.**

[![pipeline](https://github.com/vibey19/fedscreen/actions/workflows/pipeline.yml/badge.svg)](https://github.com/vibey19/fedscreen/actions/workflows/pipeline.yml)

**Dashboard: <https://vibey19.github.io/fedscreen/>**

Three fictional screening sites each hold their own individual-level data in
their own local database. Each site runs the same R pipeline on its own data,
computes standard colorectal screening quality indicators (participation, FIT
positivity, colonoscopy completion, detection rates, positive predictive value
and interval cancer rate), suppresses small counts, and exports only aggregate
tables. A central step then collects those tables, checks them against a shared
schema, combines them, and builds a dashboard. The central side never sees a
single individual record.

**All individual-level data here is simulated.** No real screening data is
used, and the simulation parameters are illustrative only. They are not real
Finnish figures and must not be read as real statistics.
[docs/assumptions.md](docs/assumptions.md) lists every parameter used.

![The overview page of the dashboard, showing four headline counts, a notice
that the data is simulated, two charts of indicators by site with confidence
intervals, and a table of the same numbers](docs/images/dashboard.png)

## Why federated

Screening quality indicators are most useful when you can compare programmes,
which usually means comparing across regions or across countries. The data
they are computed from is about identifiable people, and it generally cannot
be copied out of the registry or region that holds it.

Federated analysis is the usual way round this. Instead of moving the data to
the analysis, you move the analysis to the data. Every site runs the same
agreed code on its own records, and the only thing that travels is a small
aggregate table that has already had small counts removed. That is what this
project does, end to end, at a size you can read in an afternoon.

The structure is the point. Indicator definitions live in one file, so every
site computes participation the same way rather than each interpreting it.
Suppression happens before anything is exported, not in the dashboard, so a
small count never leaves the site at all. What a site may send is written down
in advance as a schema, and a file that does not match it is refused with a
message naming the column, the value and the row.

## How it works

```
Site A database  ->  local pipeline  ->  site_a.csv  \
Site B database  ->  local pipeline  ->  site_b.csv   >  check  ->  combine  ->  dashboard
Site C database  ->  local pipeline  ->  site_c.csv  /
```

Everything to the left of the CSVs stays at the site. The central step reads
only the aggregate files. Those files are small, readable and kept in this
repository, so you can see for yourself exactly what a site shares.

One honest note about the demonstration: all three sites run on one machine
here, as three duckdb files. There is no network boundary, so the separation
is in how the code is organised and in what moves between steps, not in
infrastructure. The real version of this would run the local step inside each
site's own environment.

## Run it yourself

You need R (built with 4.5.2) and Quarto (built with 1.10). Open R in the
project root and restore the pinned package versions:

```r
renv::restore()
```

Then run the pipeline:

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

Then build the dashboard, which writes `_site/dashboard/index.html`:

```sh
quarto render
```

And the tests, 181 of them:

```sh
Rscript -e 'testthat::test_dir("tests/testthat")'
```

### In Docker instead

If you would rather not install R, Quarto and the packages at all:

```sh
docker build -t fedscreen .
docker run --rm -v "$PWD/_site:/project/_site" fedscreen
```

The build installs R 4.5.2, the exact package versions from `renv.lock` and
Quarto 1.10. The run does the three steps above: tests, pipeline, dashboard.
The `-v` option maps the container's output folder onto your own, so when it
finishes you can open `_site/dashboard/index.html` on your machine.

The build takes a few minutes, mostly downloading. It works on both Intel and
Apple Silicon machines: the packages are fetched ready-built for whichever one
you are on, so nothing is compiled.

## Indicators

Eight indicators, each with a 95% confidence interval, each defined in
`R/indicators.R` and described with its numerator, its denominator and a plain
explanation in [docs/indicators.md](docs/indicators.md):

- Participation rate
- FIT positivity rate
- Colonoscopy completion
- Cancer detection rate per 1,000 screened
- Advanced adenoma detection rate per 1,000 screened
- PPV of FIT for cancer, and for advanced neoplasia
- Interval cancer rate per 1,000 negative FITs

Proportions get a Wilson score interval and rates get an exact Poisson
interval. Both are written out by hand in `R/indicators.R`, so the maths is
visible rather than hidden inside a package.

Any count between 1 and 4 is suppressed before a site exports anything, which
is how registries protect small groups from being identified. The rule, and
what it does not protect against, is in [docs/assumptions.md](docs/assumptions.md).

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

## Automatic checks

`.github/workflows/pipeline.yml` runs on every push. It restores the pinned
package versions, runs the tests, runs the pipeline, and renders the
dashboard, which is to say it does exactly what this README asks a person to
do. If an instruction here stops working, the run goes red.

It then checks one more thing: the aggregate CSVs in this repository were just
rebuilt from a fixed seed, so if the rebuilt files differ from the committed
ones by so much as a digit, the run fails. Reproducibility is tested rather
than asserted.

On `main`, the rendered dashboard is published to GitHub Pages, so the
published dashboard is always the one built from the code on `main`.

## What this project does not do

- **The data is simulated.** Every number on the dashboard comes from a
  generator with a fixed seed. The parameters are chosen to be believable and
  to make the three sites differ, not to match any real programme.
- **Each row is one invitation, not one followed person.** Nobody is linked
  across screening years, so there is nothing here about repeat participation.
- **Interval cancer is a flag, not a follow-up.** A real interval cancer is a
  cancer diagnosed between a negative screen and the next scheduled round,
  which needs linkage to a cancer registry and a date. Here it is drawn as a
  rare event among people with a negative FIT.
- **Rates are crude.** There is no age standardisation. The age mix is
  identical at all three sites by construction, so comparisons are not
  distorted here, but that is a property of the simulation and would not hold
  for real sites.
- **One test, one pathway.** FIT, then colonoscopy, colorectal cancer only.
- **The suppression threshold is a demonstration.** Counts of 1 to 4 are
  removed, which is a common registry rule, but a real study agrees its
  threshold and its secondary suppression with each data holder.

[docs/assumptions.md](docs/assumptions.md) says all of this in more detail.

## What I would do next with real registry data

- **Agree the schema first.** The schema is the contract between the sites and
  the centre. With real data it would be versioned and agreed before any code
  runs, and a site would be able to check its own export against it without
  sending anything anywhere.
- **Swap the simulation for a connection.** `R/simulate.R` is the only part
  that would go. Everything downstream, the indicator definitions, the
  suppression, the schema check, the combination step, works the same against
  a real local database.
- **Ship the local step as a container to each site.** The site runs it on its
  own machine, keeps its own output, and sends only the aggregate file, with a
  log of exactly what was exported.
- **Add age standardisation.** Real sites have different age mixes, so crude
  rates would not be comparable. Direct standardisation to a European standard
  population, with the crude rates kept alongside.
- **Link to the cancer registry for interval cancers.** Dates, a defined
  window after a negative screen, and the follow-up time that goes with it.
- **Work out the disclosure control properly.** The threshold, secondary
  suppression so a suppressed cell cannot be recovered by subtraction, and a
  written review of what the published tables allow someone to infer.
- **Add the boring operational parts.** Which rounds are included, how late
  colonoscopies are handled, what counts as a valid FIT, and a data quality
  report per site before any indicator is computed.

## Repository layout

```
R/              simulation, indicators, suppression, local pipeline, central step
data/           site databases (not committed), aggregate exports, combined table
schema/         the agreed shape of a site export
dashboard/      the Quarto dashboard and its charts
tests/testthat/ 181 tests
docs/           indicator definitions and every simulation parameter
_targets.R      the pipeline
Dockerfile      the whole thing in a container
```
