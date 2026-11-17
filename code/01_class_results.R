# ============================================================
# Blog Post 9 — Stage 1: Class experiment
#
# Input:
#   data/raw_data/Full_Result.xlsx
#
# Outputs:
#   data/processed_data/
#   results/tables/
#   results/figures/
#   results/notes/
#
# Adapted from the classroom reference:
#   stockmarketgameresultsFall2026.R
# ============================================================


# 1. Packages -------------------------------------------------

# Run once if needed:
# install.packages(c("readxl", "tidyverse"))

library(readxl)
library(tidyverse)

source(here::here("code", "00_config.R"))

set.seed(6409)


# 2. Paths and settings ---------------------------------------

project_dir <- here::here()

input_file <- file.path(
  project_dir, "data", "raw_data", "Full_Result.xlsx"
)

processed_dir <- file.path(project_dir, "data", "processed_data")
table_dir     <- file.path(project_dir, "results", "tables")
figure_dir    <- file.path(project_dir, "results", "figures")
note_dir      <- file.path(project_dir, "results", "notes")

for (folder in c(processed_dir, table_dir, figure_dir, note_dir)) {
  dir.create(folder, recursive = TRUE, showWarnings = FALSE)
}

initial_capital <- 100000
bootstrap_repetitions <- 10000

if (!file.exists(input_file)) {
  stop("Input file not found: ", input_file)
}


# 3. Read and validate data -----------------------------------

# Read as text to handle currency symbols and commas explicitly.
raw_results <- read_excel(input_file, sheet = 1, col_types = "text")

# Accept names such as Portfolio1, portfolio_1, or Portfolio 1.
names(raw_results) <- names(raw_results) |>
  str_to_lower() |>
  str_replace_all("[^a-z0-9]", "")

required_columns <- c("portfolio1", "portfolio2")

if (!all(required_columns %in% names(raw_results))) {
  stop(
    "Required columns: portfolio1 and portfolio2.\n",
    "Columns found: ", paste(names(raw_results), collapse = ", ")
  )
}

# Recognize common missing-value codes.
clean_text <- function(x) {
  x <- str_trim(x)
  x[str_to_lower(x) %in% c("", "na", "n/a", "null", "-")] <- NA_character_
  x
}

parse_value <- function(x) {
  x <- clean_text(x)
  suppressWarnings(
    parse_number(x, locale = locale(grouping_mark = ","))
  )
}

results_all <- raw_results |>
  transmute(
    # Row identifier, not a claimed original team ID.
    source_excel_row = row_number() + 1L,
    portfolio1_text = clean_text(portfolio1),
    portfolio2_text = clean_text(portfolio2),
    portfolio1 = parse_value(portfolio1),
    portfolio2 = parse_value(portfolio2)
  ) |>
  mutate(
    parse_issue =
      (!is.na(portfolio1_text) & is.na(portfolio1)) |
      (!is.na(portfolio2_text) & is.na(portfolio2)),
    complete_pair =
      is.finite(portfolio1) & is.finite(portfolio2)
  )

# Save an audit file before excluding incomplete pairs.
write_csv(
  results_all,
  file.path(processed_dir, "01_class_data_audit.csv")
)

if (any(results_all$parse_issue)) {
  stop(
    "Some nonempty portfolio values could not be parsed. ",
    "Inspect 01_class_data_audit.csv before continuing."
  )
}

# Both descriptive and paired comparisons use the same teams.
results <- results_all |>
  filter(complete_pair) |>
  mutate(
    return1 = portfolio1 / initial_capital - 1,
    return2 = portfolio2 / initial_capital - 1,
    difference_value = portfolio2 - portfolio1,
    difference_return = return2 - return1
  )

if (nrow(results) < 3) {
  stop("Fewer than three complete portfolio pairs.")
}

if (any(results$portfolio1 < 0 | results$portfolio2 < 0)) {
  stop("Negative final portfolio values found. Check the source data.")
}

quality_summary <- tibble(
  input_rows = nrow(results_all),
  complete_pairs = nrow(results),
  excluded_incomplete_rows = sum(!results_all$complete_pair)
)

write_csv(
  quality_summary,
  file.path(table_dir, "01_data_quality.csv")
)

write_csv(
  results,
  file.path(processed_dir, "01_class_results_clean.csv")
)


# 4. Descriptive statistics -----------------------------------

