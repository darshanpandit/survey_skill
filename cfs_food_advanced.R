#!/usr/bin/env Rscript
# ===========================================================================
# Advanced CFS Analysis: Commodity Carbon, Food Network, Weight Sensitivity
# Using the 2017 Commodity Flow Survey (CFS) Public Use File
# ===========================================================================
#
# Three panels:
#   A. Commodity-level carbon decomposition (CO2 share vs tonnage share)
#   B. Inbound food network (origin state -> metro heatmap)
#   C. Weight sensitivity (trimmed weights -> estimate stability)
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

sctg_cols <- c("Produce" = "#4DAF4A", "Dairy & Eggs" = "#377EB8",
               "Meat & Seafood" = "#E41A1C", "Grain & Bakery" = "#FF7F00",
               "Prepared Food" = "#984EA3")

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
  filter(DEST_MA %in% metro_lookup$DEST_MA) %>%
  left_join(metro_lookup, by = "DEST_MA") %>%
  mutate(sctg_2d = sprintf("%02d", suppressWarnings(as.integer(SCTG)))) %>%
  filter(sctg_2d %in% food_sctg_codes) %>%
  left_join(mode_map, by = "MODE") %>%
  left_join(epa_factors, by = "mode_label") %>%
  left_join(state_fips, by = "ORIG_STATE") %>%
  mutate(
    tons = SHIPMT_WGHT / 2000,
    ton_miles = tons * SHIPMT_DIST_ROUTED,
    co2_grams = ton_miles * gco2_per_tonmile,
    commodity = case_when(
      sctg_2d == "03" ~ "Produce",
      sctg_2d == "04" ~ "Dairy & Eggs",
      sctg_2d == "05" ~ "Meat & Seafood",
      sctg_2d == "06" ~ "Grain & Bakery",
      sctg_2d == "07" ~ "Prepared Food",
      TRUE ~ "Other"
    )
  )

cat(sprintf("Food shipments to 5 metros: %s\n", format(nrow(cfs_food), big.mark = ",")))

options(survey.lonely.psu = "adjust")
des_food <- svydesign(id = ~1, weights = ~WGT_FACTOR, data = cfs_food)

# =========================================================================
# PANEL A -- Commodity-level Carbon Decomposition
# =========================================================================
# Which food types drive the most transport emissions? Compare CO2 share
# to tonnage share -- if a commodity's CO2 share exceeds its tonnage share,
# it travels farther or uses dirtier modes.

cat("\n--- Panel A: Commodity Carbon ---\n")

commodity_carbon <- data.frame()
for (m in metro_lookup$metro) {
  for (comm in c("Produce", "Dairy & Eggs", "Meat & Seafood",
                 "Grain & Bakery", "Prepared Food")) {
    des_sub <- subset(des_food, metro == m & commodity == comm)
    n_sub <- nrow(des_sub$variables)
    if (n_sub >= 10) {
      co2_tot <- svytotal(~co2_grams, des_sub, na.rm = TRUE)
      tons_tot <- svytotal(~tons, des_sub, na.rm = TRUE)
      commodity_carbon <- rbind(commodity_carbon, data.frame(
        metro = m, commodity = comm,
        co2_metric_tons = as.numeric(coef(co2_tot)) / 1e6,
        total_tons = as.numeric(coef(tons_tot)),
        n_unwt = n_sub,
        stringsAsFactors = FALSE
      ))
    }
  }
}

commodity_carbon <- commodity_carbon %>%
  group_by(metro) %>%
  mutate(co2_share = co2_metric_tons / sum(co2_metric_tons),
         tons_share = total_tons / sum(total_tons)) %>%
  ungroup()

cat("Commodity carbon by metro:\n")
print(commodity_carbon %>%
        select(metro, commodity, co2_share, tons_share) %>%
        mutate(across(where(is.numeric), ~round(., 3))))

# Two stacked bar panels side by side
commodity_carbon$commodity <- factor(commodity_carbon$commodity,
  levels = c("Prepared Food", "Grain & Bakery", "Meat & Seafood",
             "Dairy & Eggs", "Produce"))

