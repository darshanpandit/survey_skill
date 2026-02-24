#!/usr/bin/env Rscript
# ===========================================================================
# NHANES: Design Effects in Health Equity Research
# ===========================================================================
#
# NHANES 2017-2018 (pre-pandemic cycle). Downloads data from CDC via nhanesA.
#
# Panel A: Diabetes prevalence by race/ethnicity -- design-aware vs naive.
#          Shows how ignoring the complex design and oversampling changes
#          health disparity estimates.
# Panel B: Design effect (DEFF) by health variable.
#          Shows how much NHANES clustering inflates SEs for different
#          health outcomes.
#
# r-complex-survey gates:
#   Gate 1: Cross-sectional household survey with oversampling of minorities
#   Gate 2: svydesign(id=~SDMVPSU, strata=~SDMVSTRA, weights=~WTMEC2YR, nest=TRUE)
#   Gate 3: Validate PSU/strata/weights present, all positive
#   Gate 4: All estimates through svymean(), subset() on design
#   Gate 5: SEs, CIs, DEFF, unweighted n reported
# ===========================================================================

library(dplyr)
library(tidyr)
library(ggplot2)
library(patchwork)
library(scales)
library(survey)
library(nhanesA)

out_dir <- "/home/darshan/Documents/claude_code/agent_skills_survey"

theme_set(theme_minimal(base_size = 12) +
            theme(plot.title = element_text(face = "bold", size = 13),
                  plot.subtitle = element_text(colour = "grey40", size = 10)))

race_cols <- c("Mexican American" = "#E41A1C",
               "Other Hispanic" = "#FF7F00",
               "Non-Hispanic White" = "#377EB8",
               "Non-Hispanic Black" = "#4DAF4A",
               "Non-Hispanic Asian" = "#984EA3",
               "Other/Multi" = "#A65628")

# ── Download NHANES 2017-2018 tables ─────────────────────────────────────
cat("Downloading NHANES 2017-2018 demographics...\n")
demo <- nhanes("DEMO_J")

cat("Downloading NHANES 2017-2018 glycohemoglobin (HbA1c)...\n")
ghb <- nhanes("GHB_J")

cat("Downloading NHANES 2017-2018 body measures...\n")
bmx <- nhanes("BMX_J")

cat("Downloading NHANES 2017-2018 blood pressure...\n")
bpx <- nhanes("BPX_J")

# ── Merge ─────────────────────────────────────────────────────────────────
df <- demo %>%
  left_join(ghb, by = "SEQN") %>%
  left_join(bmx %>% select(SEQN, BMXBMI), by = "SEQN") %>%
  left_join(bpx %>% select(SEQN, BPXSY1), by = "SEQN")

# Recode race/ethnicity (nhanesA returns RIDRETH3 as factor with labels)
df$race <- as.character(df$RIDRETH3)
df$race[df$race == "Other Race - Including Multi-Racial"] <- "Other/Multi"
# Anything not in our expected set becomes NA
valid_races <- c("Mexican American", "Other Hispanic", "Non-Hispanic White",
                 "Non-Hispanic Black", "Non-Hispanic Asian", "Other/Multi")
df$race[!(df$race %in% valid_races)] <- NA

# Create health indicators
df$has_diabetes <- as.numeric(!is.na(df$LBXGH) & df$LBXGH >= 6.5)
df$has_prediabetes <- as.numeric(!is.na(df$LBXGH) &
                                   df$LBXGH >= 5.7 & df$LBXGH < 6.5)
df$is_obese <- as.numeric(!is.na(df$BMXBMI) & df$BMXBMI >= 30)
df$has_hypertension <- as.numeric(!is.na(df$BPXSY1) & df$BPXSY1 >= 140)

# Filter to adults 20+ with MEC exam weight
df_adult <- df %>%
  filter(RIDAGEYR >= 20 & !is.na(WTMEC2YR) & WTMEC2YR > 0 &
         !is.na(SDMVPSU) & !is.na(SDMVSTRA))

cat(sprintf("NHANES 2017-2018 adults 20+: n = %d\n", nrow(df_adult)))

# ── Gate 3: Validate ─────────────────────────────────────────────────────
cat("\n--- Gate 3: Validation ---\n")
cat(sprintf("  Weight range: [%.1f, %.1f]\n",
            min(df_adult$WTMEC2YR), max(df_adult$WTMEC2YR)))
