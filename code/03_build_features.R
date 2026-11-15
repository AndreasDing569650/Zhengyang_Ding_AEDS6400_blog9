# ============================================================
# Stage 3: features, forward labels, and common signal dates
# ============================================================

source("D:/Rproject/6400-blog9/code/00_config.R")

prices <- readRDS(file.path(paths$raw, "prices_daily.rds"))

market <- prices |>
  filter(symbol == "SPY") |>
  arrange(date) |>
  transmute(
    date,
    spy_price = adjusted,
    spy_ret = adjusted / dplyr::lag(adjusted) - 1
  )

calendar <- market$date

# Every signal occurs 20 trading days after the preceding signal.
# Entry: close at t+1. Exit: close at t+21.
# The next portfolio enters at the preceding portfolio's exit.
first_signal <- which(calendar >= analysis_start)[1]

signal_dates <- calendar[
  seq.int(first_signal, length(calendar) - holding_days - 1L,
          by = holding_days)
]

panel <- prices |>
  filter(symbol %in% tickers) |>
  left_join(market, by = "date") |>
  group_by(symbol) |>
  arrange(date, .by_group = TRUE) |>
  mutate(
    return = adjusted / dplyr::lag(adjusted) - 1,
    
    # Classroom definitions, retained for baseline fidelity.
    mom_1m = dplyr::lag(adjusted, 21) / dplyr::lag(adjusted, 1) - 1,
    mom_3m = dplyr::lag(adjusted, 63) / dplyr::lag(adjusted, 1) - 1,
    mom_6m = dplyr::lag(adjusted, 126) / dplyr::lag(adjusted, 1) - 1,
    vol_1m = slider::slide_dbl(
      dplyr::lag(return), sd, .before = 21, .complete = TRUE
    ),
    ret_5d = dplyr::lag(adjusted, 5) / dplyr::lag(adjusted, 1) - 1,
    excess_ret = return - spy_ret,
    
    # Improved, scale-free features.
    momentum_21 = adjusted / dplyr::lag(adjusted, 21) - 1,
    momentum_63 = adjusted / dplyr::lag(adjusted, 63) - 1,
    momentum_126 = adjusted / dplyr::lag(adjusted, 126) - 1,
    
    # 12-to-1-month momentum: exclude the most recent month.
    momentum_12_1 =
      dplyr::lag(adjusted, 21) / dplyr::lag(adjusted, 252) - 1,
    
    reversal_5 = adjusted / dplyr::lag(adjusted, 5) - 1,
    
    volatility_21 = slider::slide_dbl(
      return, sd, .before = 20, .complete = TRUE
    ),
    
    relative_momentum_63 =
      (adjusted / dplyr::lag(adjusted, 63)) /
      (spy_price / dplyr::lag(spy_price, 63)) - 1,
    
    volume_ratio_21 = volume / slider::slide_dbl(
      volume, mean, .before = 20, .complete = TRUE
    ),
    
    drawdown_252 = adjusted / slider::slide_dbl(
      adjusted, max, .before = 251, .complete = TRUE
    ) - 1,
    
    # Future information appears only in these label fields.
    entry_date = dplyr::lead(date, 1),
    label_end = dplyr::lead(date, holding_days + 1L),
    target = dplyr::lead(adjusted, holding_days + 1L) /
      dplyr::lead(adjusted, 1) - 1
  ) |>
  ungroup()

original_features <- c(
  "open", "high", "low", "close", "volume", "adjusted",
  "return", "spy_ret", "mom_1m", "mom_3m", "mom_6m",
  "vol_1m", "ret_5d", "excess_ret"
)

improved_features <- c(
  "momentum_21", "momentum_63", "momentum_126",
  "momentum_12_1", "reversal_5", "volatility_21",
  "relative_momentum_63", "volume_ratio_21",
  "drawdown_252", "spy_ret"
)

# Use common complete observations for both models.
all_features <- union(original_features, improved_features)

panel <- panel |>
  filter(
    date >= analysis_start,
    !is.na(label_end),
    label_end <= test_end,
    is.finite(target)
  ) |>
  filter(if_all(all_of(all_features), ~ is.finite(.x))) |>
  mutate(is_signal = date %in% signal_dates)

# Require the complete fixed universe on every evaluation date.
signal_coverage <- panel |>
  filter(is_signal) |>
  count(date, name = "stocks")

if (any(signal_coverage$stocks != length(tickers))) {
  stop("Some signal dates do not contain all 50 stocks.")
}

saveRDS(
  list(
    panel = panel,
    original_features = original_features,
    improved_features = improved_features
  ),
  file.path(paths$processed, "03_model_panel.rds")
)

write_csv(
  panel |> count(year = as.integer(format(date, "%Y"))),
  file.path(paths$tables, "03_observations_by_year.csv")
)

write_csv(
  tibble(
    model = c(
      rep("Original", length(original_features)),
      rep("Improved", length(improved_features))
    ),
    feature = c(original_features, improved_features)
  ),
  file.path(paths$tables, "03_feature_definitions.csv")
)

message("Stage 3 completed: features and forward-return labels saved.")