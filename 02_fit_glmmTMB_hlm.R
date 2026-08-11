# ==============================================================================
# Script: 02_fit_glmmTMB_hlm.R
# Objective: Robust Cross-Classified HLM on 104k sample with AR(1)
# ==============================================================================

library(tidyverse)
library(glmmTMB)

# 1. Load Raw Data
statcast_2024_full <- read_rds("statcast_2024_full_season.rds")

message("Processing ", nrow(statcast_2024_full), " pitches...")

# 2. Engineer & Standardize Features + Calculate Continuous Swing Aggression
pitch_df <- statcast_2024_full %>%
  # Filter out missing pitch types, counts, or missing zone coordinates
  filter(!is.na(pitch_type), !is.na(balls), !is.na(strikes), !is.na(zone)) %>%
  arrange(game_date, game_pk, at_bat_number, pitch_number) %>%
  mutate(
    # Unique Identifiers
    pa_id      = paste(game_pk, at_bat_number, sep = "_"),
    batter_id  = as.factor(batter),
    pitcher_id = as.factor(pitcher),
    
    # Cap pitch sequence number at 8 to prevent extreme sparse factor levels
    pitch_num_capped = if_else(pitch_number > 8, 8, as.numeric(pitch_number)),
    pitch_factor     = numFactor(pitch_num_capped),
    
    # Covariates
    count_state       = as.factor(paste(balls, strikes, sep = "-")),
    zone_factor       = as.factor(zone),
    platoon_advantage = if_else(stand != p_throws, 1, 0),
    outs_numeric      = as.numeric(outs_when_up),
    is_swing          = if_else(type %in% c("S", "D", "E", "X"), 1, 0),
    delta_rv          = as.numeric(delta_run_exp)
  ) %>%
  
  # Calculate Empirical Contextual Swing Probability: P(Swing | Count, Zone)
  group_by(count_state, zone_factor) %>%
  mutate(
    exp_swing_prob = mean(is_swing, na.rm = TRUE)
  ) %>%
  ungroup() %>%
  
  # Pitch-Level Swing Aggression (Continuous Residual)
  # SA_ijk = Actual Decision (0/1) - Expected Contextual Swing Rate
  mutate(
    swing_aggression = is_swing - exp_swing_prob
  )

# 3. Calculate Hitter Baselines on Full Sample
hitter_baselines <- pitch_df %>%
  group_by(batter_id) %>%
  summarise(
    total_swings = sum(is_swing),
    whiffs = sum(description %in% c("swinging_strike", "swinging_strike_blocked", "foul_tip")),
    baseline_contact_rate = if_else(total_swings > 0, 1 - (whiffs / total_swings), NA_real_),
    ev_95 = quantile(launch_speed[type == "X"], probs = 0.95, na.rm = TRUE)
  ) %>%
  filter(!is.na(baseline_contact_rate), total_swings >= 15)

# 4. Merge & Standardize Continuous Variables
clean_data <- pitch_df %>%
  inner_join(hitter_baselines, by = "batter_id") %>%
  filter(!is.na(delta_rv), !is.na(ev_95)) %>%
  
  # Add Pitch Lag on the merged dataset
  group_by(pa_id) %>%
  arrange(pitch_number) %>%
  mutate(
    lag_delta_rv = lag(delta_rv, default = 0)
  ) %>%
  ungroup() %>%
  
  mutate(
    # Z-score continuous predictors
    swing_aggression_z      = as.numeric(scale(swing_aggression)),
    baseline_contact_rate_z = as.numeric(scale(baseline_contact_rate)),
    ev_95_z                 = as.numeric(scale(ev_95)),
    outs_z                  = as.numeric(scale(outs_numeric)),
    pa_id                   = as.factor(pa_id)
  )

message("Clean dataset ready: ", nrow(clean_data), " pitches across ",
        n_distinct(clean_data$batter_id), " batters and ",
        n_distinct(clean_data$pitcher_id), " pitchers.")

# 5. Add Pitch Lag (Outcome of previous pitch within the SAME PA)
clean_data_lag <- clean_data %>%
  group_by(pa_id) %>%
  arrange(pitch_number) %>%
  mutate(
    # Lagged Run Value (0 for the 1st pitch of an at-bat)
    lag_delta_rv = lag(delta_rv, default = 0)
  ) %>%
  ungroup()

message("Fitting Cross-Classified HLM with Lagged Serial Dependence...")

# 6. Fit Robust Model
hlm_lagged <- glmmTMB(
  delta_rv ~ 
    # Use standardized continuous Swing Aggression!
    swing_aggression_z * baseline_contact_rate_z + 
    count_state + 
    platoon_advantage + 
    ev_95_z + 
    outs_z + 
    lag_delta_rv + 
    (1 | batter_id) + 
    (1 | pitcher_id),
  data = clean_data,
  REML = TRUE
)

# 7. Diagnostics and View Results
cat("Exit Code : ", hlm_lagged$fit$convergence, "\n")
cat("pdHess    : ", hlm_lagged$sdr$pdHess, "\n")

summary(hlm_lagged)
