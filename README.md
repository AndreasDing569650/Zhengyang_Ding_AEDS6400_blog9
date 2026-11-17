# Zhengyang_Ding_AEDS6400_blog9: Predicting Stock Returns with Gradient Boosting

## Project Overview

This repository contains the R code, data, fitted models, tables, and figures for Blog Post 9: Predicting Stock Returns with Gradient Boosting.

The project revisits a classroom stock-selection experiment and evaluates whether changes to an XGBoost model improve stock-return predictions and investment performance.

The analysis addresses three questions:

1. Did portfolios selected after analysis outperform portfolios selected subjectively in the classroom experiment?
2. Can revised predictors and model settings improve the original gradient boosting model?
3. Do improvements in prediction accuracy translate into better investment performance?

The revised model reduced RMSE relative to the original model, but did not outperform a historical-mean forecast. Its direction accuracy and stock-ranking performance also declined. In the classroom backtest, it finished with a slightly lower cumulative return and substantially greater monthly variation.

## Introduction

In our computational economics class, we explored whether financial analysis could help investors select stocks more effectively than intuition alone. Each team created two portfolios: one based on subjective choices and another informed by analysis.

The class also introduced an XGBoost model that predicts future stock returns using historical market data. This project implements that model, modifies its predictors and settings, and compares the results using the same training observations, test observations, and portfolio procedure.

The analysis distinguishes prediction accuracy from investment performance. Smaller forecasting errors do not necessarily produce better stock rankings or a portfolio with more favorable returns and risk.

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

Each portfolio started with **$100,000**.

Classroom analytical tools included correlations, Sharpe ratios, Jensen’s alpha, portfolio optimization, and stock-return prediction. The methods actually used by each team are not identified in the results spreadsheet.

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
- figures showing return distributions, within-team comparisons, and confidence intervals.

All paired differences are defined as **Portfolio 2 minus Portfolio 1**. Positive values favor the analyzed portfolio.

The accompanying blog also discusses our five-stock subjective portfolio using its simulator screenshot. That discussion is separate from the statistical analysis of the class spreadsheet.

### Market data

