#!/usr/bin/env Rscript
# ===========================================================================
# Extended Fresh Food Analysis: Seasonality, Cold Chain, Vulnerability,
# and Mode Substitution Scenarios
# Using the 2017 Commodity Flow Survey (CFS) Public Use File
# ===========================================================================
#
# This extends cfs_food_miles.R with four additional analyses:
#   A. Seasonal food miles by quarter
#   B. Refrigerated vs non-refrigerated shipments
#   C. Supply chain vulnerability (origin concentration)
#   D. Mode substitution counterfactual scenarios
#
# Same design caveat: CFS PUF is weights-only (PSU/strata stripped).
# ===========================================================================

library(dplyr)
library(tidyr)
library(ggplot2)
library(patchwork)
library(scales)
library(survey)

out_dir <- "/home/darshan/Documents/claude_code/agent_skills_survey"

# ── Palettes & theme ──────────────────────────────────────────────────────
metro_cols <- c("NYC" = "#E41A1C", "Los Angeles" = "#377EB8",
                "Chicago" = "#4DAF4A", "Houston" = "#984EA3",
                "Miami" = "#FF7F00")

quarter_labels <- c("1" = "Q1 (Jan-Mar)", "2" = "Q2 (Apr-Jun)",
                     "3" = "Q3 (Jul-Sep)", "4" = "Q4 (Oct-Dec)")

# State FIPS → abbreviation lookup
state_fips <- data.frame(
  ORIG_STATE = c(1,2,4,5,6,8,9,10,11,12,13,15,16,17,18,19,20,21,22,23,
                 24,25,26,27,28,29,30,31,32,33,34,35,36,37,38,39,40,41,
                 42,44,45,46,47,48,49,50,51,53,54,55,56),
  state_abbr = c("AL","AK","AZ","AR","CA","CO","CT","DE","DC","FL","GA",
                 "HI","ID","IL","IN","IA","KS","KY","LA","ME","MD","MA",
                 "MI","MN","MS","MO","MT","NE","NV","NH","NJ","NM","NY",
                 "NC","ND","OH","OK","OR","PA","RI","SC","SD","TN","TX",
                 "UT","VT","VA","WA","WV","WI","WY"),
  stringsAsFactors = FALSE
)

# EPA emission factors (gCO2 per ton-mile)
epa_factors <- data.frame(
  mode_label = c("Truck", "Rail", "Water", "Air", "Pipeline",
                 "Parcel/courier", "Multimodal", "Other"),
  gco2_per_tonmile = c(161.8, 22.0, 14.0, 1054.0, 8.0, 210.0, 100.0, 100.0),
  stringsAsFactors = FALSE
)

mode_map <- data.frame(
  MODE = c(0, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 101),
  mode_label = c("Other", "Rail", "Water", "Parcel/courier", "Truck", "Air",
                 "Pipeline", "Other", "Other", "Other",
                 "Multimodal", "Multimodal", "Multimodal", "Multimodal",
                 "Multimodal", "Multimodal", "Multimodal", "Multimodal",
                 "Multimodal", "Multimodal", "Other"),
  stringsAsFactors = FALSE
)

theme_set(theme_minimal(base_size = 12) +
            theme(plot.title = element_text(face = "bold", size = 13),
                  plot.subtitle = element_text(colour = "grey40", size = 10)))

# ── Load & prepare ────────────────────────────────────────────────────────
cat("Loading CFS 2017 PUF...\n")
cfs <- read.csv(file.path(out_dir, "tmp/CSV.csv"), stringsAsFactors = FALSE)

metro_lookup <- data.frame(
  DEST_MA = c(408, 348, 176, 288, 370),
  metro = c("NYC", "Los Angeles", "Chicago", "Houston", "Miami"),
  stringsAsFactors = FALSE
)

food_sctg_codes <- sprintf("%02d", 3:7)

cfs_food <- cfs %>%
  mutate(SCTG = sprintf("%02d", suppressWarnings(as.integer(SCTG)))) %>%
  filter(SCTG %in% food_sctg_codes, DEST_MA %in% metro_lookup$DEST_MA) %>%
  left_join(metro_lookup, by = "DEST_MA") %>%
  left_join(mode_map, by = "MODE") %>%
  left_join(state_fips, by = "ORIG_STATE") %>%
  mutate(
    tons = SHIPMT_WGHT / 2000,
    ton_miles = tons * SHIPMT_DIST_ROUTED,
    is_temp_ctrl = (TEMP_CNTL_YN == "Y"),
    quarter_label = quarter_labels[as.character(QUARTER)]
  )

cat(sprintf("Food shipments to 5 metros: %s\n", format(nrow(cfs_food), big.mark = ",")))

