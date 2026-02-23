#!/usr/bin/env Rscript
# ===========================================================================
# Advanced GSS Analysis: Propensity Diagnostics & Imputation Comparison
# ===========================================================================
#
# Two panels:
#   A. Propensity to be missing -- design-weighted logistic regression
#      comparing MCAR (happy) vs MNAR (rincome) missingness mechanisms.
#   B. Imputation strategy comparison -- four approaches to handling
#      missing income and their effect on estimating mean education.
#
# Uses GSS 2018 with full complex survey design:
#   svydesign(id = ~vpsu, strata = ~vstrat, weights = ~wtssall, nest = TRUE)
# ===========================================================================

library(dplyr)
library(tidyr)
library(ggplot2)
library(patchwork)
library(scales)
library(survey)
library(gssr)

out_dir <- "/home/darshan/Documents/claude_code/agent_skills_survey"

theme_set(theme_minimal(base_size = 12) +
            theme(plot.title = element_text(face = "bold", size = 13),
                  plot.subtitle = element_text(colour = "grey40", size = 10)))

# ── Load GSS cumulative ──────────────────────────────────────────────────
cat("Loading GSS cumulative data...\n")
data(gss_all)
gss <- gss_all

# Focus on 2018 (has vstrat, vpsu, wtssall)
df18 <- gss %>%
  filter(year == 2018) %>%
  select(vstrat, vpsu, wtssall, age, sex, race, educ, degree,
         rincome, happy, polviews, realinc) %>%
  filter(!is.na(wtssall) & !is.na(vstrat) & !is.na(vpsu))

cat(sprintf("GSS 2018 sample: n = %d\n", nrow(df18)))

options(survey.lonely.psu = "adjust")
des18 <- svydesign(id = ~vpsu, strata = ~vstrat, weights = ~wtssall,
                    data = df18, nest = TRUE)

# =========================================================================
# PANEL A -- Propensity to Be Missing: MCAR vs MNAR
# =========================================================================
# Fit design-weighted logistic regressions predicting missingness of
# happy (MCAR) and rincome (MNAR) from demographics (age + educ).
#
# Under MCAR, demographics should have near-zero predictive power ->
# propensity scores cluster tightly around the marginal rate.
# Under MNAR, demographics should predict missingness strongly ->
# propensity scores are dispersed.

cat("\n--- Panel A: Propensity Diagnostics ---\n")

# Create binary missingness indicators
df18$miss_happy <- as.numeric(is.na(df18$happy))
df18$miss_rincome <- as.numeric(is.na(df18$rincome))

# Recreate design with updated data
des18_prop <- svydesign(id = ~vpsu, strata = ~vstrat, weights = ~wtssall,
                         data = df18, nest = TRUE)

# Subset to cases with complete predictors (age, educ)
des18_complete <- subset(des18_prop, !is.na(age) & !is.na(educ))

cat(sprintf("Cases with complete predictors: n = %d\n",
            nrow(des18_complete$variables)))

# Fit propensity models via svyglm
mod_happy <- svyglm(miss_happy ~ age + educ,
                     design = des18_complete, family = quasibinomial())

mod_rincome <- svyglm(miss_rincome ~ age + educ,
                       design = des18_complete, family = quasibinomial())

# Extract fitted probabilities (on response scale)
prop_happy <- fitted(mod_happy)
prop_rincome <- fitted(mod_rincome)

# Summary statistics
cat("\n=== Propensity Model: HAPPY (MCAR) ===\n")
cat(sprintf("  Propensity range: [%.4f, %.4f]\n",
            min(prop_happy), max(prop_happy)))
cat(sprintf("  Propensity SD: %.4f\n", sd(prop_happy)))
cat(sprintf("  Marginal miss rate: %.3f\n",
            mean(des18_complete$variables$miss_happy)))

cat("\n=== Propensity Model: RINCOME (MNAR) ===\n")
cat(sprintf("  Propensity range: [%.4f, %.4f]\n",
            min(prop_rincome), max(prop_rincome)))
cat(sprintf("  Propensity SD: %.4f\n", sd(prop_rincome)))
cat(sprintf("  Marginal miss rate: %.3f\n",
            mean(des18_complete$variables$miss_rincome)))

