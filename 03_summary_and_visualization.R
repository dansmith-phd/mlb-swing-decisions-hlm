# ==============================================================================
# Script: 03_summary_and_visualization.R
# Objective: Generate model summary table and interaction plot for README
# ==============================================================================

library(tidyverse)
library(glmmTMB)
library(broom.mixed) # For tidy model summaries
library(ggeffects)   # For marginal effects predictions
library(knitr)

# ------------------------------------------------------------------------------
# 1. Model Summary Table Extraction
# ------------------------------------------------------------------------------

message("Extracting tidy model estimates...")

# Tidy the fixed effects table with standard errors, z-stats, and p-values
model_summary_table <- tidy(hlm_lagged, effects = "fixed") %>%
  select(term, estimate, std.error, statistic, p.value) %>%
  mutate(
    across(c(estimate, std.error, statistic), ~ round(.x, 4)),
    p.value = if_else(p.value < 0.001, "< 0.001", as.character(round(p.value, 4)))
  )

# Print markdown table for GitHub README pasting
cat("\n=== MODEL SUMMARY TABLE (MARKDOWN) ===\n\n")
print(kable(model_summary_table, format = "markdown"))

# ------------------------------------------------------------------------------
# 2. Compute Predicted Marginal Effects for Interaction Curve
# ------------------------------------------------------------------------------

message("\nCalculating marginal effects for Swing Aggression x Contact Profile...")

# Predict marginal effects of continuous Swing Aggression (-2 SD to +2 SD)
# across 3 Hitter Contact Tiers (-1 SD, 0 SD, +1 SD)
marginal_preds <- ggpredict(
  hlm_lagged, 
  terms = c("swing_aggression_z [-2, -1, 0, 1, 2]", "baseline_contact_rate_z [-1, 0, 1]")
) %>%
  as_tibble() %>%
  mutate(
    # Continuous x-axis value (z-score of Swing Aggression)
    swing_aggression_val = x,
    
    # Map contact rate group levels to readable labels
    contact_profile = case_when(
      group == "-1" ~ "Low Contact (-1 SD)",
      group == "0"  ~ "Average Contact (Mean)",
      group == "1"  ~ "High Contact (+1 SD)"
    ),
    contact_profile = factor(
      contact_profile, 
      levels = c("Low Contact (-1 SD)", "Average Contact (Mean)", "High Contact (+1 SD)")
    )
  )

# ------------------------------------------------------------------------------
# 3. Build ggplot2 Interaction Curve
# ------------------------------------------------------------------------------

message("Generating interaction plot...")

interaction_plot <- ggplot(
  marginal_preds, 
  aes(x = swing_aggression_val, y = predicted, color = contact_profile, fill = contact_profile)
) +
  # Confidence bands around marginal trajectories
  geom_ribbon(aes(ymin = conf.low, ymax = conf.high), alpha = 0.15, color = NA) +
  
  # Trajectory lines and points
  geom_line(linewidth = 1.2) +
  geom_point(size = 3) +
  
  # Custom Color Palette (Orange/Red = Low Contact, Purple = Avg, Emerald = High Contact)
  scale_color_manual(values = c("#D95F02", "#7570B3", "#1B9E77")) +
  scale_fill_manual(values = c("#D95F02", "#7570B3", "#1B9E77")) +
  
  # Discrete breaks along standardized scale
  scale_x_continuous(
    breaks = c(-2, -1, 0, 1, 2),
    labels = c("-2 SD\n(Passive)", "-1 SD", "0\n(Expected)", "+1 SD", "+2 SD\n(Aggressive)")
  ) +
  
  labs(
    title = "Moderation of Decision Value by Hitter Contact Profile",
    subtitle = "Predicted Delta Run Value across Context-Adjusted Swing Aggression Tiers",
    x = "Context-Adjusted Swing Aggression (Z-Score)",
    y = "Predicted Delta Run Value (xRV)",
    color = "Hitter Contact Profile",
    fill = "Hitter Contact Profile",
    caption = "Data: 2024 MLB Statcast | Model: Cross-Classified HLM (p_interaction < 0.001)"
  ) +
  
  theme_minimal(base_size = 12) +
  theme(
    plot.title = element_text(face = "bold", size = 14),
    plot.subtitle = element_text(color = "gray30", size = 11, margin = margin(b = 10)),
    legend.position = "top",
    legend.title = element_text(face = "bold"),
    panel.grid.minor = element_blank(),
    axis.title = element_text(face = "bold"),
    axis.text.x = element_text(size = 9)
  )

# Display & Save High-Res PNG
print(interaction_plot)
ggsave("interaction_plot.png", plot = interaction_plot, width = 8.5, height = 5.5, dpi = 300)
message("Plot saved cleanly as 'interaction_plot.png'!")
