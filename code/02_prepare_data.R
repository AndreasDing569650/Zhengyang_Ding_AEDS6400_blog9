# ============================================================
# Stage 2: download the professor's stock universe
# ============================================================

source("D:/Rproject/6400-blog9/code/00_config.R")

snapshot_file <- file.path(
  paths$raw,
  "market_snapshot.rds"
)

symbols <- c(tickers, "SPY")

use_cache <- FALSE

if (file.exists(snapshot_file) && !refresh_data) {
  old_snapshot <- readRDS(snapshot_file)
  
  use_cache <-
    identical(old_snapshot$symbols, symbols) &&
    identical(old_snapshot$requested_from, download_from) &&
    identical(old_snapshot$requested_to, download_to)
}

if (use_cache) {
  
  snapshot <- old_snapshot
  prices <- snapshot$prices
  
  message("Using the saved snapshot for the same download date.")
  
} else {
  
  downloaded <- vector("list", length(symbols))
  download_logs <- vector("list", length(symbols))
  
  for (i in seq_along(symbols)) {
    
    ticker <- symbols[i]
    
    message(
      "[", i, "/", length(symbols), "] ",
      ticker
    )
    
    z <- NULL
    last_error <- NA_character_
    
    for (attempt in 1:3) {
      
      z <- tryCatch(
        tidyquant::tq_get(
          ticker,
          get = "stock.prices",
          from = download_from,
          to = download_to
        ),
        error = function(e) {
          last_error <<- conditionMessage(e)
          NULL
        }
      )
      
      success <- is.data.frame(z) && nrow(z) > 0L
      
      if (success) break
      
      z <- NULL
      
      if (attempt < 3) {
        Sys.sleep(2 * attempt)
      }
    }
    
    if (!is.null(z)) {
      
      downloaded[[i]] <- z |>
        transmute(
          symbol = ticker,
          date = as.Date(date),
          open,
          high,
          low,
          close,
          volume,
          adjusted
        )
    }
    
    download_logs[[i]] <- tibble(
      symbol = ticker,
      status = if (is.null(z)) "FAILED" else "OK",
      error = if (is.null(z)) last_error else NA_character_
    )
    
    Sys.sleep(0.5)
  }
  
  download_log <- bind_rows(download_logs)
  
  write_csv(
    download_log,
    file.path(paths$tables, "02_download_log.csv")
  )
  
  if (any(download_log$status != "OK")) {
    stop(
      "Some downloads failed. ",
      "Inspect 02_download_log.csv and rerun."
    )
  }
  
  # Preserve the professor's ticker-list order.
  prices <- bind_rows(downloaded) |>
    filter(
      date >= download_from,
      date < download_to
    )
  
  snapshot <- list(
    prices = prices,
    symbols = symbols,
    requested_from = download_from,
    requested_to = download_to,
    downloaded_at_utc = format(
      Sys.time(),
      tz = "UTC",
      usetz = TRUE
    )
  )
}

if (anyDuplicated(prices[c("symbol", "date")])) {
  stop("Duplicate symbol-date observations found.")
}

if (!setequal(unique(prices$symbol), symbols)) {
  stop("The downloaded stock universe is incomplete.")
}

saveRDS(snapshot, snapshot_file)

saveRDS(
  prices,
  file.path(paths$raw, "prices_daily.rds")
)

write_csv(
  prices,
  file.path(paths$raw, "prices_daily.csv")
)

coverage <- prices |>
  group_by(symbol) |>
  summarise(
    first_date = min(date),
    last_date = max(date),
    observations = n(),
    missing_adjusted = sum(is.na(adjusted)),
    .groups = "drop"
  )

write_csv(
  coverage,
  file.path(paths$tables, "02_price_coverage.csv")
)

write_csv(
  tibble(
    requested_from = snapshot$requested_from,
    requested_to = snapshot$requested_to,
    last_observed_date = max(prices$date),
    downloaded_at_utc = snapshot$downloaded_at_utc
  ),
  file.path(paths$tables, "02_snapshot.csv")
)

write_csv(
  tibble(symbol = tickers),
  file.path(paths$tables, "02_stock_universe.csv")
)

capture.output(
  sessionInfo(),
  file = file.path(paths$notes, "02_session_info.txt")
)

message("Stage 2 completed.")