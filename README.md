# Zhengyang_Ding_AEDS6400_blog9: Predicting Stock Returns with Gradient Boosting

## Project Overview

This repository contains the R code, data, fitted models, tables, and figures for Blog Post 9: Predicting Stock Returns with Gradient Boosting.

The project revisits a classroom stock-selection experiment and evaluates whether changes to an XGBoost model improve out-of-sample stock-return forecasts and investment performance.

The analysis addresses three questions:

1. Did portfolios selected after analysis outperform portfolios selected subjectively in the classroom experiment?
2. Can revised predictors, stronger regularization, and annual retraining improve the original gradient boosting model?
3. Do better forecasts translate into economically meaningful investment returns after trading costs?

The improved model reduced prediction errors relative to the original model and generated higher investment returns in the backtest. However, it did not outperform a historical-mean forecast on prediction error, and confidence intervals for its average investment-return advantages included zero.

## Introduction

Stock prices respond to new information, while future news is unknown. Relationships found in historical data may also change over time. A flexible machine learning model can therefore fit past returns without identifying patterns that remain useful in new market conditions.

This project separates predictive accuracy from investment performance. A model may forecast individual returns poorly while still ranking some stocks usefully. Conversely, a profitable backtest may reflect concentration, market exposure, or a favorable sample period.

The analysis combines a classroom portfolio comparison with a historical backtest using a common stock universe, trading schedule, and transaction-cost framework.

## Data and Method

### Classroom experiment data

The classroom analysis uses:

```text
data/raw_data/Full_Result.xlsx
```

The relevant columns are:

| Column | Description |
|:--|:--|
| `portfolio1` | Final value of the portfolio selected subjectively without analysis |
| `portfolio2` | Final value of the portfolio selected after analysis |

Each portfolio started with **$100,000**. The specific analytical procedures used for Portfolio 2 are unknown.

Holding-period returns are calculated as:

$$
R = \frac{\text{Final portfolio value}}{100000} - 1
$$

The analysis uses 45 complete team-level pairs and reports:

- descriptive statistics for both portfolios;
- the proportion of teams in which Portfolio 2 outperformed;
- paired return differences;
- a two-sided paired t-test;
- a 95% percentile bootstrap confidence interval using 10,000 resamples; and
- figures showing return distributions and within-team comparisons.

All paired differences are defined as **Portfolio 2 minus Portfolio 1**. Positive values favor the analyzed portfolio.

These comparisons describe the observed outcomes. They do not identify the causal effect of analysis, because stock selections and analytical methods were not randomly assigned.

### Market data

