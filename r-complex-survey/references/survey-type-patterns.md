# Survey Type Patterns — Decision Logic

Use this file at Gate 1 to determine how the survey's structural type
affects design specification, weight selection, and variance strategy.

---

## Cross-sectional (single wave)

One sample, one time point. Most public-use files.

**Design**: One `svydesign()` or `svrepdesign()` call.

**Decision point**: If multiple weight variables exist, the user must
specify which analysis component they are targeting (e.g., NHANES exam
vs. interview). Do not default — ask.

---

## Repeated cross-sections

Independent samples from the same population at different time points.
Different respondents each wave. Examples: BRFSS, GSS, ESS rounds.

**Design**: Each wave gets its own design object.

**Pooling rule**: Do not stack waves into one design unless the survey
explicitly provides:
1. Combined/pooled weights for the multi-wave period, AND
2. A documented combined design specification

If pooling is valid, the weight adjustment is survey-specific. Common
pattern: divide each wave's weight by the number of waves being combined.
But always check the survey's analytic guidelines — some surveys (e.g.,
NHANES multi-cycle) have specific instructions that differ from simple
division.

**Comparing across waves**: Estimates from different waves are independent.
Compute each wave's estimate with its own design, then compare using
standard formulas for differences of independent estimates (combined
SE = sqrt(SE₁² + SE₂²)).

**Watch for**: Variable definitions, response scales, and sampling frames
changing between waves. Verify comparability before computing trends.

---

## Panel / longitudinal

Same individuals tracked over multiple waves. Examples: SIPP, PSID,
Understanding Society, EU-SILC rotational, HRS.

**Design**: The initial wave defines the base design. Later waves use
attrition-adjusted weights.

**Critical weight decision**:
- **Cross-sectional analysis** (population estimate at one wave) →
  use that wave's cross-sectional weight
- **Longitudinal analysis** (change over time, transitions) →
  use longitudinal weight that adjusts for cumulative attrition

Using the wrong weight type is a common silent error. If the user does
not specify, ask which type of analysis they are doing.

**Within-person correlation**: `svyglm()` treats rows independently.
For models requiring within-person correlation structure:
- The `survey` package does not natively support mixed models or GEE
- `svyglm()` with cluster-robust SEs at the person level is a pragmatic
  approximation for some designs
- Fitting `lme4` models with survey weights as frequency weights is
  controversial — SEs do not properly reflect the full design. If the
  user wants this, warn explicitly.

**Rotational panels** (EU-SILC, CPS): The sample at any wave is a mix
of rotation groups at different stages. Weighting and design specification
must account for the rotation pattern.

**Attrition**: Check weight distributions at later waves — they become
increasingly extreme. Flag if max/min ratio exceeds 50.

---

## Two-phase (double sampling)

Phase 1: cheap/large sample. Phase 2: expensive subsample from phase 1,
stratified using phase 1 data. Examples: case-cohort studies, validation
studies, screening surveys with follow-up.

**Design**: Use `twophase()`. Requires:
- Phase 1 data (or at minimum, phase 1 totals by stratum)
- Phase 2 selection indicator
- Phase 2 stratification variable (from phase 1)

**Key advantage**: `calibrate()` can use phase 1 totals (known without
sampling error) to improve phase 2 estimates substantially.

If phase 1 is a census or near-census, its variance contribution is
negligible and the design simplifies to a stratified single-phase.

---

## Multi-frame

Target population covered by overlapping frames, sampled independently.
Classic case: dual-frame telephone (landline + cell).

**Design**: Use `multiframe()`. Each frame has its own design object plus
an overlap indicator.

**Overlap classification**: Every observation must be assigned to exactly
one frame or to the overlap. Misclassification biases compositing weights.

**Compositing method**: The overlap domain's contribution is split between
frames. Options: optimal (minimises variance), simple average, or
single-frame dominance. `multiframe()` handles this but the choice
affects efficiency.

---

## Establishment / business surveys

Sampling firms, schools, hospitals — not people. Examples: JOLTS, school
surveys, hospital discharge surveys.

**Design**: Often PPS (probability proportional to size). Use `svydesign()`
with `pps = "brewer"` or `pps = HR()` for Hartley-Rao approximation.
Set `variance = "YG"` for Yates-Grundy estimator with PPS without
replacement.

**Certainty units**: Very large establishments sampled with probability 1.
These form a take-all stratum with zero variance contribution. If not
handled correctly they create singleton PSU problems.

**Weight dispersion**: PPS gives small firms very large weights. Expect
extreme max/min ratios. Trimming may be necessary but reduces design
consistency.

---

## Self-weighting (EPSEM)

All selection probabilities equal. Weights are constant.

**The trap**: Constant weights do NOT mean you can ignore the design.
Clustering still creates correlated observations. Using `lm()` on an
EPSEM cluster sample gives wrong SEs even though weights are equal.

EPSEM can be disrupted by non-response adjustment — the weights become
unequal and the design is no longer self-weighting.

---

## Survey type decision procedure

Ask these questions in order:

1. Same or different people across waves? → Same = panel; different = repeated cross-section
2. Only one wave? → Cross-sectional
3. Two measurement stages with different intensity? → Two-phase
4. Multiple overlapping frames? → Multi-frame
5. Sampling organisations not people? → Establishment
6. All probabilities equal? → EPSEM (but still need the design for variance)

Multiple types can co-occur. A panel survey may need SAE. A repeated
cross-section may switch from single-frame to dual-frame between waves.
Resolve each applicable type's implications.