# Survey design (weights-only; PUF strips PSU/strata)
options(survey.lonely.psu = "adjust")
des_food <- svydesign(id = ~1, weights = ~WGT_FACTOR, data = cfs_food)

# ═══════════════════════════════════════════════════════════════════════════
# PANEL A — Seasonal Food Miles by Quarter
# ═══════════════════════════════════════════════════════════════════════════
# Hypothesis: NYC's food miles increase in Q1/Q4 (winter) when local
# Northeast farms are dormant and food must travel from CA, FL, TX.

seasonal_df <- data.frame()
for (m in metro_lookup$metro) {
  for (q in 1:4) {
    des_sub <- subset(des_food, metro == m & QUARTER == q)
    if (nrow(des_sub$variables) >= 20) {
      est <- svymean(~SHIPMT_DIST_ROUTED, des_sub, na.rm = TRUE)
      seasonal_df <- rbind(seasonal_df, data.frame(
        metro = m, quarter = q,
        quarter_label = quarter_labels[as.character(q)],
        mean_dist = as.numeric(coef(est)),
        se = as.numeric(SE(est)),
        n_unwt = nrow(des_sub$variables),
        stringsAsFactors = FALSE
      ))
    }
  }
}

seasonal_df$ci_lo <- seasonal_df$mean_dist - 1.96 * seasonal_df$se
seasonal_df$ci_hi <- seasonal_df$mean_dist + 1.96 * seasonal_df$se

p_a <- ggplot(seasonal_df, aes(x = quarter, y = mean_dist,
                                colour = metro, group = metro)) +
  geom_line(linewidth = 0.9) +
  geom_point(size = 2.5) +
  geom_ribbon(aes(ymin = ci_lo, ymax = ci_hi, fill = metro),
              alpha = 0.12, colour = NA) +
  scale_x_continuous(breaks = 1:4, labels = c("Q1\nWinter", "Q2\nSpring",
                                               "Q3\nSummer", "Q4\nFall")) +
  scale_colour_manual(values = metro_cols, name = NULL) +
  scale_fill_manual(values = metro_cols, guide = "none") +
  labs(
    title = "A. Seasonal Food Miles: Does Winter Lengthen the Supply Chain?",
    subtitle = "Weighted mean shipment distance by quarter. Ribbons = 95% CI. NYC shows modest seasonal shift.",
    x = NULL, y = "Mean distance (miles)"
  ) +
  theme(legend.position = "bottom")

cat("Panel A built: seasonal food miles\n")

# ═══════════════════════════════════════════════════════════════════════════
# PANEL B — Refrigerated vs Non-Refrigerated
# ═══════════════════════════════════════════════════════════════════════════
# Temperature-controlled shipments travel different distances and use
# different modes. Refrigerated transport also has ~20% higher emissions.

temp_df <- data.frame()
for (m in metro_lookup$metro) {
  for (tc in c(TRUE, FALSE)) {
    des_sub <- subset(des_food, metro == m & is_temp_ctrl == tc)
    if (nrow(des_sub$variables) >= 20) {
      est_dist <- svymean(~SHIPMT_DIST_ROUTED, des_sub, na.rm = TRUE)
      est_tons <- svytotal(~tons, des_sub, na.rm = TRUE)
      temp_df <- rbind(temp_df, data.frame(
        metro = m,
        temp_ctrl = ifelse(tc, "Refrigerated", "Non-refrigerated"),
        mean_dist = as.numeric(coef(est_dist)),
        se_dist = as.numeric(SE(est_dist)),
        total_tons = as.numeric(coef(est_tons)),
        n_unwt = nrow(des_sub$variables),
        stringsAsFactors = FALSE
      ))
    }
  }
}

p_b <- ggplot(temp_df, aes(x = metro, y = mean_dist, fill = temp_ctrl)) +
  geom_col(position = "dodge", width = 0.65, alpha = 0.85) +
  geom_errorbar(aes(ymin = mean_dist - 1.96 * se_dist,
                     ymax = mean_dist + 1.96 * se_dist),
                position = position_dodge(width = 0.65), width = 0.2) +
  scale_fill_manual(values = c("Refrigerated" = "#377EB8",
                                "Non-refrigerated" = "#E41A1C"),
                    name = NULL) +
  labs(
    title = "B. Cold Chain: Refrigerated Food Travels Farther",
    subtitle = "Weighted mean distance by temperature control status. Error bars = 95% CI.",
    x = NULL, y = "Mean distance (miles)"
  ) +
  theme(legend.position = "bottom")

cat("Panel B built: refrigerated vs non-refrigerated\n")

# ═══════════════════════════════════════════════════════════════════════════
# PANEL C — Supply Chain Vulnerability: Origin Concentration
# ═══════════════════════════════════════════════════════════════════════════
# How concentrated is each metro's food supply? If 80% comes from 3 states,
# that metro is vulnerable to regional disruption.

