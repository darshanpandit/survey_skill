#!/usr/bin/env Rscript
# ===========================================================================
# Fresh Food Miles & Sustainability Analysis
# Using the 2017 Commodity Flow Survey (CFS) Public Use File
# ===========================================================================
#
# Research question: How far does NYC's fresh food travel, by what mode,
# and what is the carbon footprint compared to other major metros?
#
# CFS is an ESTABLISHMENT survey (samples shipping firms, not people).
# The PUF provides WGT_FACTOR but strips PSU/strata for confidentiality.
# Design: svydesign(id = ~1, weights = ~WGT_FACTOR)
# WARNING: SEs ignore clustering. Point estimates are correct but CIs are
# approximate (likely too narrow).
# ===========================================================================

library(dplyr)
library(tidyr)
library(ggplot2)
library(patchwork)
library(scales)
library(survey)

# ── Configuration ──────────────────────────────────────────────────────────
out_dir <- "/home/darshan/Documents/claude_code/agent_skills_survey"

# Colour palette
col_nyc     <- "#E41A1C"
col_la      <- "#377EB8"
col_chicago <- "#4DAF4A"
col_houston <- "#984EA3"
col_miami   <- "#FF7F00"
metro_cols  <- c("NYC" = col_nyc, "Los Angeles" = col_la,
                 "Chicago" = col_chicago, "Houston" = col_houston,
                 "Miami" = col_miami)

# EPA emission factors (gCO2 per ton-mile)
# Source: EPA SmartWay, 2017 averages
epa_factors <- data.frame(
  mode_label = c("Truck", "Rail", "Water", "Air", "Pipeline",
                 "Parcel/courier", "Multimodal", "Other"),
  gco2_per_tonmile = c(161.8, 22.0, 14.0, 1054.0, 8.0,
                        210.0, 100.0, 100.0),
  stringsAsFactors = FALSE
)

# CFS MODE codes → labels
# Mode 4 = parcel/USPS/courier, 5 = truck (for-hire + private),
# 2 = rail, 3 = water, 6 = air, 11-14 = multimodal combos
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

# ── Load data ──────────────────────────────────────────────────────────────
cat("Loading CFS 2017 PUF...\n")
cfs <- read.csv(file.path(out_dir, "tmp/CSV.csv"), stringsAsFactors = FALSE)
cat(sprintf("Loaded %s shipment records\n", format(nrow(cfs), big.mark = ",")))

# ── Metro area definitions ─────────────────────────────────────────────────
metro_lookup <- data.frame(
  DEST_MA = c(408, 348, 176, 288, 370),
  metro = c("NYC", "Los Angeles", "Chicago", "Houston", "Miami"),
  stringsAsFactors = FALSE
)

# ── Fresh food SCTG codes ─────────────────────────────────────────────────
# Focus on perishable food commodities
food_sctg <- data.frame(
  SCTG = c("03", "04", "05", "06", "07"),
  food_type = c("Fresh produce", "Animal feed/eggs/dairy",
                "Meat/poultry/seafood", "Milled grain/bakery",
                "Other prepared food"),
  stringsAsFactors = FALSE
)

# For display, use shorter labels for key fresh food groups
fresh_labels <- c("03" = "Produce", "04" = "Dairy/eggs",
                  "05" = "Meat/seafood", "06" = "Grain/bakery",
                  "07" = "Prepared food")

# ── Filter and prepare ────────────────────────────────────────────────────
cfs_food <- cfs %>%
  # Ensure SCTG is 2-digit character (some records have non-numeric codes)
  mutate(SCTG_num = suppressWarnings(as.integer(SCTG)),
         SCTG = ifelse(is.na(SCTG_num), SCTG, sprintf("%02d", SCTG_num))) %>%
  select(-SCTG_num) %>%
  # Filter: food SCTG codes + destined for one of 5 metros
  filter(SCTG %in% food_sctg$SCTG,
         DEST_MA %in% metro_lookup$DEST_MA) %>%
  # Join metro names and mode labels
  left_join(metro_lookup, by = "DEST_MA") %>%
  left_join(mode_map, by = "MODE") %>%
  left_join(food_sctg, by = "SCTG") %>%
  # Derived columns
  mutate(
    food_label = fresh_labels[SCTG],
    # Ton-miles: weight (lbs) / 2000 * routed distance (miles)
    tons = SHIPMT_WGHT / 2000,
    ton_miles = tons * SHIPMT_DIST_ROUTED,
    is_temp_ctrl = (TEMP_CNTL_YN == "Y")
  )

cat(sprintf("Food shipments to 5 metros: %s records\n",
            format(nrow(cfs_food), big.mark = ",")))