# Build density plot comparing the two propensity distributions
prop_long <- rbind(
  data.frame(variable = "HAPPY (MCAR)",
             propensity = as.numeric(prop_happy),
             stringsAsFactors = FALSE),
  data.frame(variable = "RINCOME (MNAR)",
             propensity = as.numeric(prop_rincome),
             stringsAsFactors = FALSE)
)

# Compute vertical lines at mean propensity
vlines <- data.frame(
  variable = c("HAPPY (MCAR)", "RINCOME (MNAR)"),
  xint = c(mean(prop_happy), mean(prop_rincome))
)

p_a <- ggplot(prop_long, aes(x = propensity, fill = variable)) +
  geom_density(alpha = 0.55, colour = NA) +
  geom_vline(data = vlines, aes(xintercept = xint, colour = variable),
             linetype = "dashed", linewidth = 0.8, show.legend = FALSE) +
  scale_fill_manual(values = c("HAPPY (MCAR)" = "#4DAF4A",
                                "RINCOME (MNAR)" = "#E41A1C"),
                    name = NULL) +
  scale_colour_manual(values = c("HAPPY (MCAR)" = "#4DAF4A",
                                  "RINCOME (MNAR)" = "#E41A1C")) +
  annotate("text", x = max(prop_rincome) * 0.95, y = 0,
           label = paste0("MCAR: propensities cluster tightly\n",
                          "MNAR: propensities are dispersed"),
           hjust = 1, vjust = 0, size = 3.2, colour = "grey40",
           fontface = "italic") +
  labs(
    title = "A. Propensity to Be Missing: MCAR vs MNAR",
    subtitle = paste0(
      "Design-weighted logistic regression (svyglm, quasibinomial) ",
      "predicting missingness from age + education.\n",
      "Tight clustering = MCAR (demographics don't predict missingness). ",
      "Wide spread = MNAR (demographics predict who is missing)."),
    x = "Predicted probability of being missing", y = "Density"
  ) +
  theme(legend.position = "bottom")

cat("Panel A built.\n")

# =========================================================================
# PANEL B -- Imputation Strategy Comparison
# =========================================================================
# Compare four approaches to handling missing rincome when estimating
# mean education. This shows how missingness treatment affects estimates
# of OTHER variables (not just the variable with missingness).
#
# Strategy 1: Full sample, design-weighted (benchmark)
# Strategy 2: Complete cases on rincome, design-weighted
# Strategy 3: Complete cases on rincome, unweighted
# Strategy 4: Inverse propensity weighted (IPW) complete cases

cat("\n--- Panel B: Imputation Comparison ---\n")

# Strategy 1: Full sample, design-weighted (benchmark)
est_full <- svymean(~educ, subset(des18, !is.na(educ)), na.rm = TRUE)
n_full <- sum(!is.na(df18$educ))

# Strategy 2: Complete cases on rincome, design-weighted
des_cc <- subset(des18, !is.na(educ) & !is.na(rincome))
est_cc_wt <- svymean(~educ, des_cc, na.rm = TRUE)
n_cc <- nrow(des_cc$variables)

# Strategy 3: Complete cases on rincome, unweighted
cc_data <- df18 %>% filter(!is.na(educ) & !is.na(rincome))
est_cc_unwt <- mean(cc_data$educ, na.rm = TRUE)
se_cc_unwt <- sd(cc_data$educ, na.rm = TRUE) / sqrt(nrow(cc_data))
n_unwt <- nrow(cc_data)

# Strategy 4: IPW -- re-weight complete cases by 1/P(observed|X)
# P(observed) = 1 - P(missing)
df18_ipw <- df18 %>% filter(!is.na(age) & !is.na(educ))
# Predict P(missing rincome | age, educ) using the propensity model
df18_ipw$p_missing <- predict(mod_rincome,
  newdata = data.frame(age = df18_ipw$age, educ = df18_ipw$educ),
  type = "response")
df18_ipw$p_missing <- as.numeric(df18_ipw$p_missing)
df18_ipw$p_observed <- pmax(1 - df18_ipw$p_missing, 0.05)  # floor at 5%
df18_ipw$ipw_weight <- df18_ipw$wtssall / df18_ipw$p_observed

# Complete cases only, with IPW adjustment
df18_ipw_cc <- df18_ipw %>% filter(!is.na(rincome))
des_ipw <- svydesign(id = ~vpsu, strata = ~vstrat, weights = ~ipw_weight,
                      data = df18_ipw_cc, nest = TRUE)
