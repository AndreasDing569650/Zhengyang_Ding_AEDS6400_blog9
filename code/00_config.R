# ============================================================
# Blog Post 9
# Shared configuration
# ============================================================

library(readxl)
library(tidyverse)
library(tidyquant)
library(tidymodels)
library(lubridate)
library(slider)
library(xgboost)

here::i_am("code/00_config.R")
project_dir <- here::here()

paths <- list(
  raw = here::here("data", "raw_data"),
  processed = here::here("data", "processed_data"),
  models = here::here("models"),
  tables = here::here("results", "tables"),
  figures = here::here("results", "figures"),
  notes = here::here("results", "notes")
)

invisible(lapply(
  paths,
  dir.create,
  recursive = TRUE,
  showWarnings = FALSE
))

initial_capital <- 100000
class_bootstrap_repetitions <- 10000L

# Same download period and test boundary as the professor's code.
download_from <- as.Date("2022-01-01")
download_to <- Sys.Date()
test_start <- as.Date("2024-01-01")

# Force a fresh download if desired.
refresh_data <- FALSE

# Professor's actual list contains 95 stocks.
tickers <- c(
  "AAPL", "MSFT", "NVDA", "GOOG", "META", "AMZN",
  "AVGO", "ORCL", "ADBE", "CRM",
  "CSCO", "AMD", "INTC", "QCOM", "TXN",
  "IBM", "NOW", "INTU", "AMAT", "MU",
  
  "JPM", "BAC", "WFC", "GS", "MS", "BLK",
  "C", "SCHW", "SPGI", "AXP",
  "USB", "PNC", "TFC", "COF",
  
  "UNH", "JNJ", "LLY", "PFE", "MRK",
  "ABBV", "TMO", "DHR", "ABT", "BMY",
  "AMGN", "GILD", "CVS", "ISRG", "MDT",
  
  "TSLA", "HD", "MCD", "NKE", "SBUX",
  "LOW", "TJX", "BKNG", "CMG", "ORLY",
  
  "WMT", "COST", "PG", "KO", "PEP",
  "PM", "MO", "CL", "EL",
  
  "CAT", "GE", "HON", "UPS", "BA",
  "RTX", "DE", "LMT", "MMM", "ETN",
  
  "XOM", "CVX", "COP", "SLB", "EOG",
  
  "NFLX", "DIS", "CMCSA", "TMUS", "VZ",
  
  "AMT", "PLD", "NEE", "DUK", "SO", "LIN", "APD"
)

stopifnot(
  length(tickers) == 95L,
  !anyDuplicated(tickers)
)

# Revised predictors. No extra historical download is required.
improved_features <- c(
  "momentum_21",
  "momentum_63",
  "momentum_126",
  "reversal_5",
  "volatility_21",
  "relative_momentum_63",
  "volume_ratio_21",
  "drawdown_126",
  "spy_ret"
)

theme_set(theme_minimal(base_size = 12))

save_figure <- function(
    plot,
    filename,
    width = 9,
    height = 5.5
) {
  ggsave(
    filename = file.path(paths$figures, filename),
    plot = plot,
    width = width,
    height = height,
    dpi = 300,
    bg = "white"
  )
}

safe_correlation <- function(
    x,
    y,
    method = "pearson"
) {
  if (
    length(x) < 3L ||
    sd(x) == 0 ||
    sd(y) == 0
  ) {
    return(NA_real_)
  }
  
  cor(x, y, method = method)
}
