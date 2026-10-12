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

Work in progress. Phase 0 (project setup) is done.

## Getting started

You need R (built with 4.5.2). Open R in the project root and restore the
package versions:

```r
renv::restore()
```

More detail on running the pipeline and the dashboard will be added as the
project is built up.