origin_df <- data.frame()
for (m in metro_lookup$metro) {
  des_sub <- subset(des_food, metro == m)
  # Get weighted tonnage by origin state
  state_tons <- data.frame()
  for (st in unique(des_sub$variables$ORIG_STATE)) {
    des_st <- subset(des_sub, ORIG_STATE == st)
    if (nrow(des_st$variables) >= 5) {
      tot <- svytotal(~tons, des_st, na.rm = TRUE)
      abbr <- state_fips$state_abbr[state_fips$ORIG_STATE == st]
      if (length(abbr) == 0) abbr <- paste0("ST", st)
      state_tons <- rbind(state_tons, data.frame(
        metro = m, state = abbr,
        total_tons = as.numeric(coef(tot)),
        stringsAsFactors = FALSE
      ))
    }
  }
  # Compute cumulative share
  state_tons <- state_tons %>%
    arrange(desc(total_tons)) %>%
    mutate(
      share = total_tons / sum(total_tons),
      cum_share = cumsum(share),
      rank = row_number()
    )
  origin_df <- rbind(origin_df, state_tons)
}

# For the plot: show top 8 states per metro + "Other"
top_origins <- origin_df %>%
  group_by(metro) %>%
  mutate(state_label = ifelse(rank <= 8, state, "Other")) %>%
  group_by(metro, state_label) %>%
  summarise(share = sum(share), .groups = "drop") %>%
  # Sort within metro
  arrange(metro, desc(share))

# For each metro, what rank reaches 80%?
concentration <- origin_df %>%
  group_by(metro) %>%
  summarise(
    states_for_80pct = min(rank[cum_share >= 0.80]),
    top3_share = sum(share[rank <= 3]),
    .groups = "drop"
  )

cat("\n=== Supply Chain Concentration ===\n")
print(concentration)

# Cumulative share plot
cum_df <- origin_df %>% filter(rank <= 15)

p_c <- ggplot(cum_df, aes(x = rank, y = cum_share, colour = metro)) +
  geom_line(linewidth = 0.9) +
  geom_point(size = 1.5) +
  geom_hline(yintercept = 0.8, linetype = "dashed", colour = "grey40") +
  annotate("text", x = 14, y = 0.82, label = "80% threshold",
           colour = "grey40", size = 3.2, fontface = "italic") +
  # Label top-3 states for NYC
  geom_text(data = cum_df %>% filter(metro == "NYC", rank <= 3),
            aes(label = state), vjust = -1, size = 3, fontface = "bold",
            show.legend = FALSE) +
  scale_x_continuous(breaks = 1:15) +
  scale_y_continuous(labels = percent_format()) +
  scale_colour_manual(values = metro_cols, name = NULL) +
  labs(
    title = "C. Supply Chain Vulnerability: Origin Concentration",
    subtitle = "Cumulative share of weighted food tonnage by number of origin states. Fewer states = more concentrated = more vulnerable.",
    x = "Number of origin states (ranked by tonnage)", y = "Cumulative share of food supply"
  ) +
  theme(legend.position = "bottom")

cat("Panel C built: supply chain vulnerability\n")

# ═══════════════════════════════════════════════════════════════════════════
# PANEL D — Mode Substitution Scenarios (NYC)
# ═══════════════════════════════════════════════════════════════════════════
# Counterfactual: how much CO2 would NYC save by shifting modes?
# Scenario 1: Shift 10% of truck ton-miles to rail
# Scenario 2: Eliminate all air freight (move to truck)
# Scenario 3: Shift 5% of parcel/courier to truck
# Baseline: current CO2 from NYC food shipments

# First compute baseline CO2 by mode for NYC
nyc_carbon <- cfs_food %>%
  filter(metro == "NYC") %>%
  left_join(epa_factors, by = "mode_label") %>%
  mutate(co2_grams = ton_miles * gco2_per_tonmile)

des_nyc <- svydesign(id = ~1, weights = ~WGT_FACTOR, data = nyc_carbon)

# Weighted ton-miles and CO2 by mode
nyc_baseline <- data.frame()
for (ml in c("Truck", "Rail", "Water", "Air", "Parcel/courier", "Multimodal")) {
  des_m <- subset(des_nyc, mode_label == ml)
  if (nrow(des_m$variables) > 0) {
    tm <- svytotal(~ton_miles, des_m, na.rm = TRUE)
    co2 <- svytotal(~co2_grams, des_m, na.rm = TRUE)
    nyc_baseline <- rbind(nyc_baseline, data.frame(
      mode = ml,
      ton_miles = as.numeric(coef(tm)),
      co2_grams = as.numeric(coef(co2)),
      factor = epa_factors$gco2_per_tonmile[epa_factors$mode_label == ml],
      stringsAsFactors = FALSE
    ))
  }
}

