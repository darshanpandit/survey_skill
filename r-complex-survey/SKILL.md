---
name: r-complex-survey
description: >
  Use when working with survey microdata in R involving sampling weights,
  stratification, clustering/PSUs, replicate weights, FPC, or multi-stage
  probability designs. Trigger on: svydesign, svyglm, srvyr, NHANES, CPS,
  ACS, BRFSS, DHS, MICS, PUMS, design effects, DEFF, Taylor linearization,
  BRR, jackknife, raking, calibration, post-stratification, Horvitz-Thompson,
  domain estimation, subpopulation analysis, singleton PSU, or any task where
  ignoring the design would produce wrong standard errors. Even if the user
  just says "analyse this survey" or "weighted regression", use this skill.
---

# R Complex Survey Analysis

This skill enforces design-aware analysis in R. Every analysis must pass
through a resolved design object. The agent must never operate on the raw
data frame for estimation, modelling, or tabulation.

Core packages: `survey`, `srvyr`, `haven`, `mitools`.

---

## Mandatory workflow

Every survey analysis follows these gates in order. Do not skip gates.
If a gate cannot be resolved, stop and ask the user.

### Gate 1: Identify the survey type

Determine which structural type applies. This drives weight selection,
pooling rules, and variance strategy downstream. Ask the user if unclear.

| Type | Key signal | Implication |
|---|---|---|
| Cross-sectional | One wave, one sample | Standard single design object |
| Repeated cross-section | Multiple waves, different people each wave | Separate designs per wave; do not pool without explicit pooled weights |
| Panel / longitudinal | Same people tracked over waves | Use longitudinal weights for cross-wave models, cross-sectional weights for single-wave snapshots |
| Two-phase | Cheap phase 1 → expensive phase 2 subsample | Use `twophase()` |
| Multi-frame | Overlapping sampling frames (e.g., landline + cell) | Use `multiframe()` with overlap indicator |
| Establishment | Sampling firms/schools/hospitals, not people | Expect PPS, certainty strata, extreme weight dispersion |

Read `references/survey-type-patterns.md` for detailed decision logic on
each type, especially panel weight selection and repeated cross-section
pooling rules.

### Gate 2: Resolve the design specification

Before writing any analysis code, resolve exactly one design representation.
This is the most consequential decision. Output must be one of:

- **Taylor** → `svydesign()` with PSU + strata + weights
- **Replicate** → `svrepdesign()` with replicate weights
- **Weights-only** → `svydesign(id = ~1, weights = ~wt)` with an explicit
  warning that SEs ignore clustering and stratification

**Resolution procedure:**

1. If the user names a known survey, look it up in `references/known-surveys.md`.
   That file gives the exact variable names, replication parameters, and any
   required transformations (e.g., DHS weights ÷ 1,000,000).
2. If not a known survey, examine the dataset columns:
   - Replicate weight columns present (e.g., `REPWT1`–`REPWT80`)? → Replicate
   - PSU and stratum columns present? → Taylor
   - Only a weight column? → Weights-only
3. If both replicate weights and PSU/strata are present, prefer replicate.
4. If the design cannot be determined, stop and ask. Do not guess.

**You must also resolve:**

