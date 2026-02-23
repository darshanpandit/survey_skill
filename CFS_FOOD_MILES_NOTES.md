# Fresh Food Miles & Carbon Footprint: NYC vs Major US Metros

## Data Source

**2017 Commodity Flow Survey (CFS) Public Use File**
- Census Bureau / Bureau of Transportation Statistics
- 5,978,523 total shipment records; 108,207 fresh food shipments to 5 metros
- Downloaded from: https://www2.census.gov/programs-surveys/cfs/datasets/2017/

## Survey Design (r-complex-survey skill applied)

| Gate | Decision |
|------|----------|
| **Gate 1: Survey type** | Establishment survey — samples shipping firms (manufacturing, wholesale, warehousing), not people. Expect PPS sampling, certainty strata, extreme weight dispersion. |
| **Gate 2: Design spec** | Weights-only: `svydesign(id = ~1, weights = ~WGT_FACTOR)`. The PUF strips PSU and strata for confidentiality. SEs are approximate (ignore clustering). |
| **Gate 3: Validate** | Weight range [0.3, 313,947]. CV = 3.88. Max/min ratio = ~1M (extreme but expected for establishment surveys). All weights positive. |
| **Gate 4: Analyse** | All estimates through `svymean()` and `svytotal()`. Subgroups via `subset()` on design object (never `filter()` on data frame). |
| **Gate 5: Diagnostics** | SEs, CIs, unweighted n reported for all estimates. `survey.lonely.psu = "adjust"`. |

**Key caveat**: The CFS PUF strips PSU/strata for confidentiality. Our SEs
ignore clustering and are likely too narrow. Point estimates (weighted means
and totals) are correct.

## Commodity Codes (SCTG)

| Code | Description | Fresh food? |
|------|------------|-------------|
| 03 | Other agricultural products (fruits, vegetables, nuts) | Yes - core produce |
| 04 | Animal feed, eggs, dairy | Yes - dairy/eggs |
| 05 | Meat, poultry, fish, seafood | Yes - core protein |
| 06 | Milled grain products, bakery | Partially |
| 07 | Other prepared foodstuffs | Partially |

## Metro Areas (by CFS DEST_MA code)

| Metro | DEST_MA | Unweighted food shipments |
|-------|---------|--------------------------|
| NYC | 408 | 37,765 |
| Los Angeles | 348 | 33,406 |
| Chicago | 176 | 21,729 |
| Houston | 288 | 7,593 |
| Miami | 370 | 7,714 |

## Key Findings

### Panel A: Food Miles Index

| Metro | Weighted mean distance (miles) | 95% CI |
|-------|-------------------------------|--------|
| Chicago | 206 | [178, 233] |
| NYC | 252 | [229, 274] |
| Miami | 292 | [233, 350] |
| Houston | 340 | [284, 396] |
| Los Angeles | 377 | [346, 409] |

**NYC's food travels ~252 miles on average** -- the second-shortest among
the five metros. Chicago has the shortest food supply chain (206 mi),
likely because of its proximity to the Midwest agricultural heartland.
LA has the longest (377 mi) despite being in California's agricultural
Central Valley -- possibly because much of LA's food comes from national
(not local) supply chains.

### Panel B: NYC Distance Distribution by Commodity

Most NYC-bound food shipments travel < 500 miles, with a strong peak
around 50-200 miles (the Northeast corridor). However, there's a long
tail extending to 2,000+ miles for produce and meat/seafood -- these are
likely transcontinental shipments from California, Florida, and the
Pacific Northwest.

### Panel C: Modal Share

Truck dominates fresh food transport to all five metros (70-85% of
weighted tonnage). Rail plays a meaningful role only for Chicago and
Houston. NYC receives almost no food by water despite being a port city
-- modern food logistics overwhelmingly uses refrigerated trucking.

### Panel D: Carbon Intensity

| Metro | kg CO2 per ton of food |
|-------|----------------------|
| NYC | 0.07 |
| Houston | 0.09 |
| Chicago | 0.09 |
| Miami | 0.09 |
| Los Angeles | 0.11 |

**NYC has the lowest carbon intensity per ton of food** (0.07 kg CO2/ton).
This is because: (1) shorter average distances, and (2) a mode mix that
includes less air freight proportionally.

### Panel E: NYC Mode vs Carbon Decomposition

Truck carries ~75% of NYC's food tonnage and produces ~70% of CO2.
The key insight: **air freight carries a tiny share of tonnage but a
disproportionate share of CO2** (due to the 1,054 gCO2/ton-mile factor
vs 162 for truck). This means policy focused on shifting even small
amounts of air freight to ground transport would have outsized impact.

## EPA Emission Factors Used

| Mode | gCO2 per ton-mile |
|------|-------------------|
| Air | 1,054 |
| Parcel/courier | 210 |
| Truck | 161.8 |
| Multimodal | 100 |
| Rail | 22 |
| Water | 14 |
| Pipeline | 8 |

Source: EPA SmartWay, 2017 averages.

## Output Files

- `cfs_food_miles.png` -- 300 DPI raster (16 x 18 inches)
- `cfs_food_miles.pdf` -- Vector PDF
- `cfs_food_miles.R` -- Fully reproducible R script

## Reproducibility

```r
# 1. Download CFS 2017 PUF
# https://www2.census.gov/programs-surveys/cfs/datasets/2017/cfs-2017-puf-csv.zip
# Unzip to tmp/CSV.csv

# 2. Required packages
install.packages(c("dplyr", "tidyr", "ggplot2", "patchwork", "scales", "survey"))

# 3. Run
source("cfs_food_miles.R")
```
