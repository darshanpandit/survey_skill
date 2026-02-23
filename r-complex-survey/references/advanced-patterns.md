# Advanced Patterns

Non-obvious procedures that apply in specific survey situations. Read this
file when the analysis involves one of these scenarios. Each pattern
includes the conditions under which it applies and the specific steps to
execute.

---

## Multi-cycle pooling (NHANES)

**When**: The user wants to analyse multiple NHANES cycles combined for
larger sample size or to include variables that span cycles.

**Procedure**:
1. Stack the cycle data frames (ensure variable names are harmonised across
   cycles — some variables change names or coding between cycles).
2. Create the pooled weight: divide each cycle's weight by the number of
   cycles being combined. For example, combining 3 cycles:
   `pooled_wt = original_wt / 3`
3. Use the **earliest cycle's** `SDMVPSU` and `SDMVSTRA` for the design.
   If strata or PSU definitions changed across cycles, consult the NHANES
   analytic guidelines — NCHS sometimes provides bridged design variables.
4. Verify that the analyte/variable of interest was collected in all cycles
   being pooled. If it was only in a subsample, use the subsample weight
   before dividing.

**Invariant**: Do not pool cycles that use different sampling frames or
have incompatible weight structures without explicit NCHS guidance.

**Reference**: NHANES Analytic Guidelines (CDC/NCHS), updated periodically.

---

## DHS weight rescaling

**When**: Working with any DHS dataset.

**Procedure**: DHS stores weights as integers scaled by 1,000,000.
Divide by 1e6 before use. This applies to:
- `V005` (women individual recode)
- `MV005` (men)
- `HV005` (household)
- Any other weight variable in DHS files

**Validation**: After rescaling, weights should be roughly in the range
0.1–10 for most surveys. If you see weights in the millions, the
rescaling was missed. If weights are all zero or negative, something
else is wrong.

**Why this matters**: Using unrescaled weights produces estimates that
are numerically correct in relative terms (proportions, means) but
totals will be off by 10⁶ and some functions may have numerical
instability with extreme weight values.

---

## Dual-frame compositing (landline + cell)

**When**: The survey samples from two overlapping frames (typically
landline telephone and cellphone), and the user needs to combine them.

**Two approaches**:

**Approach 1 — Survey provides combined weights**: Most modern dual-frame
surveys (BRFSS, NHIS post-redesign) already provide a combined weight
that accounts for overlap. Use this weight directly in a single design.
This is the common case.

**Approach 2 — Separate frames, manual compositing**: Use `multiframe()`
when frames are provided separately with an overlap indicator.

Steps:
1. Create a design object for each frame
2. Identify overlap: each unit must be classified as frame-A-only,
   frame-B-only, or in-both
3. Call `multiframe()` with overlap indicator
4. Choose compositing: optimal (minimum variance, requires estimating
   overlap domain variances) or equal (simpler, slightly less efficient)

**Common in**: Older BRFSS designs, custom telephone surveys, any survey
transitioning from single-frame to dual-frame.

---

## Panel attrition weight adjustment

**When**: Analysing later waves of a panel survey where cumulative
non-response has made the remaining sample unrepresentative.

**Procedure**:
1. The survey usually provides wave-specific weights that already adjust
   for attrition. Use these directly — do not try to construct your own
   unless the documentation says otherwise.
2. Check the weight distribution at later waves. Attrition-adjusted
   weights become increasingly dispersed. If max/min > 50 or
   CV(weights) > 1, consider trimming and recalibrating.
3. For longitudinal analysis spanning waves, use the longitudinal weight
   (adjusts for cumulative attrition through the final wave used). For a
   single-wave cross-sectional snapshot, use that wave's cross-sectional
   weight.

**Multiple imputation alternative**: Some panels (e.g., Understanding
Society) recommend multiple imputation for item non-response alongside
attrition weighting. Use `mitools::imputationList()` with `svydesign()`
to combine both approaches.

---

## PPS variance estimation for establishment surveys

**When**: Sampling firms or organisations with probability proportional
to size (number of employees, revenue, beds, enrollment, etc.) without
replacement.

**The problem**: Standard Taylor linearization in `svydesign()` assumes
with-replacement sampling by default. For PPS without replacement, the
Horvitz-Thompson variance estimator is more appropriate but requires
pairwise inclusion probabilities.

**Options in `svydesign()`**:
- `pps = "brewer"` — Brewer's approximation (requires only first-order
  inclusion probabilities)