long_results <- results |>
  select(source_excel_row, portfolio1, portfolio2) |>
  pivot_longer(
    cols = c(portfolio1, portfolio2),
    names_to = "portfolio",
    values_to = "final_value"
  ) |>
  mutate(
    portfolio = recode(
      portfolio,
      portfolio1 = "Portfolio 1",
      portfolio2 = "Portfolio 2"
    ),
    return = final_value / initial_capital - 1
  )

# Returns are stored as decimals: 0.05 means 5%.
summary_table <- long_results |>
  group_by(portfolio) |>
  summarise(
    teams = n(),
    mean_final_value = mean(final_value),
    median_final_value = median(final_value),
    mean_return = mean(return),
    median_return = median(return),
    sd_return = sd(return),
    p25_return = quantile(return, 0.25, names = FALSE),
    p75_return = quantile(return, 0.75, names = FALSE),
    min_return = min(return),
    max_return = max(return),
    profitable_share = mean(return > 0),
    .groups = "drop"
  )

write_csv(
  summary_table,
  file.path(table_dir, "01_portfolio_summary.csv")
)


# 5. Paired comparison ---------------------------------------

# Primary question:
# Across the same teams, was Portfolio 2's mean return higher?
# Use a two-sided test; do not select the direction after seeing results.

difference <- results$difference_return

if (!is.finite(sd(difference)) || sd(difference) == 0) {
  stop(
    "Paired return differences have zero variance. ",
    "The standard paired t-test is not applicable; inspect the data."
  )
}

paired_test <- t.test(
  difference,
  mu = 0,
  alternative = "two.sided",
  conf.level = 0.95
)

# Resample team-level paired differences, preserving the pairing.
bootstrap_means <- replicate(
  bootstrap_repetitions,
  mean(sample(difference, size = length(difference), replace = TRUE))
)

bootstrap_ci <- quantile(
  bootstrap_means,
  probs = c(0.025, 0.975),
  names = FALSE
)

# Correlation is descriptive, not a test of which portfolio is better.
portfolio_correlation <- if (
  sd(results$return1) > 0 && sd(results$return2) > 0
) {
  cor(results$return1, results$return2)
} else {
  NA_real_
}

paired_summary <- tibble(
  teams = nrow(results),
  mean_difference_value = mean(results$difference_value),
  mean_difference_return = mean(difference),
  median_difference_return = median(difference),
  portfolio2_win_share = mean(difference > 0),
  tie_share = mean(difference == 0),
  return_correlation = portfolio_correlation,
  paired_t_statistic = unname(paired_test$statistic),
  paired_t_df = unname(paired_test$parameter),
  paired_t_p_value = paired_test$p.value,
  paired_t_ci_lower = paired_test$conf.int[1],
  paired_t_ci_upper = paired_test$conf.int[2],
  bootstrap_se = sd(bootstrap_means),
  bootstrap_ci_lower = bootstrap_ci[1],
  bootstrap_ci_upper = bootstrap_ci[2]
)

write_csv(
  paired_summary,
  file.path(table_dir, "01_paired_comparison.csv")
)


# 6. Figure style ---------------------------------------------

theme_set(theme_minimal(base_size = 12))

portfolio_colors <- c(
  "Portfolio 1" = "#4477AA",
  "Portfolio 2" = "#CC6677"
)

save_plot <- function(plot, filename, width = 8, height = 5) {
  ggsave(
    filename = file.path(figure_dir, filename),
    plot = plot,
    width = width,
    height = height,
    dpi = 300,
    bg = "white"
  )
}


# 7. Figure A: Distribution of class returns -------------------

p_distribution <- ggplot(
  long_results,
  aes(x = portfolio, y = return, fill = portfolio)
) +
  geom_hline(yintercept = 0, color = "grey60", linetype = "dashed") +
  geom_boxplot(width = 0.45, alpha = 0.6, outlier.shape = NA) +
  geom_point(
    position = position_jitter(width = 0.09, height = 0, seed = 6409),
    alpha = 0.65,
    size = 2
  ) +
  scale_fill_manual(values = portfolio_colors) +
  scale_y_continuous(labels = scales::label_percent(accuracy = 1)) +
  labs(
    title = "Class experiment: distribution of portfolio returns",
    subtitle = "Each point represents one team; complete pairs only",
    x = NULL,
    y = "Holding-period return"
  ) +
  theme(legend.position = "none")

save_plot(p_distribution, "01_class_return_distribution.png")


