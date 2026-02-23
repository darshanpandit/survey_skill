# Known Survey Design Specifications

Lookup table for major public-use surveys. When the user names one of
these, use the specification below. Always verify against the survey's
current technical documentation — designs can change between waves.

---

## NHANES (CDC/NCHS, United States)

**Design kind**: Taylor
**PSU**: `SDMVPSU`
**Stratum**: `SDMVSTRA`
**Weights** (component-specific — ask the user which component):
- Interview: `WTINT2YR`
- Examination: `WTMEC2YR`
- Lab/subsample: varies by analyte — check data documentation
**Options**: `nest = TRUE`, `survey.lonely.psu = "adjust"`
**Multi-cycle pooling**: When combining cycles, divide weights by number
of cycles. Use the earliest cycle's `SDMVPSU` and `SDMVSTRA`. See
references/advanced-patterns.md for full pooling procedure.

```r
options(survey.lonely.psu = "adjust")
des <- svydesign(id = ~SDMVPSU, strata = ~SDMVSTRA,
                 weights = ~WTMEC2YR, data = df, nest = TRUE)
```

---

## ACS / PUMS (Census Bureau, United States)

**Design kind**: Replicate
**Weight**: `PWGTP` (person), `WGTP` (housing unit)
**Replicate weights**: `PWGTP1`–`PWGTP80` (person), `WGTP1`–`WGTP80` (housing)
**Replication**: type = `"JK1"`, scale = `4/80`, rscales = `rep(1, 80)`, mse = `TRUE`
**Validation**: Expect exactly 80 replicate columns.

```r
repwts <- df[, grep("^PWGTP[0-9]", names(df))]
des <- svrepdesign(weights = ~PWGTP, repweights = repwts,
                   type = "JK1", scale = 4/80, rscales = rep(1, 80),
                   mse = TRUE, data = df)
```

---

## CPS — ASEC (Census Bureau / BLS, United States)

**Design kind**: Replicate
**Weight**: `MARSUPWT` (person), `HSUP_WGT` (household)
**Replicate weights**: `REPWTP1`–`REPWTP160`
**Replication**: type = `"JK1"`, scale = `4/160`, rscales = `rep(1, 160)`, mse = `TRUE`
**Validation**: Expect exactly 160 replicate columns.

```r
repwts <- df[, paste0("REPWTP", 1:160)]
des <- svrepdesign(weights = ~MARSUPWT, repweights = repwts,
                   type = "JK1", scale = 4/160, rscales = rep(1, 160),
                   mse = TRUE, data = df)
```

---

## BRFSS (CDC, United States)

**Design kind**: Taylor
**PSU**: `_PSU`
**Stratum**: `_STSTR`
**Weight**: `_LLCPWT` (combined landline + cell)
**Options**: `nest = TRUE`, `survey.lonely.psu = "adjust"`

```r
options(survey.lonely.psu = "adjust")
des <- svydesign(id = ~`_PSU`, strata = ~`_STSTR`,
                 weights = ~`_LLCPWT`, data = df, nest = TRUE)
```

---

## DHS (USAID/ICF, 90+ countries)

**Design kind**: Taylor
**PSU**: `V001` (cluster number)
**Stratum**: `V023` (or construct from `V024` × `V025` if `V023` absent)
**Weight**: `V005` (women individual) — **MUST divide by 1,000,000**
  - Men: `MV005 / 1e6`
  - Household: `HV005 / 1e6`
**Options**: `nest = TRUE`, `survey.lonely.psu = "adjust"`
**Critical**: Forgetting the ÷ 1e6 rescaling produces astronomically
wrong weighted estimates. Always verify weights are in a reasonable range
(roughly 0.1–10 for most surveys) after rescaling.

```r
df$wt <- df$V005 / 1e6
options(survey.lonely.psu = "adjust")
des <- svydesign(id = ~V001, strata = ~V023,
                 weights = ~wt, data = df, nest = TRUE)
```

---

## MICS (UNICEF, 100+ countries)

**Design kind**: Taylor
**PSU**: `HH1` (cluster number)
**Stratum**: Country-specific — check the survey report
**Weights** (questionnaire-specific):
- Household: `hhweight`
- Women: `wmweight`
- Children under 5: `chweight`
**Options**: `nest = TRUE`, `survey.lonely.psu = "adjust"`

Design is structurally similar to DHS. Always check the country-specific
survey plan document for stratum definitions and any weight rescaling.

---

## YRBS (CDC, United States)

**Design kind**: Taylor
**PSU**: `PSU`
**Stratum**: `STRATUM`
**Weight**: `WEIGHT`
**Options**: `nest = TRUE`

---

## ESS (European Social Survey, 30+ countries)

**Design kind**: Typically weights-only (PSU/strata rarely released)
**Weights**:
- Within-country: `DWEIGHT * PSPWGHT`
- Pooled cross-country: `DWEIGHT * PSPWGHT * PWEIGHT`
**PSU/strata**: Vary by country and round. When available, use them.
When not, use `id = ~1` and note the SE limitation.

```r
df$anweight <- df$DWEIGHT * df$PSPWGHT
des <- svydesign(id = ~1, weights = ~anweight, data = df)
# WARNING: SEs ignore clustering/stratification
```

---

## EU-SILC (Eurostat, EU member states)

**Design kind**: Varies by country
**Weights**:
- Household cross-sectional: `DB090`
- Personal cross-sectional: `RB050`
- Personal longitudinal: `RB060`
**Strata**: `DB040` (region). Full design variables vary by country.
**Note**: Rotational panel — read survey-type-patterns.md for panel
weight selection logic.

---

## NSDUH (SAMHSA, United States)

**Design kind**: Taylor
**PSU**: `VEREP`
**Stratum**: `VESTR`
**Weight**: `ANALWT_C`
**Options**: `nest = TRUE`

---

## SIPP (Census Bureau, United States)

**Design kind**: Varies by panel year — check documentation
**Note**: Panel survey with complex attrition weighting. Recent panels
provide replicate weights. Variable names change across panel years.
Always consult the specific panel's user guide.

---

## Unknown survey

If the survey is not listed here:

1. Ask the user for the technical documentation or sampling report
2. Examine the dataset columns for weight/PSU/strata/replicate patterns
3. Resolve using the inference procedure in SKILL.md Gate 2
4. If the design cannot be determined, do not guess — ask