cat(sprintf("  Weight CV: %.3f\n",
            sd(df_adult$WTMEC2YR) / mean(df_adult$WTMEC2YR)))
cat(sprintf("  Max/min ratio: %.0f\n",
            max(df_adult$WTMEC2YR) / min(df_adult$WTMEC2YR)))
cat(sprintf("  Unique PSUs: %d\n", n_distinct(df_adult$SDMVPSU)))
cat(sprintf("  Unique strata: %d\n", n_distinct(df_adult$SDMVSTRA)))

# ── Create survey design ─────────────────────────────────────────────────
options(survey.lonely.psu = "adjust")
des <- svydesign(id = ~SDMVPSU, strata = ~SDMVSTRA,
                  weights = ~WTMEC2YR, data = df_adult, nest = TRUE)

cat("Survey design created.\n")

# =========================================================================
# PANEL A -- Diabetes Prevalence by Race: Design-Aware vs Naive
# =========================================================================
# NHANES oversamples minorities. Ignoring this oversampling inflates
# minority-specific estimates relative to the population.

cat("\n--- Panel A: Diabetes by race ---\n")

races <- c("Mexican American", "Other Hispanic", "Non-Hispanic White",
           "Non-Hispanic Black", "Non-Hispanic Asian")

diabetes_df <- data.frame()
for (r in races) {
  # Design-aware estimate
  des_r <- subset(des, race == r & !is.na(has_diabetes))
  est_wt <- svymean(~has_diabetes, des_r)
  n_wt <- nrow(des_r$variables)

  # Naive (unweighted) estimate
  naive_data <- df_adult %>% filter(race == r & !is.na(has_diabetes))
  est_naive <- mean(naive_data$has_diabetes)
  se_naive <- sqrt(est_naive * (1 - est_naive) / nrow(naive_data))

  diabetes_df <- rbind(diabetes_df, data.frame(
    race = r,
    method = "Design-weighted",
    prevalence = as.numeric(coef(est_wt)),
    se = as.numeric(SE(est_wt)),
    n = n_wt,
    stringsAsFactors = FALSE
  ))
  diabetes_df <- rbind(diabetes_df, data.frame(
    race = r,
    method = "Naive (unweighted)",
    prevalence = est_naive,
    se = se_naive,
    n = nrow(naive_data),
    stringsAsFactors = FALSE
  ))
}

diabetes_df$ci_lo <- diabetes_df$prevalence - 1.96 * diabetes_df$se
diabetes_df$ci_hi <- diabetes_df$prevalence + 1.96 * diabetes_df$se

cat("Diabetes prevalence by race:\n")
print(diabetes_df %>%
        select(race, method, prevalence, se, n) %>%
        mutate(across(c(prevalence, se), ~round(., 4))))

diabetes_df$race <- factor(diabetes_df$race, levels = rev(races))

p_a <- ggplot(diabetes_df, aes(x = prevalence, y = race,
                                colour = method, shape = method)) +
  geom_point(size = 3.5, position = position_dodge(width = 0.5)) +
  geom_errorbarh(aes(xmin = ci_lo, xmax = ci_hi),
                 height = 0.2, linewidth = 0.7,
                 position = position_dodge(width = 0.5)) +
  scale_colour_manual(values = c("Design-weighted" = "#377EB8",
                                  "Naive (unweighted)" = "#E41A1C"),
                      name = NULL) +
  scale_shape_manual(values = c("Design-weighted" = 16,
                                 "Naive (unweighted)" = 17),
                     name = NULL) +
  scale_x_continuous(labels = percent_format()) +
  labs(
    title = "A. Diabetes Prevalence by Race: Does the Survey Design Matter?",
    subtitle = paste0(
      "NHANES 2017-2018 adults 20+. Diabetes defined as HbA1c >= 6.5%.\n",
      "NHANES oversamples minorities. ",
      "Naive estimates ignore this, distorting health disparity conclusions."),
    x = "Diabetes prevalence", y = NULL
  ) +
  theme(legend.position = "bottom")

cat("Panel A built.\n")

# =========================================================================
# PANEL B -- Design Effects (DEFF) for Key Health Variables
# =========================================================================

cat("\n--- Panel B: Design effects ---\n")

health_vars <- c("has_diabetes", "has_prediabetes", "is_obese",
                 "has_hypertension")
nice_names <- c("Diabetes\n(HbA1c >= 6.5%)", "Prediabetes\n(HbA1c 5.7-6.4%)",
                "Obesity\n(BMI >= 30)", "Hypertension\n(SBP >= 140)")

