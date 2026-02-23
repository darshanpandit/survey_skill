# Design-Aware Survey Analysis: Missing Data Mechanisms in the GSS and Food Miles in the Commodity Flow Survey

## Abstract

Survey data powers policy decisions, academic research, and corporate strategy--yet two pervasive problems routinely undermine its reliability: **missing data** and **design ignorance**. This article presents two independent analyses that illustrate how these problems manifest in real federal surveys and what researchers can do about them.

**Part I** uses the General Social Survey (1972--2024, n = 75,699) to demonstrate the difference between Missing Completely At Random (MCAR) and Missing Not At Random (MNAR) data, reproducing and extending the framework from Kim & Lee (2024). We show that survey weights--already embedded in every probability sample--can serve as a simple, underused diagnostic for detecting informative missingness, and that ignoring the survey design compounds MNAR bias.

**Part II** uses the 2017 Commodity Flow Survey (5.98 million shipment records) to map fresh food supply chains into five major US metros. We estimate weighted food miles, carbon intensity, seasonal patterns, cold-chain logistics, supply-chain vulnerability, and mode-substitution scenarios--all through design-aware estimation.

Both analyses enforce the complex survey design throughout, using the `survey` R package with proper weights, stratification, and clustering. All code is fully reproducible.

---

## Part I: When Missing Data Lies to You

### Background

Kim & Lee (2024) fine-tuned large language models on the General Social Survey to predict missing survey responses.[^1] Their paper identifies three types of missingness in repeated cross-sectional surveys:

1. **Item non-response** -- respondents skip individual questions (classic MCAR/MAR territory)
2. **Retrodiction** -- questions not asked in certain survey waves (structural MNAR)
3. **Unasked opinion prediction** -- questions never asked at all (extreme MNAR)

The distinction matters enormously. Under MCAR, the missing values are a random subsample of the complete data--you lose statistical power but not validity. Under MNAR, the probability of a value being missing depends on the value itself. Dropping MNAR cases silently biases every downstream estimate.

Our illustration makes these abstractions concrete using real GSS data.

### Data

The General Social Survey is a repeated cross-sectional probability sample of US adults, conducted by NORC at the University of Chicago since 1972. We use the cumulative file (1972--2024) containing 75,699 respondents, accessed via the `gssr` R package.

The GSS uses a stratified, clustered sampling design. For waves 2006--2018, the design variables are:

- **Strata**: `vstrat`
- **Primary Sampling Units (PSUs)**: `vpsu`
- **Weights**: `wtssall`

Weight dispersion ratio: 22.3. All weights strictly positive. We set `survey.lonely.psu = "adjust"` throughout.

### Findings

#### The Missingness Landscape (Panel A)

Not all missing data looks the same. A heatmap of 10 GSS opinion variables across survey years reveals three distinct patterns:

- **Consistently asked variables** like `happy` (general happiness) and `polviews` (political orientation) appear in nearly every wave with low missingness (~6%).
- **Intermittently asked variables** like `homosex` (attitudes toward homosexuality) appear in most but not all waves.
- **Rarely asked variables** like `marsame` (same-sex marriage) appear in only 5 of 35 survey years. This is *structural* MNAR--the question simply did not exist for most of the survey's history.

This year-level missingness is the most extreme form of MNAR. No imputation method--statistical or LLM-based--can recover a variable that was never measured.

#### MCAR in Action: General Happiness (Panel B)

The variable `happy` has ~6% missingness. When we compare the demographic profiles (age and education distributions) of respondents vs. non-respondents, the density curves nearly overlap. This is the signature of MCAR: who answers has nothing to do with what they would have answered. Dropping non-respondents loses sample size but introduces no systematic bias.

#### MNAR in Action: Respondent Income (Panel C)

The variable `rincome` has ~42% missingness--and the mechanism is informative. Comparing respondent vs. non-respondent demographics reveals systematic divergence: non-respondents are younger, less educated, and disproportionately at the extremes of the income distribution. High earners refuse to disclose; low earners may not know or feel uncomfortable reporting. This is textbook MNAR: the probability of missingness depends on the missing value itself.

#### The Bias Consequence (Panel D)

To quantify the practical impact, we ran 200 simulations of 30% deletion on GSS education data:

