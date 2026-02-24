#!/usr/bin/env Rscript
# ===========================================================================
# CFS: Value-Weighted Food Miles & Geographic Food Origin Map
# ===========================================================================
#
# Panel A: Value density ($/ton-mile) by commodity -- which food types are
#          most economically efficient to transport?
# Panel B: Choropleth of where NYC's food originates, colored by tonnage share
#
# Uses maps package for state boundaries.
# ===========================================================================

library(dplyr)
library(tidyr)
library(ggplot2)
library(patchwork)
library(scales)
library(survey)
library(maps)

out_dir <- "/home/darshan/Documents/claude_code/agent_skills_survey"

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
  state_name = tolower(c(
    "Alabama","Alaska","Arizona","Arkansas","California","Colorado",
    "Connecticut","Delaware","District of Columbia","Florida","Georgia",
    "Hawaii","Idaho","Illinois","Indiana","Iowa","Kansas","Kentucky",
    "Louisiana","Maine","Maryland","Massachusetts","Michigan","Minnesota",
    "Mississippi","Missouri","Montana","Nebraska","Nevada","New Hampshire",
    "New Jersey","New Mexico","New York","North Carolina","North Dakota",
    "Ohio","Oklahoma","Oregon","Pennsylvania","Rhode Island",
    "South Carolina","South Dakota","Tennessee","Texas","Utah","Vermont",
    "Virginia","Washington","West Virginia","Wisconsin","Wyoming"
  )),
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
  left_join(state_fips, by = "ORIG_STATE") %>%
  mutate(
    tons = SHIPMT_WGHT / 2000,
    ton_miles = tons * SHIPMT_DIST_ROUTED,
    value_k = SHIPMT_VALUE / 1000,
    commodity = case_when(
      sctg_2d == "03" ~ "Produce",
      sctg_2d == "04" ~ "Dairy & Eggs",
      sctg_2d == "05" ~ "Meat & Seafood",
      sctg_2d == "06" ~ "Grain & Bakery",
      sctg_2d == "07" ~ "Prepared Food",
      TRUE ~ "Other"
    )
  )

cat(sprintf("Food shipments: %s\n", format(nrow(cfs_food), big.mark = ",")))

options(survey.lonely.psu = "adjust")
des_food <- svydesign(id = ~1, weights = ~WGT_FACTOR, data = cfs_food)

# =========================================================================
# PANEL A -- Value Density: $/ton and $/ton-mile by Commodity and Metro
# =========================================================================
# High $/ton-mile = expensive food travelling efficiently (high value per
# unit of transport effort). Low $/ton-mile = cheap bulk moving far.

cat("\n--- Panel A: Value-weighted analysis ---\n")

value_df <- data.frame()
for (m in metro_lookup$metro) {
  for (comm in c("Produce", "Dairy & Eggs", "Meat & Seafood",
                 "Grain & Bakery", "Prepared Food")) {
    des_sub <- subset(des_food, metro == m & commodity == comm)
    n_sub <- nrow(des_sub$variables)
    if (n_sub >= 10) {
      val_tot <- svytotal(~SHIPMT_VALUE, des_sub, na.rm = TRUE)
      ton_tot <- svytotal(~tons, des_sub, na.rm = TRUE)
      tm_tot <- svytotal(~ton_miles, des_sub, na.rm = TRUE)

      total_val <- as.numeric(coef(val_tot))
      total_tons <- as.numeric(coef(ton_tot))
      total_tm <- as.numeric(coef(tm_tot))

      value_df <- rbind(value_df, data.frame(
        metro = m, commodity = comm,
        dollars_per_ton = ifelse(total_tons > 0, total_val / total_tons, NA),
        dollars_per_tonmile = ifelse(total_tm > 0, total_val / total_tm, NA),
        total_value_M = total_val / 1e6,
        n_unwt = n_sub,
        stringsAsFactors = FALSE
      ))
    }
  }
}

cat("Value density by commodity:\n")
print(value_df %>%
        select(metro, commodity, dollars_per_ton, dollars_per_tonmile) %>%
        mutate(across(where(is.numeric), ~round(., 1))))

# $/ton-mile by commodity across metros
value_df$commodity <- factor(value_df$commodity,
  levels = c("Meat & Seafood", "Dairy & Eggs", "Prepared Food",
             "Produce", "Grain & Bakery"))

p_a <- ggplot(value_df, aes(x = metro, y = dollars_per_tonmile,
                              fill = commodity)) +
  geom_col(position = "dodge", width = 0.7, alpha = 0.85) +
  scale_fill_manual(values = sctg_cols, name = NULL) +
  scale_y_continuous(labels = dollar_format()) +
  labs(
    title = "A. Value Density: How Much Is Each Ton-Mile of Food Worth?",
    subtitle = paste0(
      "Weighted total value / total ton-miles by commodity. ",
      "Higher = more economic value per unit of transport effort.\n",
      "Meat & seafood is the most valuable per ton-mile; grain is the cheapest bulk commodity."),
    x = NULL, y = "Dollars per ton-mile"
  ) +
  theme(legend.position = "bottom",
        axis.text.x = element_text(angle = 25, hjust = 1))

