# ============================================================
# Blog Post 9
# Stage 3: Original Gradient Boosting Model
# ============================================================

source(here::here("code", "00_config.R"))

set.seed(123)


# 1. Load market data -----------------------------------------

snapshot <- readRDS(
  file.path(paths$raw, "market_snapshot.rds")
)

prices <- snapshot$prices |>
  filter(symbol %in% tickers)

spy <- snapshot$prices |>
  filter(symbol == "SPY") |>
  select(
    date,
    spy_price = adjusted
  ) |>
  arrange(date) |>
  mutate(
    spy_ret =
      spy_price / dplyr::lag(spy_price) - 1
  )


# 2. Construct predictors ------------------------------------

df <- prices |>
  group_by(symbol) |>
  arrange(date) |>
  mutate(
    return =
      adjusted / dplyr::lag(adjusted) - 1
  ) |>
  ungroup() |>
  left_join(
    spy |> select(date, spy_ret),
    by = "date"
  ) |>
  group_by(symbol) |>
  mutate(
    mom_1m =
      dplyr::lag(adjusted, 21) /
      dplyr::lag(adjusted, 1) - 1,
    
    mom_3m =
      dplyr::lag(adjusted, 63) /
      dplyr::lag(adjusted, 1) - 1,
    
    mom_6m =
      dplyr::lag(adjusted, 126) /
      dplyr::lag(adjusted, 1) - 1,
    
    vol_1m = slider::slide_dbl(
      dplyr::lag(return),
      sd,
      .before = 21,
      .complete = TRUE
    ),
    
    ret_5d =
      dplyr::lag(adjusted, 5) /
      dplyr::lag(adjusted, 1) - 1,
    
    excess_ret =
      return - spy_ret
  ) |>
  ungroup() |>
  drop_na()


# 3. Construct prediction target ------------------------------

df <- df |>
  group_by(symbol) |>
  mutate(
    target =
      dplyr::lead(adjusted, 20) /
      dplyr::lead(adjusted, 1) - 1
  ) |>
  ungroup() |>
  drop_na()


# 4. Training and test samples --------------------------------

train <- df |>
  filter(date < test_start)

test <- df |>
  filter(date >= test_start)

if (
  nrow(train) == 0L ||
  nrow(test) == 0L
) {
  stop("The training or test sample is empty.")
}


# 5. Specify the original model -------------------------------

rec <- recipe(
  target ~ .,
  data = train
) |>
  update_role(
    date,
    symbol,
    new_role = "id"
  )

xgb_spec <- boost_tree(
  trees = 300,
  tree_depth = 5,
  learn_rate = 0.05,
  loss_reduction = 0,
  min_n = 10
) |>
  set_engine("xgboost") |>
  set_mode("regression")

final_wf <- workflow() |>
  add_recipe(rec) |>
  add_model(xgb_spec)


# 6. Fit and predict ------------------------------------------

final_fit <- fit(
  final_wf,
  data = train
)

preds <- predict(
  final_fit,
  test
) |>
  bind_cols(test)


# 7. Construct monthly portfolios -----------------------------

backtest <- preds |>
  mutate(
    month = floor_date(date, "month")
  ) |>
  group_by(month) |>
  filter(date == min(date)) |>
  arrange(desc(.pred)) |>
  slice(1:10) |>
  mutate(
    pred_positive = pmax(.pred, 0),
    
    weight = ifelse(
      sum(pred_positive) == 0,
      1 / n(),
      pred_positive / sum(pred_positive)
    )
  ) |>
  ungroup()


# 8. Calculate portfolio returns ------------------------------

returns <- backtest |>
  group_by(month, date) |>
  summarise(
    portfolio_return = sum(
      weight * target,
      na.rm = TRUE
    ),
    .groups = "drop"
  ) |>
  mutate(
    cumulative_return =
      cumprod(1 + portfolio_return)
  )


# 9. Calculate SPY benchmark ----------------------------------

spy_returns <- spy |>
  mutate(
    month = floor_date(date, "month")
  ) |>
  group_by(month) |>
  summarise(
    spy_return = prod(
      1 + (
        spy_price /
          dplyr::lag(spy_price) - 1
      ),
      na.rm = TRUE
    ) - 1,
    .groups = "drop"
  ) |>
  mutate(
    spy_cumulative =
      cumprod(1 + spy_return)
  )

returns <- returns |>
  left_join(
    spy_returns,
    by = "month"
  )


