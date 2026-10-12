# Indicators

Eight indicators are computed. They are defined once, in `R/indicators.R`, in
the `indicator_definitions` list. Nothing else in the project decides what a
numerator or a denominator is, so this page and the code cannot drift apart:
each entry below is the same numerator and denominator the code uses.

The definitions follow the general style of the European quality assurance
guidelines for colorectal cancer screening. No target or benchmark value is
claimed anywhere in this project, because the data is simulated and inventing
a target to compare invented data against would be meaningless.

## The screening pathway

The indicators follow one path, and each one measures a different step of it.

```
invited  ->  screened (FIT)  ->  FIT positive  ->  colonoscopy  ->  finding
                   |
                   +-------->  FIT negative  ->  interval cancer
```

## The eight indicators

| Indicator | Numerator | Denominator | Reported as | In plain words |
| --- | --- | --- | --- | --- |
| `participation` | People screened | People invited | Proportion | Of the people we invited, how many took the test. |
| `fit_positivity` | Positive FIT results | People screened | Proportion | Of the people who took the test, how many tested positive. |
| `colonoscopy_completion` | Colonoscopies done | Positive FIT results | Proportion | Of the people who tested positive, how many actually had the follow-up colonoscopy. |
| `cancer_detection_rate` | Cancers found | People screened | Rate per 1,000 | How many cancers the programme finds for every 1,000 people it screens. |
| `advanced_adenoma_detection_rate` | Advanced adenomas found | People screened | Rate per 1,000 | How many advanced adenomas (growths likely to become cancer) are found per 1,000 screened. |
| `ppv_cancer` | Cancers found | Colonoscopies done | Proportion | Of the colonoscopies done after a positive test, how many found a cancer. |
| `ppv_advanced_neoplasia` | Cancers plus advanced adenomas | Colonoscopies done | Proportion | Of the colonoscopies done, how many found either a cancer or an advanced adenoma. |
| `interval_cancer_rate` | Interval cancers | People with a negative FIT | Rate per 1,000 | Of the people told their test was negative, how many turned out to have a cancer before their next invitation. |

## Why these denominators

A few of them are easy to get wrong, and getting them wrong changes the number
a lot.

**Colonoscopy completion uses positive FITs, not people screened.** It is
asking how well the programme follows up the people it has already flagged.

**PPV uses colonoscopies done, not positive FITs.** PPV answers "when we looked,
how often did we find something". People who never attended their colonoscopy
cannot tell us anything about what was there, so including them would drag the
PPV down and make a programme with poor follow-up look like a programme with a
poorly performing test. These are two different problems and the indicators
have to keep them apart.

**Detection rates use people screened.** They describe the yield of the whole
screening process, including the people lost at each step, which is what a
programme manager wants to know.

**Interval cancer rate uses people with a negative FIT.** The indicator is
about cancers the test missed, so the denominator is the people the test
reassured.

**"Does not apply" is never counted as "no".** In the data, someone who was
never FIT positive has no colonoscopy value at all, rather than a "no". The
counting is done in SQL with `COUNT(*) FILTER (WHERE ...)`, and an empty value
never passes a `WHERE` test, so those people fall out of both the numerator and
the denominator on their own. This is what keeps 25,000 people who were never
referred out of the colonoscopy completion denominator.

## Confidence intervals

Every indicator carries a 95% confidence interval, which says how much the
figure could move simply because a different group of people happened to be
invited. Both interval functions are written out by hand in `R/indicators.R`
rather than taken from a package, so the arithmetic can be checked.

**Proportions get a Wilson score interval.** The textbook interval (the
estimate plus or minus about two standard errors) can run below 0 or above 1,
and its real coverage is poor when the count is small, which is exactly the
case for cancer detection. The Wilson interval stays inside 0 and 1 and holds
its coverage at small counts.

**Rates per 1,000 get an exact Poisson interval.** Rare counts are treated as
Poisson, and the interval is obtained from chi-squared quantiles. The useful
part is what happens at a count of zero: the exact interval gives 0 up to a
real positive number, while a normal approximation would give 0 to 0 and claim
a certainty the data does not support.

Both are spelled out with worked examples in
`tests/testthat/test-confidence-intervals.R`, where the expected numbers are
written into the test so they can be checked against a textbook.

## Breakdowns

Each site exports every indicator at six levels:

| Level | `screening_year` | `sex` | `age_group` |
| --- | --- | --- | --- |
| Whole site | All | All | All |
| By year | 2021, 2022, 2023 | All | All |
| By year and sex | 2021, 2022, 2023 | female, male | All |
| By year and age group | 2021, 2022, 2023 | All | 55-59 ... 75-79 |
| By sex | All | female, male | All |
| By age group | All | All | 55-59 ... 75-79 |

A dimension that is not broken down holds the literal value `All`, so every row
has a value in every column.

The full three-way cross of year by sex by age group is not exported. Those
cells hold a few dozen people each, so nearly every count in them would be
suppressed, and the rows would carry no information while making the file four
times bigger.

## Output format

Each site writes one CSV to `data/aggregates/`, one row per group per
indicator:

| Column | Meaning |
| --- | --- |
| `site` | Which site, read from the site's own data |
| `screening_year`, `sex`, `age_group` | The group, or `All` |
| `indicator` | One of the eight names above |
| `measure` | `proportion` or `rate_per_1000`, which tells the dashboard how to format the value |
| `numerator`, `denominator` | The counts, or empty if suppressed |
| `estimate` | The proportion, or the rate per 1,000 |
| `ci_lower`, `ci_upper` | The 95% interval, on the same scale as `estimate` |
| `suppressed` | `TRUE` if the cell was too small to publish |

These files are the only thing that leaves a site. See `docs/assumptions.md`
for the suppression rule.
