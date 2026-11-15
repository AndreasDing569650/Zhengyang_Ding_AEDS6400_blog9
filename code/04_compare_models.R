# ============================================================
# Stage 4: validation, out-of-sample predictions, and backtests
# ============================================================

source("D:/Rproject/6400-blog9/code/00_config.R")

bundle <- readRDS(file.path(paths$processed, "03_model_panel.rds"))
panel <- bundle$panel
original_features <- bundle$original_features
improved_features <- bundle$improved_features

prices <- readRDS(file.path(paths$raw, "prices_daily.rds"))

# ---------- 1. Model helpers ----------

make_matrix <- function(data, features) {
  x <- as.matrix(as.data.frame(data[, features]))
  storage.mode(x) <- "double"
  x
}

# Only labels realized strictly before the fitting cutoff are allowed.
training_data <- function(cutoff, window_years = 0L) {
  out <- panel |> filter(label_end < cutoff)
  
  if (window_years > 0L) {
    start_year <- as.integer(format(cutoff, "%Y")) - window_years
    out <- out |>
      filter(date >= as.Date(sprintf("%d-01-01", start_year)))
  }
  
  if (nrow(out) < 1000) stop("Insufficient training observations.")
  stopifnot(all(out$label_end < cutoff))
  out
}

fit_model <- function(data, features, config = NULL) {
  params <- list(
    objective = "reg:squarederror",
    eval_metric = "rmse",
    tree_method = "hist",
    nthread = 2,
    seed = 6409
  )
  
  if (is.null(config)) {
    # Main classroom model settings.
    params <- c(params, list(
      max_depth = 5L,
      eta = 0.05,
      min_child_weight = 10,
      gamma = 0,
      subsample = 1,
      colsample_bytree = 1,
      lambda = 1
    ))
    rounds <- 300L
  } else {
    params <- c(params, list(
      max_depth = as.integer(config$depth),
      eta = 0.05,
      min_child_weight = 30,
      gamma = 0,
      subsample = 0.8,
      colsample_bytree = 0.8,
      lambda = 10
    ))
    rounds <- as.integer(config$rounds)
  }
  
  xgboost::xgb.train(
    params = params,
    data = xgboost::xgb.DMatrix(
      make_matrix(data, features), label = data$target
    ),
    nrounds = rounds,
    verbose = 0
  )
}

forecast <- function(model, data, features) {
  as.numeric(predict(
    model,
    xgboost::xgb.DMatrix(make_matrix(data, features))
  ))
}

safe_cor <- function(x, y, method = "spearman") {
  if (length(x) < 3 || sd(x) == 0 || sd(y) == 0) return(NA_real_)
  cor(x, y, method = method)
}


# ---------- 2. Select settings using 2018-2019 only ----------

# window = 0: expanding history; window = 5: recent five years.
candidates <- tidyr::expand_grid(
  depth = c(2L, 3L),
  rounds = c(200L, 400L),
  window = c(0L, 5L)
) |>
  mutate(candidate = row_number())

validation_results <- vector("list", nrow(candidates))

for (k in seq_len(nrow(candidates))) {
  config <- candidates[k, ]
  yearly_predictions <- list()
  
  for (year in 2018:2019) {
    cutoff <- as.Date(sprintf("%d-01-01", year))
    
    train <- training_data(cutoff, config$window)
    
    # Validation labels must also finish before final testing begins.
    valid <- panel |>
      filter(
        is_signal,
        as.integer(format(date, "%Y")) == year,
        label_end < test_start
      )
    
    model <- fit_model(train, improved_features, config)
    
    yearly_predictions[[as.character(year)]] <- valid |>
      select(date, symbol, target) |>
      mutate(prediction = forecast(model, valid, improved_features))
  }
  
  valid_predictions <- bind_rows(yearly_predictions)
  
  rank_ic <- valid_predictions |>
    group_by(date) |>
    summarise(
      ic = safe_cor(prediction, target),
      .groups = "drop"
    )
  
  validation_results[[k]] <- config |>
    mutate(
      validation_rmse = sqrt(mean(
        (valid_predictions$target - valid_predictions$prediction)^2
      )),
      validation_mean_rank_ic = mean(rank_ic$ic, na.rm = TRUE)
    )
  
  message("Validation candidate ", k, "/", nrow(candidates))
}