# 10. Calculate performance statistics ------------------------

sharpe <-
  mean(
    returns$portfolio_return,
    na.rm = TRUE
  ) /
  sd(
    returns$portfolio_return,
    na.rm = TRUE
  ) *
  sqrt(252)

capm <- lm(
  portfolio_return ~ spy_return,
  data = returns
)

alpha <- coef(capm)[1] * 252
beta <- coef(capm)[2]


# 11. Most recent portfolio ----------------------------------

latest_date <- max(preds$date)

latest_preds <- preds |>
  filter(date == latest_date) |>
  arrange(desc(.pred))

latest_portfolio <- latest_preds |>
  slice(1:10) |>
  mutate(
    pred_positive = pmax(.pred, 0),
    
    weight = ifelse(
      sum(pred_positive) == 0,
      1 / n(),
      pred_positive / sum(pred_positive)
    )
  )


# 12. Save model and analysis outputs -------------------------

original_results <- list(
  train = train,
  test = test,
  predictions = preds,
  holdings = backtest,
  returns = returns,
  spy = spy,
  spy_returns = spy_returns,
  reported_sharpe = sharpe,
  reported_alpha = alpha,
  reported_beta = beta
)

saveRDS(
  original_results,
  file.path(
    paths$processed,
    "03_original_results.rds"
  )
)

saveRDS(
  final_fit,
  file.path(
    paths$models,
    "03_original_model.rds"
  )
)

write_csv(
  preds,
  file.path(
    paths$processed,
    "03_original_predictions.csv"
  )
)

write_csv(
  backtest,
  file.path(
    paths$processed,
    "03_original_holdings.csv"
  )
)

write_csv(
  returns,
  file.path(
    paths$tables,
    "03_original_returns.csv"
  )
)

write_csv(
  latest_portfolio,
  file.path(
    paths$tables,
    "03_latest_portfolio.csv"
  )
)

reported_metrics <- tibble(
  model = "Original XGBoost",
  sharpe_as_original_code = sharpe,
  alpha_as_original_code = unname(alpha),
  beta_as_original_code = unname(beta)
)

write_csv(
  reported_metrics,
  file.path(
    paths$tables,
    "03_original_reported_metrics.csv"
  )
)

sample_summary <- tibble(
  training_observations = nrow(train),
  test_observations = nrow(test),
  training_first_date = min(train$date),
  training_last_date = max(train$date),
  test_first_date = min(test$date),
  test_last_date = max(test$date),
  monthly_portfolios = n_distinct(backtest$month)
)

write_csv(
  sample_summary,
  file.path(
    paths$tables,
    "03_sample_summary.csv"
  )
)


# 13. Plot performance ---------------------------------------

p_original <- ggplot(
  returns,
  aes(date)
) +
  geom_line(
    aes(
      y = cumulative_return,
      color = "Machine Learning Portfolio"
    ),
    linewidth = 1.2
  ) +
  geom_line(
    aes(
      y = spy_cumulative,
      color = "S&P 500 (SPY)"
    ),
    linewidth = 1.2
  ) +
  labs(
    title = "Machine Learning Portfolio vs. S&P 500",
    subtitle = "Out-of-sample backtest",
    x = "Date",
    y = "Growth of $1",
    color = ""
  ) +
  theme(
    legend.position = "bottom"
  )

save_figure(
  p_original,
  "03_original_model_performance.png"
)


# 14. Save method and session information ---------------------

writeLines(
  c(
    "ORIGINAL GRADIENT BOOSTING MODEL",
    "",
    "Data: Yahoo Finance daily stock prices and SPY.",
    "Predictors: price, volume, returns, momentum, volatility,",
    "short-term returns, and market-adjusted returns.",
    "Target: adjusted price at t+20 divided by adjusted price at t+1, minus one.",
    "Training observations: dates before 2024-01-01.",
    "Test observations: dates from 2024-01-01 onward.",
    "Model: 300 trees, depth 5, learning rate 0.05,",
    "loss reduction 0, and min_n 10.",
    "Portfolios are selected monthly using the original weighting formula.",
    "Reported Sharpe and alpha retain the original model's formulas."
  ),
  file.path(
    paths$notes,
    "03_original_method.txt"
  )
)

capture.output(
  sessionInfo(),
  file = file.path(
    paths$notes,
    "03_session_info.txt"
  )
)

print(sample_summary)
print(reported_metrics)
print(p_original)

message("Stage 3 completed.")