- **Under MCAR**: Delete 30% of education values at random. The estimated mean education across simulations clusters tightly around the true population mean. Bias is negligible.
- **Under MNAR**: Delete 30% of education values, but with probability proportional to education level (higher education = more likely to be missing). The estimated mean shifts downward by approximately **0.8 years of education**--a substantial and consistent bias.

This is the core danger: MNAR missingness does not average out. It pushes every estimate in the same direction, and the bias persists regardless of sample size.

### Novel Contribution: Design-Aware Missingness Diagnostics

Panels E and F go beyond Kim & Lee's framework by incorporating the GSS survey design--something the original paper does not do.

#### Weighted vs. Unweighted Missingness Rates (Panel E)

**The idea**: If missingness is truly MCAR, then the *weighted* missingness rate (computed via `svymean()` on a binary indicator through the survey design object) should equal the *unweighted* rate. Any gap means the survey weights--which encode selection probabilities--correlate with the missingness mechanism, signalling MAR or MNAR.

**What we found across seven GSS waves (2006--2018)**:

- For `happy` and `polviews` (MCAR candidates): the weighted and unweighted missingness rates nearly overlap in every wave. The weights are uncorrelated with who is missing.
- For `rincome` and `realinc` (MNAR candidates): the weighted rate consistently diverges from the unweighted rate. The survey weights--which reflect differential selection probabilities across demographic strata--are picking up the informative missingness that descriptive statistics alone miss.

**Why this matters**: This is a simple, zero-assumption diagnostic that leverages information already embedded in the survey weights. Most applied researchers never perform it. It requires only a binary missingness indicator and a `svymean()` call through the design object, yet it can flag informative missingness before any modelling begins.

#### Design-Ignorance Compounds MNAR Bias (Panel F)

**The idea**: When you have MNAR missingness *and* ignore the survey design, biases compound. We estimated mean years of education in GSS 2018 three ways:

1. **Full sample, design-weighted** -- the benchmark (closest to the population truth)
2. **Complete cases only, design-weighted** -- isolates MNAR bias
3. **Complete cases only, unweighted** -- MNAR bias + design-ignorance bias

**Results**:

- For `happy` (MCAR): all three estimates converge, as expected. When missingness is random, neither dropping cases nor ignoring the design introduces meaningful bias.
- For `rincome` (MNAR): biases stack. The complete-case weighted estimate is already biased from MNAR. The complete-case *unweighted* estimate is worse--it suffers from both ignoring *who* is missing and ignoring the complex sampling design.

**Implication for Kim & Lee**: Their LLM-based imputation treats GSS responses as i.i.d. draws. But the GSS is a stratified, clustered probability sample with non-trivial weights (CV = 0.575). Ignoring this design when training imputation models--whether statistical or LLM-based--introduces additional bias on top of the MNAR problem they are trying to solve. The design-ignorance bias and the MNAR bias are additive, not offsetting.

---

## Part II: How Far Does Your Food Travel?

### Background

The "food miles" concept--the distance food travels from farm to fork--has become a common shorthand for the environmental impact of food supply chains. But most popular discussions rely on anecdote or national averages. How far does food *actually* travel to reach a specific city? Which transport modes carry it? What is the carbon cost?

We answer these questions for five major US metros using the 2017 Commodity Flow Survey, a federal establishment survey that tracks physical shipments across the US economy.

### Data

**2017 Commodity Flow Survey (CFS) Public Use File**
- Census Bureau / Bureau of Transportation Statistics
- 5,978,523 total shipment records
- 108,207 fresh food shipments destined for five metros
- Commodity codes (SCTG): 03 (produce), 04 (dairy/eggs), 05 (meat/seafood), 06 (grain/bakery), 07 (prepared food)

The CFS is an establishment survey--it samples shipping firms (manufacturing, wholesale, warehousing), not people. This means PPS (probability proportional to size) sampling, certainty strata for large firms, and extreme weight dispersion.

**Survey design**: The CFS Public Use File strips PSU and strata identifiers for confidentiality. We use a weights-only specification: `svydesign(id = ~1, weights = ~WGT_FACTOR)`. Weight range: [0.3, 313,947]. CV = 3.88. Max/min ratio ~ 1 million.