validation_results <- bind_rows(validation_results) |>
  arrange(validation_rmse, depth, rounds, candidate)

# Selection criterion is fixed in advance: lowest validation RMSE.
best <- validation_results |> slice(1)

write_csv(
  validation_results,
  file.path(paths$tables, "04_validation_results.csv")
)
saveRDS(best, file.path(paths$models, "04_selected_config.rds"))

print(best)


# ---------- 3. Final out-of-sample predictions ----------

test <- panel |>
  filter(is_signal, date >= test_start) |>
  arrange(date, symbol)

if (nrow(test) == 0) stop("No test observations.")

# Original model is frozen at the start of 2020.
pretest_train <- training_data(test_start)

original_model <- fit_model(pretest_train, original_features)

test$original <- forecast(original_model, test, original_features)

# Simple prediction benchmark, also frozen before final testing.
test$historical_mean <- mean(pretest_train$target)

saveRDS(
  original_model,
  file.path(paths$models, "04_original_model.rds")
)

# Improved model is refitted once each year.
# Its window and hyperparameters were chosen before final testing.
improved_predictions <- list()

for (year in 2020:2025) {
  cutoff <- as.Date(sprintf("%d-01-01", year))
  train <- training_data(cutoff, best$window)
  
  current <- test |>
    filter(as.integer(format(date, "%Y")) == year)
  
  if (nrow(current) == 0) next
  
  model <- fit_model(train, improved_features, best)
  
  improved_predictions[[as.character(year)]] <- current |>
    select(date, symbol) |>
    mutate(improved = forecast(model, current, improved_features))
  
  saveRDS(
    model,
    file.path(paths$models, paste0("04_improved_", year, ".rds"))
  )
}

test <- test |>
  left_join(
    bind_rows(improved_predictions),
    by = c("date", "symbol")
  ) |>
  select(
    date, symbol, entry_date, label_end, target,
    original, improved, historical_mean
  )

stopifnot(
  !anyNA(test),
  all(test$label_end > test$entry_date)
)

write_csv(
  test,
  file.path(paths$processed, "04_out_of_sample_predictions.csv")
)


# ---------- 4. Predictive evaluation ----------

predictions_long <- test |>
  pivot_longer(
    c(original, improved, historical_mean),
    names_to = "model",
    values_to = "prediction"
  )

benchmark_sse <- sum((test$target - test$historical_mean)^2)

prediction_metrics <- predictions_long |>
  group_by(model) |>
  summarise(
    observations = n(),
    rmse = sqrt(mean((target - prediction)^2)),
    mae = mean(abs(target - prediction)),
    r2_oos = 1 - sum((target - prediction)^2) / benchmark_sse,
    .groups = "drop"
  )

rank_ic <- predictions_long |>
  group_by(model, date) |>
  summarise(
    rank_ic = safe_cor(prediction, target),
    .groups = "drop"
  )

ic_summary <- rank_ic |>
  group_by(model) |>
  summarise(
    mean_rank_ic = if (all(is.na(rank_ic))) NA_real_ else
      mean(rank_ic, na.rm = TRUE),
    .groups = "drop"
  )

prediction_metrics <- prediction_metrics |>
  left_join(ic_summary, by = "model")

write_csv(
  prediction_metrics,
  file.path(paths$tables, "04_prediction_metrics.csv")
)
write_csv(rank_ic, file.path(paths$tables, "04_rank_ic_by_period.csv"))


# ---------- 5. Price matrix for actual portfolio accounting ----------