# 8. Figure B: Same-team comparison ----------------------------

# Identity line is the relevant reference:
# above it, Portfolio 2 outperformed Portfolio 1.
p_paired <- ggplot(results, aes(x = return1, y = return2)) +
  geom_abline(
    intercept = 0, slope = 1,
    linetype = "dashed", color = "grey50"
  ) +
  geom_point(color = "#4477AA", size = 2.5, alpha = 0.8) +
  scale_x_continuous(labels = scales::label_percent(accuracy = 1)) +
  scale_y_continuous(labels = scales::label_percent(accuracy = 1)) +
  coord_equal() +
  labs(
    title = "Did Portfolio 2 outperform within the same team?",
    subtitle = "Points above the dashed line favor Portfolio 2",
    x = "Portfolio 1 return",
    y = "Portfolio 2 return"
  )

save_plot(p_paired, "01_class_paired_returns.png", width = 7, height = 6)


# 9. Figure C: Mean paired advantage and uncertainty ------------

interval_data <- tibble(
  method = c("Paired t interval", "Paired bootstrap interval"),
  estimate = mean(difference),
  lower = c(paired_test$conf.int[1], bootstrap_ci[1]),
  upper = c(paired_test$conf.int[2], bootstrap_ci[2])
)

p_difference <- ggplot(interval_data, aes(x = method, y = estimate)) +
  geom_hline(yintercept = 0, linetype = "dashed", color = "grey50") +
  geom_errorbar(aes(ymin = lower, ymax = upper), width = 0.12) +
  geom_point(size = 3, color = "#CC6677") +
  scale_y_continuous(labels = scales::label_percent(accuracy = 0.1)) +
  labs(
    title = "Average return advantage of Portfolio 2",
    subtitle = "Portfolio 2 minus Portfolio 1, with 95% confidence intervals",
    x = NULL,
    y = "Return difference (percentage-point scale)"
  )

save_plot(p_difference, "01_class_mean_difference.png")


# 10. Save a concise results note ------------------------------

pct <- function(x) sprintf("%.2f%%", 100 * x)
pp  <- function(x) sprintf("%.2f percentage points", 100 * x)

notes <- c(
  "CLASS EXPERIMENT: RESULTS",
  "",
  paste("Input:", input_file),
  paste("Assumed initial capital per portfolio:", initial_capital),
  paste("Complete team pairs:", nrow(results)),
  paste("Excluded incomplete rows:", sum(!results_all$complete_pair)),
  "",
  paste("Portfolio 1 mean return:", pct(mean(results$return1))),
  paste("Portfolio 2 mean return:", pct(mean(results$return2))),
  paste("Mean paired advantage of Portfolio 2:", pp(mean(difference))),
  paste("Portfolio 2 outperformance share:", pct(mean(difference > 0))),
  paste("Ties:", sum(difference == 0)),
  paste("Return correlation:", round(portfolio_correlation, 3)),
  "",
  paste(
    "Paired t-test 95% CI:",
    pp(paired_test$conf.int[1]), "to", pp(paired_test$conf.int[2])
  ),
  paste(
    "Two-sided paired t-test p-value:",
    format.pval(paired_test$p.value, digits = 4)
  ),
  paste(
    "Paired bootstrap 95% CI:",
    pp(bootstrap_ci[1]), "to", pp(bootstrap_ci[2])
  ),
  "",
  "INTERPRETATION LIMITS",
  "These are holding-period returns, not annualized returns.",
  "Endpoint values do not identify the path, volatility, or maximum drawdown.",
  "A higher mean return does not establish repeatable forecasting skill.",
  "A confidence interval including zero indicates uncertainty, not equivalence.",
  "Teams may share stocks and market exposure; cross-team independence is imperfect.",
  "Team-level confidence intervals do not capture uncertainty across market periods.",
  "Verify the portfolio-selection rules before labeling methods in the blog."
)

writeLines(
  notes,
  file.path(note_dir, "01_class_results_summary.txt")
)

capture.output(
  sessionInfo(),
  file = file.path(note_dir, "01_session_info.txt")
)


# 11. Display results -----------------------------------------

print(quality_summary)
print(summary_table, width = Inf)
print(paired_summary, width = Inf)

print(p_distribution)
print(p_paired)
print(p_difference)

cat("\n", paste(notes, collapse = "\n"), "\n")
cat("\nStage 1 completed. Outputs saved under:\n", project_dir, "\n")
