# ============================================================
# Stage 5: compare saved original and improved model outputs
# Does not refit or modify either model
# ============================================================

source("D:/Rproject/6400-blog9/code/00_config.R")

original <- readRDS(
  file.path(paths$processed, "03_original_results.rds")
)

improved <- readRDS(
  file.path(paths$processed, "04_improved_results.rds")
)


# ---------- 1. Common prediction observations ----------

original_predictions <- original$predictions |>
  select(
    date,
    symbol,
    target,
    original_prediction = .pred
  )

improved_predictions <- improved$predictions |>
  select(
    date,
    symbol,
    improved_prediction = .pred
  )

comparison <- original_predictions |>
  left_join(
    improved_predictions,
    by = c("date", "symbol")
  ) |>
  mutate(
    historical_mean =
      mean(original$train$target)
  )

stopifnot(
  nrow(comparison) == nrow(original_predictions),
  !anyNA(comparison),
  !anyDuplicated(
    comparison[c("date", "symbol")]
  )
)

write_csv(
  comparison,
  file.path(paths$processed, "05_prediction_comparison.csv")
)


# ---------- 2. Predictive metrics ----------

benchmark_sse <- sum(
  (comparison$target - comparison$historical_mean)^2
)

stopifnot(benchmark_sse > 0)

long_predictions <- comparison |>
  pivot_longer(
    cols = c(
      original_prediction,
      improved_prediction,
      historical_mean
    ),
    names_to = "model",
    values_to = "prediction"
  )

prediction_metrics <- long_predictions |>
  group_by(model) |>
  summarise(
    observations = n(),
    
    rmse = sqrt(mean(
      (target - prediction)^2
    )),
    
    mae = mean(abs(
      target - prediction
    )),
    
    pearson_correlation = safe_correlation(
      prediction,
      target,
      method = "pearson"
    ),
    
    pooled_rank_correlation = safe_correlation(
      prediction,
      target,
      method = "spearman"
    ),
    
    directional_accuracy = mean(
      (prediction > 0) == (target > 0)
    ),
    
    r2_oos =
      1 -
      sum((target - prediction)^2) /
      benchmark_sse,
    
    .groups = "drop"
  )

# Additional within-date ranking measure.
rank_ic <- long_predictions |>
  group_by(model, date) |>
  summarise(
    rank_ic = safe_correlation(
      prediction,
      target,
      method = "spearman"
    ),
    .groups = "drop"
  )

rank_summary <- rank_ic |>
  group_by(model) |>
  summarise(
    mean_daily_rank_ic = if (all(is.na(rank_ic))) {
      NA_real_
    } else {
      mean(rank_ic, na.rm = TRUE)
    },
    .groups = "drop"
  )

prediction_metrics <- prediction_metrics |>
  left_join(
    rank_summary,
    by = "model"
  )

write_csv(
  prediction_metrics,
  file.path(paths$tables, "05_prediction_metrics.csv")
)

write_csv(
  rank_ic,
  file.path(paths$tables, "05_rank_ic_by_date.csv")
)


# ---------- 3. Retain the original investment outputs ----------

original_monthly <- original$returns |>
  select(
    month,
    date,
    original_return = portfolio_return,
    spy_return
  )

improved_monthly <- improved$returns |>
  select(
    month,
    improved_date = date,
    improved_return = portfolio_return
  )

monthly_comparison <- original_monthly |>
  left_join(
    improved_monthly,
    by = "month"
  )

stopifnot(
  !anyNA(monthly_comparison),
  all(
    monthly_comparison$date ==
      monthly_comparison$improved_date
  )
)

# Additional simple investment benchmark.
# Use the same original prediction dates and original target values.
equal_weight_benchmark <- original$predictions |>
  semi_join(
    monthly_comparison |> select(date),
    by = "date"
  ) |>
  group_by(date) |>
  summarise(
    equal_weight_return = mean(target),
    stocks = n(),
    .groups = "drop"
  )

monthly_comparison <- monthly_comparison |>
  left_join(
    equal_weight_benchmark,
    by = "date"
  ) |>
  arrange(month)

stopifnot(!anyNA(monthly_comparison))

write_csv(
  monthly_comparison,
  file.path(paths$tables, "05_monthly_return_comparison.csv")
)


# ---------- 4. Summarize investment results ----------

return_long <- monthly_comparison |>
  select(
    month,
    date,
    original_return,
    improved_return,
    equal_weight_return,
    spy_return
  ) |>
  pivot_longer(
    cols = c(
      original_return,
      improved_return,
      equal_weight_return,
      spy_return
    ),
    names_to = "strategy",
    values_to = "return"
  ) |>
  arrange(strategy, month) |>
  group_by(strategy) |>
  mutate(
    cumulative_index =
      cumprod(1 + return)
  ) |>
  ungroup()

investment_summary <- return_long |>
  group_by(strategy) |>
  group_modify(~ {
    
    r <- .x$return
    index <- cumprod(1 + r)
    
    tibble(
      months = length(r),
      
      total_compounded_return =
        tail(index, 1) - 1,
      
      mean_monthly_return =
        mean(r),
      
      monthly_return_sd =
        sd(r),
      
      positive_month_share =
        mean(r > 0),
      
      monthly_endpoint_max_drawdown =
        min(
          index /
            cummax(c(1, index))[-1] - 1
        ),
      
      # Same formula used in the professor's script.
      sharpe_as_original_code =
        if (sd(r) > 0) {
          mean(r) / sd(r) * sqrt(252)
        } else {
          NA_real_
        }
    )
  }) |>
  ungroup()