price_wide <- prices |>
  select(date, symbol, adjusted) |>
  pivot_wider(names_from = symbol, values_from = adjusted) |>
  arrange(date)

price_dates <- price_wide$date
assets <- c(tickers, "SPY")

price_matrix <- as.matrix(as.data.frame(price_wide[, assets]))
colnames(price_matrix) <- assets

stopifnot(!anyNA(price_matrix), all(price_matrix > 0))

periods <- test |>
  distinct(date, entry_date, label_end) |>
  arrange(date)

# Holdings are fixed in advance by the corresponding signal.
choose_weights <- function(strategy, signal_date) {
  weights <- setNames(rep(0, length(assets)), assets)
  
  if (strategy == "SPY") {
    weights["SPY"] <- 1
  } else if (strategy == "Equal_weight") {
    weights[tickers] <- 1 / length(tickers)
  } else {
    scores <- test |>
      filter(date == signal_date) |>
      arrange(desc(.data[[strategy]]), symbol) |>
      slice_head(n = portfolio_size)
    
    weights[scores$symbol] <- 1 / portfolio_size
  }
  
  weights
}


# ---------- 6. Backtest with drift-aware trading costs ----------

run_backtest <- function(strategy, bps) {
  rate <- bps / 10000
  wealth <- 1
  
  # Initially all capital is cash.
  previous_drifted_weights <- setNames(rep(0, length(assets)), assets)
  
  daily_parts <- list(tibble(
    date = periods$date[1],
    wealth = 1
  ))
  period_parts <- list()
  holdings_parts <- list()
  
  for (j in seq_len(nrow(periods))) {
    signal_date <- periods$date[j]
    entry <- match(periods$entry_date[j], price_dates)
    exit <- match(periods$label_end[j], price_dates)
    
    weights <- choose_weights(strategy, signal_date)
    
    # Sum of absolute buys and sells as a share of portfolio value.
    # Full replacement costs 2 * bps; initial purchase costs 1 * bps.
    traded_fraction <- sum(abs(weights - previous_drifted_weights))
    entry_cost <- rate * traded_fraction
    
    # Costs are funded from portfolio assets before investment.
    starting_wealth <- wealth
    invested_wealth <- starting_wealth * (1 - entry_cost)
    
    relative_prices <- sweep(
      price_matrix[entry:exit, , drop = FALSE],
      2,
      price_matrix[entry, ],
      "/"
    )
    
    daily_wealth <- invested_wealth *
      as.numeric(relative_prices %*% weights)
    
    asset_returns <- price_matrix[exit, ] /
      price_matrix[entry, ] - 1
    
    gross_return <- sum(weights * asset_returns)
    
    # Post-return weights, before the next rebalance.
    previous_drifted_weights <- weights * (1 + asset_returns) /
      (1 + gross_return)
    
    # All strategies are liquidated on the final date.
    if (j == nrow(periods)) {
      daily_wealth[length(daily_wealth)] <-
        tail(daily_wealth, 1) * (1 - rate)
    }
    
    wealth <- tail(daily_wealth, 1)
    
    daily_parts[[length(daily_parts) + 1L]] <- tibble(
      date = price_dates[entry:exit],
      wealth = daily_wealth
    )
    
    period_parts[[j]] <- tibble(
      strategy = strategy,
      cost_bps = bps,
      signal_date = signal_date,
      entry_date = periods$entry_date[j],
      exit_date = periods$label_end[j],
      gross_return = gross_return,
      net_return = wealth / starting_wealth - 1,
      traded_fraction = traded_fraction
    )
    
    holdings_parts[[j]] <- tibble(
      strategy = strategy,
      signal_date = signal_date,
      symbol = assets,
      weight = as.numeric(weights)
    ) |>
      filter(weight > 0)
  }
  
  # A rebalance can share a date with the previous period's exit.
  # Keep post-trade wealth on that date, including costs.
  daily <- bind_rows(daily_parts) |>
    group_by(date) |>
    summarise(wealth = last(wealth), .groups = "drop") |>
    arrange(date) |>
    mutate(
      strategy = strategy,
      cost_bps = bps,
      daily_return = wealth / dplyr::lag(wealth) - 1
    )
  
  list(
    daily = daily,
    periods = bind_rows(period_parts),
    holdings = bind_rows(holdings_parts)
  )
}