**Key caveat**: Because the PUF strips clustering information, our standard errors ignore the intra-cluster correlation and are likely too narrow. Point estimates (weighted means and totals) are correct; confidence intervals should be interpreted cautiously.

### Metro Areas

| Metro | CFS Code (DEST_MA) | Unweighted Food Shipments |
|-------|--------------------:|-------------------------:|
| New York City | 408 | 37,765 |
| Los Angeles | 348 | 33,406 |
| Chicago | 176 | 21,729 |
| Houston | 288 | 7,593 |
| Miami | 370 | 7,714 |

### Core Findings

#### Food Miles Index (Panel A)

| Metro | Weighted Mean Distance (mi) | 95% CI |
|-------|----------------------------:|-------:|
| Chicago | 206 | [178, 233] |
| **NYC** | **252** | **[229, 274]** |
| Miami | 292 | [233, 350] |
| Houston | 340 | [284, 396] |
| Los Angeles | 377 | [346, 409] |

**NYC's food travels ~252 miles on average**--the second-shortest supply chain among the five metros. Chicago leads at 206 miles, benefiting from its proximity to the Midwest agricultural heartland. Los Angeles, despite sitting adjacent to California's Central Valley, has the longest food supply chain at 377 miles--suggesting that much of LA's food comes through national distribution networks rather than local sourcing.

#### NYC's Distance Distribution by Commodity (Panel B)

Most NYC-bound food shipments travel fewer than 500 miles, with a pronounced peak at 50--200 miles reflecting the Northeast corridor (Pennsylvania, New Jersey, upstate New York). However, a long tail extends to 2,000+ miles--transcontinental shipments of produce from California, seafood from the Pacific Northwest, and citrus from Florida.

Meat and seafood (SCTG 05) show the most bimodal distribution: a local peak from regional processors and a distant peak from national suppliers.

#### Modal Share (Panel C)

Truck dominates fresh food transport across all five metros, carrying 70--85% of weighted tonnage. Rail plays a meaningful role only for Chicago and Houston--both major rail hubs. NYC receives almost no food by water despite being a port city; modern food logistics overwhelmingly relies on refrigerated trucking for time-sensitive perishables.

Air freight carries a negligible share of total food tonnage but, as we show below, a disproportionate share of carbon emissions.

#### Carbon Intensity (Panel D)

| Metro | kg CO2 per Ton of Food |
|-------|----------------------:|
| **NYC** | **0.07** |
| Houston | 0.09 |
| Chicago | 0.09 |
| Miami | 0.09 |
| Los Angeles | 0.11 |

**NYC has the lowest carbon intensity per ton of food shipped** among the five metros. Two factors drive this: (1) shorter average distances, and (2) a mode mix with proportionally less air freight.

Carbon intensity was computed using EPA SmartWay 2017 emission factors:

| Mode | gCO2 per ton-mile |
|------|------------------:|
| Air | 1,054 |
| Parcel/courier | 210 |
| Truck | 161.8 |
| Multimodal | 100 |
| Rail | 22 |
| Water | 14 |
| Pipeline | 8 |

#### NYC: Mode Share vs. Carbon Decomposition (Panel E)

Truck carries ~75% of NYC's food tonnage and accounts for ~70% of transport CO2. But the key insight is the asymmetry for air freight: **air carries a tiny share of tonnage but a disproportionate share of CO2**, because its emission factor (1,054 gCO2/ton-mile) is 6.5x that of trucking. Policy focused on shifting even small volumes of air freight to ground transport would yield outsized carbon reductions.

### Extended Findings

#### Seasonal Food Miles (Panel A-ext)

Does winter lengthen the supply chain? We hypothesized that NYC's food miles would increase in Q1 and Q4, when Northeast farms are dormant and produce must travel from California, Florida, and Texas.

The data shows a modest seasonal effect. NYC's weighted mean distance rises from ~238 miles in Q3 (summer, when local and regional farms are in season) to ~268 miles in Q1 (winter). The pattern is consistent across all five metros but most pronounced for NYC and Chicago--both northern cities dependent on southern and western produce during cold months.

LA shows the smallest seasonal variation, consistent with California's year-round growing season.

#### Cold Chain: Refrigerated Food Travels Farther (Panel B-ext)