cat("Panel A built.\n")

# =========================================================================
# PANEL B -- Geographic Choropleth: Where NYC's Food Comes From
# =========================================================================

cat("\n--- Panel B: Geographic map ---\n")

# Compute NYC food tonnage by origin state
des_nyc <- subset(des_food, metro == "NYC")
nyc_flows <- data.frame()
for (st in unique(des_nyc$variables$ORIG_STATE)) {
  des_st <- subset(des_nyc, ORIG_STATE == st)
  if (nrow(des_st$variables) >= 3) {
    tot <- svytotal(~tons, des_st, na.rm = TRUE)
    row <- state_fips[state_fips$ORIG_STATE == st, ]
    if (nrow(row) > 0) {
      nyc_flows <- rbind(nyc_flows, data.frame(
        state_abbr = row$state_abbr,
        state_name = row$state_name,
        total_tons = as.numeric(coef(tot)),
        stringsAsFactors = FALSE
      ))
    }
  }
}

nyc_flows$share <- nyc_flows$total_tons / sum(nyc_flows$total_tons)

cat("NYC food origins (top 10):\n")
print(nyc_flows %>% arrange(desc(share)) %>% head(10) %>%
        mutate(share = round(share, 3)))

# Merge with map data
us_map <- map_data("state")
map_df <- us_map %>%
  left_join(nyc_flows, by = c("region" = "state_name"))
map_df$share[is.na(map_df$share)] <- 0

# State centroids for labels
state_centers <- map_df %>%
  group_by(region) %>%
  summarise(long = mean(range(long)), lat = mean(range(lat)),
            share = first(share), .groups = "drop") %>%
  left_join(nyc_flows %>% select(state_name, state_abbr),
            by = c("region" = "state_name"))

# Label top states
top_labels <- state_centers %>%
  filter(share > 0.02) %>%
  mutate(label = sprintf("%s\n%.0f%%", state_abbr, share * 100))

p_b <- ggplot(map_df, aes(x = long, y = lat, group = group)) +
  geom_polygon(aes(fill = share), colour = "white", linewidth = 0.3) +
  geom_text(data = top_labels, aes(label = label, group = NULL),
            size = 2.8, fontface = "bold", colour = "white") +
  # NYC marker
  annotate("point", x = -74.0, y = 40.7, colour = "#E41A1C",
           size = 3, shape = 18) +
  annotate("text", x = -70.5, y = 40.7, label = "NYC",
           colour = "#E41A1C", size = 3.5, fontface = "bold") +
  scale_fill_gradient(low = "#f7fbff", high = "#08306b",
                      name = "Share of\nNYC food",
                      labels = percent_format(),
                      limits = c(0, max(nyc_flows$share))) +
  coord_map("albers", lat0 = 30, lat1 = 40) +
  labs(
    title = "B. NYC's Food Supply Map: Origin States by Tonnage Share",
    subtitle = paste0(
      "Weighted share of fresh food tonnage shipped to NYC metro area. ",
      "NY (34%), NJ (27%), PA (15%) dominate.\n",
      "Two-thirds of NYC's food originates outside New York state."),
    x = NULL, y = NULL
  ) +
  theme(axis.text = element_blank(),
        axis.ticks = element_blank(),
        panel.grid = element_blank())

cat("Panel B built.\n")

# =========================================================================
# COMPOSE
# =========================================================================

combined <- p_a / p_b +
  plot_layout(heights = c(1, 1.3)) +
  plot_annotation(
    title = "CFS Value Analysis & Geographic Food Map",
    subtitle = paste0(
      "Commodity Flow Survey 2017. SCTG 03-07. All estimates design-weighted. ",
      "n = ", format(nrow(cfs_food), big.mark = ","), " food shipments."
    ),
    caption = paste0(
      "Data: 2017 CFS PUF | map_data('state') via maps package | ",
      "survey.lonely.psu = 'adjust' | Weights-only design (SEs approximate)"
    ),
    theme = theme(
      plot.title = element_text(face = "bold", size = 16, hjust = 0.5),
      plot.subtitle = element_text(size = 10, colour = "grey30", hjust = 0.5,
                                   margin = margin(b = 15)),
      plot.caption = element_text(size = 8, colour = "grey50")
    )
  )

ggsave(file.path(out_dir, "cfs_food_value_map.png"),
       combined, width = 14, height = 16, dpi = 300, bg = "white")
cat("\nSaved: cfs_food_value_map.png\n")

ggsave(file.path(out_dir, "cfs_food_value_map.pdf"),
       combined, width = 14, height = 16, bg = "white")
cat("Saved: cfs_food_value_map.pdf\n")