strategies <- c("original", "improved", "Equal_weight", "SPY")

runs <- list()

for (bps in cost_bps) {
  for (strategy in strategies) {
    key <- paste(strategy, bps, sep = "_")
    runs[[key]] <- run_backtest(strategy, bps)
  }
}

daily_results <- bind_rows(lapply(runs, function(x) x$daily))
period_results <- bind_rows(lapply(runs, function(x) x$periods))

write_csv(
  daily_results,
  file.path(paths$processed, "04_daily_backtest.csv")
)
write_csv(
  period_results,
  file.path(paths$processed, "04_period_returns.csv")
)

# Holdings are unchanged across cost scenarios.
holdings <- bind_rows(lapply(
  runs[endsWith(names(runs), "_10")],
  function(x) x$holdings
))
write_csv(holdings, file.path(paths$processed, "04_holdings.csv"))


# ---------- 7. Economic performance ----------

performance <- daily_results |>
  group_by(strategy, cost_bps) |>
  group_modify(~ {
    d <- .x |> arrange(date)
    r <- d$daily_return[is.finite(d$daily_return)]
    years <- as.numeric(max(d$date) - min(d$date)) / 365.25
    
    tibble(
      total_return = tail(d$wealth, 1) - 1,
      cagr = tail(d$wealth, 1)^(1 / years) - 1,
      annualized_volatility = sd(r) * sqrt(252),
      sharpe_rf_zero = if (sd(r) > 0)
        mean(r) / sd(r) * sqrt(252) else NA_real_,
      max_drawdown = min(
        d$wealth / cummax(c(1, d$wealth))[-1] - 1
      )
    )
  }) |>
  ungroup() |>
  left_join(
    period_results |>
      group_by(strategy, cost_bps) |>
      summarise(
        mean_traded_fraction = mean(traded_fraction),
        positive_period_share = mean(net_return > 0),
        .groups = "drop"
      ),
    by = c("strategy", "cost_bps")
  )

write_csv(
  performance,
  file.path(paths$tables, "04_investment_performance.csv")
)

# Annual returns use daily wealth, with the previous year-end as base.
annual_returns <- daily_results |>
  group_by(strategy, cost_bps) |>
  arrange(date, .by_group = TRUE) |>
  mutate(year = as.integer(format(date, "%Y"))) |>
  filter(!is.na(daily_return)) |>
  group_by(strategy, cost_bps, year) |>
  summarise(
    return = prod(1 + daily_return) - 1,
    .groups = "drop"
  )

write_csv(
  annual_returns,
  file.path(paths$tables, "04_annual_returns.csv")
)


# ---------- 8. Uncertainty in return and forecast improvements ----------

# Circular block bootstrap:
# resample consecutive six-period blocks, preserving all stocks within
# each period. These intervals are descriptive, not proof of causality.
block_interval <- function(x, repetitions = 2000L, block_length = 6L) {
  n <- length(x)
  block_length <- min(block_length, n)
  
  draws <- replicate(repetitions, {
    starts <- sample.int(n, ceiling(n / block_length), replace = TRUE)
    
    indices <- unlist(lapply(
      starts,
      function(s) ((s - 1L + 0:(block_length - 1L)) %% n) + 1L
    ))
    
    mean(x[indices[seq_len(n)]])
  })
  
  ci <- quantile(draws, c(0.025, 0.975), names = FALSE)
  
  tibble(
    periods = n,
    mean_difference = mean(x),
    ci_lower = ci[1],
    ci_upper = ci[2]
  )
}

