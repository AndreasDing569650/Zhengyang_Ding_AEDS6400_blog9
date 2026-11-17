# ============================================================
# Stage 4: improved predictors and fixed model settings
# Same training/test rows and targets as the original model
# ============================================================

source(here::here("code", "00_config.R"))

original <- readRDS(
  file.path(paths$processed, "03_original_results.rds")
)

snapshot <- readRDS(
  file.path(paths$raw, "market_snapshot.rds")
)

prices <- snapshot$prices

market <- prices |>
  filter(symbol == "SPY") |>
  arrange(date) |>
  transmute(
    date,
    spy_price = adjusted,
    spy_ret = adjusted / dplyr::lag(adjusted) - 1
  )

# No indicator requires more history than the original
# model's approximately six-month warm-up.
feature_data <- prices |>
  filter(symbol %in% tickers) |>
  left_join(market, by = "date") |>
  group_by(symbol) |>
  arrange(date, .by_group = TRUE) |>
  mutate(
    daily_return =
      adjusted / dplyr::lag(adjusted) - 1,
    
    momentum_21 =
      adjusted / dplyr::lag(adjusted, 21) - 1,
    
    momentum_63 =
      adjusted / dplyr::lag(adjusted, 63) - 1,
    
    momentum_126 =
      adjusted / dplyr::lag(adjusted, 126) - 1,
    
    reversal_5 =
      adjusted / dplyr::lag(adjusted, 5) - 1,
    
    volatility_21 = slider::slide_dbl(
      daily_return,
      sd,
      .before = 20,
      .complete = TRUE
    ),
    
    relative_momentum_63 =
      (adjusted / dplyr::lag(adjusted, 63)) /
      (spy_price / dplyr::lag(spy_price, 63)) - 1,
    
    volume_ratio_21 =
      volume / slider::slide_dbl(
        volume,
        mean,
        .before = 20,
        .complete = TRUE
      ),
    
    drawdown_126 =
      adjusted / slider::slide_dbl(
        adjusted,
        max,
        .before = 125,
        .complete = TRUE
      ) - 1
  ) |>
  ungroup() |>
  select(
    date,
    symbol,
    all_of(improved_features)
  )

if (anyDuplicated(feature_data[c("date", "symbol")])) {
  stop("Duplicate feature observations.")
}

# Preserve the original sample rows and original target values.
improved_train <- original$train |>
  select(date, symbol, target) |>
  left_join(
    feature_data,
    by = c("date", "symbol")
  )

improved_test <- original$test |>
  select(date, symbol, target) |>
  left_join(
    feature_data,
    by = c("date", "symbol")
  )

if (
  anyNA(improved_train) ||
  anyNA(improved_test)
) {
  stop(
    "Missing improved features on original sample rows. ",
    "No rows have been removed automatically."
  )
}

if (
  !all(vapply(
    improved_train[improved_features],
    function(x) all(is.finite(x)),
    logical(1)
  )) ||
  !all(vapply(
    improved_test[improved_features],
    function(x) all(is.finite(x)),
    logical(1)
  ))
) {
  stop("Nonfinite improved features found.")
}

stopifnot(
  nrow(improved_train) == nrow(original$train),
  nrow(improved_test) == nrow(original$test),
  
  identical(
    improved_train$target,
    original$train$target
  ),
  
  identical(
    improved_test$target,
    original$test$target
  )
)

rec <- recipe(
  target ~ .,
  data = improved_train
) |>
  update_role(
    date,
    symbol,
    new_role = "id"
  )

# Fixed in advance: no validation or test-set parameter search.
improved_spec <- boost_tree(
  trees = 500,
  tree_depth = 3,
  learn_rate = 0.03,
  loss_reduction = 0.01,
  min_n = 30,
  sample_size = 0.8,
  mtry = 0.8
) |>
  set_engine(
    "xgboost",
    counts = FALSE,
    lambda = 5
  ) |>
  set_mode("regression")

improved_wf <- workflow() |>
  add_recipe(rec) |>
  add_model(improved_spec)

set.seed(123)

improved_fit <- fit(
  improved_wf,
  data = improved_train
)

improved_predictions <- predict(
  improved_fit,
  improved_test
) |>
  bind_cols(improved_test)

# Copy the original portfolio-construction calculation.
# This deliberately retains the original weight expression.
improved_holdings <- improved_predictions |>
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

# Copy the original portfolio-return calculation.
improved_returns <- improved_holdings |>
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
  ) |>
  left_join(
    original$spy_returns,
    by = "month"
  )

# Copy the original reported performance calculations.
improved_sharpe <-
  mean(
    improved_returns$portfolio_return,
    na.rm = TRUE
  ) /
  sd(
    improved_returns$portfolio_return,
    na.rm = TRUE
  ) *
  sqrt(252)

improved_capm <- lm(
  portfolio_return ~ spy_return,
  data = improved_returns
)

improved_alpha <-
  coef(improved_capm)[1] * 252

improved_beta <-
  coef(improved_capm)[2]

saveRDS(
  improved_fit,
  file.path(paths$models, "04_improved_model.rds")
)

saveRDS(
  list(
    predictions = improved_predictions,
    holdings = improved_holdings,
    returns = improved_returns,
    reported_sharpe = improved_sharpe,
    reported_alpha = improved_alpha,
    reported_beta = improved_beta
  ),
  file.path(paths$processed, "04_improved_results.rds")
)

write_csv(
  improved_predictions,
  file.path(paths$processed, "04_improved_predictions.csv")
)

write_csv(
  improved_holdings,
  file.path(paths$processed, "04_improved_holdings.csv")
)

write_csv(
  improved_returns,
  file.path(paths$tables, "04_improved_returns.csv")
)

write_csv(
  tibble(
    model = c("Original", "Improved"),
    trees = c(300, 500),
    tree_depth = c(5, 3),
    learn_rate = c(0.05, 0.03),
    loss_reduction = c(0, 0.01),
    min_n = c(10, 30),
    lambda = c(1, 5),
    subsample = c(1, 0.8),
    colsample_bytree = c(1, 0.8)
  ),
  file.path(paths$tables, "04_model_settings.csv")
)

write_csv(
  tibble(feature = improved_features),
  file.path(paths$tables, "04_improved_features.csv")
)

write_csv(
  tibble(
    training_rows_original = nrow(original$train),
    training_rows_improved = nrow(improved_train),
    test_rows_original = nrow(original$test),
    test_rows_improved = nrow(improved_test),
    training_start = min(improved_train$date),
    training_end = max(improved_train$date),
    test_start = min(improved_test$date),
    test_end = max(improved_test$date)
  ),
  file.path(paths$tables, "04_sample_comparison.csv")
)

capture.output(
  sessionInfo(),
  file = file.path(paths$notes, "04_session_info.txt")
)

message("Stage 4 completed.")