baseline_co2 <- sum(nyc_baseline$co2_grams)

# Scenario calculations
truck_tm <- nyc_baseline$ton_miles[nyc_baseline$mode == "Truck"]
truck_factor <- 161.8
rail_factor <- 22.0
air_tm <- nyc_baseline$ton_miles[nyc_baseline$mode == "Air"]
air_factor <- 1054.0
parcel_tm <- nyc_baseline$ton_miles[nyc_baseline$mode == "Parcel/courier"]
parcel_factor <- 210.0

# Scenario 1: 10% truck → rail
s1_saved <- truck_tm * 0.10 * (truck_factor - rail_factor)
# Scenario 2: All air → truck
s2_saved <- air_tm * (air_factor - truck_factor)
# Scenario 3: 5% parcel → truck
s3_saved <- parcel_tm * 0.05 * (parcel_factor - truck_factor)

scenarios <- data.frame(
  scenario = c("Baseline\n(current)",
               "Shift 10%\ntruck to rail",
               "Eliminate\nall air freight",
               "Shift 5%\nparcel to truck"),
  co2_grams = c(baseline_co2,
                baseline_co2 - s1_saved,
                baseline_co2 - s2_saved,
                baseline_co2 - s3_saved),
  savings_pct = c(0,
                  s1_saved / baseline_co2 * 100,
                  s2_saved / baseline_co2 * 100,
                  s3_saved / baseline_co2 * 100),
  stringsAsFactors = FALSE
)
scenarios$co2_metric_tons <- scenarios$co2_grams / 1e6
scenarios$scenario <- factor(scenarios$scenario, levels = scenarios$scenario)

cat("\n=== Mode Substitution Scenarios (NYC) ===\n")
print(scenarios %>% select(scenario, co2_metric_tons, savings_pct) %>%
        mutate(across(where(is.numeric), ~round(., 1))))

p_d <- ggplot(scenarios, aes(x = scenario, y = co2_metric_tons,
                              fill = scenario == "Baseline\n(current)")) +
  geom_col(width = 0.6, alpha = 0.85) +
  geom_text(aes(label = ifelse(savings_pct > 0,
                                sprintf("-%0.1f%%", savings_pct),
                                "Baseline")),
            vjust = -0.5, size = 3.5, fontface = "bold",
            colour = c("grey30", "#4DAF4A", "#4DAF4A", "#4DAF4A")) +
  scale_fill_manual(values = c("TRUE" = "#E41A1C", "FALSE" = "#4DAF4A"),
                    guide = "none") +
  scale_y_continuous(labels = comma_format()) +
  coord_cartesian(ylim = c(0, max(scenarios$co2_metric_tons) * 1.15)) +
  labs(
    title = "D. Mode Substitution: What-If Scenarios for NYC Food Carbon",
    subtitle = "Counterfactual CO2 reduction from shifting transport modes. Even small shifts in air/parcel have outsized impact.",
    x = NULL, y = expression("Total CO"[2]*" (metric tons)")
  )

cat("Panel D built: mode substitution scenarios\n")

# ═══════════════════════════════════════════════════════════════════════════
# COMPOSE FINAL FIGURE
# ═══════════════════════════════════════════════════════════════════════════

combined <- (p_a + p_b) / (p_c + p_d) +
  plot_annotation(
    title = "Extended Analysis: Seasonality, Cold Chain, Vulnerability & Scenarios",
    subtitle = paste0(
      "Commodity Flow Survey 2017. SCTG 03-07 (produce, dairy, meat, grain, prepared food). ",
      "All estimates design-weighted.\n",
      "Extends the base food miles analysis with four new dimensions of NYC's fresh food supply chain."
    ),
    caption = paste0(
      "Data: 2017 CFS PUF (n = ", format(nrow(cfs_food), big.mark = ","),
      " food shipments) | EPA SmartWay emission factors | ",
      "survey.lonely.psu = 'adjust' | Weights-only design (SEs approximate)"
    ),
    theme = theme(
      plot.title = element_text(face = "bold", size = 16, hjust = 0.5),
      plot.subtitle = element_text(size = 10, colour = "grey30", hjust = 0.5,
                                   margin = margin(b = 15)),
      plot.caption = element_text(size = 8, colour = "grey50")
    )
  )

ggsave(file.path(out_dir, "cfs_food_miles_extended.png"),
       combined, width = 16, height = 14, dpi = 300, bg = "white")
cat("\nSaved: cfs_food_miles_extended.png\n")

ggsave(file.path(out_dir, "cfs_food_miles_extended.pdf"),
       combined, width = 16, height = 14, bg = "white")
cat("Saved: cfs_food_miles_extended.pdf\n")