- `pps = HR()` — Hartley-Rao approximation
- `pps = ppsmat(joint_probs)` — exact Horvitz-Thompson using a matrix
  of pairwise inclusion probabilities (rarely available in practice)
- `variance = "YG"` — Yates-Grundy estimator (alternative to HT; often
  more stable)

**Certainty units**: Large establishments sampled with probability 1 form
a take-all stratum. They contribute to totals but not to variance. Handle
them as a separate certainty stratum, or they will create singleton PSU
errors.

---

## Small area estimation (SAE)

**When**: The user needs reliable estimates for domains (geographic areas,
demographic subgroups) where the direct survey estimate has unacceptably
high variance — typically CV > 30% or unweighted n < 20.

**Direct estimate first**: Always compute the direct estimate (`svyby()`
by domain) and its CV. If CVs are acceptable, SAE is unnecessary.

**Area-level model (Fay-Herriot)**: Use `survey::smoothArea()`.
- Input: direct estimates by area + area-level covariates (e.g., from
  census or administrative data)
- The model borrows strength across areas via a random effect
- Appropriate when only area-level summaries are available

**Unit-level model**: Use `survey::smoothUnit()`.
- Input: individual-level survey data + area-level covariates
- More efficient than area-level when individual data is available
- Requires a linking model (typically mixed-effects)

**Benchmarking**: Model-based SAE estimates will not sum to the reliable
direct estimate at a higher aggregation level. Apply benchmarking
constraints to ensure internal consistency — this is expected by users
who work with official statistics.

**When not to use SAE**: If the domain of interest was deliberately
oversampled in the design (e.g., minority oversample in NHANES), the
direct estimate may be adequate. Check the design documentation for
deliberate domain oversamples before resorting to SAE.

---

## Calibration convergence issues

**When**: `rake()` or `calibrate()` fails to converge, or converges to
extreme weights.

**Diagnostic steps**:
1. Check that population margins are compatible with the sample — if
   a calibration cell has zero or very few sample observations, the
   algorithm cannot match the target.
2. Inspect the resulting weight distribution. If convergence succeeded
   but weights are extreme (some very large, some near zero), the
   calibration targets may be too fine-grained for the sample.
3. Try wider bounds in `calibrate()` (`bounds` argument) or increase
   iterations in `rake()` (`control` argument).

**Solutions**:
- Collapse sparse calibration categories (combine age groups, merge
  small geographic areas)
- Use `calibrate()` with bounded weights instead of `rake()`
- Apply `trimWeights()` after calibration and accept small deviations
  from targets

**Invariant**: Never trim weights before calibration — the trimmed
weights will not match population targets, and the subsequent calibration
will try to compensate, producing even more extreme adjustments.

---

## Combining survey data with multiple imputation

**When**: The survey has missing data handled by multiple imputation
(either provided by the survey producer or generated by the analyst).

**Procedure**:
1. Create a list of completed datasets (one per imputation)
2. Wrap in `mitools::imputationList()`
3. Pass to `svydesign()` — it returns an `svyimputationList` object
4. Analyse with `with()` — runs the analysis on each imputation
5. Combine results with `MIcombine()` — applies Rubin's rules

```r
imp_list <- imputationList(list(df_imp1, df_imp2, ..., df_imp_m))
des <- svydesign(id = ~psu, strata = ~stratum, weights = ~wt, data = imp_list)
results <- with(des, svyglm(y ~ x1 + x2))
combined <- MIcombine(results)
```

**Key**: The same design specification applies to all imputations — only
the imputed values differ, not the design variables or weights.

---

## Variance estimation method selection

**When**: The user needs to choose between Taylor linearization and a
specific replication method.

**Decision logic**:
- If the data provides replicate weights → use them (the survey producer
  chose the method; respect that choice)
- If converting from Taylor to replication (via `as.svrepdesign()`):
  - Exactly 2 PSUs per stratum → `BRR` or `Fay` (Fay with rho 0.3–0.5
    is more stable)
  - ≥ 2 PSUs per stratum → `JKn` (delete-one-group jackknife)
  - Unstratified → `JK1`
  - General / complex nesting → `bootstrap` or `mrbbootstrap`
- Taylor linearization is the default for `svydesign()` and is appropriate
  for most published analyses

**When to convert**: Replication is sometimes preferred for non-smooth
statistics (quantiles, inequality measures) where linearization may
not perform well. Bootstrap is the safest choice for complex estimators
but is computationally expensive.