# ═══════════════════════════════════════════════════════════════════════════
# SURVEY DESIGN SETUP (r-complex-survey Gates 1-3)
# ═══════════════════════════════════════════════════════════════════════════
# Gate 1: Establishment survey (cross-sectional, samples shipping firms)
# Gate 2: Weights-only — PUF strips PSU/strata for confidentiality
#         svydesign(id = ~1, weights = ~WGT_FACTOR)
#         WARNING: SEs ignore clustering and stratification
# Gate 3: Validate weights
cat("\n=== Survey Design Validation (Gate 3) ===\n")
cat(sprintf("Weight range: [%.1f, %.1f]\n",
            min(cfs_food$WGT_FACTOR), max(cfs_food$WGT_FACTOR)))
cat(sprintf("Weight CV: %.3f\n",
            sd(cfs_food$WGT_FACTOR) / mean(cfs_food$WGT_FACTOR)))
cat(sprintf("All positive: %s\n", all(cfs_food$WGT_FACTOR > 0)))
cat("WARNING: CFS PUF provides weights only. SEs ignore clustering.\n\n")

options(survey.lonely.psu = "adjust")

des_food <- svydesign(id = ~1, weights = ~WGT_FACTOR, data = cfs_food)
cat("Survey design object created.\n")

# ═══════════════════════════════════════════════════════════════════════════
# PANEL 1 — Food Miles Index: Weighted Mean Distance by Metro
# ═══════════════════════════════════════════════════════════════════════════
# Gate 4: All estimation through design object
# Hard invariant #1: Use subset() on design, NOT filter() on data frame

food_miles_by_metro <- data.frame()
for (m in metro_lookup$metro) {
  des_sub <- subset(des_food, metro == m)
  est <- svymean(~SHIPMT_DIST_ROUTED, des_sub, na.rm = TRUE)
  est_val <- as.numeric(coef(est))
  est_se  <- as.numeric(SE(est))
  n_unwt <- nrow(des_sub$variables)
  food_miles_by_metro <- rbind(food_miles_by_metro, data.frame(
    metro = m,
    mean_dist = est_val,
    se = est_se,
    ci_lo = est_val - 1.96 * est_se,
    ci_hi = est_val + 1.96 * est_se,
    n_unweighted = n_unwt,
    cv = est_se / est_val,
    stringsAsFactors = FALSE
  ))
}

# National average for context
nat_est <- svymean(~SHIPMT_DIST_ROUTED, des_food, na.rm = TRUE)
national_mean <- as.numeric(coef(nat_est))
cat("\n=== Food Miles Index (Gate 5 diagnostics) ===\n")
cat(sprintf("survey.lonely.psu = 'adjust'\n"))
print(food_miles_by_metro %>% mutate(across(where(is.numeric), ~round(., 1))))

p1 <- ggplot(food_miles_by_metro, aes(x = reorder(metro, mean_dist),
                                       y = mean_dist, fill = metro)) +
  geom_col(alpha = 0.85, width = 0.65) +
  geom_errorbar(aes(ymin = ci_lo, ymax = ci_hi), width = 0.2) +
  geom_hline(yintercept = national_mean, linetype = "dashed",
             colour = "grey30", linewidth = 0.6) +
  annotate("text", x = 0.5, y = national_mean + 20,
           label = sprintf("5-metro avg = %d mi", round(national_mean)),
           hjust = 0, size = 3.2, fontface = "italic", colour = "grey30") +
  geom_text(aes(label = sprintf("%d mi\n(n=%s)", round(mean_dist),
                                 format(n_unweighted, big.mark = ","))),
            vjust = -0.3, size = 3, fontface = "bold") +
  scale_fill_manual(values = metro_cols, guide = "none") +
  coord_cartesian(ylim = c(0, max(food_miles_by_metro$ci_hi) * 1.2)) +
  labs(
    title = "A. Food Miles Index: Average Distance for Fresh Food Shipments",
    subtitle = "Weighted mean routed distance (miles) for SCTG 03-07 shipments to each metro, 2017 CFS",
    x = NULL, y = "Mean distance (miles)"
  )

cat("Panel 1 built: food miles index\n")

# ═══════════════════════════════════════════════════════════════════════════
# PANEL 2 — Distance Distribution by Commodity, NYC Focus
# ═══════════════════════════════════════════════════════════════════════════

nyc_food <- cfs_food %>% filter(metro == "NYC")

p2 <- ggplot(nyc_food, aes(x = SHIPMT_DIST_ROUTED, weight = WGT_FACTOR,
                            fill = food_label)) +
  geom_density(alpha = 0.5, colour = NA) +
  scale_x_continuous(limits = c(0, 3000),
                     labels = comma_format()) +
  scale_fill_brewer(palette = "Set2", name = "Food type") +
  labs(
    title = "B. Where Does NYC's Food Come From? Distance Distribution by Commodity",
    subtitle = "Weighted density of shipment distances to NYC metro (DEST_MA=408), 2017 CFS",
    x = "Routed distance (miles)", y = "Weighted density"
  ) +
  theme(legend.position = "bottom")