Daily market data are obtained from [Yahoo Finance](https://finance.yahoo.com/) through R’s [`tidyquant`](https://business-science.github.io/tidyquant/) package.

The dataset uses the classroom stock universe: **95 U.S. stocks and SPY**.

Downloaded fields are:

- ticker symbol and date;
- open, high, low, and close;
- trading volume; and
- adjusted closing price.

Adjusted closing prices are used to construct return variables.

The download request begins on **January 1, 2022**, and ends at `Sys.Date()`. The reported snapshot was downloaded on **November 16, 2026**, and contains observations from **January 3, 2022, through November 13, 2026**.

Each of the 96 securities has 1,222 observations in this snapshot.

The stock universe is:

```text
AAPL MSFT NVDA GOOG META AMZN AVGO ORCL ADBE CRM
CSCO AMD INTC QCOM TXN IBM NOW INTU AMAT MU

JPM BAC WFC GS MS BLK C SCHW SPGI AXP
USB PNC TFC COF

UNH JNJ LLY PFE MRK ABBV TMO DHR ABT BMY
AMGN GILD CVS ISRG MDT

TSLA HD MCD NKE SBUX LOW TJX BKNG CMG ORLY

WMT COST PG KO PEP PM MO CL EL

CAT GE HON UPS BA RTX DE LMT MMM ETN

XOM CVX COP SLB EOG

NFLX DIS CMCSA TMUS VZ

AMT PLD NEE DUK SO LIN APD
```

The saved snapshot is stored in:

```text
data/raw_data/market_snapshot.rds
```

It contains the price data, security list, requested date range, and download timestamp.

The combined prices are also saved as:

```text
data/raw_data/prices_daily.rds
data/raw_data/prices_daily.csv
```

### Prediction target and time divisions

The prediction target follows the classroom definition:

$$
R_{i,t}^{forward}
=
\frac{P_{i,t+20}^{adj}}{P_{i,t+1}^{adj}} - 1
$$

The denominator is the next trading day’s adjusted closing price. The numerator is the adjusted closing price on the twentieth future trading day.

The training and test samples are divided by observation date:

| Sample | Date rule | Actual observation dates | Observations |
|:--|:--|:--|--:|
| Training | Before January 1, 2024 | July 6, 2022–December 29, 2023 | 35,625 |
| Test | January 1, 2024 onward | January 2, 2024–October 16, 2026 | 66,595 |

The first usable training date reflects the historical observations required to construct the predictors. The final test date reflects the future prices required to calculate the target.

Both models use identical training rows, test rows, and target values.

Model settings are fixed in advance. There is no separate validation period, automated parameter search, or annual retraining.

### Original XGBoost model

The original model follows the classroom specification.

Its predictors include:

- open, high, low, close, and adjusted prices;
- trading volume;
- daily stock returns;
- daily SPY returns;
- classroom-defined one-, three-, and six-month momentum;
- lagged return volatility;
- short-term returns; and
- market-adjusted daily returns.

The main model settings are:

| Parameter | Setting |
|:--|--:|
| Trees | 300 |
| Tree depth | 5 |
| Learning rate | 0.05 |
| Loss reduction | 0 |
| `min_n` | 10 |

The model is implemented using a `tidymodels` workflow with the `xgboost` engine. Date and ticker symbol are assigned ID roles rather than used as predictors.

The model is fitted once using the training sample and then used to generate predictions for the test sample.

### Improved XGBoost model

The revised model replaces raw price levels with proportional indicators:

- 21-, 63-, and 126-trading-day momentum;
- five-trading-day returns;
- 21-trading-day volatility;
- 63-trading-day momentum relative to SPY;
- current volume relative to its 21-day average;
- distance below the trailing 126-day high; and
- daily SPY returns.

These features describe recent performance without depending directly on a stock’s price level.

The model uses more trees, shallower depth, a lower learning rate, and stronger regularization:

| Parameter | Original | Improved |
|:--|--:|--:|
| Trees | 300 | 500 |
| Tree depth | 5 | 3 |
| Learning rate | 0.05 | 0.03 |
| Loss reduction | 0 | 0.01 |
| `min_n` | 10 | 30 |
| L2 regularization, `lambda` | 1 | 5 |
| Row sampling proportion | 1.00 | 0.80 |
| Column sampling proportion | 1.00 | 0.80 |

In the improved `tidymodels` specification, proportional sampling is implemented using:

```r
sample_size = 0.8
mtry = 0.8
```

with:

```r
set_engine(
  "xgboost",
  counts = FALSE,
  lambda = 5
)
```

The improved model is fitted once. Its portfolio calculations follow the same procedure as the original model.

### Predictive evaluation

Both models are compared with a historical-mean forecast calculated from the original training sample.

Reported metrics are:

- root mean squared error, or RMSE;
- mean absolute error, or MAE;
- Pearson correlation;
- pooled Spearman rank correlation;
- directional accuracy;
- out-of-sample R² relative to the historical-mean forecast; and
- average daily cross-sectional Spearman rank correlation.

Negative out-of-sample R² means that a model has higher squared prediction error than the historical-mean benchmark.

The historical-mean forecast assigns every stock the same prediction. Its correlation-based measures are therefore reported as `NA`.

### Investment evaluation

The two models use the same classroom portfolio procedure:

1. Identify the first available prediction date in each month.
2. Select the ten stocks with the highest predicted returns.
3. Apply the classroom weighting calculation based on nonnegative predictions.
4. Calculate portfolio returns using the original forward-return target.
5. Compound the resulting monthly portfolio returns.

The reported comparison includes **34 monthly portfolios**, from **January 2024 through October 2026**.

Additional investment benchmarks are:

- the equal-weight return of the stock universe on the same prediction dates; and
- SPY returns calculated using the classroom monthly aggregation.

The comparison reports:

- cumulative compounded return;
- average monthly return;
- monthly return standard deviation;
- the proportion of positive months;
- maximum drawdown at monthly endpoints;
- compounded returns by signal year; and
- average return differences between strategies.

The original-formula Sharpe, alpha, and beta outputs are saved separately in `05_original_formula_metrics.csv`.

Investment figures display compounded monthly return indices. No transaction-cost scenarios are included.

## Repository Structure

The main analysis files and generated outputs are organized as follows:

```text
Zhengyang_Ding_AEDS6400_blog9/
├── README.md
├── .gitignore
├── Zhengyang_Ding_AEDS6400_blog9.Rproj
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
│   │   ├── market_snapshot.rds
│   │   ├── prices_daily.csv
│   │   └── prices_daily.rds
│   └── processed_data/
│       ├── 01_class_data_audit.csv
│       ├── 01_class_results_clean.csv
│       ├── 03_original_results.rds
│       ├── 03_original_predictions.csv
│       ├── 03_original_holdings.csv
│       ├── 04_improved_results.rds
│       ├── 04_improved_predictions.csv
│       ├── 04_improved_holdings.csv
│       └── 05_prediction_comparison.csv
├── models/
│   ├── 03_original_model.rds
│   └── 04_improved_model.rds
└── results/
    ├── figures/
    │   ├── 01_class_return_distribution.png
    │   ├── 01_class_paired_returns.png
    │   ├── 01_class_mean_difference.png
    │   ├── 03_original_model_performance.png
    │   ├── 05_model_performance_comparison.png
    │   ├── 05_annual_return_comparison.png
    │   └── 05_prediction_rmse.png
    ├── notes/
    │   ├── 01_class_results_summary.txt
    │   ├── 01_session_info.txt
    │   ├── 02_session_info.txt
    │   ├── 03_original_method.txt
    │   ├── 03_session_info.txt
    │   ├── 04_session_info.txt
    │   ├── 05_method_record.txt
    │   ├── 05_results_summary.txt
    │   └── 05_session_info.txt
    └── tables/
        ├── 01_data_quality.csv
        ├── 01_portfolio_summary.csv
        ├── 01_paired_comparison.csv
        ├── 02_download_log.csv
        ├── 02_price_coverage.csv
        ├── 02_snapshot.csv
        ├── 02_stock_universe.csv
        ├── 03_original_returns.csv
        ├── 03_original_reported_metrics.csv
        ├── 03_latest_portfolio.csv
        ├── 03_sample_summary.csv
        ├── 04_improved_returns.csv
        ├── 04_model_settings.csv
        ├── 04_improved_features.csv
        ├── 04_sample_comparison.csv
        ├── 05_prediction_metrics.csv
        ├── 05_rank_ic_by_date.csv
        ├── 05_monthly_return_comparison.csv
        ├── 05_investment_summary.csv
        ├── 05_original_formula_metrics.csv
        ├── 05_return_differences.csv
        └── 05_annual_returns.csv
```

### Script descriptions

- `code/00_config.R` loads packages and defines project paths, the stock universe, dates, and shared functions.
- `code/01_class_results.R` reads the classroom spreadsheet, compares paired portfolios, and saves statistics and figures.
- `code/02_prepare_data.R` downloads or reads the market snapshot and saves price data, coverage information, and download metadata.
- `code/03_original_model.R` constructs the original predictors and target, fits the classroom XGBoost model, and saves predictions, portfolios, returns, and the original performance figure.
- `code/04_improved_model.R` constructs the revised predictors, fits the improved model on the same sample, and applies the same portfolio procedure.
- `code/05_compare_models.R` combines the saved outputs, calculates comparison metrics, and generates tables and figures.

### Main result files

| File | Contents |
|:--|:--|
| `01_portfolio_summary.csv` | Classroom portfolio descriptive statistics |
| `01_paired_comparison.csv` | Paired differences, tests, and confidence intervals |
| `02_price_coverage.csv` | Price coverage by security |
| `02_snapshot.csv` | Requested dates, final observation date, and download timestamp |
| `03_sample_summary.csv` | Original training and test sample information |
| `04_model_settings.csv` | Original and improved model settings |
| `04_sample_comparison.csv` | Confirmation of matching sample sizes and dates |
| `05_prediction_metrics.csv` | Test-sample prediction metrics |
| `05_rank_ic_by_date.csv` | Daily cross-sectional ranking performance |
| `05_monthly_return_comparison.csv` | Monthly model and benchmark returns |
| `05_investment_summary.csv` | Compounded returns and monthly risk measures |
| `05_original_formula_metrics.csv` | Original-formula Sharpe, alpha, and beta outputs |
| `05_return_differences.csv` | Average and median return differences |
| `05_annual_returns.csv` | Compounded monthly returns by signal year |

These tables are saved in `results/tables/`.

Main figures in `results/figures/` include:

- `01_class_return_distribution.png`
- `01_class_paired_returns.png`
- `01_class_mean_difference.png`
- `03_original_model_performance.png`
- `05_model_performance_comparison.png`
- `05_annual_return_comparison.png`
- `05_prediction_rmse.png`

## Reproduction Instructions

### 1. Open the repository in RStudio

Clone or download the repository and open `Zhengyang_Ding_AEDS6400_blog9.Rproj`. The scripts locate files relative to the project.

### 2. Install the required packages

Run once:

```r
install.packages(c(
  "readxl",
  "tidyverse",
  "tidyquant",
  "tidymodels",
  "lubridate",
  "slider",
  "xgboost"
))
```

Session information is saved in `results/notes/` when the analysis scripts run.

### 3. Confirm the classroom input file

The classroom spreadsheet must be located at:

```text
data/raw_data/Full_Result.xlsx
```

The portfolio columns should be named `portfolio1` (without data analysis) and `portfolio2` (with data analysis). The classroom script also accepts differences in capitalization, spaces, and underscores.

Incomplete portfolio pairs are documented and excluded from paired comparisons. Nonempty values that cannot be parsed trigger an error for inspection.

### 4. Run the scripts in order

With the repository open as an RStudio project, run:

```r
source("code/00_config.R")
source("code/01_class_results.R")
source("code/02_prepare_data.R")
source("code/03_original_model.R")
source("code/04_improved_model.R")
source("code/05_compare_models.R")
```

The analysis scripts load `00_config.R` as needed.

Stages 03 and 04 each fit one model. Stage 05 reads their saved outputs without refitting either model.

### 5. Use the cached market data

The market snapshot is stored in:

```text
data/raw_data/market_snapshot.rds
```

By default, `02_prepare_data.R` reuses a snapshot when its requested date range and security list match the current configuration:

```r
refresh_data <- FALSE
```

Because the download endpoint is `Sys.Date()`, running Stage 02 on a later date requests a new snapshot.

To deliberately refresh the data on the same date, change the setting in `00_config.R`:

```r
refresh_data <- TRUE
```

To reproduce the reported results using the committed snapshot, skip Stage 02 and run:

```r
source("code/00_config.R")
source("code/01_class_results.R")
source("code/03_original_model.R")
source("code/04_improved_model.R")
source("code/05_compare_models.R")
```

This uses the saved `market_snapshot.rds` rather than requesting new prices.

To regenerate only the comparison tables and figures from saved model outputs, run:

```r
source("code/05_compare_models.R")
```

### 6. Inspect the outputs

The scripts create missing output directories and overwrite their corresponding generated files.

Start with:

```text
results/tables/01_paired_comparison.csv
results/tables/04_sample_comparison.csv
results/tables/04_model_settings.csv
results/tables/05_prediction_metrics.csv
results/tables/05_investment_summary.csv
results/tables/05_monthly_return_comparison.csv
```

Then review the figures in `results/figures/`.

Random seeds are specified. The saved data snapshot, result tables, and session information document the reported run.

## Expected Interpretation

### Classroom results

The analyzed portfolios earned an average return of 3.09%, compared with 1.18% for the subjective portfolios.

Their average paired advantage was 1.91 percentage points. Portfolio 2 outperformed in 30 of the 45 teams.

However, the paired-test 95% confidence interval ranged from −0.38 to 4.20 percentage points, with a two-sided p-value of approximately 0.100.

The results suggest a possible benefit from analysis, but leave uncertainty about a consistent advantage.

Our subjective portfolio screenshot also shows that a positive overall result can depend heavily on one stock: Moderna contributed approximately 79% of the holdings’ net gain.

### Predictive results

| Model | RMSE | MAE | Out-of-sample R² | Direction accuracy | Mean daily rank correlation |
|:--|--:|--:|--:|--:|--:|
| Historical mean | 0.08887 | 0.06428 | 0.0000 | 56.06% | NA |
| Original XGBoost | 0.09354 | 0.06830 | −0.1079 | 52.46% | 0.0405 |
| Improved XGBoost | 0.09184 | 0.06683 | −0.0679 | 51.00% | 0.0212 |

The revised model reduced RMSE by approximately 1.82% relative to the original. MAE also declined.

However, the historical mean remained more accurate. Direction accuracy and average daily ranking correlation declined after the model changes.

The improvement was therefore limited to some measures of return-magnitude prediction.

### Investment results

The comparison includes 34 monthly portfolios.

| Strategy | Cumulative return | Monthly return standard deviation | Monthly-endpoint maximum drawdown |
|:--|--:|--:|--:|
| Original XGBoost | 437.39% | 8.66% | −11.80% |
| Improved XGBoost | 432.37% | 16.35% | −28.06% |
| Equal-weight universe | 61.93% | 2.97% | −7.29% |
| SPY | 69.26% | 3.18% | −6.28% |

These are hypothetical results calculated from the classroom backtest procedure.

The revised model finished slightly below the original while experiencing approximately 1.89 times its monthly return standard deviation and a deeper monthly-endpoint drawdown.

Its average monthly return was higher—6.15%, compared with 5.41%—but its compounded result was lower. This illustrates the importance of distinguishing arithmetic average returns from compounded growth.

The revised model outperformed the original in 2025, but trailed in 2024 and January–October 2026.

## Summary

This project connects classroom portfolio evidence, market-data collection, feature construction, gradient boosting, and investment evaluation.

The revised model slightly reduced prediction errors but weakened direction and stock-ranking accuracy. Its cumulative investment result was close to the original’s, with substantially greater monthly variation.

The main lesson is that a smaller forecasting error does not automatically produce a better stock-selection strategy. Prediction accuracy, ranking ability, compounded returns, and investment risk need to be evaluated together.
