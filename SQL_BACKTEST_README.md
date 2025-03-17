# SQL-Based Trading Strategy Backtester

This project contains SQL scripts for backtesting trading strategies directly in ClickHouse using Binance kline data.

## Available Strategies

1. **Moving Average Crossover** (`simple_ma_crossover_strategy.sql`)
   - A classic strategy that generates buy signals when a fast moving average crosses above a slow moving average, and sell signals when it crosses below.
   - Configurable parameters include MA periods, symbol, and timeframe.

2. **Intraday Trend Following** (`intraday_trend_strategy.sql`)
   - Based on the morning trend direction, enters trades after a specified entry time if momentum exceeds a threshold.
   - Always exits at the end of the trading session.
   - Calculates stop loss and take profit levels based on the morning price range.

## How to Run

### Prerequisites

- ClickHouse server with access to Binance kline data
- The `binance.klines` table should have the following structure:
  - symbol (String)
  - open_time (DateTime64)
  - open, high, low, close, volume (Float64)
  - close_time (DateTime64)
  - quote_volume (Float64)
  - trades (UInt32)
  - taker_buy_volume, taker_buy_quote_volume (Float64)

### Running a Backtest

Use the provided shell script:

```bash
./run_backtest.sh [strategy_name]
```

Where `strategy_name` is one of:
- `ma_crossover` (default)
- `intraday_trend`

Example:
```bash
./run_backtest.sh intraday_trend
```

### Modifying Parameters

Each SQL file contains configurable parameters at the top of the file:

```sql
-- Parameters
DECLARE symbol_to_test String DEFAULT 'BTCUSDT';
DECLARE timeframe UInt16 DEFAULT 15;
-- etc.
```

Edit these values to customize your backtest.

## Output

The scripts output trading signals with the following information:
- Date and time
- OHLC prices
- Signal type (BUY, SELL, EXIT)
- Signal price
- Additional strategy-specific metrics

## Extending

To create a new strategy:
1. Create a new SQL file based on the existing templates
2. Add your strategy to the `run_backtest.sh` script
3. Implement your signal generation logic in the SQL CTEs 