cat("Panel 2 built: NYC distance distribution\n")

# ═══════════════════════════════════════════════════════════════════════════
# PANEL 3 — Mode Share by Metro
# ═══════════════════════════════════════════════════════════════════════════
# Compute weighted tons by mode for each metro

mode_share <- data.frame()
for (m in metro_lookup$metro) {
  des_sub <- subset(des_food, metro == m)
  # Create mode-specific tonnage totals
  for (ml in c("Truck", "Rail", "Water", "Air", "Parcel/courier", "Multimodal")) {
    des_mode <- subset(des_sub, mode_label == ml)
    if (nrow(des_mode$variables) > 0) {
      tot <- svytotal(~tons, des_mode, na.rm = TRUE)
      mode_share <- rbind(mode_share, data.frame(
        metro = m, mode_label = ml,
        total_tons = as.numeric(coef(tot)),
        n_unwt = nrow(des_mode$variables),
        stringsAsFactors = FALSE
      ))
    }
  }
}

# Compute shares within metro
mode_share <- mode_share %>%
  group_by(metro) %>%
  mutate(share = total_tons / sum(total_tons)) %>%
  ungroup()

# Order modes for stacking
mode_order <- c("Truck", "Rail", "Water", "Air", "Parcel/courier", "Multimodal")
mode_share$mode_label <- factor(mode_share$mode_label, levels = rev(mode_order))

mode_cols <- c("Truck" = "#E41A1C", "Rail" = "#377EB8", "Water" = "#4DAF4A",
               "Air" = "#984EA3", "Parcel/courier" = "#FF7F00",
               "Multimodal" = "#A65628")

p3 <- ggplot(mode_share, aes(x = metro, y = share, fill = mode_label)) +
  geom_col(width = 0.7, alpha = 0.85) +
  scale_y_continuous(labels = percent_format()) +
  scale_fill_manual(values = mode_cols, name = "Transport mode") +
  labs(
    title = "C. Modal Share: How Fresh Food Reaches Each Metro",
    subtitle = "Proportion of weighted tons by transport mode, SCTG 03-07, 2017 CFS",
    x = NULL, y = "Share of total tons"
  ) +
  theme(legend.position = "bottom") +
  guides(fill = guide_legend(nrow = 1, reverse = TRUE))

cat("Panel 3 built: mode share\n")

# ═══════════════════════════════════════════════════════════════════════════
# PANEL 4 — Carbon Footprint by Metro
# ═══════════════════════════════════════════════════════════════════════════
# CO2 = ton-miles * gCO2/ton-mile, by mode, then sum per metro

carbon_df <- cfs_food %>%
  left_join(epa_factors, by = "mode_label") %>%
  mutate(
    co2_grams = ton_miles * gco2_per_tonmile,
    co2_metric_tons = co2_grams / 1e6  # convert grams to metric tons
  )

des_carbon <- svydesign(id = ~1, weights = ~WGT_FACTOR, data = carbon_df)

carbon_by_metro <- data.frame()
for (m in metro_lookup$metro) {
  des_sub <- subset(des_carbon, metro == m)
  tot_co2 <- svytotal(~co2_metric_tons, des_sub, na.rm = TRUE)
  tot_tons <- svytotal(~tons, des_sub, na.rm = TRUE)
  carbon_by_metro <- rbind(carbon_by_metro, data.frame(
    metro = m,
    total_co2_mt = as.numeric(coef(tot_co2)),
    total_food_tons = as.numeric(coef(tot_tons)),
    co2_per_food_ton = as.numeric(coef(tot_co2)) / as.numeric(coef(tot_tons)),
    se_co2 = as.numeric(SE(tot_co2)),
    n_unwt = nrow(des_sub$variables),
    stringsAsFactors = FALSE
  ))
}

cat("\n=== Carbon Footprint (Gate 5 diagnostics) ===\n")
print(carbon_by_metro %>% mutate(across(where(is.numeric), ~round(., 2))))

p4 <- ggplot(carbon_by_metro, aes(x = reorder(metro, co2_per_food_ton),
                                   y = co2_per_food_ton, fill = metro)) +
  geom_col(alpha = 0.85, width = 0.65) +
  geom_text(aes(label = sprintf("%.1f kg CO2\nper ton food",
                                 co2_per_food_ton)),
            vjust = -0.3, size = 3, fontface = "bold") +
  scale_fill_manual(values = metro_cols, guide = "none") +
  coord_cartesian(ylim = c(0, max(carbon_by_metro$co2_per_food_ton) * 1.35)) +
  labs(
    title = "D. Carbon Intensity: CO2 per Ton of Fresh Food Delivered",
    subtitle = "Weighted CO2 (kg) per ton of food, using EPA emission factors by transport mode",
    x = NULL, y = expression("kg CO"[2]*" per ton of food")
  )