Temperature-controlled ("refrigerated") shipments travel 2--3x farther than non-refrigerated food shipments across all five metros. This makes intuitive sense: refrigerated logistics enables long-distance transport of perishable goods that would otherwise be sourced locally. The cold chain is what makes it possible for NYC to receive fresh produce from California in January.

This also means refrigerated transport carries a disproportionate carbon cost: longer distances multiplied by the higher energy intensity of maintaining cold temperatures throughout transit.

#### Supply Chain Vulnerability (Panel C-ext)

How concentrated is each metro's food supply? If 80% of a city's food comes from just a few states, that city is vulnerable to regional disruptions--droughts, hurricanes, infrastructure failures.

We computed cumulative concentration curves showing how many origin states account for 80% of each metro's weighted food tonnage:

| Metro | States to Reach 80% of Food Supply |
|-------|----------------------------------:|
| Miami | 4 |
| NYC | 6 |
| Houston | ~8 |
| Los Angeles | ~8 |
| Chicago | 10 |

**Miami is the most concentrated** (and therefore most vulnerable): just 4 states supply 80% of its food. **Chicago is the most diversified** with 10 origin states needed to reach 80%. NYC falls in between at 6 states, with New York, Pennsylvania, and New Jersey comprising the dominant share--reflecting the importance of the regional Northeast food economy.

#### Mode Substitution: What-If Scenarios (Panel D-ext)

What if NYC shifted its food transport modes? We modelled three counterfactual scenarios against the current baseline:

| Scenario | CO2 Reduction |
|----------|-------------:|
| Eliminate all air freight (shift to truck) | ~15% |
| Shift 10% of truck ton-miles to rail | ~0.4% |
| Shift 5% of parcel/courier to truck | < 0.1% |

The results are striking. **Eliminating air freight--which carries a tiny share of total food tonnage--would reduce NYC's food transport CO2 by approximately 15%.** This is because air's emission factor is so much higher than any ground mode (1,054 vs. 162 gCO2/ton-mile). By contrast, shifting 10% of truck volume to rail saves less than 1%, because truck already dominates and the factor difference (162 vs. 22) applies to a smaller absolute volume.

The policy implication is clear: the highest-leverage intervention is not shifting between ground modes but eliminating the small volume of perishable air freight--likely premium seafood and out-of-season produce--in favour of ground transport with better cold-chain logistics.

---

## Methodology: Design-Aware Analysis

Both analyses follow the `r-complex-survey` skill's mandatory 5-gate workflow, ensuring that no estimate bypasses the survey design.

### Gate Structure

| Gate | GSS Application | CFS Application |
|------|----------------|-----------------|
| **1. Survey type** | Repeated cross-section. Each wave gets its own `svydesign()` object. Never pool waves without explicit pooled weights. | Establishment survey. PPS sampling, certainty strata, extreme weight dispersion expected. |
| **2. Design spec** | Taylor linearization: `svydesign(id = ~vpsu, strata = ~vstrat, weights = ~wtssall, nest = TRUE)` | Weights-only: `svydesign(id = ~1, weights = ~WGT_FACTOR)`. PUF strips PSU/strata. |
| **3. Validate** | `vstrat`, `vpsu`, `wtssall` present with no NAs for 2006--2018. Weight dispersion ratio = 22.3. | Weight range [0.3, 313,947]. CV = 3.88. All positive. |
| **4. Analyse** | All estimates via `svymean()`. Complete-case subsets via `subset()` on design object. | All estimates via `svymean()` and `svytotal()`. Subgroups via `subset()` on design object. |
| **5. Diagnostics** | SEs, CIs, unweighted n reported. `survey.lonely.psu = "adjust"`. | SEs, CIs, unweighted n reported. `survey.lonely.psu = "adjust"`. |

### Hard Invariants Enforced

Three non-negotiable rules from the complex survey analysis framework:

1. **Never filter the data frame for domain estimation.** We used `subset()` on the design object, not `dplyr::filter()` on the data frame. Filtering drops PSUs and strata that contribute to variance estimation. Point estimates may look identical; standard errors will be wrong.

2. **Never pool repeated cross-section waves without pooled weights.** Each GSS wave (2006--2018) was analysed with its own `svydesign()` object. Stacking waves into one design without survey-provided pooled weights produces nonsense variance estimates.