write_csv(
  investment_summary,
  file.path(paths$tables, "05_investment_summary.csv")
)

reported_metrics <- tibble(
  model = c(
    "Original XGBoost",
    "Improved XGBoost"
  ),
  
  sharpe_as_original_code = c(
    original$reported_sharpe,
    improved$reported_sharpe
  ),
  
  alpha_as_original_code = c(
    original$reported_alpha,
    improved$reported_alpha
  ),
  
  beta_as_original_code = c(
    original$reported_beta,
    improved$reported_beta
  )
)

write_csv(
  reported_metrics,
  file.path(paths$tables, "05_original_formula_metrics.csv")
)


# ---------- 5. Return differences ----------

return_differences <- bind_rows(
  lapply(
    c(
      "original_return",
      "equal_weight_return",
      "spy_return"
    ),
    function(comparator) {
      
      difference <-
        monthly_comparison$improved_return -
        monthly_comparison[[comparator]]
      
      tibble(
        comparison = paste(
          "Improved minus",
          comparator
        ),
        
        months = length(difference),
        
        mean_monthly_difference =
          mean(difference),
        
        median_monthly_difference =
          median(difference),
        
        outperformance_share =
          mean(difference > 0)
      )
    }
  )
)

write_csv(
  return_differences,
  file.path(paths$tables, "05_return_differences.csv")
)


# ---------- 6. Results by year ----------

annual_results <- return_long |>
  mutate(
    year = year(month)
  ) |>
  group_by(
    strategy,
    year
  ) |>
  summarise(
    months = n(),
    
    compounded_return =
      prod(1 + return) - 1,
    
    .groups = "drop"
  )

write_csv(
  annual_results,
  file.path(paths$tables, "05_annual_returns.csv")
)


# ---------- 7. Comparison figures ----------

strategy_labels <- c(
  original_return = "Original XGBoost",
  improved_return = "Improved XGBoost",
  equal_weight_return = "Equal-weight universe",
  spy_return = "SPY: original calculation"
)

p_performance <- return_long |>
  mutate(
    strategy = recode(
      strategy,
      !!!strategy_labels
    )
  ) |>
  ggplot(
    aes(
      date,
      cumulative_index,
      color = strategy
    )
  ) +
  geom_line(linewidth = 0.8) +
  labs(
    title = "Original and improved model comparison",
    subtitle = "Saved monthly returns; original portfolio rules retained",
    x = NULL,
    y = "Compounded monthly return index",
    color = NULL
  ) +
  theme(
    legend.position = "bottom"
  )

save_figure(
  p_performance,
  "05_model_performance_comparison.png",
  width = 10,
  height = 6
)

p_annual <- annual_results |>
  mutate(
    strategy = recode(
      strategy,
      !!!strategy_labels
    )
  ) |>
  ggplot(
    aes(
      factor(year),
      compounded_return,
      fill = strategy
    )
  ) +
  geom_col(
    position = "dodge"
  ) +
  scale_y_continuous(
    labels = scales::label_percent()
  ) +
  labs(
    title = "Performance by year",
    subtitle = "The final year may contain fewer than 12 portfolios",
    x = NULL,
    y = "Compounded monthly return",
    fill = NULL
  ) +
  theme(
    legend.position = "bottom"
  )

save_figure(
  p_annual,
  "05_annual_return_comparison.png",
  width = 10,
  height = 6
)

p_prediction <- prediction_metrics |>
  mutate(
    model = recode(
      model,
      original_prediction = "Original XGBoost",
      improved_prediction = "Improved XGBoost",
      historical_mean = "Historical mean"
    )
  ) |>
  ggplot(
    aes(
      model,
      rmse,
      fill = model
    )
  ) +
  geom_col(width = 0.6) +
  labs(
    title = "Out-of-sample prediction error",
    subtitle = "Lower RMSE is better",
    x = NULL,
    y = "RMSE"
  ) +
  theme(
    legend.position = "none"
  )

save_figure(
  p_prediction,
  "05_prediction_rmse.png"
)


# ---------- 8. Method record ----------

writeLines(
  c(
    "MODEL COMPARISON",
    "",
    "Data: Yahoo Finance daily prices for 95 stocks and SPY.",
    "Both models use the same price snapshot, training observations,",
    "test observations, and forward-return targets.",
    "",
    "The original model follows the classroom specification.",
    "The improved model changes the predictors and model parameters.",
    "",
    "Both models are trained using observations before 2024-01-01",
    "and evaluated using observations from 2024-01-01 onward.",
    "Portfolio selection and return calculations follow the same procedure.",
    "",
    "Prediction performance is compared using RMSE, MAE, correlations,",
    "directional accuracy, and out-of-sample R-squared.",
    "The historical-mean forecast provides a simple prediction benchmark.",
    "",
    "Investment performance is compared using monthly portfolio returns.",
    "Additional benchmarks include the equal-weight stock universe and SPY."
  ),
  file.path(
    paths$notes,
    "05_method_record.txt"
  )
)

capture.output(
  print(prediction_metrics, width = Inf),
  print(investment_summary, width = Inf),
  print(reported_metrics, width = Inf),
  print(return_differences, width = Inf),
  file = file.path(
    paths$notes,
    "05_results_summary.txt"
  )
)

capture.output(
  sessionInfo(),
  file = file.path(paths$notes, "05_session_info.txt")
)

print(prediction_metrics, width = Inf)
print(investment_summary, width = Inf)
print(reported_metrics, width = Inf)
print(return_differences, width = Inf)

print(p_performance)
print(p_annual)
print(p_prediction)

message("Stage 5 completed.")