est_ipw <- svymean(~educ, des_ipw, na.rm = TRUE)
n_ipw <- nrow(df18_ipw_cc)

# Assemble results
comparison_df <- data.frame(
  strategy = c("Full sample\n(design-weighted)",
               "Complete cases\n(design-weighted)",
               "Complete cases\n(unweighted)",
               "IPW-adjusted\n(design-weighted)"),
  estimate = c(as.numeric(coef(est_full)),
               as.numeric(coef(est_cc_wt)),
               est_cc_unwt,
               as.numeric(coef(est_ipw))),
  se = c(as.numeric(SE(est_full)),
         as.numeric(SE(est_cc_wt)),
         se_cc_unwt,
         as.numeric(SE(est_ipw))),
  n = c(n_full, n_cc, n_unwt, n_ipw),
  stringsAsFactors = FALSE
)

comparison_df$ci_lo <- comparison_df$estimate - 1.96 * comparison_df$se
comparison_df$ci_hi <- comparison_df$estimate + 1.96 * comparison_df$se
comparison_df$strategy <- factor(comparison_df$strategy,
                                  levels = rev(comparison_df$strategy))

cat("\n=== Imputation Strategy Comparison ===\n")
print(comparison_df %>%
        mutate(across(c(estimate, se, ci_lo, ci_hi), ~round(., 3))))

# Horizontal dot plot
p_b <- ggplot(comparison_df, aes(x = estimate, y = strategy,
                                  colour = strategy)) +
  geom_point(size = 4) +
  geom_errorbarh(aes(xmin = ci_lo, xmax = ci_hi),
                 height = 0.2, linewidth = 0.8) +
  geom_vline(xintercept = comparison_df$estimate[comparison_df$strategy ==
               "Full sample\n(design-weighted)"],
             linetype = "dashed", colour = "grey50") +
  geom_text(aes(label = sprintf("n=%s", format(n, big.mark = ","))),
            vjust = -1.2, size = 3, show.legend = FALSE) +
  annotate("text",
           x = comparison_df$estimate[comparison_df$strategy ==
                 "Full sample\n(design-weighted)"] + 0.01,
           y = 0.6, label = "Benchmark", colour = "grey50",
           size = 3, fontface = "italic", hjust = 0) +
  scale_colour_manual(values = c(
    "Full sample\n(design-weighted)" = "#4DAF4A",
    "Complete cases\n(design-weighted)" = "#E41A1C",
    "Complete cases\n(unweighted)" = "#984EA3",
    "IPW-adjusted\n(design-weighted)" = "#377EB8"
  ), guide = "none") +
  labs(
    title = "B. Missing Income Strategy: Impact on Education Estimates",
    subtitle = paste0(
      "Mean years of education (GSS 2018) under four missingness strategies.\n",
      "Conditioning on MNAR income missingness biases education estimates. ",
      "IPW partially corrects."),
    x = "Mean years of education", y = NULL
  )

cat("Panel B built.\n")

# =========================================================================
# COMPOSE FINAL FIGURE
# =========================================================================

combined <- p_a / p_b +
  plot_annotation(
    title = "Advanced GSS Analysis: Propensity Diagnostics & Missing Data Strategies",
    subtitle = paste0(
      "General Social Survey 2018 (n = ", format(nrow(df18), big.mark = ","),
      "). Design: svydesign(id=~vpsu, strata=~vstrat, weights=~wtssall, nest=TRUE).\n",
      "survey.lonely.psu = 'adjust'. All models use svyglm() with quasibinomial()."
    ),
    caption = "Data: GSS 2018 via gssr R package | r-complex-survey skill: Gate 1-5 enforced",
    theme = theme(
      plot.title = element_text(face = "bold", size = 16, hjust = 0.5),
      plot.subtitle = element_text(size = 10, colour = "grey30", hjust = 0.5,
                                   margin = margin(b = 15)),
      plot.caption = element_text(size = 8, colour = "grey50")
    )
  )

ggsave(file.path(out_dir, "gss_advanced.png"),
       combined, width = 14, height = 14, dpi = 300, bg = "white")
cat("\nSaved: gss_advanced.png\n")

ggsave(file.path(out_dir, "gss_advanced.pdf"),
       combined, width = 14, height = 14, bg = "white")
cat("Saved: gss_advanced.pdf\n")

cat("\nDone.\n")
