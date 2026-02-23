# MCAR vs MNAR Illustration — Analysis Notes

## Paper Reference

Kim, J. & Lee, B. (2024). *AI-Augmented Surveys: Leveraging Large Language
Models and Surveys for Opinion Prediction*. arXiv:2305.09620v3.

The paper uses the General Social Survey (GSS) to fine-tune LLMs for
predicting missing survey responses. It identifies three types of missing
data in repeated cross-sectional surveys (their Figure 1):

- **Panel A — Missing Data Imputation**: Item non-response where respondents
  skip individual questions. Classic MCAR/MAR territory.
- **Panel B — Retrodiction**: Year-level missingness where questions were not
  asked in certain survey waves. Structural MNAR.
- **Panel C — Unasked Opinion Prediction**: Questions that have never been
  asked at all. Extreme MNAR.

## What Our Illustration Covers

### Panels A–D: Standard Diagnostics (from the paper's framework)

| Panel | What it shows | Key variable |
|-------|--------------|--------------|
| A. Missingness heatmap | Which GSS opinion questions were asked in which years (1972–2024). Reveals structural MNAR: `marsame` (same-sex marriage) only asked 5 of 35 years. | 10 opinion variables |
| B. MCAR diagnostic | Density plots comparing demographics of `HAPPY` respondents vs non-respondents. Distributions overlap — confirming MCAR. | `happy` (6% missing) |
| C. MNAR diagnostic | Same comparison for `RINCOME`. Distributions diverge systematically — confirming MNAR. | `rincome` (42% missing) |
| D. Bias consequence | 200 simulations of 30% deletion on education data. MCAR clusters around the true mean; MNAR shifts it by ~0.8 years. | `educ` (simulated deletion) |

### Panels E–F: Novel Design-Aware Analysis (beyond the paper)

These panels use the `survey` R package to account for the GSS complex
sampling design — something Kim & Lee do not do.

#### Panel E: Weighted vs Unweighted Missingness Rates

**The idea**: If missingness is truly MCAR, then the *weighted* missingness
rate (computed via `svymean()` on a binary indicator through the design
object) should match the *unweighted* rate. Any gap means the survey
weights — which encode selection probabilities — correlate with the
missingness mechanism, signalling MAR or MNAR.

**What we found**: For `HAPPY` (MCAR candidate) and `POLVIEWS` (moderate
MCAR), the weighted and unweighted dots nearly overlap across all 7 waves
(2006–2018). For `RINCOME` and `REALINC` (MNAR candidates), the weighted
rate consistently diverges from the unweighted rate.

**Why this matters**: This is a simple design-aware diagnostic that most
applied researchers do not perform. It leverages information already
embedded in the survey weights to detect informative missingness without
needing external data or strong modelling assumptions.

#### Panel F: Design-Ignorance Compounds MNAR Bias

**The idea**: When you have MNAR missingness AND ignore the survey design,
biases compound. We estimate mean education in GSS 2018 three ways:

1. **Full sample, design-weighted** — the benchmark (closest to population truth)
2. **Complete cases only, design-weighted** — isolates MNAR bias
3. **Complete cases only, unweighted** — MNAR bias + design-ignorance bias

**What we found**:
- For HAPPY (MCAR): all three estimates converge, as expected.
- For RINCOME (MNAR): biases stack. The unweighted complete-case estimate
  is the worst — it suffers from both ignoring who is missing AND ignoring
  the complex sampling design.

**Why this matters**: Kim & Lee's LLM-based imputation treats GSS responses
as iid draws. But the GSS is a stratified, clustered probability sample with
weights (CV = 0.575). Ignoring this design when training imputation models
— whether statistical or LLM-based — introduces additional bias on top of
the MNAR problem they are trying to solve.

## How the r-complex-survey Skill Was Applied

The analysis followed the skill's mandatory 5-gate workflow:

| Gate | Application |
|------|------------|
| **Gate 1: Survey type** | GSS is a *repeated cross-section* — different respondents each wave. This triggered hard invariant #3: never pool waves into one design without explicit pooled weights. Each wave 2006–2018 was analysed with its own `svydesign()` object. |
| **Gate 2: Design spec** | Taylor linearization: `svydesign(id = ~vpsu, strata = ~vstrat, weights = ~wtssall, nest = TRUE)`. Weight variable `wtssall` selected (available 2006–2018; 2021+ uses different methodology). `survey.lonely.psu = "adjust"` set before any analysis. |
| **Gate 3: Validate** | Confirmed `vstrat`, `vpsu`, `wtssall` all present with no NAs for 2006–2018. Weight dispersion ratio = 22.3 (below the 50 threshold). All weights strictly positive. |
| **Gate 4: Analyse through design** | All estimates computed via `svymean()`. Complete-case subsets created with `subset()` on the design object, never by filtering the data frame (hard invariant #1). |
| **Gate 5: Diagnostics** | Reported SEs, 95% CIs, unweighted sample sizes, and the `survey.lonely.psu` setting in the figure caption. |

Key hard invariants enforced:
- **#1**: Used `subset(des18, ...)` instead of `dplyr::filter(df18, ...)` for
  complete-case analysis. Filtering drops PSUs/strata that contribute to
  variance estimation.
- **#3**: Built separate `svydesign()` per wave year. Never stacked 2006–2018
  into a single design.
- **#7**: Set `options(survey.lonely.psu = "adjust")` before any analysis.

## Output Files

- `mcar_mnar_illustration.png` — 300 DPI raster (14 x 28 inches)
- `mcar_mnar_illustration.pdf` — Vector PDF
- `mcar_mnar_illustration.R` — Fully reproducible R script

## Reproducibility

```r
# Required packages
install.packages(c("ggplot2", "dplyr", "tidyr", "patchwork", "scales", "survey"))
remotes::install_github("kjhealy/gssr")

# Run
source("mcar_mnar_illustration.R")
```

Data source: General Social Survey 1972–2024 (n = 75,699) via the `gssr`
R package. No external downloads needed — `gssr` bundles the cumulative file.