net_wide <- period_results |>
  filter(cost_bps == 10) |>
  select(signal_date, strategy, net_return) |>
  pivot_wider(names_from = strategy, values_from = net_return) |>
  arrange(signal_date)

set.seed(6409)

return_uncertainty <- bind_rows(lapply(
  c("original", "Equal_weight", "SPY"),
  function(comparator) {
    block_interval(net_wide$improved - net_wide[[comparator]]) |>
      mutate(comparison = paste("Improved minus", comparator))
  }
))

write_csv(
  return_uncertainty,
  file.path(paths$tables, "04_return_difference_intervals.csv")
)

# Positive loss reduction means that the improved model is better.
loss_by_period <- test |>
  group_by(date) |>
  summarise(
    versus_original = mean(
      (target - original)^2 - (target - improved)^2
    ),
    versus_mean = mean(
      (target - historical_mean)^2 - (target - improved)^2
    ),
    .groups = "drop"
  ) |>
  arrange(date)

loss_uncertainty <- bind_rows(lapply(
  c("versus_original", "versus_mean"),
  function(comparator) {
    block_interval(loss_by_period[[comparator]]) |>
      mutate(comparison = comparator)
  }
))

write_csv(
  loss_uncertainty,
  file.path(paths$tables, "04_prediction_loss_intervals.csv")
)


# ---------- 9. Figures ----------

labels <- c(
  original = "Original XGBoost",
  improved = "Improved XGBoost",
  Equal_weight = "Equal-weight universe",
  SPY = "SPY"
)

p_wealth <- daily_results |>
  filter(cost_bps == 10) |>
  mutate(strategy = recode(strategy, !!!labels)) |>
  ggplot(aes(date, wealth * initial_capital, color = strategy)) +
  geom_line(linewidth = 0.7) +
  scale_y_continuous(labels = scales::label_dollar()) +
  labs(
    title = "Out-of-sample investment performance",
    subtitle = "2020–2025; 10 bps per dollar bought or sold",
    x = NULL, y = "Portfolio value", color = NULL
  ) +
  theme(legend.position = "bottom")

ggsave(
  file.path(paths$figures, "04_net_wealth.png"),
  p_wealth, width = 10, height = 6, dpi = 300, bg = "white"
)

p_annual <- annual_returns |>
  filter(cost_bps == 10) |>
  mutate(strategy = recode(strategy, !!!labels)) |>
  ggplot(aes(factor(year), return, fill = strategy)) +
  geom_col(position = "dodge") +
  scale_y_continuous(labels = scales::label_percent()) +
  labs(
    title = "Does performance persist across years?",
    x = NULL, y = "Net annual return", fill = NULL
  ) +
  theme(legend.position = "bottom")

ggsave(
  file.path(paths$figures, "04_annual_returns.png"),
  p_annual, width = 10, height = 6, dpi = 300, bg = "white"
)

p_cost <- performance |>
  mutate(strategy = recode(strategy, !!!labels)) |>
  ggplot(aes(cost_bps, cagr, color = strategy)) +
  geom_line() +
  geom_point() +
  scale_x_continuous(breaks = cost_bps) +
  scale_y_continuous(labels = scales::label_percent()) +
  labs(
    title = "Sensitivity to transaction costs",
    x = "One-way transaction cost (basis points)",
    y = "Compound annual growth rate",
    color = NULL
  ) +
  theme(legend.position = "bottom")

ggsave(
  file.path(paths$figures, "04_cost_sensitivity.png"),
  p_cost, width = 9, height = 5, dpi = 300, bg = "white"
)

capture.output(
  sessionInfo(),
  file = file.path(paths$notes, "04_session_info.txt")
)

print(prediction_metrics)
print(performance |> filter(cost_bps == 10), width = Inf)
print(return_uncertainty, width = Inf)

message("Stage 4 completed. Inspect results/tables and results/figures.")