p_a1 <- ggplot(commodity_carbon,
               aes(x = metro, y = co2_share, fill = commodity)) +
  geom_col(width = 0.65, alpha = 0.85) +
  scale_fill_manual(values = sctg_cols, name = NULL) +
  scale_y_continuous(labels = percent_format()) +
  labs(title = "A. Which Foods Drive Transport Emissions?",
       subtitle = "Left: share of CO2. Right: share of tonnage. If CO2 share > tonnage share, that commodity is carbon-intensive.",
       x = NULL, y = "Share of transport CO2") +
  theme(legend.position = "bottom",
        axis.text.x = element_text(angle = 25, hjust = 1))

p_a2 <- ggplot(commodity_carbon,
               aes(x = metro, y = tons_share, fill = commodity)) +
  geom_col(width = 0.65, alpha = 0.85) +
  scale_fill_manual(values = sctg_cols, guide = "none") +
  scale_y_continuous(labels = percent_format()) +
  labs(x = NULL, y = "Share of tonnage") +
  theme(axis.text.x = element_text(angle = 25, hjust = 1))

p_a <- p_a1 + p_a2 + plot_layout(widths = c(1.15, 1))

cat("Panel A built.\n")

# =========================================================================
# PANEL B -- Inbound Food Network (Origin State -> Metro)
# =========================================================================
# For each metro, what fraction of food tonnage comes from each origin
# state? Shows geographic dependence and supply chain geography.

cat("\n--- Panel B: Food Network ---\n")

flow_df <- data.frame()
for (m in metro_lookup$metro) {
  des_sub <- subset(des_food, metro == m)
  for (st in unique(des_sub$variables$ORIG_STATE)) {
    des_st <- subset(des_sub, ORIG_STATE == st)
    if (nrow(des_st$variables) >= 5) {
      tot <- svytotal(~tons, des_st, na.rm = TRUE)
      abbr <- state_fips$state_abbr[state_fips$ORIG_STATE == st]
      if (length(abbr) == 0) abbr <- paste0("ST", st)
      flow_df <- rbind(flow_df, data.frame(
        metro = m, state = abbr,
        total_tons = as.numeric(coef(tot)),
        stringsAsFactors = FALSE
      ))
    }
  }
}

# Top 15 origin states by total tonnage across all metros
top_states <- flow_df %>%
  group_by(state) %>%
  summarise(total = sum(total_tons), .groups = "drop") %>%
  arrange(desc(total)) %>%
  head(15) %>%
  pull(state)

flow_top <- flow_df %>%
  filter(state %in% top_states) %>%
  group_by(metro) %>%
  mutate(share = total_tons / sum(total_tons)) %>%
  ungroup()

flow_top$state <- factor(flow_top$state, levels = rev(top_states))

cat("Top origin states:\n")
print(flow_top %>%
        select(metro, state, share) %>%
        pivot_wider(names_from = metro, values_from = share) %>%
        mutate(across(where(is.numeric), ~round(., 3))))

p_b <- ggplot(flow_top, aes(x = metro, y = state, fill = share)) +
  geom_tile(colour = "white", linewidth = 0.5) +
  geom_text(aes(label = ifelse(share > 0.04,
                                sprintf("%.0f%%", share * 100), "")),
            colour = "white", size = 3, fontface = "bold") +
  scale_fill_gradient(low = "#f7fbff", high = "#08519c",
                      name = "Share of\ntonnage",
                      labels = percent_format()) +
  labs(
    title = "B. Where Does Each Metro's Food Come From?",
    subtitle = "Weighted food tonnage share by origin state (top 15 nationally). Darker = larger share.",
    x = NULL, y = NULL
  ) +
  theme(axis.text.x = element_text(angle = 25, hjust = 1),
        panel.grid = element_blank())

cat("Panel B built.\n")

# =========================================================================
# PANEL C -- Weight Sensitivity Analysis
# =========================================================================
# The CFS has extreme weight dispersion (max/min ~ 1M). How much do
# our estimates change when we trim the most extreme weights?

cat("\n--- Panel C: Weight Sensitivity ---\n")

trim_levels <- c(1.0, 0.99, 0.975, 0.95, 0.90)