deff_df <- data.frame()
for (i in seq_along(health_vars)) {
  v <- health_vars[i]
  des_sub <- subset(des, !is.na(des$variables[[v]]))
  fml <- as.formula(paste0("~", v))
  est <- svymean(fml, des_sub, deff = TRUE)
  d <- deff(est)
  if (length(d) == 0 || all(is.na(d))) {
    se_complex <- as.numeric(SE(est))
    x_vals <- des_sub$variables[[v]]
    se_srs <- sd(x_vals, na.rm = TRUE) / sqrt(length(x_vals))
    d <- (se_complex / se_srs)^2
  } else {
    d <- as.numeric(d)
  }
  se_complex <- as.numeric(SE(est))
  n_actual <- nrow(des_sub$variables)

  deff_df <- rbind(deff_df, data.frame(
    variable = nice_names[i],
    estimate = as.numeric(coef(est)),
    se_complex = se_complex,
    se_srs = se_complex / sqrt(as.numeric(d)),
    deff = as.numeric(d),
    n_actual = n_actual,
    n_effective = round(n_actual / as.numeric(d)),
    stringsAsFactors = FALSE
  ))
}

cat("NHANES design effects:\n")
print(deff_df %>% mutate(across(c(estimate, deff), ~round(., 3))))

deff_df$variable <- factor(deff_df$variable,
  levels = deff_df$variable[order(deff_df$deff)])

# Paired bar chart: SE under complex design vs SRS
se_long <- deff_df %>%
  select(variable, se_complex, se_srs) %>%
  pivot_longer(c(se_complex, se_srs), names_to = "type", values_to = "se") %>%
  mutate(type = ifelse(type == "se_complex",
                       "Complex design SE", "Simple random sample SE"))

p_b <- ggplot(se_long, aes(x = variable, y = se, fill = type)) +
  geom_col(position = "dodge", width = 0.6, alpha = 0.85) +
  geom_text(data = deff_df,
            aes(x = variable, y = se_complex * 1.1,
                label = sprintf("DEFF = %.1f", deff)),
            inherit.aes = FALSE, size = 3.2, fontface = "bold",
            colour = "grey30") +
  scale_fill_manual(values = c("Complex design SE" = "#E41A1C",
                                "Simple random sample SE" = "#377EB8"),
                    name = NULL) +
  labs(
    title = "B. Standard Errors: Complex Design vs Simple Random Sample",
    subtitle = paste0(
      "NHANES clustering inflates SEs. DEFF > 1 means the real SE is ",
      "larger than naive calculations assume.\n",
      "Ignoring the design produces confidence intervals that are too narrow ",
      "-- leading to false precision in health estimates."),
    x = NULL, y = "Standard error of prevalence estimate"
  ) +
  theme(legend.position = "bottom",
        axis.text.x = element_text(size = 10))

cat("Panel B built.\n")

# =========================================================================
# COMPOSE
# =========================================================================

combined <- p_a / p_b +
  plot_annotation(
    title = "NHANES 2017-2018: Design Effects in Health Equity Research",
    subtitle = paste0(
      "National Health and Nutrition Examination Survey (n = ",
      format(nrow(df_adult), big.mark = ","), " adults 20+). ",
      "Complex design: oversampled minorities, stratified, clustered.\n",
      "Design: svydesign(id=~SDMVPSU, strata=~SDMVSTRA, ",
      "weights=~WTMEC2YR, nest=TRUE). survey.lonely.psu = 'adjust'."
    ),
    caption = paste0(
      "Data: NHANES 2017-2018 via nhanesA R package | ",
      "CDC/NCHS | r-complex-survey skill: Gate 1-5 enforced"
    ),
    theme = theme(
      plot.title = element_text(face = "bold", size = 16, hjust = 0.5),
      plot.subtitle = element_text(size = 10, colour = "grey30", hjust = 0.5,
                                   margin = margin(b = 15)),
      plot.caption = element_text(size = 8, colour = "grey50")
    )
  )

ggsave(file.path(out_dir, "nhanes_design_effects.png"),
       combined, width = 14, height = 14, dpi = 300, bg = "white")
cat("\nSaved: nhanes_design_effects.png\n")

ggsave(file.path(out_dir, "nhanes_design_effects.pdf"),
       combined, width = 14, height = 14, bg = "white")
cat("Saved: nhanes_design_effects.pdf\n")

cat("\nDone.\n")