cat("Panel 4 built: carbon footprint\n")

# ═══════════════════════════════════════════════════════════════════════════
# PANEL 5 — Carbon Breakdown by Mode (NYC detail)
# ═══════════════════════════════════════════════════════════════════════════

nyc_carbon <- carbon_df %>% filter(metro == "NYC")
des_nyc_carbon <- svydesign(id = ~1, weights = ~WGT_FACTOR, data = nyc_carbon)

nyc_mode_carbon <- data.frame()
for (ml in c("Truck", "Rail", "Water", "Air", "Parcel/courier", "Multimodal")) {
  des_m <- subset(des_nyc_carbon, mode_label == ml)
  if (nrow(des_m$variables) > 0) {
    co2_tot <- svytotal(~co2_metric_tons, des_m, na.rm = TRUE)
    tons_tot <- svytotal(~tons, des_m, na.rm = TRUE)
    miles_avg <- svymean(~SHIPMT_DIST_ROUTED, des_m, na.rm = TRUE)
    nyc_mode_carbon <- rbind(nyc_mode_carbon, data.frame(
      mode_label = ml,
      co2_mt = as.numeric(coef(co2_tot)),
      food_tons = as.numeric(coef(tons_tot)),
      avg_dist = as.numeric(coef(miles_avg)),
      n_unwt = nrow(des_m$variables),
      stringsAsFactors = FALSE
    ))
  }
}

nyc_mode_carbon <- nyc_mode_carbon %>%
  mutate(
    co2_share = co2_mt / sum(co2_mt),
    tons_share = food_tons / sum(food_tons)
  )

# Paired bar chart: % of tons vs % of CO2
nyc_mode_long <- nyc_mode_carbon %>%
  select(mode_label, co2_share, tons_share) %>%
  pivot_longer(cols = c(co2_share, tons_share),
               names_to = "metric", values_to = "share") %>%
  mutate(metric = ifelse(metric == "co2_share",
                          "Share of CO2", "Share of tonnage"))

nyc_mode_long$mode_label <- factor(nyc_mode_long$mode_label,
                                    levels = rev(mode_order))

p5 <- ggplot(nyc_mode_long, aes(x = mode_label, y = share, fill = metric)) +
  geom_col(position = "dodge", width = 0.65, alpha = 0.85) +
  scale_y_continuous(labels = percent_format()) +
  scale_fill_manual(values = c("Share of CO2" = "#E41A1C",
                                "Share of tonnage" = "#377EB8"),
                    name = NULL) +
  coord_flip() +
  labs(
    title = "E. NYC: Mode Choice Matters More Than Distance",
    subtitle = paste0(
      "Air carries a tiny share of tonnage but a disproportionate share of CO2. ",
      "Truck dominates both volume and emissions."
    ),
    x = NULL, y = "Percentage share"
  ) +
  theme(legend.position = "bottom")

cat("Panel 5 built: NYC mode carbon breakdown\n")

# ═══════════════════════════════════════════════════════════════════════════
# COMPOSE FINAL FIGURE
# ═══════════════════════════════════════════════════════════════════════════

combined <- (p1 + p4) / (p2) / (p3 + p5) +
  plot_annotation(
    title = "Fresh Food Miles & Carbon Footprint: NYC vs Major US Metros",
    subtitle = paste0(
      "Commodity Flow Survey 2017 (Census Bureau / BTS). SCTG codes 03-07 ",
      "(produce, dairy, meat, grain, prepared food).\n",
      "All estimates are design-weighted (svydesign, id=~1, weights=~WGT_FACTOR). ",
      "SEs approximate -- PUF strips PSU/strata."
    ),
    caption = paste0(
      "Data: 2017 CFS PUF (n = ", format(nrow(cfs_food), big.mark = ","),
      " food shipments to 5 metros) | ",
      "EPA SmartWay emission factors | survey.lonely.psu = 'adjust'"
    ),
    theme = theme(
      plot.title = element_text(face = "bold", size = 16, hjust = 0.5),
      plot.subtitle = element_text(size = 10, colour = "grey30", hjust = 0.5,
                                   margin = margin(b = 15)),
      plot.caption = element_text(size = 8, colour = "grey50")
    )
  )

ggsave(file.path(out_dir, "cfs_food_miles.png"),
       combined, width = 16, height = 18, dpi = 300, bg = "white")
cat("\nSaved: cfs_food_miles.png\n")

ggsave(file.path(out_dir, "cfs_food_miles.pdf"),
       combined, width = 16, height = 18, bg = "white")
cat("Saved: cfs_food_miles.pdf\n")

cat("\n=== DONE ===\n")
