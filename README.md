# Zhengyang_Ding_AEDS6400_blog9: Predicting Stock Returns with Gradient Boosting

## Project Overview

This repository contains the R scripts, input and market data, fitted models, tables, and figures for Blog Post 9. The analysis revisits a classroom stock-selection experiment and evaluates whether revised predictors and settings improve an XGBoost model's return predictions and investment results.

The project addresses three questions:

1. Did portfolios selected after analysis outperform portfolios selected subjectively in the classroom experiment?
2. Can revised predictors and model settings improve the original gradient boosting model?
3. Do improvements in prediction accuracy translate into better investment performance?

The revised model reduced RMSE relative to the original XGBoost model, but both models performed worse than a historical-mean forecast. The revised model's direction and stock-ranking performance also declined. Its cumulative investment result was close to the original model's, with greater monthly return variability and a deeper drawdown. See the tables and figures in `results/` for the reported results.

## Repository Structure

```text
.
├── Zhengyang_Ding_AEDS6400_blog9.Rproj
├── README.md
├── code/
│   ├── 00_config.R
│   ├── 01_class_results.R
│   ├── 02_prepare_data.R
│   ├── 03_original_model.R
│   ├── 04_improved_model.R
│   └── 05_compare_models.R
├── data/
│   ├── raw_data/
│   │   ├── Full_Result.xlsx
│   │   └── market_snapshot.rds
│   └── processed_data/
├── models/
└── results/
    ├── figures/
    ├── notes/
    └── tables/
```

The scripts create required output folders when needed. Generated files are saved under `data/processed_data/`, `models/`, and `results/`.

## Code and Path Configuration

