# ============================================================
# Stage 2: download and cache daily Yahoo Finance data
# ============================================================

source("D:/Rproject/6400-blog9/code/00_config.R")

cache_dir <- file.path(paths$raw, "yahoo_cache")
dir.create(cache_dir, recursive = TRUE, showWarnings = FALSE)

# Change to TRUE only when deliberately refreshing the snapshot.
refresh_cache <- FALSE

all_symbols <- c(tickers, "SPY")
download_log <- vector("list", length(all_symbols))
downloaded <- vector("list", length(all_symbols))

for (i in seq_along(all_symbols)) {
  symbol <- all_symbols[i]
  cache_file <- file.path(cache_dir, paste0(symbol, ".rds"))
  message("[", i, "/", length(all_symbols), "] ", symbol)
  
  used_cache <- file.exists(cache_file) && !refresh_cache
  error_text <- NA_character_
  price_data <- NULL
  
  if (used_cache) {
    price_data <- readRDS(cache_file)
  } else {
    # Bounded retries for transient service errors.
    for (attempt in 1:3) {
      price_data <- tryCatch({
        z <- quantmod::getSymbols(
          Symbols = symbol,
          src = "yahoo",
          from = download_start,
          to = download_end,
          auto.assign = FALSE,
          warnings = FALSE
        )
        
        tibble(
          symbol = symbol,
          date = as.Date(zoo::index(z)),
          open = as.numeric(quantmod::Op(z)),
          high = as.numeric(quantmod::Hi(z)),
          low = as.numeric(quantmod::Lo(z)),
          close = as.numeric(quantmod::Cl(z)),
          volume = as.numeric(quantmod::Vo(z)),
          adjusted = as.numeric(quantmod::Ad(z))
        )
      }, error = function(e) {
        error_text <<- conditionMessage(e)
        NULL
      })
      
      if (!is.null(price_data)) break
      if (attempt < 3) Sys.sleep(2 * attempt)
    }
  }
  
  if (!is.null(price_data)) {
    price_data <- price_data |>
      filter(date >= download_start, date < download_end) |>
      arrange(date)
    
    valid <- nrow(price_data) > 0 &&
      !anyDuplicated(price_data$date) &&
      all(is.finite(price_data$adjusted)) &&
      all(price_data$adjusted > 0)
    
    if (!valid) {
      error_text <- "Empty data, duplicate dates, or invalid adjusted prices."
      price_data <- NULL
    } else if (!used_cache) {
      saveRDS(price_data, cache_file)
    }
  }
  
  downloaded[i] <- list(price_data)
  
  download_log[[i]] <- tibble(
    symbol = symbol,
    status = if (is.null(price_data)) "FAILED" else "OK",
    used_cache = used_cache,
    rows = if (is.null(price_data)) 0L else nrow(price_data),
    checked_at_utc = format(Sys.time(), tz = "UTC", usetz = TRUE),
    error = if (is.null(price_data)) error_text else NA_character_
  )
  
  if (!used_cache) Sys.sleep(0.5)
}

download_log <- bind_rows(download_log)
write_csv(download_log, file.path(paths$tables, "02_download_log.csv"))

if (any(download_log$status != "OK")) {
  stop("Some downloads failed. Inspect 02_download_log.csv and rerun.")
}

prices <- bind_rows(downloaded) |> arrange(symbol, date)

# Require the requested historical endpoints.
coverage <- prices |>
  group_by(symbol) |>
  summarise(
    first_date = min(date),
    last_date = max(date),
    observations = n(),
    .groups = "drop"
  )

write_csv(coverage, file.path(paths$tables, "02_price_coverage.csv"))

if (any(coverage$first_date > as.Date("2010-01-04")) ||
    any(coverage$last_date < test_end)) {
  stop("Historical coverage is incomplete. Inspect 02_price_coverage.csv.")
}

# Require every stock to cover SPY's trading calendar.
# Missing quotes are not filled using future information.
calendar <- prices |> filter(symbol == "SPY") |> pull(date)

missing_quotes <- tidyr::expand_grid(
  symbol = tickers,
  date = calendar
) |>
  anti_join(prices |> select(symbol, date), by = c("symbol", "date"))

write_csv(
  missing_quotes,
  file.path(paths$tables, "02_missing_quotes.csv")
)

if (nrow(missing_quotes) > 0) {
  stop("Missing stock trading dates found. Inspect 02_missing_quotes.csv.")
}

saveRDS(prices, file.path(paths$raw, "prices_daily.rds"))
write_csv(prices, file.path(paths$raw, "prices_daily.csv"))

capture.output(
  sessionInfo(),
  file = file.path(paths$notes, "02_session_info.txt")
)

message("Stage 2 completed: all 50 stocks and SPY downloaded.")