sensitivity_df <- data.frame()
for (trim in trim_levels) {
  if (trim < 1.0) {
    threshold <- quantile(cfs_food$WGT_FACTOR, trim)
    cfs_trimmed <- cfs_food
    cfs_trimmed$WGT_TRIMMED <- pmin(cfs_food$WGT_FACTOR, threshold)
    trim_label <- sprintf("Trim top %g%%", (1 - trim) * 100)
  } else {
    cfs_trimmed <- cfs_food
    cfs_trimmed$WGT_TRIMMED <- cfs_food$WGT_FACTOR
    trim_label <- "No trimming"
  }

  des_trim <- svydesign(id = ~1, weights = ~WGT_TRIMMED, data = cfs_trimmed)

  for (m in metro_lookup$metro) {
    des_sub <- subset(des_trim, metro == m)
    if (nrow(des_sub$variables) >= 20) {
      est <- svymean(~SHIPMT_DIST_ROUTED, des_sub, na.rm = TRUE)
      sensitivity_df <- rbind(sensitivity_df, data.frame(
        trim = trim, trim_label = trim_label,
        metro = m,
        mean_dist = as.numeric(coef(est)),
        se = as.numeric(SE(est)),
        stringsAsFactors = FALSE
      ))
    }
  }
}

sensitivity_df$trim_label <- factor(sensitivity_df$trim_label,
  levels = c("No trimming", "Trim top 1%", "Trim top 2.5%",
             "Trim top 5%", "Trim top 10%"))

cat("Weight sensitivity:\n")
print(sensitivity_df %>%
        select(trim_label, metro, mean_dist) %>%
        pivot_wider(names_from = metro, values_from = mean_dist) %>%
        mutate(across(where(is.numeric), ~round(., 0))))

p_c <- ggplot(sensitivity_df, aes(x = trim_label, y = mean_dist,
                                   colour = metro, group = metro)) +
  geom_line(linewidth = 0.8) +
  geom_point(size = 2.5) +
  geom_errorbar(aes(ymin = mean_dist - 1.96 * se,
                     ymax = mean_dist + 1.96 * se),
                width = 0.15, alpha = 0.5) +
  scale_colour_manual(values = metro_cols, name = NULL) +
  labs(
    title = "C. How Sensitive Are Food Miles to Extreme Weights?",
    subtitle = "Weighted mean distance under progressive weight trimming. Stable lines = robust estimates. Large shifts = outlier-driven.",
    x = "Weight trimming threshold", y = "Weighted mean distance (miles)"
  ) +
  theme(legend.position = "bottom",
        axis.text.x = element_text(angle = 20, hjust = 1))

cat("Panel C built.\n")

# =========================================================================
# COMPOSE FINAL FIGURE
# =========================================================================

combined <- p_a / p_b / p_c +
  plot_annotation(
    title = "Advanced CFS Analysis: Commodity Carbon, Food Network, Weight Sensitivity",
    subtitle = paste0(
      "Commodity Flow Survey 2017. SCTG 03-07 (produce, dairy, meat, grain, prepared food). ",
      "All estimates design-weighted.\n",
      "n = ", format(nrow(cfs_food), big.mark = ","), " food shipments to 5 metros."
    ),
    caption = paste0(
      "Data: 2017 CFS PUF | EPA SmartWay emission factors | ",
      "survey.lonely.psu = 'adjust' | Weights-only design (SEs approximate)"
    ),
    theme = theme(
      plot.title = element_text(face = "bold", size = 16, hjust = 0.5),
      plot.subtitle = element_text(size = 10, colour = "grey30", hjust = 0.5,
                                   margin = margin(b = 15)),
      plot.caption = element_text(size = 8, colour = "grey50")
    )
  )

ggsave(file.path(out_dir, "cfs_food_advanced.png"),
       combined, width = 16, height = 22, dpi = 300, bg = "white")
cat("\nSaved: cfs_food_advanced.png\n")

ggsave(file.path(out_dir, "cfs_food_advanced.pdf"),
       combined, width = 16, height = 22, bg = "white")
cat("Saved: cfs_food_advanced.pdf\n")