3. **Always set `survey.lonely.psu` before analysis.** Both analyses set `options(survey.lonely.psu = "adjust")` before any estimation. Without this, R errors on singleton strata rather than applying the recommended conservative adjustment.

---

## Conclusions

### Missing Data Is Not Just a Nuisance

The GSS analysis demonstrates that the mechanism behind missing data--not just the rate--determines whether your results are trustworthy. A 6% missingness rate under MCAR (like `happy`) is benign. A 42% rate under MNAR (like `rincome`) systematically distorts every estimate. And structural MNAR--variables that were never asked in certain years--cannot be recovered by any imputation method, no matter how sophisticated.

Survey weights offer a free, underused diagnostic: if the weighted and unweighted missingness rates diverge, the missingness mechanism is likely informative. This is a one-line computation that should be standard practice.

### NYC's Food Supply Chain Is Shorter Than You Think

At 252 miles on average, NYC's food supply chain is the second-shortest among the five largest US metros. Chicago's proximity to the agricultural Midwest gives it the shortest at 206 miles. LA's, paradoxically, is the longest at 377 miles despite California's agricultural dominance--a consequence of national distribution networks that route food through LA from distant origins.

### Carbon Policy Should Target Air Freight, Not Truck-to-Rail

The mode-substitution analysis reveals that eliminating the small volume of air-freighted food to NYC would reduce food transport CO2 by ~15%, while shifting 10% of truck tonnage to rail would save less than 1%. Air freight's emission factor is so extreme (1,054 gCO2/ton-mile vs. 162 for truck) that even tiny volumes dominate the carbon budget. The policy priority should be investing in cold-chain ground logistics that make air freight unnecessary for premium perishables.

### Design Matters, Always

Both analyses show that ignoring the survey design produces wrong results. In the GSS, design-ignorance bias compounds MNAR bias, making the worst estimates even worse. In the CFS, where weights span a million-fold range (0.3 to 313,947), unweighted estimates would be dominated by the sampling strategy rather than the population reality. Every survey analysis should pass through the design object. There are no exceptions.

---

## Reproducibility

All analyses are fully reproducible with the following R scripts:

```r
# Part I: GSS MCAR/MNAR Illustration
install.packages(c("ggplot2", "dplyr", "tidyr", "patchwork", "scales", "survey"))
remotes::install_github("kjhealy/gssr")
source("mcar_mnar_illustration.R")

# Part II: CFS Food Miles (base)
# Download CFS 2017 PUF from:
# https://www2.census.gov/programs-surveys/cfs/datasets/2017/cfs-2017-puf-csv.zip
# Unzip to tmp/CSV.csv
source("cfs_food_miles.R")

# Part II: CFS Food Miles (extended)
source("cfs_food_miles_extended.R")
```

## Output Files

| File | Description |
|------|------------|
| `mcar_mnar_illustration.R` | GSS missing data analysis (6-panel figure) |
| `mcar_mnar_illustration.png` | 300 DPI raster, 14 x 28 inches |
| `mcar_mnar_illustration.pdf` | Vector PDF |
| `cfs_food_miles.R` | CFS food miles analysis (5-panel figure) |
| `cfs_food_miles.png` | 300 DPI raster, 16 x 18 inches |
| `cfs_food_miles.pdf` | Vector PDF |
| `cfs_food_miles_extended.R` | Extended CFS analysis (4-panel figure) |
| `cfs_food_miles_extended.png` | 300 DPI raster, 16 x 14 inches |
| `cfs_food_miles_extended.pdf` | Vector PDF |

## Data Sources

- **General Social Survey** (1972--2024): NORC at the University of Chicago. Accessed via the `gssr` R package (n = 75,699).
- **Commodity Flow Survey** (2017): US Census Bureau / Bureau of Transportation Statistics. Public Use File (n = 5,978,523). Downloaded from https://www2.census.gov/programs-surveys/cfs/datasets/2017/.
- **EPA SmartWay** emission factors (2017 averages): gCO2 per ton-mile by transport mode.

## References

[^1]: Kim, J. & Lee, B. (2024). *AI-Augmented Surveys: Leveraging Large Language Models and Surveys for Opinion Prediction*. arXiv:2305.09620v3.
