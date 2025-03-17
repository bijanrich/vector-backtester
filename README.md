# Vector Backtester

A high-performance trading strategy backtester using pure ClickHouse SQL for cryptocurrency market data.

## Features

- Pure SQL implementation for extremely fast backtesting
- Multiple built-in strategies (Moving Average Crossover, Intraday Trend Following)
- Parameterized strategy files that work with any trading pair
- Unified trade storage in a single ClickHouse table
- Comprehensive performance metrics and trade analysis
- Flexible date range and symbol selection

## Prerequisites

- ClickHouse database with Binance kline data
- The `binance.klines` table should have the following structure:
  - symbol (String)
  - open_time (DateTime64)
  - open, high, low, close, volume (Float64)
  - close_time (DateTime64)
  - quote_volume (Float64)
  - trades (UInt32)
  - taker_buy_volume, taker_buy_quote_volume (Float64)

## Usage

### Running a Single Strategy

```bash
./run_backtest.sh <strategy_name> [symbol] [start_date] [end_date]
```

Parameters:
- `strategy_name`: Name of the strategy to run (required)
- `symbol`: Trading pair to test (default: BTCUSDT)
- `start_date`: Start date for backtest (default: 2023-01-01)
- `end_date`: End date for backtest (default: 2024-01-01)

Example:
```bash
./run_backtest.sh simple_ma_crossover ETHUSDT 2022-01-01 2023-01-01
```

### Running Multiple Backtests

Run all strategies for a single coin:
```bash
./run_all_strategies_one_coin.sh <symbol> [start_date] [end_date]
```

Run one strategy for all coins:
```bash
./run_strategy_all_coins.sh <strategy_name> [start_date] [end_date]
```

Run all strategies for all coins:
```bash
./run_all_backtests.sh [start_date] [end_date]
```

## Available Strategies

### Simple Moving Average Crossover (`simple_ma_crossover`)

- Timeframe: 15m
- Fast MA: 20 periods
- Slow MA: 50 periods
- Entry Long: Fast MA crosses above Slow MA
- Entry Short: Fast MA crosses below Slow MA
- Exit Long: Fast MA crosses below Slow MA
- Exit Short: Fast MA crosses above Slow MA

### Intraday Trend Following (`intraday_trend`)

- Timeframe: 5m
- Session time: 09:00 - 11:00
- Entry time: 10:00
- Trend period: Morning session (09:00 - 10:00)
- Momentum threshold: 0.001 (0.1%)
- Exit time: 11:00

## Trade Storage

All trades are stored in a unified `backtest.trades` table with the following structure:
- `strategy` (String): Strategy name
- `symbol` (String): Trading pair
- `entry_time` (DateTime): Trade entry timestamp
- `exit_time` (DateTime): Trade exit timestamp
- `entry_price` (Float64): Entry price
- `exit_price` (Float64): Exit price
- `direction` (String): LONG or SHORT
- `pnl` (Float64): Profit/Loss in quote currency
- `pnl_percent` (Float64): Profit/Loss as percentage
- `trade_duration_hours` (Float64): Trade duration in hours

## Performance Analysis

After running backtests, you can analyze performance with:

```bash
# View all trades for a specific strategy and symbol
clickhouse client --query "SELECT * FROM backtest.trades WHERE strategy = 'simple_ma_crossover' AND symbol = 'BTCUSDT' ORDER BY entry_time"

# Compare performance across all strategies and symbols
clickhouse client --query "SELECT strategy, symbol, count(*) as trades, round(avg(pnl_percent), 2) as avg_pnl_pct, round(sum(pnl), 2) as total_pnl FROM backtest.trades GROUP BY strategy, symbol ORDER BY total_pnl DESC"
```

## Customizing Strategies

You can customize existing strategies by editing the SQL files in the `strategies/` directory:
- `simple_ma_crossover_strategy.sql`
- `intraday_trend_strategy.sql`

Parameters that can be adjusted include:
- Moving average periods
- Timeframes
- Session times
- Momentum thresholds
- Entry/exit conditions

## Creating New Strategies

To create a new strategy:
1. Create a new SQL file in the `strategies/` directory (e.g., `strategies/my_strategy_strategy.sql`)
2. Use the existing strategy files as templates
3. Ensure your strategy inserts trades into the `backtest.trades` table
4. Run your strategy with `./run_backtest.sh my_strategy`

## Advanced Analysis Examples

```sql
-- Calculate win rate by strategy
SELECT
    strategy,
    symbol,
    count(*) AS total_trades,
    countIf(
        (direction = 'LONG' AND exit_price > entry_price) OR 
        (direction = 'SHORT' AND exit_price < entry_price)
    ) AS winning_trades,
    round(
        countIf(
            (direction = 'LONG' AND exit_price > entry_price) OR 
            (direction = 'SHORT' AND exit_price < entry_price)
        ) / count(*), 
        2
    ) AS win_rate
FROM backtest.trades
GROUP BY strategy, symbol
ORDER BY win_rate DESC
``` 
``` 