All scripts now build file paths with the [`here`](https://here.r-lib.org/) package instead of relying on the original machine-specific `D:/Rproject/6400-blog9` path. `code/00_config.R` marks `code/00_config.R` as the project anchor with `here::i_am()` and defines project-relative paths for raw data, processed data, models, tables, figures, and notes. Other scripts source the shared configuration with `here::here("code", "00_config.R")`.

You do **not** need to edit project paths or call `setwd()` to a machine-specific directory. Clone or download the repository, open `Zhengyang_Ding_AEDS6400_blog9.Rproj` in RStudio, and run the scripts from that project. `here` locates files inside the local project checkout; it does not read or execute files directly from the GitHub website. Keep the repository's folder structure intact.

### Script sequence

| Script | Purpose | Depends on |
|:--|:--|:--|
| `code/00_config.R` | Loads packages; establishes the project root and shared paths, settings, stock universe, features, and helper functions; creates output directories. | Project checkout |
| `code/01_class_results.R` | Reads and validates the classroom spreadsheet; calculates paired portfolio statistics, tests, bootstrap intervals, figures, and notes. | `data/raw_data/Full_Result.xlsx` |
| `code/02_prepare_data.R` | Reuses a matching market snapshot or downloads daily prices for 95 stocks and SPY; saves prices, coverage, and snapshot metadata. | Yahoo Finance access if downloading |
| `code/03_original_model.R` | Builds the original predictors and forward-return target; fits the original XGBoost model; saves predictions, holdings, returns, model, and diagnostics. | `data/raw_data/market_snapshot.rds` |
| `code/04_improved_model.R` | Builds revised features on the original model's exact training and test rows; fits and saves the improved model and outputs. | Stage 3 outputs and market snapshot |
| `code/05_compare_models.R` | Compares the saved predictions and returns; writes predictive and investment metrics, tables, figures, and notes. Does not refit either model. | Stage 3 and 4 outputs |

## Data and Analysis

### Classroom portfolios

`data/raw_data/Full_Result.xlsx` contains the final values for two portfolios, each of which started with $100,000. `portfolio1` is the portfolio selected subjectively; `portfolio2` is the portfolio selected after analysis. The Stage 1 script accepts variations in column capitalization, spaces, and underscores. It records incomplete pairs in an audit file and excludes them from paired comparisons; nonempty values that cannot be parsed stop the script for inspection.

The analysis calculates holding-period returns, descriptive statistics, the share of teams in which Portfolio 2 outperformed, paired return differences, a two-sided paired t-test, and a 95% percentile bootstrap confidence interval using 10,000 resamples. Differences are defined as Portfolio 2 minus Portfolio 1.

### Market data and prediction models

Stage 2 obtains daily prices through `tidyquant` from Yahoo Finance for the classroom universe of 95 U.S. stocks plus SPY. The request starts on January 1, 2022 and ends at `Sys.Date()`. The downloaded adjusted closing prices are used to construct returns. A saved market snapshot includes the prices, security list, requested dates, and download timestamp.

The target is the adjusted-price return from the next trading day to the twentieth future trading day:

```text
adjusted price at t+20 / adjusted price at t+1 - 1
```

The training sample uses observations dated before January 1, 2024; the test sample starts on that date. Both XGBoost models use matching observations and target values. Settings are fixed in advance; there is no separate validation period, automated parameter search, or annual retraining.

The original model uses price, volume, return, momentum, volatility, and market-adjusted predictors. It uses 300 trees, depth 5, learning rate 0.05, loss reduction 0, and `min_n = 10`.

The improved model uses proportional indicators, including 21-, 63-, and 126-trading-day momentum, five-day returns, 21-day volatility, relative momentum versus SPY, a volume ratio, and distance below the trailing 126-day high. It uses 500 trees, depth 3, learning rate 0.03, loss reduction 0.01, `min_n = 30`, L2 regularization of 5, and 0.8 row and column sampling proportions.

Stage 5 compares both models with a historical-mean forecast using RMSE, MAE, correlations, directional accuracy, out-of-sample R-squared, and daily cross-sectional rank correlation. Investment results use the classroom procedure: select the ten highest-predicted stocks on the first available prediction date of each month, apply the existing nonnegative-prediction weighting calculation, and compound monthly returns. The script also compares an equal-weight stock-universe benchmark and SPY. Transaction costs are not modeled; backtest results are hypothetical.

## Reproduction Instructions

### 1. Get the project and open it

Clone or download this repository, then open `Zhengyang_Ding_AEDS6400_blog9.Rproj` in RStudio. Opening the project is recommended so `here` can identify the project root. Do not replace paths with a local absolute path.

### 2. Install required packages

Install these packages once if they are not already available:

```r
install.packages(c(
  "here",
  "readxl",
  "tidyverse",
  "tidyquant",
  "tidymodels",
  "lubridate",
  "slider",
  "xgboost"
))
```

### 3. Check required input files

For the classroom analysis, confirm that `data/raw_data/Full_Result.xlsx` is present and includes the two portfolio columns. To run model stages without downloading data, confirm that `data/raw_data/market_snapshot.rds` is present. If the market snapshot is absent, Stage 2 needs an internet connection to Yahoo Finance.

### 4. Run the complete analysis

From the opened RStudio project, run the following in order in the R console:

```r
source(here::here("code", "00_config.R"))
source(here::here("code", "01_class_results.R"))
source(here::here("code", "02_prepare_data.R"))
source(here::here("code", "03_original_model.R"))
source(here::here("code", "04_improved_model.R"))
source(here::here("code", "05_compare_models.R"))
```

The analysis scripts also source `00_config.R` themselves. Stages 3 and 4 each fit one model; Stage 5 uses their saved outputs and does not refit them. Run the stages sequentially because later stages depend on files produced by earlier stages.

### 5. Reproduce using the saved market snapshot

By default, `refresh_data` is `FALSE`. Stage 2 reuses `market_snapshot.rds` only when its saved security list and requested start and end dates match the current configuration. Because the end date is `Sys.Date()`, running Stage 2 on a later date may request fresh data even when refresh is off.

To use the committed snapshot as-is, skip Stage 2 and run the other stages in order:

```r
source(here::here("code", "00_config.R"))
source(here::here("code", "01_class_results.R"))
source(here::here("code", "03_original_model.R"))
source(here::here("code", "04_improved_model.R"))
source(here::here("code", "05_compare_models.R"))
```

This requires the snapshot and classroom spreadsheet to be present in the checkout. To intentionally request current market data, set `refresh_data <- TRUE` in `code/00_config.R` and run Stage 2. New data can change model results.

To regenerate only the comparison tables and figures from existing Stage 3 and Stage 4 outputs, run:

```r
source(here::here("code", "05_compare_models.R"))
```

### 6. Review generated outputs

Useful tables are saved in `results/tables/`, including:

- `01_data_quality.csv`, `01_portfolio_summary.csv`, and `01_paired_comparison.csv`;
- `02_price_coverage.csv` and `02_snapshot.csv`;
- `03_sample_summary.csv` and `04_sample_comparison.csv`;
- `04_model_settings.csv` and `04_improved_features.csv`;
- `05_prediction_metrics.csv`, `05_rank_ic_by_date.csv`, and `05_investment_summary.csv`; and
- `05_monthly_return_comparison.csv`, `05_return_differences.csv`, and `05_annual_returns.csv`.

Figures are saved in `results/figures/`; method records, result summaries, and R session details are saved in `results/notes/`. Scripts overwrite the generated files with the same names. Random seeds are specified in the analysis scripts.

## Reported Results (Reference)

The reported classroom analysis used 45 complete pairs. Portfolio 2's mean return was 3.09%, compared with 1.18% for Portfolio 1; its mean paired advantage was 1.91 percentage points, with Portfolio 2 outperforming in 30 pairs. The paired-test 95% confidence interval ranged from -0.38 to 4.20 percentage points (two-sided p-value approximately 0.100).

| Model | RMSE | MAE | Out-of-sample R² | Direction accuracy | Mean daily rank correlation |
|:--|--:|--:|--:|--:|--:|
| Historical mean | 0.08887 | 0.06428 | 0.0000 | 56.06% | NA |
| Original XGBoost | 0.09354 | 0.06830 | -0.1079 | 52.46% | 0.0405 |
| Improved XGBoost | 0.09184 | 0.06683 | -0.0679 | 51.00% | 0.0212 |

In the reported 34-month backtest, cumulative returns were 437.39% for the original model, 432.37% for the improved model, 61.93% for the equal-weight universe, and 69.26% for SPY. These are historical, hypothetical results and are not guarantees of future performance.