- The specific weight variable (many surveys have multiple — identify which
  one matches the user's analysis component)
- Whether `nest = TRUE` is needed (PSU IDs recycled across strata — true for
  most public-use files)
- The `survey.lonely.psu` setting (default to `"adjust"` unless there is a
  reason not to)
- For replicate designs: the replication type, scale, and rscales (these are
  survey-specific and documented in technical notes)

### Gate 3: Validate before proceeding

Before emitting any design object code, verify:

1. All required columns actually exist in the dataset. If any are missing,
   report which ones and stop.
2. The weight variable has no unexpected values (all positive, no NAs in
   analysis rows). Warn if extreme dispersion (max/min > 50).
3. For replicate designs, the expected number of replicate columns matches
   the documentation (e.g., ACS should have exactly 80).

Only after validation: emit the `svydesign()` or `svrepdesign()` call.

### Gate 4: Analyse through the design

All estimation, modelling, and tabulation goes through the design object.

### Gate 5: Report with mandatory diagnostics

Every analysis output must include:
- Weighted estimates with SEs and confidence intervals
- Unweighted sample sizes (per domain if applicable)
- Design effect (DEFF) for key estimates
- The `survey.lonely.psu` setting that was used
- Weight CV if weights were constructed or modified

Flag any estimate where CV > 30% or unweighted n < 20 as potentially
unreliable.

---

## Hard invariants

These rules are non-negotiable. Violating them produces silently wrong results.

1. **Never filter the data frame for domain estimation.** Use `subset()` on
   the design object. Filtering drops PSUs/strata that contribute to variance.
   Point estimates may look the same; SEs will be wrong.

2. **Never mix replicate weights with Taylor linearization.** A design is
   either replicate-based or PSU/strata-based. Not both. If you have replicate
   weights, use `svrepdesign()`. If you have PSU/strata, use `svydesign()`.

3. **Never pool repeated cross-section waves without pooled weights.** Each
   wave gets its own design. Stacking waves into one design without
   survey-provided pooled weights and a combined design spec produces
   nonsense variance estimates.

4. **Never use `lm()`/`glm()`/`table()`/`xtabs()` on survey data.** Use
   `svyglm()`, `svytable()`, and their equivalents. The unweighted versions
   ignore the design entirely.

5. **Always use quasi families for discrete outcomes.** `quasibinomial()` for
   binary, `quasipoisson()` for counts. The non-quasi versions are numerically
   identical but emit warnings about non-integer successes.

6. **Never compare survey models with raw AIC.** `svyglm` is not fitted by
   maximum likelihood. Use `regTermTest()` for nested comparisons. If AIC is
   needed, it uses the Lumley-Scott (2015) adjustment and is not comparable
   to `glm()` AIC.

7. **Always set `survey.lonely.psu` before analysis.** If not set and a
   singleton stratum exists, R will error. Set it explicitly and document
   the choice.

---

## Design-aware modelling

`svyglm()` uses the Binder (1983) sandwich estimator, not MLE. Consequences:
- `anova()` does not work. Use `regTermTest()` (Wald or Rao-Scott LRT).
- Pseudo-R² via `psrsq()` only.
- Predictions with `predict.svyglm()` propagate design-based SEs.

Model selection by type:
- Binary outcome → `svyglm(..., family = quasibinomial())`
- Count outcome → `svyglm(..., family = quasipoisson())`
- Ordinal (Likert, self-rated health) → `svyolr()`
- Survival / time-to-event → `svycoxph()`
- Association in contingency tables → `svyloglin()`
- Chi-squared tests → `svychisq()` (Rao-Scott adjusted, not Pearson)
- t-tests → `svyttest()`

---

## Weight construction pipeline

When building or adjusting weights (not using pre-made ones), the order
is strict:

1. **Base weights** = 1 / inclusion probability (multiply across stages)
2. **Non-response adjustment** (cell-based or propensity model)
3. **Calibration** — one of:
   - `postStratify()` — single cross-classification
   - `rake()` — multiple marginal distributions (most common)
   - `calibrate()` — GREG; handles continuous auxiliaries
4. **Trimming** — `trimWeights()` AFTER calibration, never before

After calibration, check weight efficiency: `1 / (1 + CV²(weights))`.

---

## Reference files

- `references/known-surveys.md` — Canonical design specs for major surveys
  (NHANES, ACS/PUMS, CPS, BRFSS, DHS, MICS, YRBS, ESS, EU-SILC, NSDUH, SIPP).
  Read when the user names a specific survey.

- `references/survey-type-patterns.md` — Decision logic for survey structural
  types. Read at Gate 1 to determine how the survey type affects weight
  selection, pooling, and variance strategy.

- `references/advanced-patterns.md` — Non-obvious, survey-specific procedures:
  multi-cycle pooling, weight rescaling conventions, dual-frame compositing,
  panel attrition strategies, PPS variance estimators, SAE model selection.
  Read when the analysis involves one of these specific situations.
