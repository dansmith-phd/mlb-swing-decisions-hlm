# ==============================================================================
# Script: 01_scrape_full_2024_season.R
# Objective: Download Full 2024 Statcast Regular Season (~700k pitches)
# ==============================================================================

library(tidyverse)
library(janitor)

# Robust direct pull function with automatic retry logic
fetch_statcast_robust <- function(s_date, e_date, max_attempts = 3) {
  url <- paste0(
    "https://baseballsavant.mlb.com/statcast_search/csv?all=true&hfPT=&hfAB=&hfGT=R%7C&hfPR=&hfZ=&hfStadium=&hfBBD=&hfNewZones=&hfPull=&hfC=&hfSea=2024%7C&hfSit=&player_type=batter&hfOuts=&hfOpponent=&pitcher_throws=&batter_stands=&hfSA=&player_type=batter&hfInfield=&hfOutfield=&hfRO=&home_road=&game_date_gt=",
    s_date, "&game_date_lt=", e_date, "&as_e=true&type=details"
  )
  
  for (attempt in 1:max_attempts) {
    df <- tryCatch({
      read_csv(url, show_col_types = FALSE) %>% clean_names()
    }, error = function(e) {
      message("   [Attempt ", attempt, " failed with server error. Retrying in 5 seconds...]")
      Sys.sleep(5)
      return(NULL)
    })
    
    if (!is.null(df) && nrow(df) > 0) return(df)
  }
  
  warning("   [FAILED] Could not retrieve data for range: ", s_date, " to ", e_date)
  return(tibble())
}

# Date ranges for Months in Season
season_months <- list(
  c("2024-03-28", "2024-04-30"), # April + late March
  c("2024-05-01", "2024-05-31"), # May
  c("2024-06-01", "2024-06-30"), # June
  c("2024-07-01", "2024-07-31"), # July
  c("2024-08-01", "2024-08-31"), # August
  c("2024-09-01", "2024-09-30")  # September
)

monthly_dfs <- list()

for (m in seq_along(season_months)) {
  s <- season_months[[m]][1]
  e <- season_months[[m]][2]
  message("--- Fetching Range ", s, " to ", e, " ---")
  
  # Fetch in 4-day increments
  date_seq <- seq(as.Date(s), as.Date(e), by = "4 days")
  month_chunks <- list()
  
  for (i in 1:(length(date_seq) - 1)) {
    chunk_start <- date_seq[i]
    chunk_end   <- date_seq[i + 1] - 1
    
    df_chunk <- fetch_statcast_robust(as.character(chunk_start), as.character(chunk_end))
    month_chunks[[i]] <- df_chunk
    
    Sys.sleep(1.5) # Friendly delay to avoid overloading Baseball Savant
  }
  
  monthly_dfs[[m]] <- bind_rows(month_chunks)
  message("Successfully saved ", nrow(monthly_dfs[[m]]), " pitches for this block.")
}

# Combine all months and save master file
statcast_2024_full <- bind_rows(monthly_dfs)
write_rds(statcast_2024_full, "statcast_2024_full_season.rds", compress = "gz")
message("\n=== ALL SET! Master dataset saved cleanly. ===")
