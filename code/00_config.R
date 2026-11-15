# ============================================================
# Blog Post 9: shared configuration
# ============================================================

library(tidyverse)
library(quantmod)
library(slider)
library(xgboost)

set.seed(6409)

project_dir <- "D:/Rproject/6400-blog9"

paths <- list(
  raw       = file.path(project_dir, "data", "raw_data"),
  processed = file.path(project_dir, "data", "processed_data"),
  tables    = file.path(project_dir, "results", "tables"),
  figures   = file.path(project_dir, "results", "figures"),
  notes     = file.path(project_dir, "results", "notes"),
  models    = file.path(project_dir, "models")
)

invisible(lapply(paths, dir.create, recursive = TRUE, showWarnings = FALSE))

# Fixed, ex-post universe. Not historical S&P 500 membership.
tickers <- c(
  # Technology
  "AAPL", "MSFT", "NVDA", "IBM", "ORCL", "CSCO",
  "INTC", "AMD", "QCOM", "TXN", "ADBE", "AMAT",
  
  # Financials
  "JPM", "BAC", "WFC", "GS", "MS", "AXP", "BLK",
  
  # Healthcare
  "JNJ", "PFE", "MRK", "ABT", "AMGN", "GILD", "MDT", "UNH",
  
  # Consumer
  "PG", "KO", "PEP", "WMT", "COST", "MCD", "HD", "NKE", "SBUX",
  
  # Industrials
  "CAT", "HON", "UPS", "BA", "LMT",
  
  # Energy
  "XOM", "CVX", "COP", "SLB",
  
  # Communication and utilities
  "DIS", "VZ", "T", "DUK", "SO"
)

stopifnot(length(tickers) == 50L, !anyDuplicated(tickers))

download_start <- as.Date("2010-01-01")
download_end   <- as.Date("2026-01-01")  # Exclusive endpoint
analysis_start <- as.Date("2011-01-01")
validation_start <- as.Date("2018-01-01")
test_start       <- as.Date("2020-01-01")
test_end         <- as.Date("2025-12-31")

holding_days <- 20L
portfolio_size <- 10L
initial_capital <- 100000
cost_bps <- c(0, 10, 25)

theme_set(theme_minimal(base_size = 12))

writeLines(
  c(
    "Fixed sample: 50 selected US stocks; not point-in-time index constituents.",
    "Yahoo adjusted close is used as a total-return proxy.",
    "The sample is exposed to survivorship and ex-post selection bias.",
    "Original model is reconstructed on a common sample and evaluation protocol.",
    "Validation: 2018-2019. Final test: 2020-2025.",
    "Signals are formed after the close; trades occur at the next close.",
    "All feature selection and hyperparameter choices precede the final test.",
    "Sharpe ratios use a zero risk-free rate; this is explicitly an approximation."
  ),
  file.path(paths$notes, "00_design_notes.txt")
)