Daily market data are obtained from [Yahoo Finance](https://finance.yahoo.com/) through the Yahoo interface in R's [quantmod](https://www.quantmod.com/) package.

This is an unofficial interface and does not require an API key.

The dataset contains 50 selected U.S. stocks and SPY, used as a market proxy and investment benchmark. Downloaded fields are:

- date and ticker symbol;
- open, high, low, and close;
- trading volume; and
- adjusted closing price.

Adjusted closing prices are used as a total-return proxy when constructing returns.

The saved snapshot covers **January 4, 2010, through December 31, 2025**, with 4,024 observations for each of the 51 securities.

The fixed stock sample is:

```text
AAPL MSFT NVDA IBM ORCL CSCO INTC AMD QCOM TXN ADBE AMAT
JPM BAC WFC GS MS AXP BLK
JNJ PFE MRK ABT AMGN GILD MDT UNH
PG KO PEP WMT COST MCD HD NKE SBUX
CAT HON UPS BA LMT
XOM CVX COP SLB
DIS VZ T DUK SO
```

This is an ex-post selected sample, not a reconstruction of historical index membership. Survivorship and selection bias limit how broadly the results can be generalized.

Individual downloads are cached in `data/raw_data/yahoo_cache/`. The download script records coverage and failures and stops if required securities or trading dates are missing.

### Prediction target and time divisions

Features use information available by the signal-date close.

For a signal on trading day \(t\), the prediction target is:

$$
R_{i,t}^{forward}
=
\frac{P_{i,t+21}^{adj}}{P_{i,t+1}^{adj}} - 1
$$

This represents buying at the next trading day's close and holding for 20 trading days.

Signals occur every 20 trading days. Consecutive portfolios share an exit and entry date, so their holding intervals do not overlap.

The time divisions are:

| Period | Purpose |
|:--|:--|
| 2010 | Feature-history preparation |
| 2011 onward | Eligible model observations |
| 2018–2019 | Parameter validation |
| 2020–2025 | Final out-of-sample evaluation |

At every fitting cutoff, training includes only observations whose future-return labels have already been realized.

Final evaluation contains **74 prediction dates and 3,700 stock-level forecasts**. The first and last calendar years cover partial investment years.

### Original XGBoost model

The baseline reconstructs the classroom-reference XGBoost model using a common sample and evaluation procedure.

Its predictors include raw price and volume variables, daily returns, classroom-defined momentum measures, volatility, short-term returns, and SPY returns.

The main settings are:

| Parameter | Setting |
|:--|--:|
| Boosting rounds | 300 |
| Maximum tree depth | 5 |
| Learning rate | 0.05 |
| Minimum child weight | 10 |
| Row subsampling | 1.00 |
| Column subsampling | 1.00 |
| L2 regularization, `lambda` | 1 |

The baseline is fitted using labels realized before January 1, 2020, and remains fixed during testing.

The classroom-reference script is available in [this archive](https://github.com/Changlin-DU/Stock_Returns/blob/main/code/original/original_xgboost.R).

Because this project changes the stock sample, training periods, and evaluation rules, it is a reconstruction rather than an exact replication of the classroom results.

### Improved XGBoost model

The improved model replaces raw price levels with scale-free predictors:

- 21-, 63-, and 126-trading-day momentum;
- 12-to-1-month momentum, excluding the most recent month;
- five-trading-day returns;
- 21-trading-day volatility;
- momentum relative to SPY;
- current volume relative to its 21-day average;
- distance below the trailing 252-day high; and
- daily SPY returns.

Eight candidate configurations combine:

- tree depths of 2 or 3;
- 200 or 400 boosting rounds; and
- expanding or trailing five-year training windows.

Selection uses the lowest validation RMSE in 2018–2019. Test-period performance is not used to select parameters.

The selected configuration is:

| Parameter | Setting |
|:--|--:|
| Boosting rounds | 200 |
| Maximum tree depth | 2 |
| Learning rate | 0.05 |
| Minimum child weight | 30 |
| Row subsampling | 0.80 |
| Column subsampling | 0.80 |
| L2 regularization, `lambda` | 10 |
| Training window | Expanding |

The improved model is retrained annually using only previously realized labels.

Because several model components change together, the comparison evaluates the combined procedure rather than isolating the contribution of any single modification.

### Predictive evaluation

Both models are compared with a historical-mean forecast calculated from the pre-test training sample.

Reported metrics are:

- root mean squared error, or RMSE;
- mean absolute error, or MAE;
- out-of-sample R² relative to the historical-mean forecast; and
- average within-date Spearman rank correlation.

Negative out-of-sample R² means a model has higher squared prediction error than the historical-mean benchmark.

The historical-mean forecast assigns all stocks the same prediction, so its within-date rank correlation is undefined and reported as `NA`.

### Investment evaluation

The original and improved model portfolios each hold the ten highest-ranked stocks at equal weights.

They are compared with:

1. an equal-weight portfolio of all 50 sample stocks; and
2. buy-and-hold SPY.

All strategies use the same investment window. The backtest accounts for weight drift before rebalancing and applies transaction costs to estimated purchases and sales.

Cost scenarios are **0, 10, and 25 basis points per dollar bought or sold**. Initial purchases and final liquidation are included.

Daily wealth is used to calculate:

- total return;
- compound annual growth rate;
- annualized volatility;
- Sharpe ratio;
- maximum drawdown; and
- calendar-year returns within the backtest window.

Sharpe ratios assume a zero risk-free rate.

Uncertainty in return differences and prediction-loss reductions is assessed using 2,000 circular block-bootstrap resamples with blocks of six holding periods. Each period retains its full cross-section of stocks.

## Repository Structure

The main analysis files and generated outputs are organized as follows:

```text
6400-blog9/
├── README.md
├── code/
│   ├── 00_config.R
│   ├── 01_class_results.R
│   ├── 02_download_prices.R
│   ├── 03_build_features.R
│   └── 04_compare_models.R
├── data/
│   ├── raw_data/
│   │   ├── Full_Result.xlsx
│   │   ├── yahoo_cache/
│   │   ├── prices_daily.rds
│   │   └── prices_daily.csv
│   └── processed_data/
│       ├── 01_class_data_audit.csv
│       ├── 01_class_results_clean.csv
│       ├── 03_model_panel.rds
│       ├── 04_out_of_sample_predictions.csv
│       ├── 04_daily_backtest.csv
│       ├── 04_period_returns.csv
│       └── 04_holdings.csv
├── models/
│   ├── 04_selected_config.rds
│   ├── 04_original_model.rds
│   └── 04_improved_2020.rds ... 04_improved_2025.rds
└── results/
    ├── tables/
    ├── figures/
    └── notes/
```

### Script descriptions

- `code/00_config.R` loads packages and defines project paths, the stock universe, evaluation dates, and trading assumptions.
- `code/01_class_results.R` reads the classroom spreadsheet, validates values, compares paired portfolios, and saves statistics and figures.
- `code/02_download_prices.R` downloads or reads cached Yahoo data, validates coverage, and saves the combined price dataset.
- `code/03_build_features.R` constructs both feature sets, forward-return labels, and common prediction dates.
- `code/04_compare_models.R` selects parameters using validation data, generates out-of-sample predictions, runs portfolio backtests, and saves evaluation results.

### Main result files

| File | Contents |
|:--|:--|
| `01_portfolio_summary.csv` | Classroom portfolio descriptive statistics |
| `01_paired_comparison.csv` | Paired differences, tests, and confidence intervals |
| `02_price_coverage.csv` | Data coverage by security |
| `03_observations_by_year.csv` | Eligible model observations by year |
| `04_validation_results.csv` | Candidate configurations and validation scores |
| `04_prediction_metrics.csv` | Out-of-sample prediction metrics |
| `04_rank_ic_by_period.csv` | Within-date ranking performance |
| `04_investment_performance.csv` | Investment metrics across cost scenarios |
| `04_annual_returns.csv` | Annual returns within the investment window |
| `04_return_difference_intervals.csv` | Bootstrap intervals for return differences |
| `04_prediction_loss_intervals.csv` | Bootstrap intervals for prediction-loss reductions |

These tables are saved in `results/tables/`.

Main figures in `results/figures/` include:

- `01_class_return_distribution.png`
- `01_class_paired_returns.png`
- `01_class_mean_difference.png`
- `04_net_wealth.png`
- `04_annual_returns.png`
- `04_cost_sensitivity.png`

## Reproduction Instructions

### 1. Open the repository in RStudio

Clone or download the repository and open an R session.

The original local project directory is:

```text
D:/Rproject/6400-blog9
```

The scripts currently contain absolute paths. If using another location, update:

- `project_dir` in `code/00_config.R`;
- `project_dir` in `code/01_class_results.R`; and
- the `source()` path to `00_config.R` at the beginning of scripts 02, 03, and 04.

Keep the relative directory structure unchanged.

### 2. Install the required packages

Run once:

```r
install.packages(c(
  "readxl",
  "tidyverse",
  "quantmod",
  "slider",
  "xgboost"
))
```

Use an R version compatible with the installed package versions. Session information is saved under `results/notes/` when the scripts run.

### 3. Confirm the classroom input file

The classroom spreadsheet must be located at:

```text
data/raw_data/Full_Result.xlsx
```

Its portfolio columns should be named `portfolio1` and `portfolio2`. The script also accepts differences in capitalization, spaces, and underscores.

Nonempty values that cannot be parsed trigger an error. Incomplete portfolio pairs are documented and excluded from paired comparisons.

### 4. Run the scripts in order

For the original local directory:

```r
setwd("D:/Rproject/6400-blog9")

source("code/01_class_results.R")
source("code/02_download_prices.R")
source("code/03_build_features.R")
source("code/04_compare_models.R")
```

`00_config.R` is loaded automatically by the market-analysis scripts.

The model-comparison stage fits multiple candidate models and may take several minutes, depending on the computer.

### 5. Use the cached market data

By default, the download script uses existing per-security cache files:

```r
refresh_cache <- FALSE
```

With complete caches, no new market-data requests are needed.

To deliberately obtain a new snapshot, change this setting in `02_download_prices.R`:

```r
refresh_cache <- TRUE
```

Yahoo may revise historical adjusted prices, and interface availability can change. Using the committed snapshot is preferable when reproducing the reported results.

If `prices_daily.rds` already exists, scripts 03 and 04 can also be run directly without rerunning the download stage.

### 6. Inspect the outputs

The scripts create missing output directories and overwrite their corresponding generated files.

Start with:

```text
results/tables/01_paired_comparison.csv
results/tables/04_validation_results.csv
results/tables/04_prediction_metrics.csv
results/tables/04_investment_performance.csv
results/tables/04_return_difference_intervals.csv
```

Then review the figures in `results/figures/`.

Random seeds are specified, but exact model results may vary with package versions and computing environments. The saved tables and session information document the reported run.

## Expected Interpretation

### Classroom results

The analyzed portfolios earned an average return of 3.09%, compared with 1.18% for the subjective portfolios.

Their average paired advantage was 1.91 percentage points. However, the paired-test 95% interval ranged from −0.38 to 4.20 percentage points, and the two-sided p-value was approximately 0.100.

The results suggest a possible advantage but do not establish a stable or causal benefit from analysis.

### Predictive results

| Model | RMSE | Out-of-sample R² | Mean rank correlation |
|:--|--:|--:|--:|
| Historical mean | 0.08433 | 0.0000 | NA |
| Original XGBoost | 0.08951 | −0.1266 | 0.0130 |
| Improved XGBoost | 0.08486 | −0.0125 | 0.0288 |

The improved model reduced RMSE by approximately 5.20% relative to the original model. It also improved stock-ranking performance.

Nevertheless, the historical mean remained the more accurate point forecast.

### Investment results

At a one-way trading cost of 10 basis points:

| Strategy | Annualized return | Annualized volatility | Sharpe ratio | Maximum drawdown |
|:--|--:|--:|--:|--:|
| Original XGBoost | 19.40% | 24.93% | 0.84 | −41.31% |
| Improved XGBoost | 23.04% | 28.80% | 0.87 | −35.98% |
| Equal-weight universe | 14.77% | 20.22% | 0.78 | −33.43% |
| SPY | 14.81% | 20.88% | 0.77 | −33.72% |

The improved strategy generated higher returns in this sample, but also had higher volatility than the original strategy and both simple benchmarks.

Its return advantage was not consistent across years. Bootstrap intervals for its average holding-period return advantage over each comparator included zero.

At 25 basis points, its annualized return declined to 20.64%, and its Sharpe ratio fell to approximately 0.80.

## Summary

This project demonstrates a complete workflow connecting classroom portfolio evidence, market-data collection, feature construction, gradient boosting, and out-of-sample investment evaluation.

More careful model design improved prediction errors relative to the original model and produced higher returns in the reported backtest. It did not outperform a historical-mean forecast on prediction accuracy or establish reliable investment outperformance.

The main lesson is to evaluate forecasting errors, investment returns, risk, trading costs, and uncertainty together. A higher final portfolio value alone does not demonstrate repeatable stock-prediction ability.
